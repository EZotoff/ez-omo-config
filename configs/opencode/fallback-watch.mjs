// fallback-watch.mjs — observability for out-of-band model fallbacks.
//
// Detects when an OMO agent serves a turn on a model that is NEITHER its
// configured primary NOR in its declared `fallback_models` — i.e. the built-in
// upstream model-core fallback chain fired (e.g. google/gemini-3.1-pro serving
// oracle/momus review subagents during the 2026-10-04/05 outage, ~15M tokens,
// discovered only by forensic attribution after the fact).
//
// Evidence states: this plugin is repo_implemented on a branch. It is NOT
// registered in opencode.json#plugin and NOT installed until the operator
// approves deployment (registration + server restart).
//
// Design constraints (mirrors provider-connect-retry.mjs):
// - Server plugins get ctx = {client, project, worktree, directory, $}. There
//   is NO ctx.logger/toast/notify. User-facing output MUST go through
//   ctx.client.tui.showToast (silently dropped when no TUI is attached).
// - console.* is FORBIDDEN: text goes to server stdout/journald and leaks into
//   the TUI viewport (the [retry-plugin] spam regression).
// - Routine ops go to the local log file only.
// - ONLY function exports: the plugin loader (getLegacyPlugins) rejects any
//   module with a non-function export ("Plugin export is not a function") —
//   a named object export silently disabled provider-connect-retry from
//   2026-08-18 to 2026-08-20.
//
// Registration (pending operator approval): add "./fallback-watch.mjs" to the
// `plugin` array in configs/opencode/opencode.json, then restart the server
// via scripts/restart-with-continuation.sh.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const PATHS = {
  omoConfig: path.join(os.homedir(), ".config", "opencode", "oh-my-openagent.json"),
  opencodeConfig: path.join(os.homedir(), ".config", "opencode", "opencode.json"),
  retryRegistry: path.join(os.homedir(), ".config", "opencode", "retry-errors.json"),
  log: path.join(os.homedir(), ".config", "opencode", "fallback-watch.log"),
};

// Test-isolation hook (same pattern as globalThis.__providerConnectRetryTestPaths).
const testPaths = () => globalThis.__fallbackWatchTestPaths ?? {};
const omoConfigPath = () => testPaths().omoConfig ?? PATHS.omoConfig;
const opencodeConfigPath = () => testPaths().opencodeConfig ?? PATHS.opencodeConfig;
const retryRegistryPath = () => testPaths().retryRegistry ?? PATHS.retryRegistry;
const logPath = () => testPaths().log ?? PATHS.log;

const LOG_MAX_BYTES = 10 * 1024 * 1024; // 10 MB before rotation

function rotateLogIfNeeded() {
  try {
    const stat = fs.statSync(logPath());
    if (stat.size > LOG_MAX_BYTES) {
      const backup = `${logPath()}.1`;
      try { fs.unlinkSync(backup); } catch {}
      try { fs.renameSync(logPath(), backup); } catch { try { fs.unlinkSync(logPath()); } catch {} }
    }
  } catch {
    // file doesn't exist yet — nothing to rotate
  }
}

function log(level, message) {
  try {
    rotateLogIfNeeded();
    fs.appendFileSync(logPath(), `${new Date().toISOString()} [${level}] ${message}\n`);
  } catch {
    // never let logging break the event loop
  }
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return undefined;
  }
}

// Normalize a model reference to "providerID/modelID".
const modelRef = (model) =>
  model && typeof model === "object" && model.providerID && model.modelID
    ? `${model.providerID}/${model.modelID}`
    : typeof model === "string" ? model : undefined;

// Declared models for one OMO assignment: primary + fallback_models.
function declaredFor(assignment, into) {
  if (!assignment || typeof assignment !== "object") return;
  const primary = modelRef(assignment.model);
  if (primary) into.add(primary);
  for (const fb of assignment.fallback_models ?? []) {
    const ref = modelRef(fb);
    if (ref) into.add(ref);
  }
}

// Build { agents: Map<name, Set<ref>>, smallModel: ref|undefined, compaction: Set<ref> }
// from the live configs. Compaction runs on the session model, so its declared
// set is the union of everything we know about (handled by the caller-side
// "unknown assignment = skip" rule); we still track the explicit chain for the
// weekly report.
export function buildDeclaredSets() {
  const omo = readJson(omoConfigPath()) ?? {};
  const oc = readJson(opencodeConfigPath()) ?? {};
  const retry = readJson(retryRegistryPath()) ?? {};

  const agents = new Map();
  for (const [name, assignment] of Object.entries(omo.agents ?? {})) {
    const set = new Set();
    declaredFor(assignment, set);
    if (set.size > 0) agents.set(name, set);
  }
  const categories = new Map();
  for (const [name, assignment] of Object.entries(omo.categories ?? {})) {
    const set = new Set();
    declaredFor(assignment, set);
    if (set.size > 0) categories.set(name, set);
  }

  const compaction = new Set();
  for (const ref of retry.compaction_fallback_models ?? []) {
    const r = modelRef(ref);
    if (r) compaction.add(r);
  }

  return {
    agents,
    categories,
    smallModel: modelRef(oc.small_model),
    compaction,
  };
}

// Returns the out-of-band model ref, or undefined if the usage is declared
// (or the agent has no OMO expectation — builtin agents are skipped).
export function classifyAgentTurn({ agentName, model }, declared) {
  const ref = modelRef(model);
  if (!ref) return undefined;
  const set = declared.agents.get(agentName) ?? declared.categories.get(agentName);
  if (!set) return undefined; // no expectation — not our verdict to make
  if (set.has(ref)) return undefined;
  if (ref === declared.smallModel) return undefined;
  return ref;
}

export const FallbackWatchPlugin = async (ctx) => {
  const processedMessages = new Set(); // messageID -> already evaluated
  const toasted = new Set(); // `${sessionID}|${model}` -> toast sent

  let declared = buildDeclaredSets();
  let declaredLoadedAt = 0;
  const DECLARED_TTL_MS = 60_000; // pick up operator config edits within a minute

  const refreshDeclared = () => {
    const now = Date.now();
    if (now - declaredLoadedAt < DECLARED_TTL_MS) return declared;
    declared = buildDeclaredSets();
    declaredLoadedAt = now;
    return declared;
  };

  const surfaceToast = async (sessionID, agentName, ref) => {
    const key = `${sessionID}|${ref}`;
    if (toasted.has(key)) return;
    toasted.add(key);
    try {
      await ctx.client.tui.showToast({
        body: {
          title: "Out-of-band model fallback",
          message: `${agentName} served on ${ref} — outside its declared primary/fallback_models (built-in OMO chain). Logged to fallback-watch.log.`,
          variant: "warning",
          duration: 10000,
        },
      });
    } catch {
      // no TUI attached — event is dropped server-side; log already has it
    }
  };

  log("info", `FallbackWatchPlugin initialized (pid ${process.pid}, log ${logPath()})`);

  return {
    event: async ({ event }) => {
      try {
        if (event?.type !== "message.updated") return;
        const info = event.properties?.info;
        if (!info || info.role !== "assistant") return;
        const messageID = info.id;
        if (!messageID || processedMessages.has(messageID)) return;
        processedMessages.add(messageID);
        // Cap in-memory dedup state; sessions are long-lived but message IDs
        // are unique, so a plain trim keeps the Set bounded.
        if (processedMessages.size > 5000) {
          const first = processedMessages.values().next().value;
          processedMessages.delete(first);
        }

        const sessionID = info.sessionID ?? event.properties?.sessionID;
        const agentName = info.agent;
        const model = { providerID: info.providerID, modelID: info.modelID };
        const sets = refreshDeclared();
        const outOfBand = classifyAgentTurn({ agentName, model }, sets);
        if (!outOfBand) return;

        const tokens = info.tokens ?? {};
        const cache = tokens.cache ?? {};
        const record = {
          ts: new Date().toISOString(),
          sessionID,
          messageID,
          agent: agentName,
          model: outOfBand,
          input: tokens.input ?? null,
          output: tokens.output ?? null,
          cacheRead: cache.read ?? null,
          cost: info.cost ?? null,
        };
        log("warn", `out_of_band_fallback ${JSON.stringify(record)}`);
        if (sessionID) await surfaceToast(sessionID, agentName, outOfBand);
      } catch (e) {
        log("error", `event handler failed: ${e?.message ?? e}`);
      }
    },
  };
};
