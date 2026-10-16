#!/usr/bin/env bash
# Test: scripts/session-wake.sh fire-path contract (Oracle design 2026-10-16,
# docs/rollout-protocol.md §10): exactly-one-fire claim, precondition
# self-cancel, delivery + audit events. arm/cancel are systemd-bound and are
# only syntax-checked here; fire is exercised with a stub curl.
set -uo pipefail

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/session-wake.sh"
REAL_HOME="$HOME"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/cont-swake.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

bash -n "$SCRIPT" && ok "bash -n clean"

export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"   # WAKE_DIR/WAKE_LOG land in scratch
WAKE_DIR="$XDG_STATE_DIR/session-wakes"
WAKE_LOG="$WAKE_DIR/wakes.jsonl"
mkdir -p "$HOME"

# stub curl: logs posts, always succeeds
mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/curl" <<EOF
#!$(command -v python3)
import os, sys
with open(os.environ["STUB_LOG"], "a") as f:
    f.write("post:" + sys.argv[-1] + "\n")
print("ok")
EOF
chmod +x "$SCRATCH/bin/curl"
export PATH="$SCRATCH/bin:$PATH"
export STUB_LOG="$SCRATCH/stub.log"

# minimal env file so server_password resolves (headless default for :3021)
mkdir -p "$HOME/.config/opencode"
printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$HOME/.config/opencode/serve.env"

PROMPT="$WAKE_DIR/test-wake.prompt.md"
mkdir -p "$WAKE_DIR"
printf 'WAKE test — scheduled now. Action: run the report.\n' > "$PROMPT"

# --- 1: precondition exists -> suppressed, no POST, no claim ---------------
touch "$SCRATCH/resolved.marker"
"$SCRIPT" fire --session ses_x --server http://127.0.0.1:3021 --prompt-file "$PROMPT" \
  --unit test-wake --precondition "$SCRATCH/resolved.marker" > "$SCRATCH/out1.txt" 2>&1
if grep -q 'suppressed-precondition' "$WAKE_LOG" && [[ ! -s "$STUB_LOG" ]]; then
  ok "precondition self-cancel: audited, no POST"
else
  bad "precondition suppression failed ($(cat "$SCRATCH/out1.txt"))"
fi

# --- 2: first fire delivers; second fire dup-suppressed --------------------
rm -f "$SCRATCH/resolved.marker"; : > "$STUB_LOG"
"$SCRIPT" fire --session ses_x --server http://127.0.0.1:3021 --prompt-file "$PROMPT" \
  --unit test-wake > "$SCRATCH/out2.txt" 2>&1
"$SCRIPT" fire --session ses_x --server http://127.0.0.1:3021 --prompt-file "$PROMPT" \
  --unit test-wake > "$SCRATCH/out3.txt" 2>&1
POSTS="$(grep -c "post:.*ses_x/prompt_async" "$STUB_LOG" || true)"
if [[ "$POSTS" -eq 1 ]] && grep -q '"event":"delivered"' "$WAKE_LOG" && grep -q 'dup-suppressed' "$WAKE_LOG"; then
  ok "exactly-one delivery + dup-suppressed audit"
else
  bad "claim contract broken: $POSTS posts (out2: $(tail -1 "$SCRATCH/out2.txt"); out3: $(tail -1 "$SCRATCH/out3.txt"))"
fi

# --- 3: every event carries a timezone-stamped ts ---------------------------
if python3 - "$WAKE_LOG" <<'PY'
import json, sys, re
for line in open(sys.argv[1]):
    ts = json.loads(line)["ts"]
    if not re.search(r'[+-]\d{4}$', ts):
        sys.exit(1)
sys.exit(0)
PY
then ok "audit timestamps carry %z"; else bad "audit timestamps missing timezone"; fi

echo "session-wake: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
