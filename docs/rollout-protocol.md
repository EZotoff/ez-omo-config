# Feature Rollout Protocol

Status: active · Created 2026-10-02 · Harness-agnostic base (no opencode/OMO dependencies)
OMO binding: see `.opencode/skill/rollout-watch/SKILL.md` (adapter layer, deliberately separate)

## 1. Purpose

Codifies the iterative rollout process proven on the Project Supervisor (2026-09/10):
instrument-first, observe mode, partial enablement, and scheduled monitoring rounds
with exponentially increasing gaps — where each round cross-examines durable
evidence rather than merely pinging liveness, and capability unlocks are earned
by gates, not granted by calendar time.

Applies to any new capability of a long-running harness (daemons, agents,
watchers, pipelines) where a silent failure is worse than a loud one.

## 2. Empirical basis — the error taxonomy

Every class below was found in the field. The protocol's rounds are designed so
each class has a scheduled detector; the detector column is how it was actually
caught.

| # | Class | Field examples | Detector that caught it | Phase that should catch it |
|---|-------|----------------|-------------------------|---------------------------|
| A | **Schema ghost** — defined, unit-tested, never invoked | collect forcing function unreachable behind an early return; STEER/REFORMULATE actions had gates + green tests but no call site; stall detector short-circuited | zero-frequency histogram of the action across all history; grep call sites; reading the execution path | P1 rounds; first-activation round |
| B | **Claim-vs-reality divergence** — logs/metrics assert success, world differs | "PROPAGATION_DELIVERED" events carried question text, workers got no answer (0/9); queueDepths counter said 0 with 4 open cards; items resolved as "propagated" on empty delivery | three-way cross-exam: claims log vs source-of-truth store (real transcripts) vs read model | P1 rounds 2+ |
| C | **Concurrency race** | shared tmp-file rename collisions (×2 subsystems); watermark advanced past a still-streaming message → ruling lost forever | error-class histogram after a burst event; timeline correlation (event exists in source at T, absent in consumer log at T) | P2 early rounds (races fire on concurrency) |
| D | **Fatal-error isolation gap** — one transient failure kills the process | single failed session fetch crashed the whole supervisor; sat dead 22h unnoticed | availability check (process alive?) + error tail | P0/P1 round 1 (2 min) |
| E | **Premise-validation gap** — acting on unverified preconditions | kick-starts on already-complete sessions; watermark consuming incomplete data; queue resolving on delivery of nothing | semantic sampling of decisions against the transcripts they cite | P1 round 3+ (semantic rounds) |
| F | **Presentation defect** — duplicated blocks, mid-sentence trims | ticket rendered Why: and Citations: byte-identical; quotes cut mid-word | the human operator's eye — the one detector agents lack | operator review rounds (mandatory) |
| G | **Baseline rot** — repo itself broken (tsc red, failing tests) | mid-refactor commit left the tree unbuildable; test fixtures asserted the wrong shape | baseline gates BEFORE any new work | pre-P0 |

Structural insight: **every class except F is detectable from durable evidence
without the feature being enabled to act.** That is why the protocol starts in
observe mode with full logging — the evidence has to exist before behavior is
unlocked, or there is nothing to cross-examine.

## 3. Phases

**P0 — Instrument.** No behavior change. Ship only: structured logging of every
decision and action (append-only, tamper-evident if feasible), counters that can
read ZERO (a counter that cannot read zero cannot detect class A), and read
models. Baseline gates green (build, typecheck, full tests) before starting.

**P1 — Observe.** The feature runs read-only: it may record what it *would* do,
write to shadow/scratch surfaces, but never mutates the systems it supervises.
The monitoring ladder starts here.

**P2 — Partial enablement.** One write path enabled, capped (rate limits, daily
caps), behind a config flag with a one-line rollback. The ladder RESTARTS from
round 1 on first activation. One capability per unlock — never two.

**P3 — Unlock ladder.** Each further capability is a named gate earned by
evidence (§6). Enablement order: least-intrusive first (ask > nudge > mutate >
delete), lowest-blast-radius surface first.

**P4 — Steady state.** Plateau rounds continue indefinitely (semantic audits);
the feature is never "done", only currently-behaving.

## 4. The monitoring ladder

Default schedule (each round happens AFTER the previous round + gap):

| Round | Gap | Looks for | Class |
|-------|-----|-----------|-------|
| 1 | 2 min | crashes, fatal errors, core loop alive | D |
| 2 | 15 min | **first activations** — did the new path actually fire? early bug histogram | A, C |
| 3 | 30 min | more activations; error-class histogram delta; claim-vs-reality spot check | B, C |
| 4 | 1 h | stability; cross-exam one claimed success against source of truth | B |
| 5 | 2 h | semantic sample: N decisions audited against their evidence | E |
| 6 | 4 h | semantic + presentation: render outputs for the operator | E, F |
| 7 | 8 h | drift check: is it still doing what it was built FOR (intent), not just not-erroring | E |
| 8+ | 12 h, 12 h, 12 h … | plateau: recurring semantic + error-class audits | B, C, E |

On ANY error found: fix, then **restart the ladder from round 1** — the schedule
itself is evidence (a system that keeps resetting to 2-minute checks is a system
still on fire). Keep a per-feature ladder-reset counter; >3 resets at the same
round is a stop-and-redesign signal, not a schedule to grind through.

## 5. Evidence weighting (activity-adjusted intervals)

Wall time is a weak proxy. 15 minutes across 20 active sessions proves more than
5 hours across one idle session. Therefore every round carries an evidence
quota:

- A round is *due* by wall clock, but only *passes* when its evidence quota is
  met (e.g., round 2 requires "≥1 observed activation of the new path";
  a semantic round requires "≥N activations to sample from").
- If the quota is unmet, the round EXTENDS (up to a configured max) rather than
  passing vacuously — "nothing happened" is not "it works".
- Gates always require a minimum activation count in addition to zero errors:
  zero errors over zero activations proves nothing (class A hides exactly there).
- Conversely, quota met early may advance a round early — evidence outranks
  the calendar.

## 6. Gates

A gate is a named unlock attached to ladder position:

```json
{
  "name": "enable-write-path-B",
  "after_round": 4,
  "requires": { "max_new_errors": 0, "min_activations": 3, "min_ladder_resets_at_or_below": 1 },
  "action": ["config", "set", "feature.B", "enabled"]
}
```

Rules: one capability per gate; gates are evaluated only at round completion;
an executed gate is recorded durably (idempotent on restart); a ladder reset
after a gate un-locks nothing automatically but requires an explicit operator
decision to re-earn or roll back.

## 7. Detector toolkit (in order of cost)

1. **Availability probe** — is the process alive, did it restart (start-time
   check), error tail since last round.
2. **Error-class histogram** — group the feature's error log by normalized
   message; ANY new class since the last round is a finding, even self-healed
   ones (the consoles.json race "self-healed" 11 times before anyone looked).
3. **Telemetry motion** — every counter must have moved if its path was
   supposedly active; stuck-at-zero over an active period = class A.
4. **Three-way cross-exam** — claims log vs source-of-truth store vs read
   model; any two disagreeing is a finding.
5. **Timeline correlation** — for every produced artifact, the consuming side
   must show the corresponding event within tolerance; produce-without-consume
   = class C.
6. **Ground-truth reconstruction** — execute the real pipeline modules over
   real captured inputs (the strongest semantic check; found class A ghosts
   that all other detectors missed).
7. **Human review** — render the outputs the operator would see. Non-optional
   at presentation rounds; class F is invisible to agents.

## 8. Operational rules

- Monitoring must survive the deploying agent's turn ending: the ladder runs as
  a durable mechanism (service/timer + state file), never as an agent's promise.
- State file per feature: round index, timestamps, error streaks, gate status,
  evidence counts. Killing and relaunching the monitor must lose nothing
  (idempotent resume from state).
- Every round appends a structured record (JSONL) — the rollout itself gets
  class-B treatment: its claims are auditable.
- Rollback is a first-class command: config flip + restart procedure documented
  before P2 begins.

## 9. What lives where

- **This document + `scripts/rollout-monitor.py`** — harness-agnostic base.
  No opencode, OMO, systemd-user, or path assumptions beyond POSIX + Python 3.
- **`.opencode/skill/rollout-watch/`** — the OMO adapter: how to arm the runner
  durably on this host, which evidence sources map to the detectors
  (journalctl, ledger jq, status files, session DB), how gates flip configs,
  and the restart-with-continuation interplay. The base must remain usable
  without any of it.
