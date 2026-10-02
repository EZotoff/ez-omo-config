---
name: rollout-watch
description: OMO/opencode adapter for the feature rollout protocol (docs/rollout-protocol.md + scripts/rollout-monitor.py). Use when deploying or enabling ANY new harness capability — a daemon, watcher, pipeline stage, or agent write-path — to arm the monitoring ladder durably, wire the evidence sources, and execute gates. Covers arming mechanics (systemd transient units, never agent promises), OMO evidence sources, and unlock procedures.
---

# rollout-watch — OMO binding for the rollout protocol

Base (harness-agnostic): `docs/rollout-protocol.md`, `scripts/rollout-monitor.py`.
This skill adds ONLY the opencode/OMO-specific wiring. The base must stay usable
without anything on this page.

## When this fires

Any task that (a) adds a write-path or autonomous behavior to a harness
component, (b) flips an `enabled` flag that activates previously-shadow
behavior, or (c) deploys a new long-running service. If the change cannot fail
silently, the protocol still applies — it just terminates early.

## 1. Arming the ladder (durably — never an agent promise)

A turn-based agent has no clock; the ladder's 12h plateau gaps exceed any
subagent's 30-min inactivity window. Therefore the monitor runs as a **systemd
transient unit**, not a background subagent and not a `nohup &`:

```bash
systemd-run --user --unit="rollout-<feature>" \
  -p Restart=on-failure -p RestartSec=15 \
  python3 ~/ez-omo-config/scripts/rollout-monitor.py \
    --config ~/.local/state/opencode-rollout/<feature>.rollout.json
# daemon mode sleeps ≤600s between due-checks. Restart=on-failure (NOT always):
# the monitor exits 0 on ladder completion/stopped — an always-restart would
# respawn-churn a finished rollout.
```

Check arming: `systemctl --user status rollout-<feature>`. State + rounds log
live under `~/.local/state/opencode-rollout/` — killing the unit loses nothing;
relaunching resumes from state (idempotent by design).

The deploying agent's obligation after arming: verify the unit is active AND
the state file exists in the same turn. Then end the turn — the wake trigger is
the unit itself; findings surface via the rounds log and gate records.

## 2. Evidence sources (detector → OMO adapter)

| Protocol detector | Adapter on this host |
|---|---|
| Availability probe | `systemctl --user is-active <unit>`; `ps -eo pid,lstart,args` start-time check for bare processes |
| Error-class histogram | `journalctl --user -u <unit> --since <ts> -p err`; for ledger-keeping services: `jq -r 'select(.type=="ERROR") \| .payload.error' <ledger> \| normalize \| sort \| uniq -c` |
| Telemetry motion | status JSON counters (`~/.local/state/<svc>/status.json`) — any counter that can read 0 must be checked for motion once its path was active |
| Three-way cross-exam | claims ledger vs `~/.local/share/opencode/opencode.db` (read-only sqlite: `message`+`part` tables) vs published read models (`operator-view.json` etc.) |
| Timeline correlation | for each produced artifact, grep the consumer's log/ledger for the corresponding event id within tolerance |
| Ground-truth reconstruction | run the feature's real modules over a captured real input (bun/python import from the repo) — never trust the green test suite alone |
| Human review | render outputs to the operator (paste rendered artifact in the final message, or screenshot for UI) — mandatory at presentation rounds |

## 3. Gates as config flips (OMO pattern)

A gate action typically: (1) edit the store config in `~/ez-omo-config` (edit →
JSON-validate → commit), (2) restart the owning service via
`scripts/restart-with-continuation.sh` (session-safe — never bare-restart),
(3) update MANIFEST/docs per repo rules. Rollback = the inverse flip, written
BEFORE P2 begins and committed next to the enablement.

If the feature lives in the opencode binary/plugins, a gate additionally owes a
`tests/regressions/` paired `.sh`/`.kill.sh` entry (repo policy) and must pass
`bash tests/run_all.sh` before executing.

## 4. Configuration skeleton for an OMO feature

```json
{
  "feature": "supervisor-steer-writes",
  "ladder": [120, 900, 1800, 3600, 7200, 14400, 28800, 43200],
  "plateau_gap_s": 43200,
  "max_ladder_resets": 3,
  "checks": [{"name": "unit-active", "cmd": ["systemctl", "--user", "is-active", "opencode-supervisor.service"]}],
  "error_tail": {"cmd": ["journalctl", "--user", "-u", "opencode-supervisor.service", "--no-pager"],
                 "pattern": "ERROR"},
  // NOTE: error sources must be monotonic/append-only — avoid --since windows
  // (a sliding window resets the watermark; protocol §6). Full unit logs only.
  "evidence": {"cmd": ["sh", "-c", "jq -s '[.[]|select(.type==\"INTERVENTION_SENT\" and .mode==\"steer\")]|length' ~/.local/state/opencode-supervisor/ledger.jsonl"],
               "min_per_round": [0, 1, 1, 3, 3, 3, 3, 3], "max_extends": 8},
  "gates": [{"name": "unlock-next-write-path", "after_round": 4,
             "requires": {"min_activations": 3, "max_new_errors": 0},
             "action": ["bash", "~/ez-omo-config/scripts/<feature>-gate-unlock.sh"]}],
  // gate actions point at a COMMITTED script (config flip + restart-with-
  // continuation + docs sync) — never an inline sh -c pipeline.
  "state_path": "~/.local/state/opencode-rollout/supervisor-steer-writes.state.json",
  "log_path": "~/.local/state/opencode-rollout/supervisor-steer-writes.rounds.jsonl"
}
```

Note `max_extends: 8` for sparse-activation features: on a quiet host, waiting
out quota extensions IS the protocol (evidence outranks calendar; the reverse
ratio also holds — 20 active sessions can earn a gate in the 15-min round).

## 5. Semantic rounds on this host

Rounds 5-7 (2h-8h) sample decisions against their evidence: pick N activations
from the ledger, open the cited sessions in `opencode.db`, verify the action
matched intent. Drift to check explicitly: "is it still doing what it was built
FOR" — e.g., a supervisor meant to catch operator-decisions that only ever
ABORTs is technically healthy and semantically dead. Record the sample verdict
in the rollout's rounds log as a manual record.
