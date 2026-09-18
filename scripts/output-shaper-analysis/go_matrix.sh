#!/usr/bin/env bash
# Live wire probe — opencode-go zen gateway (2026-09). Evidence: README.md finding 2.
# curl is REQUIRED: urllib's TLS fingerprint is Cloudflare-banned (403 error 1010).
# Keys are read in-process from auth.json and never printed.
set -euo pipefail
KEY=$(python3 -c "import json;print(json.load(open('/home/ezotoff/.local/share/opencode/auth.json'))['opencode-go']['key'])")
PROMPT="A bat and a ball cost \$1.10 together. The bat costs \$1.00 more than the ball. How much is the ball? Then compute 17*23."
for model in deepseek-v4-pro deepseek-v4-flash; do
  for eff in absent low high; do
    if [ "$eff" = absent ]; then EXTRA=""; else EXTRA=",\"reasoning_effort\":\"$eff\""; fi
    BODY=$(printf '{"model":"%s","max_tokens":3000%s,"messages":[{"role":"user","content":"%s"}]}' "$model" "$EXTRA" "$PROMPT")
    RESP=$(curl -sS -m 120 "https://opencode.ai/zen/go/v1/chat/completions" \
      -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" -A "opencode/1.18.5" -d "$BODY" || true)
    printf "%-18s effort=%-7s -> " "$model" "$eff"
    echo "$RESP" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    if 'error' in d: print('ERROR:', json.dumps(d['error'])[:200]); raise SystemExit
    u=d.get('usage',{}); rc=d['choices'][0]['message'].get('reasoning_content') or ''
    det=u.get('completion_tokens_details') or {}
    print(json.dumps({'completion':u.get('completion_tokens'),'reasoning_detail':det.get('reasoning_tokens'),
        'reasoning_content_len':len(rc.split()) if rc else 0,'finish':d['choices'][0].get('finish_reason')}))
except SystemExit: pass
except Exception as e: print('parse-fail:', str(e)[:120])
"
  done
done
# Observed 2026-09: both models accept reasoning_effort=low (HTTP 200, no 400s)
# and respond monotonically (low < absent < high): v4-pro reasoning 117->92
# (-21%), v4-flash completion 134->85 (-37%). The models-snapshot registry
# values lists (["high","max"]) are picker metadata, not gateway capability.
