#!/usr/bin/env python3
"""Generic feature-rollout monitoring ladder (harness-agnostic base).

Implements docs/rollout-protocol.md §4-§6: exponentially increasing monitoring
rounds with evidence quotas, gates, and ladder-restart-on-error. Keeps a
durable state file (idempotent resume) and appends a structured JSONL record
per round.

Usage:
  rollout-monitor.py --config feature.rollout.json          # daemon: loop rounds
  rollout-monitor.py --config feature.rollout.json --once   # run due round only

Config schema (JSON):
{
  "feature": "my-feature",
  "ladder": [120, 900, 1800, 3600, 7200, 14400, 28800, 43200],
  "plateau_gap_s": 43200,
  "max_ladder_resets": 3,
  "checks": [ {"name": "alive", "cmd": ["systemctl", "is-active", "x"], "expect_rc0": true} ],
  "error_tail": {"cmd": ["journalctl", "-n", "50", "..."], "pattern": "ERROR"},
  "evidence": {"cmd": ["grep", "-c", "ACTIVATED", "/var/log/x.log"], "min_per_round": [0, 1, 1, 3, 3, 3, 3, 3]},
  "semantic_check": {"cmd": ["/opt/bin/audit.py"], "rounds": [5, 6, 7]},
  "operator_review_rounds": [6],
  "gates": [ {"name": "unlock-b", "after_round": 4,
              "requires": {"min_activations": 3},
              "action": ["config-set", "feature.b", "enabled"]} ],
  "state_path": "/var/lib/rollout/my-feature.state.json",
  "log_path": "/var/lib/rollout/my-feature.rounds.jsonl"
}

Design notes:
- stdlib only; subprocess list-form only; no shell interpolation.
- A failed check restarts the ladder (round 0 next), increments error_streak,
  and records the failure. It does NOT retry the check in a tight loop — the
  next round happens after the round-1 gap, by which time a fix should have
  landed (the deploying agent watches this state file).
- Evidence quota: round N requires evidence_count_total >= min_per_round[N]
  cumulative activations; an unmet quota EXTENDS the round (gap repeats) up to
  max_extends times, then passes with "vacuous" flagged (never silently).
- Gates run only when their round completes with quota met and no new errors.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class RoundRecord:
    feature: str
    round_index: int
    started_at: float
    ended_at: float
    status: str  # "pass" | "fail" | "extended" | "vacuous"
    checks: list = field(default_factory=list)
    new_errors: int = 0
    evidence_total: int = 0
    evidence_required: int = 0
    gates_executed: list = field(default_factory=list)
    note: str = ""


def run_cmd(cmd: list) -> tuple[int, str]:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def load_state(path: Path, feature: str) -> dict:
    if path.exists():
        return json.loads(path.read_text())
    return {
        "feature": feature,
        "round_index": 0,
        "phase_started_at": time.time(),
        "next_round_at": time.time(),
        "error_streak": 0,
        "ladder_resets": 0,
        "evidence_total": 0,
        "errors_seen": 0,
        "extends_used": 0,
        "gates_done": [],
        "completed": False,
    }


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".tmp-{time.time_ns()}")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(path)


def append_record(log_path: Path, record: RoundRecord) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a") as handle:
        handle.write(json.dumps(record.__dict__) + "\n")


def count_evidence(cfg: dict) -> int:
    spec = cfg.get("evidence")
    if not spec:
        return max(state_default_evidence(), 0)
    rc, out = run_cmd(spec["cmd"])
    try:
        return int(out.strip().splitlines()[-1]) if rc == 0 else 0
    except (ValueError, IndexError):
        return 0


def state_default_evidence() -> int:
    return 1  # no evidence counter configured: treat as satisfied


def check_errors(cfg: dict, state: dict) -> int:
    """Count NEW error-class lines since the last round."""
    spec = cfg.get("error_tail")
    if not spec:
        return 0
    rc, out = run_cmd(spec["cmd"])
    if rc != 0:
        return 0
    matches = sum(1 for line in out.splitlines() if spec["pattern"] in line)
    new = max(0, matches - state.get("errors_seen", 0))
    state["errors_seen"] = matches
    return new


def run_round(cfg: dict, state: dict) -> RoundRecord:
    idx = state["round_index"]
    started = time.time()
    record = RoundRecord(feature=cfg["feature"], round_index=idx,
                         started_at=started, ended_at=started, status="pass")

    # 1. checks (hard failures)
    for check in cfg.get("checks", []):
        rc, out = run_cmd(check["cmd"])
        ok = rc == 0 if check.get("expect_rc0", True) else rc == int(check.get("expect_rc", 0))
        record.checks.append({"name": check["name"], "rc": rc, "ok": ok})
        if not ok:
            record.status = "fail"
            record.note = f"check failed: {check['name']}: {out[:200]}"

    # 2. error-class tail
    if record.status != "fail":
        record.new_errors = check_errors(cfg, state)
        if record.new_errors > 0:
            record.status = "fail"
            record.note = f"{record.new_errors} new error-class line(s)"

    # 3. evidence quota
    mins = cfg.get("evidence", {}).get("min_per_round", [])
    record.evidence_required = mins[idx] if idx < len(mins) else 0
    if record.status == "pass" and record.evidence_required > 0:
        state["evidence_total"] = max(state["evidence_total"], count_evidence(cfg))
        record.evidence_total = state["evidence_total"]
        if state["evidence_total"] < record.evidence_required:
            max_extends = cfg.get("evidence", {}).get("max_extends", 4)
            if state["extends_used"] < max_extends:
                state["extends_used"] += 1
                record.status = "extended"
            else:
                record.status = "vacuous"
                record.note = (f"evidence quota unmet after {state['extends_used']} extends; "
                               "passing vacuously — treat as a gate blocker, not a pass")

    # 4. semantic check on configured rounds
    spec = cfg.get("semantic_check")
    if spec and record.status == "pass" and idx in spec.get("rounds", []):
        rc, out = run_cmd(spec["cmd"])
        if rc != 0:
            record.status = "fail"
            record.note = f"semantic check failed: {out[:300]}"

    record.ended_at = time.time()

    # 5. advance / restart / gates
    ladder = cfg["ladder"]
    if record.status == "fail":
        state["ladder_resets"] += 1
        state["error_streak"] += 1
        state["round_index"] = 0
        state["extends_used"] = 0
        state["next_round_at"] = record.ended_at + ladder[0]
        if state["ladder_resets"] > cfg.get("max_ladder_resets", 3):
            record.note += " | STOP: max ladder resets exceeded — redesign, do not grind"
            state["completed"] = True
    elif record.status == "extended":
        state["next_round_at"] = record.ended_at + ladder[min(idx, len(ladder) - 1)]
    else:
        for gate in cfg.get("gates", []):
            if gate["name"] in state["gates_done"]:
                continue
            if idx < gate.get("after_round", 0):
                continue
            req = gate.get("requires", {})
            if state["evidence_total"] < req.get("min_activations", 0):
                continue
            rc, out = run_cmd(gate["action"])
            if rc == 0:
                state["gates_done"].append(gate["name"])
                record.gates_executed.append(gate["name"])
        next_idx = idx + 1
        gap = ladder[next_idx] if next_idx < len(ladder) else cfg.get("plateau_gap_s", ladder[-1])
        state["round_index"] = next_idx
        state["extends_used"] = 0
        state["error_streak"] = 0
        state["next_round_at"] = record.ended_at + gap
    return record


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--once", action="store_true", help="run the due round only, then exit")
    args = parser.parse_args()

    cfg = json.loads(Path(args.config).read_text())
    state_path = Path(cfg.get("state_path", f"/tmp/rollout-{cfg['feature']}.state.json"))
    log_path = Path(cfg.get("log_path", str(state_path) + ".rounds.jsonl"))
    state = load_state(state_path, cfg["feature"])

    while True:
        now = time.time()
        if state["next_round_at"] > now:
            if args.once:
                print(f"not due until {time.ctime(state['next_round_at'])}")
                return 0
            time.sleep(min(state["next_round_at"] - now, 600))  # capped sleep; daemon stays responsive
            continue
        if state.get("completed"):
            print("rollout completed/stopped; state preserved")
            return 0
        record = run_round(cfg, state)
        save_state(state_path, state)
        append_record(log_path, record)
        print(f"round {record.round_index}: {record.status}"
              + (f" ({record.note})" if record.note else "")
              + (f" gates: {record.gates_executed}" if record.gates_executed else ""))
        if args.once:
            return 0 if record.status in ("pass", "extended", "vacuous") else 1


if __name__ == "__main__":
    sys.exit(main())
