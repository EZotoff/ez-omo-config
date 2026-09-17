// agent-default-guard.mjs — config-layer plugin
//
// Rewrites incoming chat messages that explicitly request the demoted "build"
// agent to the configured default agent, before the message is persisted.
//
// Why this exists (2026-09-05/06 incident): OC Beacon (Android client,
// LeoNardo-LB/oc-beacon) hardcodes "build" as the preselected agent for new
// sessions (ModelConfigDelegate.kt: `MutableStateFlow("build" to false)`) and
// never reads the server's default_agent for chat preselection. On this rig
// OMO demotes build to a hidden subagent and sets default_agent at runtime,
// but OpenCode still ACCEPTS hidden agents for dispatch, so every new phone
// session ran as build. Restarting the app or server cannot change a
// client-side hardcoded default — the server must neutralize it at dispatch.
//
// Mechanics: the `chat.message` plugin hook fires in
// packages/opencode/src/session/prompt.ts createUserMessage() BEFORE
// sessions.updateMessage(info) persists the user message, and the run loop
// resolves the turn's agent from the persisted lastUser.agent. Mutating
// output.message.agent here therefore flips the whole session to the default
// agent. OC Beacon's UI then auto-syncs: its ModelConfigDelegate adopts
// lastUserAgent when it is a visible primary agent.
//
// Fail-open: any error (config unreadable, agent registry unreachable, target
// agent missing) leaves the message untouched — the plugin must never break
// message dispatch.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const PATHS = {
  // Sibling of this plugin file (~/.config/opencode/opencode.json) — the same
  // config-relative resolution OpenCode uses for the plugin array itself.
  config: new URL("./opencode.json", import.meta.url).pathname,
  log: path.join(os.homedir(), ".config", "opencode", "agent-default-guard.log"),
};

// Test-isolation hook via globalThis (same pattern as provider-connect-retry).
// MUST NOT be a module export: OpenCode's plugin loader rejects any module
// with a non-function export.
const testPaths = () => globalThis.__agentDefaultGuardTestPaths ?? {};
const configPath = () => testPaths().config ?? PATHS.config;
const logPath = () => testPaths().log ?? PATHS.log;

const LOG_MAX_BYTES = 2 * 1024 * 1024;
const REGISTRY_TTL_MS = 60_000;

function log(level, msg) {
  const line = `[${new Date().toISOString()}] [${level}] ${msg}\n`;
  try {
    try {
      const stat = fs.statSync(logPath());
      if (stat.size > LOG_MAX_BYTES) {
        const backup = `${logPath()}.1`;
        try { fs.unlinkSync(backup); } catch {}
        try { fs.renameSync(logPath(), backup); } catch {}
      }
    } catch {}
    fs.appendFileSync(logPath(), line);
  } catch {}
  // No console.* — raw output leaks into the TUI viewport / journald.
}

function readDefaultAgent() {
  try {
    const cfg = JSON.parse(fs.readFileSync(configPath(), "utf8"));
    const agent = cfg.default_agent;
    return typeof agent === "string" && agent.trim().length > 0 ? agent.trim() : undefined;
  } catch {
    return undefined;
  }
}

async function fetchRegistry(ctx) {
  const response = await ctx.client.app.agents();
  const agents = response?.data ?? response;
  if (!Array.isArray(agents)) throw new Error("unexpected /agent response shape");
  return agents;
}

const AgentDefaultGuardPlugin = async (ctx) => {
  let cache = { at: 0, agents: null };

  // `trace` is a per-invocation out-param: registry() records whether the
  // agents fetch was served from the TTL cache (hit) or refetched (miss),
  // so the chat.message timing line can attribute hook cost correctly.
  const registry = async (trace) => {
    const now = Date.now();
    if (cache.agents !== null && now - cache.at < REGISTRY_TTL_MS) {
      trace.cache = "hit";
      return cache.agents;
    }
    const agents = await fetchRegistry(ctx);
    cache = { at: now, agents };
    trace.cache = "miss";
    return agents;
  };

  return {
    "chat.message": async (input, output) => {
      const startedAt = Date.now();
      const trace = { cache: null, rewrite: "no" };
      try {
        if (input?.agent !== "build") return;
        if (!output?.message) return;

        const target = readDefaultAgent();
        if (!target) {
          log("warn", "no default_agent configured in opencode.json — leaving build untouched");
          return;
        }

        let agents;
        try {
          agents = await registry(trace);
        } catch (error) {
          // A failed refetch still counts as a miss: the fetch was attempted.
          trace.cache = "miss";
          log("warn", `agent registry fetch failed (${error?.message ?? error}) — leaving build untouched`);
          return;
        }

        const isVisiblePrimary = (a) => a && a.mode !== "subagent" && a.hidden !== true;
        const buildEntry = agents.find((a) => a?.name === "build");
        const targetEntry = agents.find((a) => a?.name === target);

        // Fail-open: if OMO is not loaded, build is a visible primary again and
        // the hardcoded client default is legitimate — do not rewrite.
        if (buildEntry && isVisiblePrimary(buildEntry)) {
          log("info", "build is a visible primary agent (OMO not applied?) — leaving untouched");
          return;
        }
        if (!targetEntry || !isVisiblePrimary(targetEntry)) {
          log("warn", `configured default agent "${target}" is not a visible primary — leaving build untouched`);
          return;
        }

        const from = output.message.agent;
        output.message.agent = target;
        trace.rewrite = "yes";
        log(
          "info",
          `rewrote message agent "${from ?? input.agent}" -> "${target}" (session ${input.sessionID ?? "?"}, message ${output.message.id ?? "?"})`,
        );
      } catch (error) {
        log("warn", `chat.message guard failed open: ${error?.message ?? error}`);
      } finally {
        // Emitted only once the registry was consulted, so cache= is always
        // hit|miss. Guards that return before the registry (non-build agent,
        // missing message, missing default_agent) log nothing here.
        if (trace.cache !== null) {
          log(
            "info",
            `hook=chat.message dur_ms=${Date.now() - startedAt} cache=${trace.cache} rewrite=${trace.rewrite}`,
          );
        }
      }
    },
  };
};

export default AgentDefaultGuardPlugin;
