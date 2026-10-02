// configs/opencode/skill-nudger/signals.mjs
// Sliding-window tool-call tracking + deterministic signal detection

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const RETRY_ERRORS_PATH = join(homedir(), ".config", "opencode", "retry-errors.json");

// A tool result is considered failed when its text matches this heuristic.
const FAILURE_RE =
  /(exit(?:ed)?(?: with)?(?: code)?\s*[1-9]\d*)|\berror\b|\bfailed\b|\btimeout\b|\bexception\b|\bcommand not found\b|\bno such file or directory\b|\bpermission denied\b|\btraceback\b/i;

// Commands that bind a network port / start a server (mirrors the global
// AGENTS.md deployment-skill mandate list).
const PORT_BINDING_RES = [
  /\b(?:npm|yarn|pnpm)\s+(?:run\s+)?dev\b/,
  /\bbun\s+run\s+dev\b/,
  /\bvite\b/,
  /\bnext\s+dev\b/,
  /\bnuxt\s+dev\b/,
  /\bng\s+serve\b/,
  /\bpython3?\s+-m\s+http\.server\b/,
  /\buvicorn\b/,
  /\bgunicorn\b/,
  /\bflask\s+run\b/,
  /\brails\s+s(?:erver)?\b/,
  /\bphp\s+artisan\s+serve\b/,
  /\bdocker\s+run\b[^&|;]*\s-p\b/,
  /\bdocker\s+compose\s+up\b/,
  /\bpodman\s+run\b[^&|;]*\s-p\b/,
  /\bkubectl\s+port-forward\b/,
];

// Commands that create upstream PRs/issues (mirrors the global AGENTS.md
// upstream-contribution pre-flight mandate).
const UPSTREAM_CONTRIBUTION_RE = /\bgh\s+(?:pr|issue)\s+create\b/;

// Commands that launch a detached / long-running job (mirrors the global
// AGENTS.md long-running-job monitoring and durable-execution rules).
const LONG_JOB_RE = /\b(?:systemd-run|durable-run|setsid|nohup)\b/;

let retryPatternsCache = null;

export function loadRetryPatterns() {
  if (retryPatternsCache) return retryPatternsCache;
  const compiled = [];
  try {
    const raw = JSON.parse(readFileSync(RETRY_ERRORS_PATH, "utf8"));
    for (const entry of raw?.errors ?? []) {
      if (!entry?.pattern) continue;
      try {
        compiled.push({ id: entry.id, re: new RegExp(entry.pattern, "i") });
      } catch {
        // Skip invalid regex entries
      }
    }
  } catch {
    // No registry / unreadable — no retryable-error signal
  }
  retryPatternsCache = compiled;
  return compiled;
}

// Test hook: force-reload the registry (harness swaps the cache)
export function __resetRetryPatternCache() {
  retryPatternsCache = null;
}

function stableFingerprint(tool, args) {
  if (tool === "bash" || tool === "terminal") {
    const cmd = typeof args?.command === "string" ? args.command.trim() : "";
    if (cmd) return `bash:${cmd}`;
  }
  if (tool === "tmux_command" || tool === "interactive_bash") {
    const cmd = typeof args?.tmux_command === "string" ? args.tmux_command.trim() : "";
    if (cmd) return `${tool}:${cmd}`;
  }
  const keys = args && typeof args === "object" ? Object.keys(args).sort() : [];
  const parts = keys.map((k) => `${k}=${JSON.stringify(args[k] ?? null)?.slice(0, 120)}`);
  return `${tool}:{${parts.join(",")}}`;
}

function isPortBinding(tool, args) {
  if (tool !== "bash" && tool !== "terminal") return false;
  const cmd = typeof args?.command === "string" ? args.command : "";
  return PORT_BINDING_RES.some((re) => re.test(cmd));
}

function isUpstreamContribution(tool, args) {
  if (tool !== "bash" && tool !== "terminal") return false;
  const cmd = typeof args?.command === "string" ? args.command : "";
  return UPSTREAM_CONTRIBUTION_RE.test(cmd);
}

function isLongJobLaunch(tool, args) {
  if (tool !== "bash" && tool !== "terminal") return false;
  const cmd = typeof args?.command === "string" ? args.command : "";
  return LONG_JOB_RE.test(cmd);
}

// True when this fingerprint had >= threshold consecutive failures earlier in
// the window and has now succeeded — the fix just landed, the lesson is fresh.
function hadResolvedFailureStreak(windows, sessionID, fp, threshold) {
  const w = windows.get(sessionID) ?? [];
  let run = 0;
  let maxRun = 0;
  for (const e of w) {
    if (e.fp !== fp) {
      run = 0;
      continue;
    }
    if (e.failed) {
      run += 1;
      if (run > maxRun) maxRun = run;
    } else {
      run = 0;
    }
  }
  return maxRun >= threshold;
}

export function createSignalTracker(config) {
  const windows = new Map(); // sessionID -> [{fp, failed, ts}]
  const counters = new Map(); // sessionID -> total observed calls

  function window(sessionID) {
    if (!windows.has(sessionID)) {
      windows.set(sessionID, []);
      counters.set(sessionID, 0);
    }
    return windows.get(sessionID);
  }

  function trim(sessionID) {
    const w = windows.get(sessionID);
    if (w && w.length > config.windowSize) {
      w.splice(0, w.length - config.windowSize);
    }
  }

  function countFingerprint(sessionID, fp) {
    const w = windows.get(sessionID) ?? [];
    return w.filter((e) => e.fp === fp).length;
  }

  function consecutiveFailures(sessionID, fp) {
    const w = windows.get(sessionID) ?? [];
    let n = 0;
    for (let i = w.length - 1; i >= 0; i--) {
      if (w[i].fp !== fp) break;
      if (!w[i].failed) break;
      n++;
    }
    return n;
  }

  /**
   * Observe one completed tool call. Returns detected signals (array, possibly empty).
   * Each signal: { type, skill, evidence }
   */
  function observe({ sessionID, tool, args, outputText }) {
    const fp = stableFingerprint(tool, args);
    const text = typeof outputText === "string" ? outputText : "";
    const failed = FAILURE_RE.test(text);
    const w = window(sessionID);
    w.push({ fp, failed, ts: Date.now() });
    trim(sessionID);
    counters.set(sessionID, (counters.get(sessionID) ?? 0) + 1);

    const signals = [];

    if (failed) {
      // retryable-error: output matches a registered retry pattern
      for (const { id, re } of loadRetryPatterns()) {
        if (re.test(text)) {
          signals.push({
            type: "retryableError",
            skill: "register-retry-error",
            evidence: `tool output matched retry pattern \`${id}\``,
          });
          break;
        }
      }

      // repeated-failure: same fingerprint failed N times consecutively
      const consec = consecutiveFailures(sessionID, fp);
      if (consec >= config.repeatFailureThreshold) {
        signals.push({
          type: "repeatedFailure",
          skill: "debugging",
          evidence: `same call failed ${consec} times in a row: \`${fp.slice(0, 80)}\``,
        });
      }
    }

    // port-binding: server-starting command observed
    if (isPortBinding(tool, args)) {
      signals.push({
        type: "portBinding",
        skill: "deployment",
        evidence: "a port-binding / server-start command was executed",
      });
    }
    // upstream-contribution: external PR/issue creation command observed
    if (isUpstreamContribution(tool, args)) {
      signals.push({
        type: "upstreamContribution",
        skill: "wisdom",
        evidence: "an upstream PR/issue creation command was executed (`gh pr/issue create`)",
      });
    }

    // loop-precursor: same fingerprint repeated heavily within the window
    const repeats = countFingerprint(sessionID, fp);
    if (repeats >= config.loopThreshold) {
      signals.push({
        type: "loop",
        skill: null, // meta-nudge, no skill
        evidence: `same call executed ${repeats} times within the last ${config.windowSize} tool calls: \`${fp.slice(0, 80)}\``,
      });
    }

    // learning-capture: detached / long-running job launched — capture the
    // operational facts and record a monitoring owner while context is fresh.
    // Appended LAST: the pending-nudge slot is one per session, so the
    // learning nudge must never preempt the higher-urgency rules above.
    if (isLongJobLaunch(tool, args)) {
      signals.push({
        type: "learningCapture",
        skill: "wisdom",
        evidence: "a detached / long-running job was launched (systemd-run / durable-run / nohup / setsid)",
      });
    } else if (
      !failed &&
      hadResolvedFailureStreak(windows, sessionID, fp, config.repeatFailureThreshold)
    ) {
      // learning-capture: a failure streak for this exact call just resolved —
      // the root cause / fix is established and uncaptured.
      signals.push({
        type: "learningCapture",
        skill: "wisdom",
        evidence: `a repeated-failure streak for this call just resolved: \`${fp.slice(0, 80)}\``,
      });
    }

    return signals;
  }

  function totalCalls(sessionID) {
    return counters.get(sessionID) ?? 0;
  }

  function deleteSession(sessionID) {
    windows.delete(sessionID);
    counters.delete(sessionID);
  }

  return { observe, totalCalls, deleteSession, __windows: windows };
}
