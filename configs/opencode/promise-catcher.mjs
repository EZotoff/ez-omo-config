import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// Promise-catcher — server plugin.
//
// Failure mode addressed (2026-09-28 unbound-probe audit): agents end their
// turn with "I'll probe / I'll monitor / I'll track" and no wake trigger
// armed. A turn-based agent has no self-wake, so the promise never fires and
// the operator has to return with the outcome (2026-09-26 ez-omo-bench: three
// consecutive turns ended on probe promises; the operator came back with the
// result every time). Instruction-layer fixes (AGENTS.md monitoring lesson,
// rewritten 2026-09-28) make the right behavior findable; this plugin makes
// the wrong behavior impossible to get away with.
//
// Detection: on the live `session.status` {type:"idle"} event (the schema's
// session.idle is deprecated), inspect the session's newest message. If it is
// a COMPLETED assistant message whose text contains a monitoring promise,
// with no running tool parts and no armed wake trigger (pending background
// task or watcher mention in text), inject a continuation prompt forcing the
// agent to either execute the monitoring now (bounded sleeps + probes) or arm
// a real wake trigger (run_in_background watcher subagent).
//
// Rollout: dry_run defaults to true (log + toast only). Review the hit rate in
// promise-catcher.log, then flip dry_run:false in promise-catcher.json.
//
// User-facing output MUST go through ctx.client.tui.showToast (see
// surfaceToast); console.* leaks into the TUI viewport / journald as spam.
// Test-isolation hook via globalThis (same pattern as busy-stall-reaper).
const testPaths = () => globalThis.__promiseCatcherTestPaths ?? {};
const PATHS = {
  config: path.join(os.homedir(), ".config", "opencode", "promise-catcher.json"),
  log: path.join(os.homedir(), ".config", "opencode", "promise-catcher.log"),
};
const configPath = () => testPaths().config ?? PATHS.config;
const logPath = () => testPaths().log ?? PATHS.log;

const LOG_MAX_BYTES = 2 * 1024 * 1024; // rotate at 2 MB, one .1 backup

const DEFAULTS = {
  enabled: true,
  dry_run: true,
  max_wakes_per_session: 2, // dead-letter after this many wake injections
  exempt_sessions: [],
  exempt_directories: [],
};

function rotateLogIfNeeded() {
  try {
    const stat = fs.statSync(logPath());
    if (stat.size > LOG_MAX_BYTES) {
      const backup = `${logPath()}.1`;
      try { fs.unlinkSync(backup); } catch {}
      try { fs.renameSync(logPath(), backup); } catch { try { fs.unlinkSync(logPath()); } catch {} }
    }
  } catch {}
}

function log(level, msg) {
  const ts = new Date().toISOString();
  const line = `[${ts}] [${level}] ${msg}\n`;
  try { rotateLogIfNeeded(); fs.appendFileSync(logPath(), line); } catch {}
}

async function surfaceToast(ctx, { title, message, variant = "info", duration = 8000 }) {
  try {
    await ctx.client.tui.showToast({
      body: { ...(title ? { title } : {}), message, variant, duration },
    });
  } catch (error) {
    log("warn", `Toast call failed: ${error?.message ?? error}; intended message: ${message}`);
  }
}

function loadConfig() {
  try {
    const raw = JSON.parse(fs.readFileSync(configPath(), "utf8"));
    return {
      ...DEFAULTS,
      ...raw,
      exempt_sessions: Array.isArray(raw?.exempt_sessions) ? raw.exempt_sessions : [],
      exempt_directories: Array.isArray(raw?.exempt_directories) ? raw.exempt_directories : [],
    };
  } catch {
    return { ...DEFAULTS };
  }
}

// --- Promise / armed-wait detection (pure; exported for tests) ---

const PROMISE_PATTERNS = [
  /\b(?:i|we)'?(?:ll|\s+will)\s+probe\b/i,
  /\b(?:i|we)'?(?:ll|\s+will)\s+(?:continue\s+to\s+|keep\s+|now\s+)?(?:monitor|track|watch)\b/i,
  /\b(?:i|we)'?(?:ll|\s+will)\s+(?:keep\s+)?(?:probing|monitoring|tracking|watching)\b/i,
  /\b(?:i|we)'?(?:ll|\s+will)\s+check\s+(?:back|again|in\b)/i,
  /\b(?:i|we)'?(?:ll|\s+will)\s+keep\s+(?:an\s+eye|monitoring)\b/i,
  /\b(?:i|we)\s+(?:am|are)\s+(?:now\s+|actively\s+|still\s+)?monitoring\b/i,
  /\bcontinu\w+\s+(?:to\s+)?(?:monitor|probe|track)\b/i,
  /\bnext\s+probe\b/i,
];

// Text signals that a wake trigger is ALREADY armed (skip — the session will
// be woken by the background-task completion reminder, the one mechanism that
// verifiably works).
const ARMED_TEXT_RE =
  /\bbg_[0-9a-z]{4,}\b|\brun_in_background\b|background\s+(?:task|watcher|subagent)|watcher\s+subagent|waiting\s+on\s+(?:the\s+)?\w[\w-]*\s+notification|await\w*\s+(?:the\s+)?\w[\w-]*\s+notification/i;

const BG_ID_RE = /\bbg_[0-9a-z]{4,}\b/g;

function textOf(parts) {
  return (Array.isArray(parts) ? parts : [])
    .filter((p) => typeof p?.text === "string")
    .map((p) => p.text)
    .join("\n");
}

// Count background tasks spawned in the transcript but not yet completed.
// Completion = the bg_<id> appears in any LATER message's text (OMO's
// [BACKGROUND TASK COMPLETED] system-reminder quotes the id). A spawn whose
// output carries no trackable bg_ id counts as pending (conservative: assume
// armed rather than false-wake a legitimately-waiting session).
function pendingBackgroundTasks(messages) {
  let pending = 0;
  for (let i = 0; i < messages.length; i++) {
    const parts = Array.isArray(messages[i]?.parts) ? messages[i].parts : [];
    for (const part of parts) {
      if (part?.type !== "tool") continue;
      if (part?.state?.input?.run_in_background !== true) continue;
      const out = typeof part?.state?.output === "string" ? part.state.output : "";
      const ids = [...out.matchAll(BG_ID_RE)].map((m) => m[0]);
      if (ids.length === 0) {
        pending += 1;
        continue;
      }
      const laterText = messages
        .slice(i + 1)
        .map((m) => textOf(m?.parts))
        .join("\n");
      for (const id of ids) {
        if (!laterText.includes(id)) pending += 1;
      }
    }
  }
  return pending;
}

function snippetAround(text, index, radius = 90) {
  const start = Math.max(0, index - radius);
  const end = Math.min(text.length, index + radius);
  return text.slice(start, end).replace(/\s+/g, " ").trim();
}

// Evaluate one session's messages at idle; returns {ok:true, phrase, detail}
// when the session ended on an unbacked monitoring promise, else
// {ok:false, reason} explaining the skip.
export function evaluatePromise(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return { ok: false, reason: "no-messages" };
  const last = messages[messages.length - 1];
  const info = last?.info ?? last;
  const parts = Array.isArray(last?.parts) ? last.parts : [];
  if (info?.role !== "assistant") return { ok: false, reason: "last-not-assistant" };
  if (!info?.time?.completed) return { ok: false, reason: "message-incomplete" };
  const running = parts.some((p) => p?.type === "tool" && p?.state?.status === "running");
  if (running) return { ok: false, reason: "running-tool-part" };
  const text = textOf(parts);
  if (!text.trim()) return { ok: false, reason: "no-text" };
  const hit = PROMISE_PATTERNS.map((re) => re.exec(text)).find(Boolean);
  if (!hit) return { ok: false, reason: "no-promise" };
  const phrase = snippetAround(text, hit.index);
  if (ARMED_TEXT_RE.test(text)) return { ok: false, reason: "armed-text", phrase };
  const pending = pendingBackgroundTasks(messages);
  if (pending > 0) return { ok: false, reason: `pending-bg-tasks(${pending})`, phrase };
  return { ok: true, reason: "promise", phrase, detail: `unbacked promise: "${phrase}"` };
}

const wakePrompt = (phrase) =>
  "AUTOMATED WAKE (promise-catcher): your previous turn ended with a monitoring promise " +
  `("${phrase}") and no wake trigger is armed. A turn-based agent has no clock — nothing ` +
  "would have re-started this session. Act now, exactly one of:\n" +
  "1. Execute the monitoring in THIS turn: bounded sleeps (<=60s per tool call) with a " +
  "status probe after each wait, backoff between probes (30s -> 60s -> 120s -> 240s, " +
  "cap ~8 min), circuit-break on repeated identical failures.\n" +
  "2. Arm a real wake trigger: spawn a run_in_background watcher subagent that probes " +
  "the job on your behalf and returns the verdict; then end the turn stating you are " +
  "waiting on it.\n" +
  "Do NOT end this turn with another unbacked monitoring promise.";

export const PromiseCatcher = async (ctx) => {
  log("info", `PromiseCatcher initialized (pid ${process.pid}, directory ${ctx.directory ?? "unknown"}, log ${logPath()})`);

  const wakeCounts = new Map(); // sessionID -> injections so far
  const wokenMsgIds = new Set(); // assistant message IDs already woken for
  const deadLettered = new Set();
  let handling = false;

  const q = () => (ctx.directory ? { query: { directory: ctx.directory } } : {});

  async function handleIdle(sessionID) {
    if (handling) return;
    handling = true;
    try {
      const cfg = loadConfig(); // hot-reloaded per event
      if (!cfg.enabled) return;

      let info = null;
      try {
        const listed = await ctx.client.session.list(q());
        const sessions = Array.isArray(listed?.data) ? listed.data : Array.isArray(listed) ? listed : [];
        info = sessions.find((s) => (s?.info ?? s)?.id === sessionID)?.info ?? null;
      } catch (error) {
        log("warn", `session.list failed: ${error?.message ?? error}`);
        return;
      }
      if (!info) return; // not in this instance's directory scope
      if (info.parentID) return; // child sessions: OMO retry/wake machinery governs
      if (cfg.exempt_sessions.includes(sessionID)) return;
      if (cfg.exempt_directories.some((d) => info.directory === d)) return;

      let msgs;
      try {
        const res = await ctx.client.session.messages({ path: { id: sessionID }, ...q() });
        msgs = res?.data ?? res;
      } catch (error) {
        log("warn", `messages fetch failed for ${sessionID}: ${error?.message ?? error}`);
        return;
      }

      const verdict = evaluatePromise(msgs);
      if (!verdict.ok) return;

      const lastMsgId = (msgs[msgs.length - 1]?.info ?? msgs[msgs.length - 1])?.id;
      if (lastMsgId && wokenMsgIds.has(lastMsgId)) return;

      const count = wakeCounts.get(sessionID) ?? 0;
      if (count >= cfg.max_wakes_per_session) {
        if (!deadLettered.has(sessionID)) {
          deadLettered.add(sessionID);
          log("warn", `dead-letter session ${sessionID}: ${count} wake injections exhausted; no further automatic action`);
          await surfaceToast(ctx, {
            title: "Promise-catcher: dead-letter",
            message: `Session ${sessionID} ended on an unbacked promise again after ${count} wakes; manual attention required.`,
            variant: "warning",
            duration: 12000,
          });
        }
        return;
      }

      const action = cfg.dry_run ? "WOULD wake" : "waking";
      log("info", `${action} session ${sessionID}: ${verdict.detail}`);
      await surfaceToast(ctx, {
        title: cfg.dry_run ? "Promise-catcher (dry-run)" : "Promise-catcher: unbacked promise caught",
        message: `${cfg.dry_run ? "Would wake" : "Waking"} session ${sessionID}: turn ended on ${verdict.detail}`,
        variant: cfg.dry_run ? "info" : "warning",
      });
      if (cfg.dry_run) return;

      try {
        await ctx.client.session.promptAsync({
          path: { id: sessionID },
          ...q(),
          body: { parts: [{ type: "text", text: wakePrompt(verdict.phrase) }] },
        });
        wakeCounts.set(sessionID, count + 1);
        if (lastMsgId) wokenMsgIds.add(lastMsgId);
        log("info", `wake dispatched for ${sessionID} (attempt ${count + 1}/${cfg.max_wakes_per_session})`);
      } catch (error) {
        log("warn", `wake injection failed for ${sessionID}: ${error?.message ?? error}`);
      }
    } finally {
      handling = false;
    }
  }

  return {
    event: async ({ event }) => {
      try {
        // session.idle is deprecated in the schema; the live signal is
        // session.status with status.type === "idle".
        if (event?.type === "session.status" && event?.properties?.status?.type === "idle") {
          const sid = event?.properties?.sessionID;
          if (sid) await handleIdle(sid);
        }
      } catch (error) {
        log("warn", `event handler failed: ${error?.message ?? error}`);
      }
    },
  };
};

export default PromiseCatcher;
