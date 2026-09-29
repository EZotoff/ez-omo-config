#!/usr/bin/env bash
# Kill-switch: restores the pre-fix SDK SSE finally block (releaseLock only),
# reintroducing the socket leak. Run to verify the regression test FAILS on
# the unfixed source.
set -o errexit
SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
FILE="$SRC/packages/sdk/js/src/gen/core/serverSentEvents.gen.ts"
git -C "$SRC" stash push -- "$FILE" >/dev/null 2>&1 || true
python3 - "$FILE" <<'EOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
# strip the teardown: cancel + conn.abort lines out of the inner finally
s = s.replace("          conn.abort()\n", "")
s = re.sub(r"          // Secondary belt-and-braces: cancel the body stream\.\n          try \{\n            await reader\.cancel\(\)\n          \} catch \{\n            // noop\n          \}\n", "", s)
open(p, "w").write(s)
EOF
echo "kill: SSE teardown removed from $FILE (re-apply via git checkout)"
