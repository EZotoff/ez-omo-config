#!/usr/bin/env bash
# Kill-switch: restores the directory-equality filter on the instance /event
# route, re-starving cross-directory subscribers. Run to verify the regression
# test FAILS on the unfixed source.
set -o errexit
SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
FILE="$SRC/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
python3 - "$FILE" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace(
    "        (event) =>\n          event.location?.workspaceID === undefined || event.location.workspaceID === workspaceID,",
    "        (event) =>\n          event.location?.directory === instance.directory &&\n          (event.location.workspaceID === undefined || event.location.workspaceID === workspaceID),",
)
open(p, "w").write(s)
EOF
echo "kill: directory filter restored in $FILE (re-apply via git checkout)"
