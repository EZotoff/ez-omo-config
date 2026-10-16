# Plan: Continuation false-positive Wave A (deterministic guards + measurement)

Operator-approved (supervisor relay, ledger seq 119865, 2026-10-16): wave A first, then
measure residual FPs, then OMO-leak drill only if the residual points at the consumption
leak, then ledger design B on clean data.

## Coordination conditions (operator-mandated, resolved here)

1. **Q24 same-file collision — resolved: no active claim.** Q24's plan
   (`restart-continuation-subagent-coverage.md`) is EXECUTED (Execution baseline
   `e9554f8953a7e67fd635c86ee738cb309dbf69ce`; children[] capture/resume machinery is live
   in `scripts/restart-with-continuation.sh`). Wave A builds ON TOP of that state; one
   change-stream, no concurrent editor (git clean, no commits from other agents in 3h+).
2. **Q2 settlement — flip condition MET, recorded.** `wake-redundancy-decision.md` REJECTed
   proposal #1 (consumption-aware flush) with a registered flip condition:
   ">50 redundant wakes/week". Measured 2026-10-16 (7-day window, real projects):
   **156 redundant wake FPs/week** — the condition is met 3× over. This plan's T1 is the
   CONFIG-SIDE complement (restart-union predicate), NOT the declined OMO-fork proposal;
   the OMO-fork consumption-aware flush re-enters the menu as the data-driven follow-up
   (option-2 drill) if post-wave-A residuals still point at the leak.
3. **Deploy discipline.** Hook-script changes are read fresh from disk at every restart —
   T1/T2/T3 self-deploy at the next 6h recycle; no restart is needed or performed by this
   plan. T4's daemon-reload + timer enablement JOIN the idle-window queue (currently
   carrying Q6, Q8, Q19's candidate) as the single integration point. T4 ships in
   observe mode per the rollout protocol.
4. **Before/after measurement is load-bearing.** Baseline (this plan, 7-day window ending
   2026-10-16, real projects, excluding /tmp test-corpus and session-learning dirs):

   | class        | nudges | FP  | TP  | precision |
   |--------------|--------|-----|-----|-----------|
   | wake         | 165    | 156 | 7   | 4%        |
   | maintenance  | 94     | 28  | 65  | 69%       |
   | child        | 4      | 4   | 0   | 0%        |
   | **total**    | 263    | 188 | 72  | **28.5%** |

   Also: 36 burst-minutes (same session, 2–12 identical nudges within 60s); wake-journal
   backlog 1170 `dispatched-awaiting-output` vs 78 consumed (2026-10-16).
   After ≥2 restart cycles post-deploy, `scripts/continuation-fp-report.py` reproduces
   this table in one command; success gate: wake-class precision ≥ 50% and total FP rate
   ≤ 25%, or the residual class analysis decides the option-2 drill.

## Root causes (evidence in the investigation transcript; ranked)

1. Wake-journal union re-kicks `dispatched-awaiting-output` sessions whose notifications
   already landed (OMO consumption-detection leak) — 95% of wake nudges are noise.
2. `resume()` top-level loop lacks the freshness guard that children/checkpoint paths
   have — sessions that finish during the restart gap get re-prompted anyway.
3. Dedup marker is check-then-write; both servers restart simultaneously and race the
   same shared STATE_DIR → up to 12 identical nudges/minute.
4. Fixed 6h RuntimeMaxSec recycles interrupt busy sessions 4×/day by design.
5. No outcome accounting — 96%-noise signal shipped for weeks unmeasured.

## Tasks

### T1 — wake-union parent-silence predicate (union_wakes)
- File: `scripts/restart-with-continuation.sh` (`union_wakes` python block only).
- For `state == dispatched-awaiting-output`: additionally require parent-silence —
  look up `session.time_updated` for `sessionID` in the shared DB (READ-ONLY; one
  connection, reused) and keep the wake ONLY IF `time_updated is None` OR
  `time_updated < age_basis * 1000`.
  **UNITS (Momus R1 critical fix): `age_basis()` returns SECONDS (ms→s via `v / 1000.0`);
  `session.time_updated` is MS epoch. The comparison MUST scale age_basis to ms.
  A bare `time_updated < age_basis` is unit-inconsistent and would drop nearly all wakes
  (false drops — the forbidden direction).**
- DB open failure → keep current behavior for that wake (fail-open: a dropped wake
  strands compute; a redundant one costs one turn — wake-redundancy-decision asymmetry).
- Consume the check for ALL union callers (hook-resume snapshot path, checkpoint path,
  db_fallback path, standalone converge path) — single function, all four call sites.
- Must NOT: change MAX_WAKE_AGE_SECONDS, touch OMO wake files, edit wake states.

### T2 — top-level resume freshness guard (resume())
- File: same script, `resume()` top-level sessions loop.
- Before the dedup marker: if `s["directory"]` present AND `s.get("status") != "wake-pending"`
  (Momus R1 fix: wake-pending entries DO carry directory and captured_at_ms — enforce the
  exclusion IN the condition, not by reader inference), GET `/session?directory=...`
  (dir-cached, as the children loop already does); if `time.updated > captured_at_ms` →
  `skip-stale`, continue. Fail-open: lookup failure → proceed as today. Scope note:
  `resume()` consumes ONLY snapshot files (hook path, standalone, --resume-only);
  checkpoint and db_fallback files are separate python blocks that already carry
  created_ms guards — no edit needed there.

### T3 — atomic dedup claim (all three python resume blocks)
- Replace check-then-write marker logic with `os.open(marker, O_CREAT|O_EXCL|O_WRONLY)`;
  `FileExistsError` + fresh mtime → skip-dup; stale existing marker → RE-CHECK mtime
  immediately before unlink (Momus R1 TOCTOU fix: if the re-check finds it fresh,
  treat as skip-dup — two racers must never unlink each other's fresh marker), then
  unlink + retry the O_EXCL claim ONCE. Claim released only on rc=7 (provable
  non-delivery) as today.
- Sites: `resume()`, checkpoint-fallback block, `db_fallback` block.

### T4 — quiesce-gated recycle (observe mode first)
- New `scripts/opencode-recycle-gate.sh` (`set -euo pipefail`): for each unit
  (opencode.service, opencode-interactive.service): read RSS (cgroup memory.current);
  busy/retry count via the unit's API WITH directory enumeration — (Momus R1 fix:
  /session/status is instance-scoped; a bare call covers only the root dir and would
  miss busy sessions elsewhere; reuse the discover_dirs DB read + per-dir status
  probes exactly as snapshot() does). OBSERVE mode (default): log decision only.
  ENFORCE mode: if RSS ≥ threshold (interactive 5G, headless 3G — both below MemoryHigh
  6G/4G) AND zero busy/retry → `systemctl --user restart <unit>` (session-safe via
  existing hooks); else defer.
- New `systemd/user/opencode-recycle-gate.{service,timer}` (every 5 min; OBSERVE=1
  default in the service env). Drop-ins: RuntimeMaxSec 21600 → 86400 (hard backstop).
- Rollout: the observe timer IS the durable instrument (survives the agent's turn).
  Unlock gate: ≥1 would-fire observe event with zero busy sessions AND ≥48h clean
  observe log → flip OBSERVE=0 via the same idle-window queue entry; ladder arming via
  `scripts/rollout-monitor.py` is the unlock-time obligation (Momus R1 info — follow-up
  at unlock, not a deploy step of this plan).
- Deployment: `daemon-reload` + `systemctl --user enable --now` of the timer JOINS the
  idle-window queue — NOT executed by this plan's implementer without an idle window.

### T5 — FP-rate report + accounting
- New `scripts/continuation-fp-report.py`: DB read-only; classifies synthetic nudge
  parts (3 known prompt texts) over a window (`--days N`, default 7); per class:
  nudges/FP/TP/precision (FP = latest prior assistant message has time.completed);
  excludes `/tmp/*` and `*session-learning*` dirs; `--json` output; exit 0.
- New `tests/test_continuation_fp_report.sh` (fixture DB or synthetic rows; asserts
  counts) — auto-discovered by `tests/run_all.sh`.
- Regression pairs (tests/regressions/, paired .sh + .kill.sh):
  - `continuation-resume-freshness-guard` (T2)
  - `continuation-dedup-atomic-claim` (T3)
  - `continuation-wake-parent-silence` (T1)
- Extend `tests/test_continuation_hooks.sh` only if its existing harness covers the
  touched paths.

### T6 — docs sync (repo rules)
- MANIFEST.md: rows for recycle-gate script + service/timer + fp-report script; update
  restart-with-continuation.sh row.
- README.md: scripts count, systemd count, feature line only if category counts change.
- docs/non-wisdom-observability.md: wake-union predicate + FP report note.
- systemd drop-in comments updated (RuntimeMaxSec rationale).

## Must NOT (whole plan)
- No server restarts, no daemon-reload, no service enable/disable (idle-window queue owns those).
- No OMO fork edits, no wake-file writes, no changes to MAX_WAKE_AGE_SECONDS or
  RESUME_TTL_SECONDS semantics.
- No `as any`-class shortcuts; bash `set -euo pipefail`; python list-form subprocess.

## Verification (F gates)
- F1: `bash -n scripts/restart-with-continuation.sh scripts/opencode-recycle-gate.sh` exit 0
  (Momus R1: new script included); `python3 -m py_compile scripts/continuation-fp-report.py` exit 0.
- F2: all 3 new regression pairs + their .kill.sh exit 0; `bash tests/run_all.sh` → NO NEW
  failures vs the pre-change baseline run captured at execution start (Momus R1: absolute
  exit 0 is unachievable with known pre-existing failures).
- F3: `python3 scripts/continuation-fp-report.py --days 7` reproduces the baseline table
  (within sampling drift) BEFORE the fixes deploy — proves the classifier.
- F4: plan-compliance audit — diff touches only the files listed in T1–T6; targeted greps:
  T1 comparison contains `age_basis * 1000`; T2 condition contains the `wake-pending`
  exclusion; freshness guard `captured_at_ms` present in resume() top-level loop only.
- Post-deploy (separate session, ≥2 restart cycles later): FP report after-numbers vs
  baseline; success gate per Coordination condition 4.

## Execution Record

Execution baseline: f72a284 (master, pre-change). run_all.sh pre-change baseline: Pass 60 / Fail 2 / Acknowledged 2, exit 1 — reference copy /tmp/opencode/run_all_baseline_20261016-202156.txt (F2 gate = no new failures vs this).
Momus R1: REJECT (1 CRITICAL unit bug + 4 WARNING + 2 INFO) — all addressed in plan.
Momus R2: APPROVE — all fixes verified, round 2/4, no new issues.
Momus R2: APPROVE — all fixes verified, round 2/4, no new issues.
F#1: APPROVE — bash -n both scripts exit 0; py_compile fp-report exit 0.
F#2: APPROVE — run_all.sh after: Pass 61/Fail 2/Ack 2 (same 2 pre-existing fails as baseline); regression corpus 50 passed/0 failed (baseline 47/0); kill-tests 57 proved/0 broken; 3 new pairs green both directions.
F#3: APPROVE — continuation-fp-report.py --days 7 reproduces baseline (wake 4.2%, maintenance 70.2%, total 27.7% precision) before deploy.
F#4: APPROVE — diff limited to plan files; greps: `ab * 1000` predicate ×2, `wake-pending` exclusion in T2 condition, captured_at_ms guard in resume() top-level only.


## Cross-reference: task-tool-side nudge (added 2026-10-16)

The task_list concurrency nudge ("Maximize parallel execution…") is TASK-TOOL-side
and is owned by `.omo/plans/task-list-owned-views.md` (Phase 1, T2) — not by this
plan. This plan owns the continuation wake/maintenance/child nudge decider only;
the plans share measurement vocabulary but no files. Joint measurement point:
this plan's post-deploy residual-class table — if residuals implicate a
task-tool/reminder class, the owned-views plan's nudge removal is the complement.