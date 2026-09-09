#!/usr/bin/env bash
set -euo pipefail

# smoke-boot-check.sh — fresh-boot smoke gate for the OpenCode/OMO runtime.
#
# A cutover can pass verify-live-patches.sh (pattern presence) yet ship an
# unimportable runtime module. 2026-09-08 proved pattern-presence != bootability.
# This gate boots a FRESH throwaway opencode server and asserts that plugins
# load, the agent resolves, and a prompt round-trips through the model loop.
#
# Exit 0 = healthy boot. Exit 1 = broken boot (offending lines + log path echoed).
# Exit 2 = usage error.

usage() {
    printf 'Usage: %s [--dir PATH] [--registry-canary]\n' "${0##*/}" >&2
    printf '  --dir PATH         run the smoke boot in PATH instead of a fresh mktemp dir\n' >&2
    printf '  --registry-canary  no-op flag: the stream-line assertion IS the registry\n' >&2
    printf '                    canary — agent resolution is proven by the agent=Sisyphus\n' >&2
    printf '                    field on the stream log line; no separate API call is made.\n' >&2
    exit 2
}

WORKDIR=""
while (($#)); do
    case "$1" in
        --dir)
            [[ $# -ge 2 ]] || usage
            WORKDIR="$2"
            shift 2
            ;;
        --registry-canary)
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# --- setup ---
LOG="/tmp/opencode/smoke-boot-$$.log"
mkdir -p /tmp/opencode
if [[ -z "$WORKDIR" ]]; then
    WORKDIR="$(mktemp -d /tmp/opencode/smoke-boot.XXXXXX)"
    CLEANUP_WORKDIR=1
else
    CLEANUP_WORKDIR=0
fi

BEFORE="$(mktemp /tmp/opencode/smoke-before.XXXXXX)"
AFTER="$(mktemp /tmp/opencode/smoke-after.XXXXXX)"
FILTERED="$(mktemp /tmp/opencode/smoke-filtered.XXXXXX)"

cleanup() {
    if ((CLEANUP_WORKDIR)); then
        rm -rf "$WORKDIR"
    fi
    rm -f "$LOG" "$BEFORE" "$AFTER" "$FILTERED"
}
trap cleanup EXIT

# Non-interference self-proof: snapshot pre-existing serve processes. Exclude
# the current shell PID so the pgrep invocation itself is not counted.
snapshot_serves() {
    pgrep -af 'opencode serve' | grep -v "$$" | sort
}

snapshot_serves > "$BEFORE"

# --- boot the throwaway server ---
# Capture opencode's exit via PIPESTATUS so a non-zero opencode exit FAILS the
# gate rather than being swallowed by tee. set +e around the pipeline.
# --print-logs is REQUIRED: without it, a plugin that fails to load (e.g. a stray
# pure-helper export called as a plugin constructor) logs 'failed to load plugin'
# at ERROR level to stderr, which is suppressed by default and would make the
# gate blind to the exact incident bug class this check exists to catch.
set +e
printf 'Reply with the single word ok' | timeout 120 opencode run \
    --agent Sisyphus \
    --model zai-coding-plan/glm-5.3 \
    --print-logs \
    --dir "$WORKDIR" \
    --title smoke-boot 2>&1 | tee "$LOG"
pipeline_rc=("${PIPESTATUS[@]}")
set -e
opencode_rc="${pipeline_rc[1]:-1}"

snapshot_serves > "$AFTER"

# --- assertions ---
fail=0
fail_msg() {
    fail=1
    printf 'FAIL: %s\n' "$1" >&2
}

# models.dev refresh-failure lines are whitelisted: the gate MUST NOT depend on
# models.dev. Filter them out before counting so a degraded network cannot
# produce a false failure.
MODELS_DEV_FILTER='models\.dev.*(refresh|fetch|fail|error|network|unreachable)'
grep -v -iE "$MODELS_DEV_FILTER" "$LOG" > "$FILTERED" || true

if ((opencode_rc != 0)); then
    fail_msg "opencode run exited non-zero (rc=$opencode_rc); log: $LOG"
fi

plugin_errors="$(grep -c 'failed to load plugin' "$FILTERED" || true)"
if ((plugin_errors > 0)); then
    fail_msg "$plugin_errors 'failed to load plugin' line(s):"
    grep 'failed to load plugin' "$FILTERED" >&2 || true
fi

agent_not_found="$(grep -cE 'agent ".*" not found' "$FILTERED" || true)"
if ((agent_not_found > 0)); then
    fail_msg "$agent_not_found 'agent ".*" not found' line(s):"
    grep -E 'agent ".*" not found' "$FILTERED" >&2 || true
fi

# --print-logs renders log-formatted output: the assistant reply appears as a
# bare standalone line, and '"type":"text"' only exists in --format json mode
# (incompatible with --print-logs). So the round-trip is asserted via the log
# stream instead: the agent-attributed stream line is the registry canary —
# absent when agents never registered (the 2026-09-08 incident bug class) —
# and the 'exiting loop' line proves the prompt completed a model round-trip.
stream_lines="$(grep -cE 'message=stream providerID=\S+ modelID=\S+ .*agent=Sisyphus' "$FILTERED" || true)"
if ((stream_lines < 1)); then
    fail_msg "no agent-attributed 'stream providerID=... agent=Sisyphus' log line (agent never streamed a prompt)"
fi
loop_lines="$(grep -c 'message="exiting loop"' "$FILTERED" || true)"
if ((loop_lines < 1)); then
    fail_msg "no 'exiting loop' log line (prompt did not complete a model round-trip)"
fi

# Non-interference: the pre-existing serve set must be unchanged.
disappeared="$(comm -23 "$BEFORE" "$AFTER")"
appeared="$(comm -13 "$BEFORE" "$AFTER")"
if [[ -n "$disappeared" ]]; then
    fail_msg "pre-existing opencode serve process(es) disappeared during the run:"
    printf '%s\n' "$disappeared" >&2
fi
if [[ -n "$appeared" ]]; then
    fail_msg "opencode serve process(es) appeared during the run (leaked throwaway server?):"
    printf '%s\n' "$appeared" >&2
fi

if ((fail)); then
    printf 'Smoke-boot FAILED. Full log: %s\n' "$LOG" >&2
    exit 1
fi

printf 'Summary: smoke-boot OK | %d plugin-load errors | %d agent-not-found | stream+loop confirmed | opencode rc=%d\n' \
    "$plugin_errors" "$agent_not_found" "$opencode_rc"
exit 0
