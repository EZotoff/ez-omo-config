#!/usr/bin/env bash
# Group 3 — restart isolation: while a campaign runs, perform the SAME
# read-only discovery the OpenCode continuation hooks use (their sqlite
# session-DB query + opencode unit listing) and assert the campaign unit is
# outside that discovery set and remains untouched (same MainPID, still
# active, no continuation artifact references it). Nothing belonging to the
# real continuation machinery is mutated.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="restart-isolation"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-restart-isolation.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 restart-isolation fixture — $(date +%F)"
ev "Discovery simulated READ-ONLY (same sqlite query + unit listing the hooks use); no continuation state mutated."
suite_setup
trap suite_cleanup EXIT
make_workspace isolation

RUN=t11iso
write_manifest "$WS/$RUN.json" "$RUN" 'sleep 8; printf isolated' \
  'sut:sut:family-a:fixture-model:case-1'

launch_campaign "$RUN" "$WS/$RUN.json"
U="$(unit_name "$RUN")"
sleep 1
[[ "$(systemctl --user is-active "$U" 2>/dev/null || true)" == active ]] || fail "unit not active before discovery"

pid_before="$(systemctl --user show "$U" -p MainPID --value)"
assert_ne_nonzero() { [[ -n "$1" && "$1" != 0 ]] || fail "MainPID not populated"; }
assert_ne_nonzero "$pid_before"

# Read-only discovery, mirroring restart-with-continuation.sh snapshot():
# (a) opencode unit listing, (b) the shared session DB distinct-directories query.
opencode_units="$(systemctl --user list-units 'opencode*' --all --no-legend 2>/dev/null || true)"
assert_no_match "campaign unit not in opencode unit discovery set" "$opencode_units" "$U"

session_db="$HOME/.local/share/opencode/opencode.db"
if [[ -r "$session_db" ]]; then
  discovered_dirs="$(python3 - "$session_db" <<'PY'
import sqlite3, sys, time
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
cutoff = (time.time() - 7200) * 1000
rows = con.execute(
    "select distinct directory from session "
    "where time_updated >= ? and time_archived is null and directory != ''", (cutoff,))
print("\n".join(sorted(r[0] for r in rows)))
PY
)"
  assert_no_match "campaign workspace not in session-DB discovery" "$discovered_dirs" "bench-campaign"
  assert_no_match "campaign workspace not in session-DB discovery" "$discovered_dirs" "$WORK_ROOT"
else
  ev "note: shared session DB not present; directory-discovery leg vacuously isolated"
fi

# Continuation artifacts (read-only grep): no snapshot references the campaign.
cont_dir="$HOME/.local/share/opencode/restart-continuations"
if [[ -d "$cont_dir" ]]; then
  hits="$(grep -rl "$U" "$cont_dir" 2>/dev/null || true)"
  assert_eq "continuation artifacts referencing campaign unit" "$hits" ""
else
  ev "note: restart-continuations dir absent; artifact leg vacuously isolated"
fi

# After the discovery pass the campaign unit is untouched.
pid_after="$(systemctl --user show "$U" -p MainPID --value)"
assert_eq "MainPID unchanged across discovery" "$pid_after" "$pid_before"
assert_eq "unit still active after discovery" "$(systemctl --user is-active "$U" 2>/dev/null || true)" "active"

terminal="$(wait_terminal "$WS/state" "$RUN" 120)"
assert_eq "campaign completed unadopted" "$terminal" "completed"
assert_eq "exitCode" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "0"

cleanup_unit "$RUN"
ev "RESULT: PASS"
echo "PASS: restart-isolation"
