#!/usr/bin/env bash
# metrics.sh — per-plugin metrics collection for the perf-review-server-plugins plan.
#
# Emits one "== <plugin-name>" section per plugin to stdout, built from the
# plugin logs under $HOME/.config/opencode/ and the proof-event sinks under
# $HOME/.local/share/opencode/. Uses only wc/du/grep/jq/stat. Missing files
# print MISSING and never abort the script (evidence capture must complete);
# grep -c returns exit 1 on zero matches, so every count is wrapped with
# `|| true` to survive `set -e` while still printing 0.
set -euo pipefail

LOG_DIR="$HOME/.config/opencode"
DATA_DIR="$HOME/.local/share/opencode"

# gc <file> <pattern> — grep -c with MISSING-file guard and exit-1 tolerance.
gc() {
  local file=$1 pattern=$2
  if [ -f "$file" ]; then
    grep -c -- "$pattern" "$file" || true
  else
    echo "MISSING"
  fi
}

# lines_per_day <file> — per-day line counts from [YYYY-MM-DD log prefixes.
lines_per_day() {
  local file=$1
  if [ -f "$file" ]; then
    grep -oE '^\[2026-[0-9]{2}-[0-9]{2}' "$file" | sort | uniq -c || true
  else
    echo "MISSING"
  fi
}

# log_size <file> — byte size via stat, MISSING-guarded.
log_size() {
  local file=$1
  if [ -f "$file" ]; then
    stat -c%s "$file"
  else
    echo "MISSING"
  fi
}

# ===================== output-shaper =====================
echo "== output-shaper"
os_log="$LOG_DIR/output-shaper.log"
echo "terseness_injected: $(gc "$os_log" 'Terseness injected')"
echo "clamped: $(gc "$os_log" 'Clamped')"
echo "plugin_loaded: $(gc "$os_log" 'Plugin loaded')"
echo "bytes: $(log_size "$os_log")"
echo "-- lines/day:"
lines_per_day "$os_log"

# ===================== aspect-dynamics =====================
echo "== aspect-dynamics"
ad_log="$LOG_DIR/aspect-dynamics.log"
ad_ev="$DATA_DIR/aspect-dynamics/events.jsonl"
echo "plugin_loaded(log): $(gc "$ad_log" 'Plugin loaded')"
if [ -f "$ad_ev" ]; then
  echo "-- event histogram:"
  jq -r '.event' "$ad_ev" 2>/dev/null | sort | uniq -c || true
  echo "-- nudge_sent/score ratio:"
  jq -rs '
    {sent: ([.[] | select(.event == "nudge_sent")] | length),
     scored: ([.[] | select(.event == "score")] | length)} |
    "nudge_sent=\(.sent) score=\(.scored) ratio=\(if .scored > 0 then (.sent / .scored) else 0 end)"
  ' "$ad_ev" 2>/dev/null || echo "(jq error)"
else
  echo "events.jsonl: MISSING"
fi

# ===================== skill-nudger =====================
echo "== skill-nudger"
sn_ev="$DATA_DIR/skill-nudger/events.jsonl"
if [ -f "$sn_ev" ]; then
  echo "-- nudge_delivered by rule:"
  jq -r 'select(.event == "nudge_delivered") | .rule' "$sn_ev" 2>/dev/null | sort | uniq -c || true
  echo "-- skip by reason:"
  jq -r 'select(.event == "skip") | .reason' "$sn_ev" 2>/dev/null | sort | uniq -c || true
  echo "-- queued vs delivered:"
  jq -rs '
    {queued: ([.[] | select(.event == "nudge_queued")] | length),
     delivered: ([.[] | select(.event == "nudge_delivered")] | length)} |
    "queued=\(.queued) delivered=\(.delivered)"
  ' "$sn_ev" 2>/dev/null || echo "(jq error)"
else
  echo "events.jsonl: MISSING"
fi

# ===================== provider-connect-retry =====================
echo "== provider-connect-retry"
rp_log="$LOG_DIR/retry-plugin.log"
echo "error_matched_rule: $(gc "$rp_log" 'Error matched rule')"
echo "exhausted_retries: $(gc "$rp_log" 'Exhausted retries')"
echo "falling_back: $(gc "$rp_log" 'falling back to')"
if [ -f "$rp_log" ]; then
  echo "-- matched rule histogram:"
  grep -oE 'matched rule "[^"]+"' "$rp_log" | sort | uniq -c || true
else
  echo "matched rule histogram: MISSING"
fi

# ===================== agent-default-guard =====================
echo "== agent-default-guard"
ag_log="$LOG_DIR/agent-default-guard.log"
echo "rewrote_message_agent: $(gc "$ag_log" 'rewrote message agent')"
echo "leaving_build_untouched: $(gc "$ag_log" 'leaving build untouched')"
echo "registry_fetch_failed: $(gc "$ag_log" 'registry fetch failed')"

# ===================== live-config-guard =====================
echo "== live-config-guard"
lc_log="$LOG_DIR/live-config-guard.log"
echo "blocking: $(gc "$lc_log" 'BLOCKING')"
echo "guard_failed_open: $(gc "$lc_log" 'guard failed open')"
