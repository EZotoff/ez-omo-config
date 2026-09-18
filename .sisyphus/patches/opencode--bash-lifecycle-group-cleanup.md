---
patch_id: "opencode--bash-lifecycle-group-cleanup"
dependency: "opencode"
target_file: "packages/opencode/src/tool/shell.ts, packages/core/src/cross-spawn-spawner.ts, packages/core/src/process-group.ts, packages/opencode/src/tool/shell/lifecycle.ts, packages/opencode/src/cli/cmd/durable-run.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-18"
dep_version: "1.18.5-local"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "escaped-observed"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: "server-api, cli-run, tui-interactive"
---

# OpenCode bash lifecycle process-group cleanup

## Problem

Bash tool calls could outlive their declared timeout or return while owned work
was still running. The incident class included `nohup rsync &` being killed by
the tool timeout, orphaned sleep monitors wedging later session work, and an
escaped `setsid` holder retaining the output pipe until its full child lifetime.
The unpatched escaped-holder baseline took about 20012ms rather than returning
within the timeout plus cleanup grace.

## Patch Description

Implements the addendum-v2 lifecycle contract across the shell tool, core spawn
layer, process-group supervisor, lifecycle helper, and `oc-durable-run` CLI:

- identify the owned process group from Linux `/proc/<pid>/stat` field 5;
- enumerate group membership before signaling, so cleanup is enumeration-gated;
- treat process-group quiescence, not leader exit or output EOF, as completion;
- bound output drain when an escaped process retains a pipe;
- await TERM/grace/KILL escalation within fixed bounds;
- disarm lifecycle cleanup only after quiescence is established;
- emit lifecycle telemetry, including the minification-survivor state
  `escaped-observed`;
- register supervised groups so shutdown cleanup can find active ownership; and
- provide `oc-durable-run` for work intentionally meant to outlive a bash tool
  call instead of relying on `nohup` or bare backgrounding.

## Verification

Pattern (necessary, NOT sufficient):

```bash
grep -a -c "escaped-observed" /home/ezotoff/.opencode/bin/opencode
```

The expected result is at least one match. Runtime exercises below remain the
authority for effectiveness because the marker is a preserved string literal.

## Runtime Verification

1. On the CLI surface, run `opencode run --format json` with a prompt requiring
   a bash tool call with `timeout=4000` and command
   `setsid sh -c 'echo $$ > /tmp/opencode/verify9.pid; exec sleep 25' & echo leader-done`,
   followed immediately by a separate `true` call. Confirm the first call is
   well below the 25-second child lifetime and the second completes in under
   two seconds; inspect the recorded PID and clean only that exact escaped PID.
2. Repeat three short escaped-holder calls, each followed by `true`, and confirm
   every call remains bounded and every follow-up completes in under two seconds.
3. Run `tests/regressions/bash-group-cleanup-timeout.sh` and
   `tests/regressions/bash-pipe-wedge-bounded.sh`; both must exit 0. Run each
   paired `.kill.sh` afterward to remove only recorded test PIDs.
4. Against the interactive server at `http://127.0.0.1:3030`, create a session
   through its authenticated API, dispatch the equivalent wedge prompt, and
   observe the session return to idle promptly with a completed bash tool part
   and an immediate follow-up. Never print the authentication password.
5. Regression signal: a call lasts approximately the child lifetime, a contained
   child survives group cleanup, a follow-up takes two seconds or more, either
   regression exits nonzero, or either surface fails to return to idle. On any
   such signal, keep `runtime_effective: false` and do not claim the patch works.

## Reapply Instructions

1. Check out the exact release tag matching the live OpenCode version; never
   build this patch from `dev`. Then cherry-pick this patch onto a branch
   that ALREADY carries every other active binary patch — base on the
   aggregate branch `fix/all-patches-v1.18.5` (fork `EZotoff/opencode`), or
   cherry-pick all of its commits. Rebuilding from a patch-less base silently
   drops every other patch (2026-09-18 11:32 incident: this patch's rebuild
   dropped turn-summary-timestamp + 5 TUI patches; caught by the operator
   hours later; restored via `fix/all-patches-v1.18.5`).
2. Reapply the process-group supervisor and `/proc` field-5 identity logic in
   `packages/core/src/process-group.ts` and
   `packages/core/src/cross-spawn-spawner.ts`.
3. Reapply shell lifecycle integration in
   `packages/opencode/src/tool/shell.ts` and
   `packages/opencode/src/tool/shell/lifecycle.ts`, preserving enumeration-gated
   kill, bounded drain/escalation, disarm, telemetry, and registry behavior.
4. Reapply `packages/opencode/src/cli/cmd/durable-run.ts` and its CLI registration
   so intentionally durable work has an explicit supervised path.
5. Run the source test suite and both paired regression tests, then build with
   `OPENCODE_VERSION=<live-version> bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
6. Verify the built version and `escaped-observed` marker, back up the live
   binary, install it while both OpenCode services are stopped, restart both
   services with continuation enabled, and repeat every Runtime Verification
   step before setting `runtime_effective: true`.

## Durable Alternative

This behavior belongs in OpenCode's process-launch and bash-tool lifecycle; a
plugin or configuration option cannot establish process-group ownership or
guarantee bounded descriptor drain. Upstreaming the source implementation would
remove the local binary rebuild and patch-registry burden.

Status: not-yet-pursued
