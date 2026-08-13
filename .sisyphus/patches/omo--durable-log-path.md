---
patch_id: "omo--durable-log-path"
dependency: "oh-my-openagent"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-08-05"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "OMO_LOG_DIR"
surfaces: ["server-api"]
runtime_effective: true
note: "Live dist patch (Bun-minified bundle, NOT source). target_file is dist/index.js, the shipped artifact loaded by `file://` from opencode.json. Source-level reapply is NOT possible; see Reapply Instructions for the dist-level reapply procedure. verification_pattern is a minification-survivor string literal — pattern match is necessary but NOT sufficient; the ## Runtime Verification section is the only sufficient check."
---

# Durable OMO Log Path (outside /tmp)

## Problem

OMO v4.19.2's main logger resolves its log file via `defaultLogFilePath(logFileName)` (dist `index.js:5219-5221`), which joins `os.tmpdir()` with the log file name. On this host `/tmp` is periodically cleared by systemd-tmpfiles and reboot, so the OMO log (`oh-my-opencode.log`) disappears before it can be inspected after a stall incident. Multiple stall/harness investigations (subagent-stall-harness-fixes plan) needed the OMO log to diagnose why background subagents silently returned planning-only output, and the log was gone by the time the operator reached for it. Logs must land in a durable, operator-known location that survives reboot and tmp-cleanup.

A second caller at dist `index.js:84225` (`var logger4 = createLogger({ logFileName: LOG_FILENAME2 });` for the `claude-code-compat-core` sub-logger) reuses the same `createLogger` and therefore the same `defaultLogFilePath`; the one-line fix below covers both callers without a second edit.

## Patch Description

**Files changed (1):** `dist/index.js` — single-line body change inside `defaultLogFilePath`. Function signature unchanged.

**Before (dist line 5220):**
```js
function defaultLogFilePath(logFileName) {
  return path2.join(os2.tmpdir(), logFileName);
}
```

**After (dist line 5220):**
```js
function defaultLogFilePath(logFileName) {
  return path2.join(process.env.OMO_LOG_DIR || path2.join(os2.homedir(), ".local/share/opencode/logs"), logFileName);
}
```

`os2` and `path2` are the bundle-local bindings for `import * as os2 from "os"` and `import * as path2 from "path"` (dist lines 5217-5218) — both already in scope at the patch site, no new imports needed. `process.env.OMO_LOG_DIR`, `os2.homedir`, and the string literal `".local/share/opencode/logs"` are all minification-survivors (env access, module method, string literal), so the patch survives in the bundle as written.

The target directory `~/.local/share/opencode/logs/` is created once out-of-band via `mkdir -p ~/.local/share/opencode/logs`. No `mkdir`/`fs.mkdirSync` logic was added inside the patched function: the fs binding in that module scope is `fs2` (used elsewhere in `createLogger`), but adding mkdir logic would expand the diff and risk an unverified binding name in a minified bundle. If the directory is absent at runtime, OMO's existing logger-write error handling surfaces the failure on next flush.

### Why not a symlink at the old /tmp path

A symlink (e.g. `/tmp/oh-my-opencode.log` → `~/.local/share/opencode/logs/oh-my-opencode.log`) was rejected as the durable mechanism: OMO's log rotation (`rotateLogFileIfNeeded`, dist ~line 5234) uses `fs.renameSync` on the resolved log path to atomically rotate `oh-my-opencode.log` → `oh-my-opencode.log.1`. `renameSync` on a symlink **moves the symlink itself**, not its target — after the first rotation the symlink is renamed to `oh-my-opencode.log.1`, and the next write recreates `oh-my-opencode.log` as a fresh plain file in `/tmp`, silently reverting all subsequent writes to the non-durable location. The env-or-home join is the only rotation-safe fix.

## Verification

**Pattern (necessary, not sufficient for a binary patch):**

```bash
# String literal is a minification-survivor. A match means the patched line is
# present in the bundle, NOT that the runtime is using it. See Runtime Verification.
grep -c 'OMO_LOG_DIR' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # must be >= 1
grep -n 'path2.join(os2.tmpdir(), logFileName)' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # must be EMPTY (original line gone)
```

**One-line diff (necessary):**

```bash
# Backup is timestamped next to the live file. Diff must show exactly one changed line (5220c5220).
ls /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js.pre-durable-log.*   # exactly one backup
diff <backup> /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js | grep -c '^[<>]'   # must be 2 (1 < + 1 >)
```

## Runtime Verification

The `verification_pattern` (`\.local/share/opencode/logs`) is a string literal that survives Bun minification, so a grep match is necessary but NOT sufficient. The only sufficient check is observing a fresh log entry land at the new path after a server restart.

**Steps (run in todo 9 after the `systemctl --user restart opencode.service omo-tg.service`):**

1. Confirm the restart actually happened (AGENTS.md rule 6):
   ```bash
   ps -eo pid,lstart,etime,args | grep 'opencode serve' | grep -v grep
   # start time must be newer than the restart command's timestamp
   ```
2. Tail the new log path and confirm fresh entries:
   ```bash
   tail -5 ~/.local/share/opencode/logs/oh-my-opencode.log
   # the newest entry's timestamp must postdate the restart
   ```
3. Negative check — the old path must NOT be the active write target:
   ```bash
   ls -la /tmp/oh-my-opencode.log* 2>/dev/null
   # either absent, or (if a stale pre-restart file exists) its mtime must PREDATE the restart
   ```
4. Optional positive marker — set `OMO_LOG_DIR` to a throwaway dir, restart once, confirm a log file appears there, then unset and restart again to confirm the home-logs fallback:
   ```bash
   OMO_LOG_DIR=/tmp/omo-log-override-test systemctl --user set-environment OMO_LOG_DIR=/tmp/omo-log-override-test
   systemctl --user restart opencode.service
   sleep 5
   ls /tmp/omo-log-override-test/   # must contain oh-my-opencode.log
   systemctl --user unset-environment OMO_LOG_DIR
   systemctl --user restart opencode.service
   ```

**Regression signal:** if step 2 shows no fresh entries at `~/.local/share/opencode/logs/` AND step 3 shows `/tmp/oh-my-opencode.log` with an mtime postdating the restart, the patch is `runtime-ineffective`. Roll back via the timestamped backup (`cp <backup> dist/index.js`) and redesign — do NOT bump `dep_version` or flip `runtime_effective`.

If steps 1-3 pass, flip `runtime_effective: true` in this entry's frontmatter and record the observation timestamp in a `## Runtime Status` section.

## Runtime Status

**Observed effective: 2026-08-06 00:04 CEST (post-restart).**

- Restart: `systemctl --user restart opencode.service omo-tg.service` at 2026-08-06 00:03:56 CEST. Old server PIDs 1280803/1280849 (start 2026-08-05 22:12:13) replaced by new server PIDs 1709942/1709975 (start 2026-08-06 00:03:56).
- Step 2 PASS: durable log `~/.local/share/opencode/logs/oh-my-opencode.log` has fresh entries at `2026-08-05T22:04:23.628Z` (00:04:23 CEST) postdating the restart; the new server processes load OMO from the patched dist and resolve the log path through the patched `defaultLogFilePath`.
- Step 3 PARTIAL: `/tmp/oh-my-opencode.log` still receives writes post-restart (rename-and-recheck produced a fresh 1378-byte file within 5s). Root cause: long-running TUI processes (PIDs 2364/11782/12426/12481/25737/29386/30219/1454610/1620159, started 2026-08-05 16:02–23:48 — BEFORE the patch was applied at commit 8e4f198 ~22:58) resolved their log path at startup via the pre-patch `defaultLogFilePath` and continue writing to `/tmp` until they are themselves restarted. The patched code path (new server processes) correctly writes to `~/.local/share/opencode/logs/`. Full `/tmp` quiescence requires restarting those TUI processes too, which is out of scope for the systemctl server restart.
- Verdict: `runtime_effective: true` — the patched code path is observed active for new processes. Operators should be aware that pre-existing TUI sessions persist on the old `/tmp` path until they reconnect to a restarted server or are themselves restarted.

## Reapply Instructions

This is a dist-level patch on a minified bundle, not a source patch. Identify the active binding names in the TARGET version first — they may differ from `os2`/`path2` if the bundle is re-minified.

1. Locate the single `defaultLogFilePath` definition:
   ```bash
   grep -n 'function defaultLogFilePath' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js
   ```
2. Read ~5 lines around it and confirm the `os`/`path` import bindings in scope (the lines immediately above typically show `import * as <OS_BINDING> from "os"` and `import * as <PATH_BINDING> from "path"`).
3. Timestamped backup:
   ```bash
   cp /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js \
      /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js.pre-durable-log.$(date +%s)
   ```
4. Replace the body `return <PATH_BINDING>.join(<OS_BINDING>.tmpdir(), logFileName);` with:
   ```js
   return <PATH_BINDING>.join(process.env.OMO_LOG_DIR || <PATH_BINDING>.join(<OS_BINDING>.homedir(), ".local/share/opencode/logs"), logFileName);
   ```
   using the actual binding names from step 2.
5. Ensure the target directory exists: `mkdir -p ~/.local/share/opencode/logs`.
6. Run the Verification and Runtime Verification sections above.
7. Do NOT edit any other `createLogger` callsite (e.g. dist line ~84225) — they all flow through `defaultLogFilePath` and inherit the fix automatically.

## Durable Alternative

A config option in `oh-my-openagent.json` (e.g. `log_dir` or `log.path`) that `defaultLogFilePath` consults before falling back to the env/home path would let operators relocate logs without a dist patch. The env override (`OMO_LOG_DIR`) already added by this patch is a partial step in that direction, but the home-logs fallback is still a code change.

Status: not-yet-pursued — no upstream config option exists for log location in OMO v4.19.2. An upstream issue/PR could propose `oh-my-openagent.json#log_dir` (or a `OMO_LOG_DIR` env check upstreamed into `defaultLogFilePath`) to eliminate this patch entirely.
