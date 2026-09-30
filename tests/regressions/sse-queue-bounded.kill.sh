#!/usr/bin/env bash
# Kill-switch: restore unbounded queues (pre-fix) to verify the test FAILS.
set -o errexit
SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
E="$SRC/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
G="$SRC/packages/opencode/src/server/routes/instance/httpapi/handlers/global.ts"
python3 - "$E" "$G" <<'EOF'
import sys
e,g=sys.argv[1],sys.argv[2]
s=open(e).read()
s=s.replace("Queue.sliding<EventV2.Payload>(256)","Queue.unbounded<EventV2.Payload>()")
open(e,'w').write(s)
s=open(g).read()
s=s.replace("      { bufferSize: 256, strategy: \"sliding\" },\n","")
open(g,'w').write(s)
EOF
echo "kill: unbounded queues restored (re-apply via git checkout)"
