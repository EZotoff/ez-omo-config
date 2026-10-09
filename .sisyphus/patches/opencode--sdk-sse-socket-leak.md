---
patch_id: "opencode--sdk-sse-socket-leak"
dependency: "opencode"
target_file: "packages/sdk/js/src/gen/core/serverSentEvents.gen.ts"
target_install_path: "/home/ezotoff/src/opencode/packages/sdk/js/src/gen/core/serverSentEvents.gen.ts"
surfaces:
  - tui-interactive
  - cli-run
status: "active"
applied_date: "2026-09-29"
dep_version: "1.18.31-p4"
verification_pattern: "releaseLock"
verification_strength: "weak"
required_evidence: "runtime"
runtime_effective: true
runtime_effective_note: "Verified live 2026-09-29 ~20:10 CEST on 1.18.31-p2 (build 3787fd6b): unit A/B probe against a live server — unpatched source leaves 1 established socket after early `for await` break (exit 1); patched source leaves 0 (exit 0). Fresh attach socket population stable at 18/18/18 over 55s (Bun keep-alive pool, no growth)."
---

# OpenCode SDK SSE client: guaranteed connection teardown on generator exit

## Problem
`createSseClient.createStream`'s inner `finally` called only `signal.removeEventListener(...)` + `reader.releaseLock()`. When a consumer exited the event stream early (`break` out of `for await`, generator `.return()` — the `opencode run` stream.transport close path and any paned TUI consumer), the underlying fetch socket stayed established forever. `opencode attach` accumulated 19 live SSE sockets at birth and 30-40+ over ~30 minutes; every abandoned socket kept receiving the full server event broadcast.

## Patch Description
Per fetch iteration, a local `AbortController` (`conn`) is created; caller-signal aborts are forwarded onto it; `fetch` uses `conn.signal`. The generator `finally` (and the per-iteration `finally` covering pre-reader failures) always calls `conn.abort()` — aborting terminates the in-flight connection (the same AbortSignal mechanism the codebase already relies on) — plus `await reader.cancel().catch(...)` as secondary cleanup, then `releaseLock`. Natural completion is unaffected (abort after done is a no-op; the SDK retry loop is untouched, each attempt on a fresh controller).

## Runtime Verification
1. Unit A/B (discriminating): subscribe via the workspace SDK, consume 2 events, `break`; count own established sockets 3s later. Patched: 0 (PASS). Unpatched (`git checkout 48eedf9406 -- <file>`): 1 leaked (FAIL).
2. `opencode attach` socket count stable over minutes (no growth).
3. Server restart while attach is open → reconnect → count stable.

## Notes
- `verification_pattern` (`releaseLock`) is intentionally weak: minification renames the locals and strips comments, so no source-marker survives. `runtime_effective` + the Runtime Verification section are the authoritative signals per the binary-patch policy.
- No upstream fix: `serverSentEvents.gen.ts` unchanged v1.18.5 → v2.0.11. Related: upstream issues #28492, #34574, #46035 (dead-SSE-client accumulation class).
