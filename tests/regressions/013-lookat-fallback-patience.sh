#!/usr/bin/env bash
# Regression 013: look_at must wait for runtime-fallback answers.
#
# Bug (2026-08-16, ses_ff594298bffeWXBu7AhWFcF4jk): when the multimodal-looker
# primary model (openai/gpt-5.6-terra, quota-dead) failed and OMO's
# runtime-fallback hook rescued the look_at child session with a fallback model
# (google/gemini-3.7-flash), the look_at runner extracted the child's messages
# ONCE, saw only the failed primary attempt's empty assistant row, and returned
# "Error: No response from multimodal-looker agent" ~2.5s BEFORE the fallback
# answer landed (proven in ~/.local/share/opencode/logs/oh-my-opencode.log:
# tool gave up 18:56:18.703Z, gemini answer 18:56:20.7Z).
#
# Fix: dist patch omo--lookat-fallback-patience — patience re-poll loop in
# runLookAtSessionResult, bounded by LOOK_AT_FALLBACK_PATIENCE_MS (60s).
# This test asserts the live OMO dist carries the patched markers.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OMO_DIST="${OMO_DIST:-/home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js}"

assert_file_exists "$OMO_DIST"

# The patch const and the patience-loop log line must both be present...
assert_grep "LOOK_AT_FALLBACK_PATIENCE_MS = 60000" "$OMO_DIST"
assert_grep "runtime-fallback answer may still land" "$OMO_DIST"
# ...and the pre-patch one-shot extract must be gone.
assert_no_grep "const responseText = observedText" "$OMO_DIST"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo "FAIL: look_at fallback-patience patch missing from $OMO_DIST (lost on OMO update? see .sisyphus/patches/omo--lookat-fallback-patience.md)"
  exit 1
fi
echo "PASS: look_at fallback-patience markers present in live dist"
