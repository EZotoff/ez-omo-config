---
patch_id: "omo--fallback-toast-origin"
dependency: "oh-my-openagent"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-08-05"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "formatFallbackOrigin"
surfaces: ["server-api"]
runtime_effective: false
note: "Live dist patch (Bun-minified bundle, NOT source). target_file is dist/index.js, the shipped artifact loaded by `file://` from opencode.json. Source-level reapply is NOT possible; see Reapply Instructions for the dist-level reapply procedure. verification_pattern is a function name — Bun minification preserves declared function names, so the pattern is a minification-survivor; pattern match is necessary but NOT sufficient. The ## Runtime Verification section is the only sufficient check."
---

# Fallback Toast Names the Originating Agent/Session

## Problem

When OMO's runtime-fallback hook dispatches a model fallback (e.g. oracle on `openai/gpt-5.6-sol` falling back to `kimi-for-coding-oauth/k3`), it fires a TUI toast via `deps.ctx.client.tui.showToast` inside `dispatchFallbackRetry` (dist `index.js`, toast callsite at the `Model Fallback` title). The toast body's `message` was built solely by `resolveDispatchMessage(dispatchOutcome, result.newModel)`, which produces strings like `Switched to k3 for next request`. The toast carries **no indication of which session or agent fell back**.

Concrete incident: session `ses_036d6347bffeM6h3s1NBznVUXt`. An unlabeled "Switched to k3" toast fired from an oracle subagent's fallback path while a separate mephistopheles stall was being investigated. With no session/agent label on the toast, the fallback was initially misattributed to the mephistopheles stall, muddying the diagnosis. The toast needs to name its origin so a single "Switched to k3" popup is self-identifying when multiple subagents are running.

## Patch Description

**Files changed (1):** `dist/index.js` — two disjoint edits inside the runtime-fallback hook region (lines ~116503-116538). No other region touched (the durable-log-path patch at line 5220 is disjoint and already tracked separately).

**Edit 1 — new helper immediately above `dispatchFallbackRetry` (inserted at dist line 116503, before the `async function dispatchFallbackRetry` declaration):**

```js
function formatFallbackOrigin(options) {
  const agent = typeof options?.resolvedAgent === "string" ? options.resolvedAgent : undefined;
  const sid = typeof options?.sessionID === "string" ? options.sessionID.slice(-6) : "?";
  return ` [${agent || "session"}:…${sid}]`;
}
```

**Edit 2 — extend the toast `message:` property (dist line ~116538, inside `dispatchFallbackRetry`'s `if (deps.config.notify_on_fallback)` block):**

Before:
```js
message: resolveDispatchMessage(dispatchOutcome, result.newModel),
```

After:
```js
message: resolveDispatchMessage(dispatchOutcome, result.newModel) + formatFallbackOrigin(options),
```

Net effect: every fallback toast now reads e.g. `Switched to k3 for next request [oracle:…NBznVU]` when `resolvedAgent` is known, or `Switched to k3 for next request [session:…NBznVU]` when it is not. The 6-char session suffix is enough to disambiguate concurrent subagents without leaking the full session ID into a transient popup.

### Shape of `resolvedAgent` (verified at this dep_version)

`options.resolvedAgent` reaches `dispatchFallbackRetry` from the four session-status/event callsites (dist lines 116691, 116904, 117072, 117329). Its producer is `helpers.resolveAgentForSessionFromContext` (`createAgentContextResolver`, dist line 115719), which returns the lowercased agent name string produced by `normalizeAgentName` (dist line 115679 — returns `agent.toLowerCase().trim()` matched against `AGENT_NAMES`, or undefined) or `undefined`. **It is always either a string agent name (e.g. `"oracle"`, `"atlas"`) or `undefined` — never an object.** The `typeof ... === "string"` guard in `formatFallbackOrigin` therefore never needs to dig into a sub-property; the plan's fallback-to-`[session:…<sid>]` form covers the `undefined` case.

### What is NOT changed

- The toast `title` (`"Model Fallback"`), `variant` (`"warning"`), and `duration` (`5000`) are untouched.
- `resolveDispatchMessage` itself is untouched.
- Fallback dispatch behavior, model ordering, `prepareFallback`, `autoRetryWithFallback`, and `session.status` handling are untouched.
- The `.catch(() => {})` swallow on the toast call is preserved.

## Verification

**Pattern (necessary, not sufficient for a binary patch):**

```bash
# formatFallbackOrigin is a declared function name. Bun minification preserves
# declared function names, so a match proves the string is IN the bundle, NOT
# that the runtime is invoking it. See Runtime Verification for the sufficient check.
grep -c 'formatFallbackOrigin' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # must be >= 2 (definition + callsite)

# Regression guard: the toast title string must still be present (proves the edit
# did not accidentally remove the toast path).
grep -c 'Model Fallback' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js          # must be >= 1
```

**Diff scope (necessary):**

```bash
# Exactly two changed regions: a 6-line insert (helper + blank) above dispatchFallbackRetry,
# and a one-line message-property extension at the toast callsite.
diff /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js.pre-toast-origin.<ts> \
     /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js
```

## Runtime Verification

The `verification_pattern` (`formatFallbackOrigin`) is a function name that survives Bun minification, so a grep match is necessary but NOT sufficient. The only sufficient check is observing a real fallback toast whose message ends in `[<agent|session>:…<6-char-sid>]`.

**Steps (run in todo 9 after the `systemctl --user restart opencode.service omo-tg.service`):**

1. Confirm the restart actually happened (AGENTS.md rule 6):
   ```bash
   ps -eo pid,lstart,etime,args | grep 'opencode serve' | grep -v grep
   # start time must be newer than the restart command's timestamp
   ```
2. Wait for a natural fallback to occur (cannot be forced on demand without a real provider error). When a fallback toast fires, capture its rendered message. The message MUST now end in a bracketed origin tag, e.g.:
   - `Switched to k3 for next request [oracle:…NBznVU]` (agent known), or
   - `Switched to k3 for next request [session:…NBznVU]` (agent unknown).
3. Cross-check the suffix against the OMO log to confirm the tag identifies the session that actually fell back:
   ```bash
   tail -50 ~/.local/share/opencode/logs/oh-my-opencode.log | grep -i fallback
   # the sessionID in the log line must end with the same 6 chars shown in the toast
   ```
4. If the toast renders WITHOUT the bracketed tag (or the toast fails to fire at all when a fallback is logged), the patch is `runtime-ineffective`. Roll back via the timestamped backup (`cp <backup> dist/index.js`) and redesign — do NOT bump `dep_version` or flip `runtime_effective`.

**Regression signal:** `grep -c 'Model Fallback' dist/index.js` returning 0 would indicate the toast path was damaged; this is already covered as a repo-level gate.

If steps 1-3 pass with a real observation, flip `runtime_effective: true` in this entry's frontmatter and record the observation (toast text + log line + timestamp) in a `## Runtime Status` section.

If NO natural fallback occurs during the verification window, leave `runtime_effective: false`. The patch is structurally correct (gates pass) but runtime effectiveness remains unobserved; the final report must state `Not verified live: toast rendering`.

## Reapply Instructions

This is a dist-level patch on a minified bundle, not a source patch. Identify the active symbol locations in the TARGET version first — line numbers will drift, but the function names (`dispatchFallbackRetry`, `resolveDispatchMessage`) and the toast title literal (`"Model Fallback"`) are minification-survivors and will be greppable.

1. Locate the `dispatchFallbackRetry` definition:
   ```bash
   grep -n 'async function dispatchFallbackRetry' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js
   ```
2. Locate the toast callsite inside it (the `title: "Model Fallback"` literal is the stable anchor):
   ```bash
   grep -n 'Model Fallback' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js
   ```
3. Read ~10 lines around the toast callsite and confirm the `message:` property still reads `resolveDispatchMessage(dispatchOutcome, result.newModel)`. If a future OMO version changed the message builder, re-derive the patch against the new callsite rather than blindly reapplying.
4. Confirm `options.resolvedAgent` is still a string-or-undefined at the new version (grep for `createAgentContextResolver` / `normalizeAgentName` and read their return shape). If it became an object, update `formatFallbackOrigin` to read the appropriate name-ish property.
5. Timestamped backup:
   ```bash
   cp /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js \
      /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js.pre-toast-origin.$(date +%s)
   ```
6. Insert the `formatFallbackOrigin` function definition immediately ABOVE the `async function dispatchFallbackRetry` declaration (with a blank line separator).
7. Replace the `message:` property value with `<existing message expression> + formatFallbackOrigin(options)`.
8. Run the Verification gates (grep counts) and the Runtime Verification steps after restart.

## Durable Alternative

A config option in `oh-my-openagent.json` (e.g. `runtime_fallback.toast_label_template` or `runtime_fallback.include_session_in_toast: true`) that the upstream `dispatchFallbackRetry` consults when building the toast message would let operators enable origin labeling without a dist patch. Upstreaming the agent/session tag into the stock toast message (always on, or behind a config flag) is the cleanest fix and would make this patch disappear on the next OMO version that includes it.

Status: not-yet-pursued — no upstream config option exists for toast labeling in OMO v4.19.2. An upstream issue/PR could propose appending the resolved agent + session suffix to the fallback toast message directly in `dispatchFallbackRetry` (or behind a `runtime_fallback.toast_label_template` config field) to eliminate this patch.
