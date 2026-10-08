# Supervisor thrash root cause + diet — 2026-10-08

Operator demand: "you were supposed to find out the root cause of the thrash."

## Root cause (each step observed, not inferred)

1. **Amplification**: the supervisor's reconcile fetched transcripts for EVERY in-window session on every sweep — `initial_window_days: 7` ⇒ ~2,209 sessions / ~54,810 messages in scope (measured 2026-10-07 via read-only sqlite), with no skip for unchanged sessions, and a full re-scan also fired on every session idle tick (service.ts processIdle) plus every 10-min periodic sweep. Each fetch is a per-request connection (64–172 established sockets observed from one bun client).
2. **Server heap**: to serve those fetches, the opencode server materializes message data into its Bun heap. Fresh :3021 (restarted 23:13) reached **2.75 GB anonymous (Private_Dirty) heap in 20 minutes** while supervisors restarted around it; the pre-restart instance held 3.7 GB over 26 h.
3. **Control group**: the three UNsupervised opencode servers (:3040 bench, :46946, :46457) sat at 166–300 MB. Only the supervised pair ballooned.
4. **Host**: two 2.7 GB servers + supervisor ~1 GB + winnow 1.4 GB + neo4j + chromes + desktop > 32 GB RAM ⇒ 15–40 GB swap ⇒ 24 s API latencies ⇒ the supervisor's 15 s client timeouts fail ⇒ the "error peak" in OC Beacon. The peak is the alarm, not the fire.
5. **Enablers**: `opencode.service.d/memory-cap.conf` (MemoryHigh=4G, committed 2026-09-30, 324c299) was **never installed live** (install.sh carried no `.d` entry; the transient `set-property` value survived, but the persistence promise was unmet); the headless unit had no `RuntimeMaxSec` recycle (the interactive unit did — 1d, and stayed healthier). Shutdown during a sweep hung ~5 min (fetches not abort-aware; boundedDrain from a8eeb40 covers the poll loops, not bootstrap/mid-sweep fetches). SSE-leak patches are provenance-verified but their runtime smokes FAIL — open defect per the deployment-closure rule.

## Fixes (this change)

- **Reconcile diet** (`reconcile.ts`): sessions whose `timeUpdatedMs` is unchanged reuse the previous scan — no transcript fetch; `ScanManifest.sessionMarks` carries the watermark map; child-session IDs carried forward. First sweep after restart is still full (now window-bounded).
- **Window**: `initial_window_days` 7→1 (schema default + live config).
- **Abort-aware shutdown**: `OpencodeClient.request/listSessions/listMessages` accept the shutdown signal (`AbortSignal.any` with the 15s timeout, no retry on abort); reconcile checks abort per fetch; service passes the signal + previous manifest.
- **Systemd**: `RuntimeMaxSec=86400` drop-in for `opencode.service` (mirrors interactive); both `memory-cap.conf` drop-ins (4G/6G) now actually installed (symlinked into live `.d`, previously uninstalled); `install.sh` ITEMS extended to carry all four server drop-in confs.

## Verification

- `repo_implemented` + `tests_passed`: `bun test` 374 pass / 0 fail (incl. new skip-unchanged, refetch-on-change, abort tests); `tsc --noEmit` clean; `bash -n install.sh` clean.
- Deploy evidence appended below after live restart + measurement.

## Deployment + live verification (2026-10-08 16:20-16:45 CEST)

- Commits: `933b538` (diet + shutdown + systemd), `1dc5736` (boot-reconcile regression fix, below).
- Boot reconcile with the diet: **4 seconds** after supervisor start (lastReconcile 14:40:21Z, start 14:40:17Z) — window 1d = 267 sessions.
- First dieted sweep: server RSS moved 630 → 653 MB; yesterday's equivalent restart cycle drove 2.75 GB in 20 min.
- Supervisor stop: bounded at the 120s drain force-exit with ledger receipt (was 5-min SIGKILL pre-a8eeb40). Residual wait = console/beacon/poller calls not yet signal-aware (follow-up).
- **Regression found + fixed during verification**: `a8eeb40`'s stop-drain refactor had DELETED the boot `Promise.all(activeRoots.map(reconcile))` — every supervisor restart since went blind (no poll loops, no ticks; modes empty; ledger silent). Restored in `1dc5736` with an abort guard; verified live: `modes` populated for 20 roots, boot reconcile 4 s, errors 0.
- 3021 recycled session-safe (resumed=0) at 16:33; RSS 646-757 MB through two dieted sweeps + resumed-session traffic.

Not verified live: TICK emission on this instance (needs an idle-session event; poll loops confirmed started via `status.modes` = 20 roots).
