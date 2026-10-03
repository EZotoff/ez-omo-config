---
patch_id: "opencode--sse-queue-bounded"
dependency: "opencode"
target_file: "packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts, packages/opencode/src/server/routes/instance/httpapi/handlers/global.ts"
target_install_path: "/home/ezotoff/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/"
surfaces: "server-api"
status: "active"
applied_date: "2026-09-30"
dep_version: "1.18.31-p3"
verification_pattern: "bufferSize:256"
verification_strength: "discriminative"
required_evidence: "runtime"
upstream_issue: "https://github.com/anomalyco/opencode/issues/45215"
runtime_effective: true
runtime_effective_note: "Verified live 2026-09-30 ~08:40 CEST on build 8b932b7e (generation opencode-1.18.31-patches.2): five parallel streaming sessions on 3030 — lo 11/11 samples <=1.26 MiB/s (pre-fix: 9-17.6), RSS amplitude ~0.5 GB flat baseline 1.8 GB (pre-fix: 1.2 GB oscillation, 4.9 GB idle balloons), zero restarts, all five completed. G4a unit: Stream.callback bufferSize 4 sliding fed 10 -> consumer sees [7,8,9,10] (drop-oldest proven at pinned effect 4.0.0-beta.83, Stream.ts:777; Queue.ts:526)."
---

# Bound SSE subscriber event queues (drop-oldest sliding, 256)

## Problem
Every SSE subscriber got an UNBOUNDED Effect queue (`Queue.unbounded` in event.ts `eventResponse()`; `Stream.callback` default in global.ts). A slow/stalled consumer accumulated unlimited event payloads — with parts carrying full text this reached GB-scale RSS oscillation (measured 1.5→2.7 GB in 80s single-session; servers ballooned to 4.9 GB idle) → zram exhaustion → server stalls → keeper restarts killing sessions. Upstream: #45215 (exact match, OPEN), fix PR #31922 bot-reaped unmerged.

## Patch
- event.ts: `Queue.sliding<EventV2.Payload>(256)` — drop-oldest, publisher never blocks (offerUnsafe unchanged).
- global.ts: `Stream.callback(fn, { bufferSize: 256, strategy: "sliding" })`.

Worst-case cap: 256 × ~500 KB pathological part = 128 MB/subscriber, 640 MB aggregate for five; realistic ~180 KB.

## Dropped-event recovery
TUI `sync.tsx:392` reconciles the FULL part on `message.part.updated` — dropped deltas repaired by the next snapshot. The only lossless-requirement consumer (workspace sync) runs solely for REMOTE workspace targets (workspace.ts:369 early-return for local) — none configured on this fleet.

## Known limitation
Remote-workspace deployments could lose durable sync events on an open sliding connection (no overflow-triggered resync). Out of scope locally; the proper fix (overflow marker → reconnect → /sync/history) noted for upstream engagement via #45215.

## Related
CLOSE_WAIT zombie SSE sockets (client half-close, #22198 class) accumulate during heavy activity and self-heal via RST reaping; with bounded queues their cost is capped. A server-side reaper is future work.
