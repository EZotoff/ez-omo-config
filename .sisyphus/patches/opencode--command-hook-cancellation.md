---
patch_id: "opencode--command-hook-cancellation"
dependency: "opencode"
target_file: "packages/plugin/src/index.ts, packages/opencode/src/session/prompt.ts, packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-06-26"
dep_version: "1.17.9-local"
upstream_issue: "https://github.com/anomalyco/opencode/pull/18559"
verification_pattern: "cancelled: boolean|commandOutput.cancelled|HttpServerResponse.empty\(\)"
---

# OpenCode command.execute.before cancellation

## Problem
OpenCode runs `command.execute.before` hooks and then unconditionally calls `prompt()` for the command. Local commands such as `/session-info`, `/session-id`, and `/vscode` need to perform a side effect and stop there. Throwing from the hook used to abort the pipeline, but OpenCode 1.17.5+ surfaces plugin hook throws as TUI error toasts. Clearing `output.parts` avoids the throw but still starts the agent with empty/minimal input.

## Patch Description
Adds a `cancelled: boolean` field to the `command.execute.before` hook output type. The command path now passes `{ parts, cancelled: false }` to plugins and returns before `prompt()` when a plugin sets `output.cancelled = true`. The HTTP command handler converts a cancelled command result to an empty response so TUI/API callers do not receive a schema error.

## Verification
```bash
grep -ER "cancelled: boolean|commandOutput.cancelled|HttpServerResponse.empty\(\)" \
  /home/ezotoff/src/opencode/packages/plugin/src/index.ts \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt.ts \
  /home/ezotoff/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts
```

Runtime/build verification:
```bash
cd /home/ezotoff/src/opencode/packages/opencode
PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun test test/session/prompt.test.ts -t "command.execute.before can cancel command dispatch"
PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun run typecheck
OPENCODE_VERSION="$(/home/ezotoff/.opencode/bin/opencode --version)" PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun run script/build.ts --single --skip-install --skip-embed-web-ui
```

## Reapply Instructions
1. In `packages/plugin/src/index.ts`, change `command.execute.before` output from `{ parts: Part[] }` to `{ parts: Part[]; cancelled: boolean }`.
2. In `packages/opencode/src/session/prompt.ts`, widen `Interface.command` to return `SessionV1.WithParts | undefined`, pass `{ parts, cancelled: false }` to `plugin.trigger`, and `return undefined` before `prompt()` when `commandOutput.cancelled` is true.
3. In `packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts`, wrap `promptSvc.command(...)` in a local `result` and return `result ?? HttpServerResponse.empty()`.
4. Rebuild from `/home/ezotoff/src/opencode/packages/opencode` with `OPENCODE_VERSION="$(/home/ezotoff/.opencode/bin/opencode --version)" PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
5. Back up `~/.opencode/bin/opencode`, then atomically replace it with `packages/opencode/dist/opencode-linux-x64/bin/opencode`.
6. Restart OpenCode so the running process uses the patched binary.

## Durable Alternative
Upstream PR #18559 adds the same plugin cancellation concept. Once merged and installed, this local source/binary patch can be deprecated and the local plugins can keep using `output.cancelled = true` against upstream OpenCode.
Status: pursued
