// live-config-guard.mjs — config-layer plugin
//
// Blocks write-intent operations against the LIVE OpenCode/OMO config surface
// from sessions that do not belong to the config store repo (~/ez-omo-config).
//
// Why this exists (2026-09-10 and 2026-09-12 incidents, both caused by
// benchmark-sandbox builders in OTHER projects): ~/.config/opencode/opencode.json
// and ~/.config/opencode/oh-my-openagent.json are symlinks into the versioned
// config store. Sandbox setup scripts that use a shell-variable alt-root
// (e.g. `cat > $A/home/.config/opencode/opencode.json`) hit sessions where the
// variable expanded EMPTY (each bash tool call is a fresh shell), so the write
// resolved through the live symlinks and gutted the tracked config. Running
// servers masked the damage until the next restart/reboot reloaded it — OMO and
// all plugins were silently dead on boot (missing file-path plugins are skipped
// without any error log).
//
// Policy: ALL changes to OpenCode/OMO config come through sessions working in
// ~/ez-omo-config (including its worktrees). Other projects may READ the live
// config but never write, move, delete, or chmod it. File-edit tools (write/
// edit) are additionally blocked from touching the store's configs/ tree from
// outside the repo — the sanctioned edit path is a session in the repo itself.
//
// Detection notes:
//   - Substring matching catches the exact empty-expansion incident shape:
//     `cat > $A/home/.config/opencode/opencode.json <<EOF` contains the live
//     path as a literal suffix of the redirect target token.
//   - Reads are never blocked: `cat`/`json.load(open(p))` without write signals
//     pass through. The classifier errs toward blocking only when a protected
//     path is named AND a write signal is present.
//   - Exemption: any candidate working directory (bash workdir arg, session
//     directory) that is inside ~/ez-omo-config or is a git worktree whose
//     toplevel is ~/ez-omo-config.
//
// Fail-open on internal errors; the ONLY thrown error is a deliberate block
// (same BLOCKING contract as git-safety.ts).

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const PATHS = {
  log: path.join(os.homedir(), ".config", "opencode", "live-config-guard.log"),
  repo: path.join(os.homedir(), "ez-omo-config"),
};

// Test-isolation hook via globalThis (same pattern as agent-default-guard).
// MUST NOT be a module export: OpenCode's plugin loader rejects any module
// with a non-function export.
const testPaths = () => globalThis.__liveConfigGuardTestPaths ?? {};
const logPath = () => testPaths().log ?? PATHS.log;
const repoRoot = () => testPaths().repo ?? PATHS.repo;

const LOG_MAX_BYTES = 2 * 1024 * 1024;

// Substrings that identify the live config surface. Matched anywhere in a
// command string — this is what catches `$VAR`-prefixed paths whose variable
// expands empty at runtime (the actual incident shape).
const PROTECTED_SUBSTRINGS = [
  ".config/opencode/opencode.json",
  ".config/opencode/oh-my-openagent.json",
  ".config/opencode/opencode.jsonc",
];

function log(level, msg) {
  const line = `[${new Date().toISOString()}] [${level}] ${msg}\n`;
  try {
    try {
      const stat = fs.statSync(logPath());
      if (stat.size > LOG_MAX_BYTES) {
        const backup = `${logPath()}.1`;
        try { fs.unlinkSync(backup); } catch {}
        try { fs.renameSync(logPath(), backup); } catch {}
      }
    } catch {}
    fs.appendFileSync(logPath(), line);
  } catch {}
  // No console.* — raw output leaks into the TUI viewport / journald.
}

const toplevelCache = new Map();

// Returns { toplevel, mainRoot } for a directory: the checkout's toplevel and
// the MAIN repository root (via --git-common-dir, so linked worktrees of the
// config repo resolve to the repo root even though their toplevel is the
// worktree path itself).
function gitIdentity(dir) {
  if (toplevelCache.has(dir)) return toplevelCache.get(dir);
  const identity = { toplevel: null, mainRoot: null };
  try {
    identity.toplevel =
      execFileSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], {
        encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "ignore"],
      }).trim() || null;
  } catch {}
  try {
    const commonDir =
      execFileSync("git", ["-C", dir, "rev-parse", "--git-common-dir"], {
        encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "ignore"],
      }).trim() || null;
    if (commonDir) {
      const abs = path.resolve(dir, commonDir);
      identity.mainRoot = abs.endsWith(".git") ? path.dirname(abs) : abs;
    }
  } catch {}
  toplevelCache.set(dir, identity);
  return identity;
}

function isRepoSession(candidateDirs) {
  const root = repoRoot();
  for (const dir of candidateDirs) {
    if (!dir || typeof dir !== "string") continue;
    const resolved = path.resolve(dir);
    if (resolved === root || resolved.startsWith(root + path.sep)) return true;
    const { toplevel, mainRoot } = gitIdentity(resolved);
    if (toplevel && (toplevel === root || toplevel.startsWith(root + path.sep))) return true;
    if (mainRoot && (mainRoot === root || mainRoot.startsWith(root + path.sep))) return true;
  }
  return false;
}

function hasProtectedSubstring(text) {
  return PROTECTED_SUBSTRINGS.some((s) => text.includes(s));
}

// Write-intent classifier for bash-like command strings. Assumes the command
// already names a protected path (checked by the caller).
function bashWriteIntent(command) {
  // Redirect targets: `> file`, `>> file` (skip 2>/&> fd-only forms whose target
  // is another stream). If the target token contains a protected substring,
  // this is a write through the live surface.
  const redirects = command.matchAll(/(?<![0-9&>])>{1,2}\s*([^\s;|&<]+)/g);
  for (const m of redirects) {
    if (hasProtectedSubstring(m[1])) return `redirect to ${m[1]}`;
  }

  for (const s of PROTECTED_SUBSTRINGS) {
    // tee writing into the protected path
    if (new RegExp(`\\btee\\b[^|;&]*${escapeRegex(s)}`).test(command)) return `tee ${s}`;
    // file-mutation commands with the protected path as any operand
    // (cp/rsync source reads are collateral — fail-safe, rerun from the repo)
    if (new RegExp(`\\b(cp|mv|rsync|install|rm|unlink|chmod|chown)\\b[^|;&]*${escapeRegex(s)}`).test(command)) {
      return `mutating command touching ${s}`;
    }
    // in-place stream editors
    if (new RegExp(`\\b(sed|perl|gawk)\\b[^|;&]*\\s-i\\b[^|;&]*${escapeRegex(s)}`).test(command)) {
      return `in-place edit of ${s}`;
    }
  }

  // Inline python writing to the protected path: the path is named AND a write
  // signal appears (open mode "w"/"a", write_text, dump, remove/unlink,
  // shutil, rename). Pure reads (json.load(open(p))) carry none of these.
  if (/\bpython3?\b/.test(command) && hasProtectedSubstring(command)) {
    if (
      /,\s*['"][wa]['"]/.test(command) ||
      /write_text|json\.dump|yaml\.dump|os\.remove|os\.unlink|shutil\.|\.rename\(/.test(command)
    ) {
      return "python write signal with protected path";
    }
  }

  return null;
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
}

// Expand a leading ~ or $HOME for file-tool paths.
function expandHome(p) {
  if (!p || typeof p !== "string") return p;
  if (p === "~") return os.homedir();
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
  const homeEnv = `$HOME`;
  if (p.startsWith(homeEnv + "/")) return path.join(os.homedir(), p.slice(homeEnv.length + 1));
  return p;
}

function fileToolViolation(filePath) {
  const resolved = path.resolve(expandHome(filePath));
  const liveDir = path.join(os.homedir(), ".config", "opencode");
  for (const name of ["opencode.json", "oh-my-openagent.json", "opencode.jsonc"]) {
    const protectedPath = path.join(liveDir, name);
    if (resolved === protectedPath || resolved.startsWith(protectedPath + path.sep)) {
      return `write/edit on live config ${protectedPath}`;
    }
  }
  const configsRoot = path.join(repoRoot(), "configs");
  if (resolved.startsWith(configsRoot + path.sep)) {
    return `write/edit on config store ${resolved} from outside the config repo`;
  }
  return null;
}

const LiveConfigGuardPlugin = async (input) => {
  const sessionDirectory = input?.directory;

  return {
    "tool.execute.before": async (toolInput, output) => {
      const start = performance.now();
      let blockReason = null;
      let command = null;
      // False-positive accounting (perf-review task 11): command_class=write
      // means a block fired; read = bash-like pass that named a protected
      // path (bashWriteIntent returned null); benign = file-tool pass. The
      // block/(block+read) ratio derivable from these lines is the FP rate.
      let guardMetric = null;
      try {
        const tool = toolInput?.tool;
        const args = output?.args ?? {};
        const candidateDirs = [args.workdir, sessionDirectory];

        if (tool === "bash" || tool === "terminal") {
          command = args.command;
          if (typeof command === "string" && command &&
              hasProtectedSubstring(command) && !isRepoSession(candidateDirs)) {
            blockReason = bashWriteIntent(command);
            if (!blockReason) guardMetric = "command_class=read";
          }
        } else if (tool === "interactive_bash" || tool === "tmux") {
          command = args.tmux_command;
          if (typeof command === "string" && command &&
              hasProtectedSubstring(command) && !isRepoSession(candidateDirs)) {
            blockReason = bashWriteIntent(command);
            if (!blockReason) guardMetric = "command_class=read";
          }
        } else if (tool === "write" || tool === "edit") {
          const filePath = args.filePath;
          if (typeof filePath === "string" && filePath &&
              !isRepoSession(candidateDirs)) {
            blockReason = fileToolViolation(filePath);
            if (!blockReason) guardMetric = "command_class=benign";
          }
        }

        if (blockReason) guardMetric = `block=${blockReason} command_class=write`;

        // Instrumentation: emitted on every hook call, BEFORE any blocking
        // throw propagates. dur_ms covers the classifier body only. log()
        // never throws, so timing is fail-open.
        log(
          "info",
          `hook=tool.execute.before dur_ms=${(performance.now() - start).toFixed(3)} tool=${toolInput?.tool} verdict=${blockReason ? "block" : "pass"}`,
        );
        if (guardMetric) log("info", `guard_metric ${guardMetric}`);

        if (blockReason) {
          log("warn", `BLOCKING (${blockReason}): ${String(command).slice(0, 300)}`);
          throw new Error(
            `[LIVE CONFIG GUARD] BLOCKED: ${blockReason}\n\n` +
            `Command: ${String(command).slice(0, 300)}\n\n` +
            `The live OpenCode/OMO config (~/.config/opencode/*.json, symlinked into\n` +
            `~/ez-omo-config) is write-protected outside the config repo. Two incidents\n` +
            `(2026-09-10, 2026-09-12) destroyed the live config through sandbox scripts\n` +
            `whose alt-root variable expanded empty — this guard exists so it cannot\n` +
            `happen again.\n\n` +
            `To change OpenCode/OMO config: work in a session inside ~/ez-omo-config\n` +
            `(edit the store files, commit, then restart the opencode services).\n` +
            `For sandbox setups: write sandbox configs ONLY under the sandbox root with\n` +
            `the root assigned in the same shell invocation (set -euo pipefail).`,
          );
        }
      } catch (error) {
        // Deliberate blocks must propagate; anything else fails open.
        if (error && String(error.message).startsWith("[LIVE CONFIG GUARD]")) throw error;
        log("warn", `guard failed open: ${error?.message ?? error}`);
      }
    },
  };
};

export default LiveConfigGuardPlugin;
