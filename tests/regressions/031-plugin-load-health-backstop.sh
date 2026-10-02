#!/usr/bin/env bash
# Regression 031: check-plugin-load-health.sh must detect fresh plugin-load failures
#
# Incidents fixed conceptually by the script (2026-10-02 backstop): 2026-08-06
# git-safety `__test__` export (~1,251 silent "failed to load plugin" errors,
# guardrails offline 14 days) and 2026-08→09 review-enforcer helper exports
# (2,084 `output.includes` errors). Both were invisible: one ERROR log line per
# server start, no toast, and static registration tests (regressions/010) kept
# passing while the plugins were dead at load. The /update-to-latest smoke-boot
# gate only fires during skill cutovers, so binary installs that bypass the
# skill had no detection at all.
#
# This test guards the backstop itself: the script wired into
# opencode-patch-integrity-check.service MUST (a) pass on a clean log,
# (b) exclude /tmp scratch-probe plugin paths, (c) exit 1 on a real failure,
# (d) re-arm across log rotation.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0__/../../.." && pwd)" 2>/dev/null || cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-plugin-load-health.sh"

[[ -f "$SCRIPT" ]] || { echo "FAIL: $SCRIPT not found"; exit 1; }
assert_file_exists "$SCRIPT"

S=$(mktemp -d /tmp/opencode/reg-plh.XXXXXX)
trap 'rm -rf "$S"' EXIT
export OPENCODE_LOG_PATH="$S/log" PLUGIN_LOAD_HEALTH_STATE_DIR="$S/state"

# 1. First run on a clean log bootstraps (observe mode) and passes.
printf 'timestamp=2026-10-02T10:00:00Z level=INFO message=init\n' > "$S/log"
"$SCRIPT" >/dev/null || { echo "FAIL: clean first run should exit 0"; exit 1; }

# 2. /tmp scratch-probe plugin failures are excluded (session-attachment hygiene).
printf 'timestamp=2026-10-02T10:05:00Z level=ERROR message="failed to load plugin" path=file:///tmp/opencode/probe/fake-plugin error="x"\n' >> "$S/log"
"$SCRIPT" >/dev/null || { echo "FAIL: /tmp probe failure should be excluded"; exit 1; }

# 3. A real plugin-load failure MUST exit 1 with an identifying stderr line.
printf 'timestamp=2026-10-02T10:10:00Z level=ERROR message="failed to load plugin" path=file:///home/ezotoff/.opencode/plugin/git-safety.ts error="Plugin export is not a function"\n' >> "$S/log"
if "$SCRIPT" 2>"$S/err"; then
  echo "FAIL: real plugin-load failure must exit 1"
  exit 1
fi
grep -q "PLUGIN-LOAD HEALTH: 1 new" "$S/err" || { echo "FAIL: stderr must report the failure count"; exit 1; }

# 4. Watermark advances — same failure must not re-alert on the next run.
"$SCRIPT" >/dev/null || { echo "FAIL: watermark should advance past the alerted line"; exit 1; }

# 5. Log rotation re-arms detection: new file, new failure line → exit 1.
printf 'timestamp=2026-10-02T11:00:00Z level=ERROR message="failed to load plugin" path=file:///home/ezotoff/.opencode/plugin/review-enforcer.ts error="y"\n' > "$S/log.new"
mv "$S/log" "$S/log.old" && mv "$S/log.new" "$S/log"
if "$SCRIPT" 2>/dev/null; then
  echo "FAIL: post-rotation failure must exit 1"
  exit 1
fi

[[ "$TESTS_FAILED" -gt 0 ]] && { echo "FAIL: plugin-load health backstop checks failed"; exit 1; }
echo "PASS: check-plugin-load-health.sh detects fresh plugin-load failures, excludes /tmp probes, re-arms on rotation"
exit 0
