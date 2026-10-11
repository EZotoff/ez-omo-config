# OMO logging regression: durable-path patch lost during rebuild

Observed 2026-10-11, approximately 07:22-07:28 UTC. Written for the operator and maintenance owner. Investigation only: no runtime/source/config edits, service signals, restarts, or model probes were performed.

## Verdict

**Oh-My-OpenAgent (OMO) logging has not stopped. The current plugin writes to `/tmp/oh-my-opencode.log`, not the expected durable directory.** The built bundle lacks the tracked `omo--durable-log-path` patch and has reverted to the upstream temporary-directory resolver. Fresh entries for this investigation's own session prove actual runtime logging, not merely source-code intent.

The immediate restore is the existing one-line dist patch, applied by the maintenance owner with a new build receipt and coordinated continuation-safe restart. A config log-level change will not restore the path. The exact rebuild invocation/actor is not established; do not mislabel a task-scoping merge as a logger-code regression.

## Where logs go, and why

| Finding | Direct evidence |
|---|---|
| Active logging to `/tmp` | Read `/tmp/oh-my-opencode.log:8540`: `[2026-10-11T07:24:52.882Z] [runtime-fallback] first-prompt-watchdog: cancelled (assistant progress observed) {"sessionID":"ses_ed629c361ffe1M7bvmN3qL3VN4"}`. Line 8548 records this same session under `[background-agent]` at `07:24:54.474Z`. This is the current investigation session. |
| Current destination resolver is temporary | [dist/index.js:5219-5220](file:///home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js): `return path2.join(os2.tmpdir(), logFileName);`. Source agrees at [packages/utils/src/logging/logger.ts:33-34](file:///home/ezotoff/oh-my-openagent-v4.19.2/packages/utils/src/logging/logger.ts). |
| Filename is unchanged | [dist/index.js:10068,10077](file:///home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js): product identity sets `logFileName: "oh-my-opencode.log"`, then assigns `LOG_FILENAME`. |
| Initialization occurs at module load | [packages/omo-opencode/src/shared/logger.ts:5-10](file:///home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/shared/logger.ts) creates the logger and configures the shared-subunit logger. Bundled equivalent: [dist/index.js:10099-10106](file:///home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js). The path is resolved once, not per write. |
| No global level gate or stdout redirect in this logger | [dist/index.js:5258-5293](file:///home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js) buffers entries, flushes using `fs2.appendFileSync(logFile, data)`, and catches write errors. No console sink or level check. Defaults are 500 ms or 50 entries: [packages/utils/src/logging/logger.ts:7-8,86-106](file:///home/ezotoff/oh-my-openagent-v4.19.2/packages/utils/src/logging/logger.ts). |
| An absent persistent FD is not evidence of disabled logging | The sink uses synchronous append calls, not a retained file stream: source line 79 / dist line 5264. The parent's FD observation is consistent with either destination. |

`stat` at 07:22:06 UTC reported `/tmp/oh-my-opencode.log` size 14,661,234 bytes, mtime `2026-10-11T07:22:05.392800116Z`. Subsequent `wc -l` reported 8,572 lines, and the targeted read above found fresh subsystem events. No paid CLI probe was needed because the real session already supplied identifying runtime evidence. Attribution to each serve instance individually was not attempted.

### Config explanation ruled out for the shared logger

- Grep of the current bundle for `OMO_LOG|OMO_DEBUG` returned **no matches**. `OMO_LOG`, `OMO_LOG_FILE`, `OMO_LOG_DIR`, and `OMO_DEBUG` cannot change this resolver in this build.
- Grep of `packages/omo-opencode/src/config` for `OMO_LOG|OMO_DEBUG|log_level|logLevel|disable.*log` returned **no matches**. The complete shared logger path above has no config input or enable/disable branch.
- Existing `logLevel: "info"` keys belong to `aspectDynamics`, `outputShaper`, and `skillNudger`, not the shared logger: [configs/oh-my-openagent/oh-my-openagent.json:261-296](file:///home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json).
- Plugin registration is [configs/opencode/opencode.json:26](file:///home/ezotoff/ez-omo-config/configs/opencode/opencode.json), `../../oh-my-openagent-v4.19.2`. `readlink -f` confirmed both active config paths resolve to this repository's store files.

## Breaking mechanism and commit evidence

**Mechanism confirmed: an out-of-flow bundle rebuild discarded a dist-only patch, exposing unchanged upstream source.**

Commands run in the runtime checkout:

```text
git rev-parse HEAD
b6b94302c1596f4e14fd016628a996c8fe149719

TZ=UTC stat -c '%n %y %s' dist/index.js
dist/index.js 2026-10-10 15:48:26.418672515 +0000 5667371

sha256sum dist/index.js
b8508004eb6ee5c825850c179916808d0a2336dff8485245bfee8ad5f5175c90

git diff 6b2d2fe65..b6b94302c -- packages/utils/src/logging/logger.ts packages/omo-opencode/src/shared/logger.ts
(empty)

git log -1 --format='%H %cI %s' -- packages/utils/src/logging/logger.ts
e46dfd822472c27048d773fa110032cec0238c57 2026-06-15T12:08:25+09:00 refactor(utils): add shared logging core
```

All git commands actually used the required `GIT_MASTER=1` prefix; omitted above for readability. `git show e46dfd822:packages/utils/src/logging/logger.ts` confirmed the same temporary resolver. That June commit is source ancestry, **not the October breaking deployment**.

`git log -8` and `git show --stat b6b94302c` establish:

- `b6b94302c` merged task-list session-directory scoping on October 10 at **15:47:52 UTC**; its changes affect task storage/create/get/list/update, not logging.
- `2a2fd5fcd` is the underlying task-scoping fix, committed at **15:47:45 UTC**.
- `f0cdded74` merged task-noop-loop-guard at **14:52:44 UTC**; the logger-path diff across both merges is empty.
- The bundle mtime is 34 seconds after `b6b94302c`. This strongly associates the current rebuild with that maintenance deployment, but mtime and HEAD alone do not prove its invocation, builder, or embedded source revision.

The tracked patch specifies the missing line exactly: [omo--durable-log-path.md:29-43](file:///home/ezotoff/ez-omo-config/.sisyphus/patches/omo--durable-log-path.md). Targeted backup comparisons (not full-bundle diffs) corroborate two distinct build states:

| Bundle inspected | Resolver at line 5220 |
|---|---|
| Current `dist/index.js` | `path2.join(os2.tmpdir(), logFileName)` |
| `index.js.pre-subagent-fallback-inplace`, mtime October 5 09:35:21 UTC | `path2.join(process.env.OMO_LOG_DIR || path2.join(os2.homedir(), ".local/share/opencode/logs"), logFileName)` |
| `index.js.pre-patch-reapply.1790792753`, mtime September 30 18:25:53 UTC | upstream temporary resolver |
| `index.js.pre-dist-patches.1789727963`, mtime September 18 10:39:23 UTC | upstream temporary resolver |

The patch record also documents an October 9 restore after a previous rebuild dropped it: [omo--durable-log-path.md:157-159](file:///home/ezotoff/ez-omo-config/.sisyphus/patches/omo--durable-log-path.md). That is historical documentary evidence, not fresh verification of the earlier build. A bounded Wisdom search found an October 9 candidate pattern describing the same dist-patch-loss mechanism; no authority promotion was assumed.

No exact October 10 logger-breaking **source commit** exists in the inspected range. The actionable breaking artifact is bundle SHA `b8508004...`, with upstream resolver at line 5220. Exact rebuild-command provenance remains unverified. A grep of build receipts for `b6b94302|179164|2026-10-10` returned no matches; that limited search does not establish absence of every possible receipt.

## Timeline caveats: initial observations have changed

The parent supplied October 10 restarts at 21:44:06/21:44:24 UTC and a last durable entry at 21:19:10 UTC. Fresh inspection must not silently preserve those as current facts:

- `systemctl --user show ... -p MainPID -p ExecMainStartTimestamp` now reports headless PID **1194046**, start **October 11 03:44:12 UTC**, and interactive PID **1195413**, start **03:44:30 UTC**. No service action was taken by this investigation.
- The durable file does contain later writes: `/home/ezotoff/.local/share/opencode/logs/oh-my-opencode.log:106918-106936` contains sparse `[tui-sidebar] mirror flush failed` events after the parent's cutoff, ending at **October 11 06:20:59.464 UTC**. `stat` agrees on the mtime. Their writer is not identified; an older in-memory patched process is plausible, not proven.
- Therefore the correct claim is **newly loaded current bundle loses the durable destination**, not “every process stopped logging” or “the durable file has literally zero subsequent writes.” Module-load path resolution explains how mixed process generations can use different destinations.

## Minimal restore proposal (not executed)

1. Maintenance owner coordinates an idle/deployment window and backs up the current bundle. Reapply only the documented resolver replacement at dist line 5220:

   ```js
   return path2.join(process.env.OMO_LOG_DIR || path2.join(os2.homedir(), ".local/share/opencode/logs"), logFileName);
   ```

   The destination directory already exists (verified by `stat`). Do not restore an entire old backup: it predates current task/wake fixes.
2. Record the new artifact SHA and truthful provenance in the standard build receipt; reconcile the patch's present effectiveness metadata. Current [patch frontmatter:6-14](file:///home/ezotoff/ez-omo-config/.sisyphus/patches/omo--durable-log-path.md) still says `runtime_effective: true` even though the marker is absent.
3. Use the documented continuation-safe restart procedure for both servers, outside this read-only investigation. Existing processes retain their resolved path until reloaded.
4. Acceptance: marker present; resolver is no longer `os2.tmpdir()`; an identified real session produces fresh background/fallback entries in the durable file after restart. Attribute evidence to each server independently. Do not demand global `/tmp` quiescence while older processes remain.

**Not config-only:** neither raising `logLevel` nor setting `OMO_LOG_DIR` restores this unpatched build. Do not set `TMPDIR` globally: it redirects unrelated temporary storage. Do not symlink the `/tmp` filename: rotation renames the symlink itself (source logger lines 57-68; tracked patch lines 47-49).

**Small durable follow-up:** carry the same path resolution in OMO fork source (with a regression test) rather than hand-editing every rebuild. Prefer an OMO-specific resolver passed from `packages/omo-opencode/src/shared/logger.ts` through the existing `resolveLogFilePath` option if changing all consumers of the shared utility is undesirable. This is a separate approved implementation, not a prerequisite for the one-line restore.

## Evidence-state table

| State | Diagnosis / restore status |
|---|---|
| repo_implemented | Diagnosis report only; no restore implementation made. Historical restore patch is documented in repo. |
| tests_passed | No code changed or tests run. Source/bundle/history checks and identified-session log observation support the diagnosis; restoration tests remain pending. |
| live_file_installed | Current bundle exists and its SHA/mtime/resolver were inspected. Missing durable-path patch verified in that file. |
| active_config_registered | Active config symlinks verified; store config registers this runtime directory at line 26. |
| runtime_loaded | Logging for this investigation's live session observed in `/tmp`; no attribution probe for both servers separately. |
| real_project_behavior_proven | Current investigation session emits `[runtime-fallback]` and `[background-agent]` events at `/tmp` with its exact session ID. Restored durable-path behavior is not proven. |

Not verified live: restored `runtime_loaded`, restored `real_project_behavior_proven`, and per-server sink attribution. No service/config/source/dist modifications were made. The only deliverable is this report.

**Next action:** maintenance owner reapplies the one-line durable-path patch with receipt and coordinated reload, then captures one identified-session durable-log event from each server before claiming restoration.
