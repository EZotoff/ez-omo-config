// Pure detection helpers for promise-catcher.mjs — NOT a plugin module; lives in a
// subdirectory so the OpenCode plugin loader and regression 018's top-level
// export-surface scan never treat it as a plugin (review-enforcer helpers.ts
// precedent, 2026-09-08 incident).

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

// Count background tasks spawned RECENTLY but not yet completed. Bounded to
// the trailing window (last BG_WINDOW messages): long bench sessions
// accumulate dozens of historical spawns, and a single stale never-completed
// spawn must not suppress wakes forever (2026-10-01 dry-run audit: 7mJjPC,
// 71 spawns). Completion = the bg_<id> appears in any LATER message's text
// (OMO's [BACKGROUND TASK COMPLETED] system-reminder quotes the id). A spawn
// whose output carries no trackable bg_ id counts as pending (conservative:
// assume armed rather than false-wake a legitimately-waiting session).
const BG_WINDOW = 40;
function pendingBackgroundTasks(messages) {
  const window = messages.slice(-BG_WINDOW);
  let pending = 0;
  for (let i = 0; i < window.length; i++) {
    const parts = Array.isArray(window[i]?.parts) ? window[i].parts : [];
    for (const part of parts) {
      if (part?.type !== "tool") continue;
      if (part?.state?.input?.run_in_background !== true) continue;
      const out = typeof part?.state?.output === "string" ? part.state.output : "";
      const ids = [...out.matchAll(BG_ID_RE)].map((m) => m[0]);
      if (ids.length === 0) {
        pending += 1;
        continue;
      }
      const laterText = window
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
