import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// Busy-stall reaper — server plugin.
//
// Root causes addressed (2026-09-22 diagnosis, see docs/plugins.md):
//   RC1  silent model-stream hang: assistant message created, zero output
//        tokens, never completes, no error event -> session busy forever and
//        no retry machinery fires (retry only reacts to FAILURES).
//   RC2/RC3  tool calls / background_output awaits that outlive their own
//        declared timeout (wedge propagates: parent awaits child forever).
//
// Detection is session-level, so it catches all wedge classes without binary
// patches: a top-level session whose newest message shows no progress past a
// deadline is aborted (interrupt) and re-kicked with a continuation prompt,
// which routes through the normal retry/fallback machinery on the next turn.
//
// User-facing output MUST go through ctx.client.tui.showToast (see
// surfaceToast); console.* leaks into the TUI viewport / journald as spam.
// Test-isolation hook via globalThis (same pattern as provider-connect-retry).
const testPaths = () => globalThis.__busyStallReaperTestPaths ?? {};
const PATHS = {
  config: path.join(os.homedir(), ".config", "opencode", "busy-stall-reaper.json"),
  log: path.join(os.homedir(), ".config", "opencode", "busy-stall-reaper.log"),
};
const configPath = () => testPaths().config ?? PATHS.config;
const logPath = () => testPaths().log ?? PATHS.log;

const LOG_MAX_BYTES = 2 * 1024 * 1024; // rotate at 2 MB, one .1 backup
const SCAN_INTERVAL_MS = 60_000;
const SILENT_STALL_MS_DEFAULT = 10 * 60_000; // incomplete message, no part updates
const TOOL_NO_TIMEOUT_FLOOR_MS = 30 * 60_000; // running tool without declared timeout
const TOOL_DECLARED_GRACE_MS = 90_000; // declared timeout + cleanup grace
const TOOL_MIN_DEADLINE_MS = 150_000;
const RETRY_GRACE_MS = 60_000; // skip sessions in retry until next + grace
const MAX_REAPS_PER_SESSION = 3; // dead-letter after this many reap attempts

const DEFAULTS = {
  enabled: true,
  dry_run: true,
  silent_stall_ms: SILENT_STALL_MS_DEFAULT,
  tool_no_timeout_floor_ms: TOOL_NO_TIMEOUT_FLOOR_MS,
  max_reaps_per_session: MAX_REAPS_PER_SESSION,
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

const CONTINUE_PROMPT =
  "Your previous turn stalled with no progress for an extended period " +
  "(likely a provider stream stall or a wedged tool call). The busy-stall " +
  "watchdog aborted it. Re-check the current state (files, running " +
  "processes, background tasks via background_output) and continue the " +
  "work from where it stopped. Do not repeat already-completed steps.";

function toolDeadlineMs(part, cfg) {
  const declared = Number(part?.state?.input?.timeout);
  if (Number.isFinite(declared) && declared > 0) {
    return Math.max(declared + TOOL_DECLARED_GRACE_MS, TOOL_MIN_DEADLINE_MS);
  }
  return cfg.tool_no_timeout_floor_ms;
}

// Evaluate one session's messages; returns {rule, detail} when stalled.
function evaluateSession(messages, now, cfg, liveRef = 0) {
  if (!Array.isArray(messages) || messages.length === 0) return null;
  const last = messages[messages.length - 1];
  const info = last?.info ?? last;
  const parts = Array.isArray(last?.parts) ? last.parts : [];
  const lastProgressAt = Math.max(
    Number(info?.time?.created) || 0,
    liveRef,
    ...parts.map((p) => Number(p?.time?.start) || 0),
  );

  // Rule T: a running tool part past its deadline (wedge, incl. bash with a
  // declared timeout that never fired and background_output awaits).
  for (const part of parts) {
    if (part?.type !== "tool" || part?.state?.status !== "running") continue;
    const startedAt = Number(part?.state?.time?.start) || 0;
    if (!startedAt) continue;
    const deadline = toolDeadlineMs(part, cfg);
    if (now - startedAt > deadline) {
      return {
        rule: "T",
        detail: `tool "${part.tool}" running ${Math.round((now - startedAt) / 1000)}s past ${Math.round(deadline / 1000)}s deadline`,
        lastProgressAt,
      };
    }
  }

  // Rule S: newest message incomplete with zero output tokens and no part
  // activity past the silent window (silent model-stream hang; also covers a
  // delivered user prompt that never produced an assistant message).
  // liveRef carries live event-bus activity: a still-streaming reasoning part
  // keeps time.start at its start, so only event freshness proves progress.
  const incomplete = info?.role === "assistant" && !info?.time?.completed;
  const silentUser = info?.role === "user" && !messages.some((m) => (m?.info ?? m)?.role === "assistant");
  if ((incomplete || silentUser) && (Number(info?.tokens?.output) || 0) === 0) {
    const ref = Math.max(lastProgressAt, liveRef) || Number(info?.time?.created) || 0;
    if (ref && now - ref > cfg.silent_stall_ms) {
      return {
        rule: "S",
        detail: `${info?.role} message silent ${Math.round((now - ref) / 1000)}s (threshold ${Math.round(cfg.silent_stall_ms / 1000)}s), output=0, incomplete`,
        lastProgressAt: ref,
      };
    }
  }
  return null;
}

export const BusyStallReaper = async (ctx) => {
  const cfg = loadConfig();
  log("info", `BusyStallReaper initialized (pid ${process.pid}, directory ${ctx.directory ?? "unknown"}, log ${logPath()})`);

  const statusTrack = new Map(); // sessionID -> {type, next}
  const lastActivity = new Map(); // sessionID -> epoch ms of last live part/message event
  const reapCounts = new Map(); // sessionID -> attempts
  const deadLettered = new Set();
  let scanning = false;

  const q = () => (ctx.directory ? { query: { directory: ctx.directory } } : {});

  async function reap(sessionID, verdict, cfg) {
    const count = reapCounts.get(sessionID) ?? 0;
    if (count >= cfg.max_reaps_per_session) {
      if (!deadLettered.has(sessionID)) {
        deadLettered.add(sessionID);
        log("warn", `dead-letter session ${sessionID}: ${count} reap attempts exhausted; no further automatic action`);
        await surfaceToast(ctx, {
          title: "Stall watchdog: dead-letter",
          message: `Session ${sessionID} stalled again after ${count} automatic interventions; manual attention required.`,
          variant: "warning",
          duration: 12000,
        });
      }
      return;
    }
    const action = cfg.dry_run ? "WOULD reap" : "reaping";
    log("info", `${action} session ${sessionID} rule=${verdict.rule}: ${verdict.detail}`);
    await surfaceToast(ctx, {
      title: cfg.dry_run ? "Stall watchdog (dry-run)" : "Stall watchdog: stalled session reaped",
      message: `${cfg.dry_run ? "Would abort" : "Aborted"} stalled session ${sessionID} (rule ${verdict.rule}: ${verdict.detail}).`,
      variant: cfg.dry_run ? "info" : "warning",
    });
    if (cfg.dry_run) return;

    try {
      await ctx.client.session.abort({ path: { id: sessionID }, ...q() }).catch(() => {});
      await new Promise((r) => setTimeout(r, 1500));
      await ctx.client.session.promptAsync({
        path: { id: sessionID },
        ...q(),
        body: { parts: [{ type: "text", text: CONTINUE_PROMPT }] },
      });
      reapCounts.set(sessionID, count + 1);
      log("info", `reaped session ${sessionID}: abort+continuation dispatched (attempt ${count + 1}/${cfg.max_reaps_per_session})`);
    } catch (error) {
      log("warn", `reap of ${sessionID} failed: ${error?.message ?? error}`);
    }
  }

  async function scan() {
    if (scanning) return;
    scanning = true;
    try {
      const cfg = loadConfig(); // hot-reloaded every scan
      if (!cfg.enabled) return;
      const listed = await ctx.client.session.list(q());
      const sessions = Array.isArray(listed?.data) ? listed.data : Array.isArray(listed) ? listed : [];
      const now = Date.now();
      for (const s of sessions) {
        const info = s?.info ?? s;
        const sid = info?.id;
        if (!sid) continue;
        if (info?.parentID) continue; // child sessions: OMO retry machinery governs
        if (cfg.exempt_sessions.includes(sid)) continue;
        if (cfg.exempt_directories.some((d) => info?.directory === d)) continue;
        const st = statusTrack.get(sid);
        if (st?.type === "retry" && (!st.next || now < Number(st.next) + RETRY_GRACE_MS)) continue;
        let msgs;
        try {
          const res = await ctx.client.session.messages({ path: { id: sid }, ...q() });
          msgs = res?.data ?? res;
        } catch (error) {
          log("warn", `messages fetch failed for ${sid}: ${error?.message ?? error}`);
          continue;
        }
        const verdict = evaluateSession(msgs, now, cfg, lastActivity.get(sid) ?? 0);
        if (verdict) await reap(sid, verdict, cfg);
      }
    } catch (error) {
      log("warn", `scan failed: ${error?.message ?? error}`);
    } finally {
      scanning = false;
    }
  }

  const timer = setInterval(scan, SCAN_INTERVAL_MS);
  if (typeof timer?.unref === "function") timer.unref();
  setTimeout(scan, 5_000).unref?.(); // first pass shortly after startup

  return {
    event: async ({ event }) => {
      try {
        const props = event?.properties ?? {};
        if (event?.type === "session.status") {
          const sid = props?.sessionID;
          const status = props?.status;
          if (sid && status) statusTrack.set(sid, { type: status.type, next: status.next });
        } else if (event?.type === "message.part.updated" || event?.type === "message.updated") {
          const sid = props?.info?.sessionID ?? props?.part?.sessionID;
          if (sid) lastActivity.set(sid, Date.now());
        }
      } catch {}
    },
  };
};

export default BusyStallReaper;
