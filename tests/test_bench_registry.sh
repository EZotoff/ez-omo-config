#!/usr/bin/env bash
# Registry contract test for ez-omo-bench (bench/registry.json).
#
# Enforces:
#   - registry shape: suite id, shared_capability_review fields, benchmarks array
#   - per-entry required fields, kebab-case ids, '<kind>-<name>' id convention,
#     allowed enums, existing bench_dir, sha256 config_fingerprint
#   - unique ids; no unregistered benchmark directories under bench/
#   - the Ten-Benchmark Shared-Capability Gate (fails at >=10 benchmarks
#     until shared_capability_review.assessed is true)
#   - results.schema.json parses and is a plausible JSON Schema
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$REPO_ROOT/bench/registry.json"
SCHEMA="$REPO_ROOT/bench/schemas/results.schema.json"

for f in "$REGISTRY" "$SCHEMA"; do
    if [[ ! -f "$f" ]]; then
        echo "FAIL: required file missing: ${f#$REPO_ROOT/}"
        exit 1
    fi
done

python3 - "$REGISTRY" "$SCHEMA" "$REPO_ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

registry_path, schema_path, repo_root = (Path(a) for a in sys.argv[1:4])

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


reg = json.loads(registry_path.read_text(encoding="utf-8"))

check(reg.get("suite") == "ez-omo-bench", "registry.suite must be 'ez-omo-bench'")
check(isinstance(reg.get("version"), int), "registry.version must be an integer")

scr = reg.get("shared_capability_review")
check(isinstance(scr, dict), "missing shared_capability_review object")
if isinstance(scr, dict):
    check(scr.get("due_at_benchmark_count") == 10,
          "shared_capability_review.due_at_benchmark_count must be 10")
    check(isinstance(scr.get("assessed"), bool),
          "shared_capability_review.assessed must be a boolean")

benchmarks = reg.get("benchmarks")
check(isinstance(benchmarks, list), "registry.benchmarks must be an array")

ALLOWED_STATUS = {"draft", "designed", "developed", "validated", "retired"}
ALLOWED_KIND = {"agent", "category", "capability"}
REQUIRED_FIELDS = ("id", "capability", "status", "created", "bench_dir",
                   "config_fingerprint")

ids = []
for i, entry in enumerate(benchmarks):
    ctx = f"benchmarks[{i}]"
    for field in REQUIRED_FIELDS:
        check(field in entry, f"{ctx}: missing required field '{field}'")
    cap = entry.get("capability", {})
    kind = cap.get("kind")
    name = cap.get("name")
    check(kind in ALLOWED_KIND, f"{ctx}: capability.kind must be one of {sorted(ALLOWED_KIND)}")
    check(isinstance(name, str) and name != "", f"{ctx}: capability.name must be a non-empty string")
    check(entry.get("status") in ALLOWED_STATUS,
          f"{ctx}: status must be one of {sorted(ALLOWED_STATUS)}")
    bid = entry.get("id", "")
    check(re.fullmatch(r"[a-z0-9][a-z0-9-]*", bid) is not None,
          f"{ctx}: id must be kebab-case: '{bid}'")
    check(bid == f"{kind}-{name}", f"{ctx}: id must equal '<kind>-<name>', got '{bid}'")
    bench_dir = entry.get("bench_dir", "")
    check(bench_dir.startswith("bench/"), f"{ctx}: bench_dir must start with 'bench/'")
    check((repo_root / bench_dir).is_dir(), f"{ctx}: bench_dir does not exist: {bench_dir}")
    check(re.fullmatch(r"sha256:[0-9a-f]{16,64}", entry.get("config_fingerprint", "")) is not None,
          f"{ctx}: config_fingerprint must be 'sha256:<hex>'")
    if kind == "category":
        check("composed_from" in entry or "composition" in json.dumps(entry),
              f"{ctx}: category benchmarks must document their effective-stack composition")
    ids.append(bid)

check(len(ids) == len(set(ids)), "duplicate benchmark ids in registry")

registered_dirs = {entry.get("bench_dir") for entry in benchmarks}
bench_root = repo_root / "bench"
for child in sorted(bench_root.iterdir()):
    if child.is_dir() and child.name != "schemas":
        rel = f"bench/{child.name}"
        check(rel in registered_dirs, f"unregistered benchmark directory: {rel}")

if len(benchmarks) >= 10 and isinstance(scr, dict) and not scr.get("assessed"):
    failures.append(
        "GATE OPEN: 10+ benchmarks registered but shared_capability_review.assessed "
        "is false — run the Ten-Benchmark Shared-Capability Gate "
        "(skills/bench-author/SKILL.md) before authoring further benchmarks"
    )

schema = json.loads(schema_path.read_text(encoding="utf-8"))
check(schema.get("type") == "object", "results.schema.json: root type must be 'object'")
for field in ("required", "properties", "definitions"):
    check(field in schema, f"results.schema.json: missing '{field}'")

if failures:
    print("FAIL: bench registry contract violations:")
    for msg in failures:
        print(f"  - {msg}")
    sys.exit(1)

print(f"OK: bench registry contract satisfied ({len(benchmarks)} benchmark(s) registered)")
PY
