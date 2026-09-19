#!/usr/bin/env bash
# run-bench-campaign-suite.sh — task-11 fixture suite runner.
# Hermetic: isolated HOME/state/repo/output per group, fake runners only,
# every unit stopped+reset-failed and verified absent, workspaces removed.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE_DIR="${BENCH_CAMPAIGN_EVIDENCE_DIR:-/home/ezotoff/AI_projects/veran/.sisyphus/evidence}"
mkdir -p "$EVIDENCE_DIR"

groups=(
  bench-campaign-survival.sh
  bench-campaign-canary.sh
  bench-campaign-restart-isolation.sh
  bench-campaign-stale-lock.sh
  bench-campaign-status.sh
  bench-campaign-case-counts.sh
  bench-campaign-schema-rejection.sh
  bench-campaign-phase-failfast.sh
)

failed=()
for g in "${groups[@]}"; do
  if bash "$DIR/$g"; then :; else failed+=("$g"); fi
done

echo
if (( ${#failed[@]} == 0 )); then
  echo "bench-campaign fixture suite: ALL 8 GROUPS PASS"
  exit 0
fi
echo "bench-campaign fixture suite: FAILED — ${failed[*]}"
exit 1
