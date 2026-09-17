// tests/live-config-guard/harness.mjs
// Unit harness for the live-config-guard config-layer plugin.
//
// Contract under test:
//   - bash/terminal/tmux commands with write intent against the live config
//     surface are BLOCKED (throw) from non-repo sessions — including the exact
//     empty-alt-root incident shapes (`cat > $A/home/.config/opencode/opencode.json`).
//   - Read-only commands naming the live config are NOT blocked.
//   - Sessions inside the config repo (or its worktrees) are exempt.
//   - write/edit tools on the live surface or the store configs/ tree are
//     blocked from non-repo sessions; repo sessions exempt.
//   - Internal errors fail open; only deliberate blocks throw.

import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";

const PLUGIN_PATH = new URL("../../configs/opencode/live-config-guard.mjs", import.meta.url).pathname;

let passed = 0;
let failed = 0;

function check(cond, msg) {
  if (cond) {
    passed++;
    console.log(`PASS: ${msg}`);
  } else {
    failed++;
    console.log(`FAIL: ${msg}`);
  }
}

const FIXTURES = mkdtempSync(join(tmpdir(), "live-config-guard-"));

// A fake "other project" dir that IS a git repo (so git-toplevel resolves, but
// to itself — not the config repo). This exercises the worktree-exemption logic
// negatively: being a git repo is not enough; toplevel must be the config repo.
const OTHER_PROJECT = join(FIXTURES, "other-project");
mkdirSync(OTHER_PROJECT);
execFileSync("git", ["-C", OTHER_PROJECT, "init", "-q"]);

// A worktree of the config repo must be exempt.
const REPO_CHECKOUT = new URL("../../", import.meta.url).pathname.replace(/\/$/, "");
const REPO_COMMON_DIR = execFileSync(
  "git",
  ["-C", REPO_CHECKOUT, "rev-parse", "--path-format=absolute", "--git-common-dir"],
  { encoding: "utf8" },
).trim();
const REPO_ROOT = basename(REPO_COMMON_DIR) === ".git" ? dirname(REPO_COMMON_DIR) : REPO_COMMON_DIR;
const WT = join(FIXTURES, "cfg-worktree");
execFileSync("git", ["-C", REPO_CHECKOUT, "worktree", "add", "-q", "--detach", WT, "HEAD"]);
const WT_TOPLEVEL = execFileSync("git", ["-C", WT, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const WT_COMMON_DIR = execFileSync(
  "git",
  ["-C", WT, "rev-parse", "--path-format=absolute", "--git-common-dir"],
  { encoding: "utf8" },
).trim();
const WT_MAIN_ROOT = basename(WT_COMMON_DIR) === ".git" ? dirname(WT_COMMON_DIR) : WT_COMMON_DIR;
if (WT_TOPLEVEL !== WT || WT_MAIN_ROOT !== REPO_ROOT) {
  throw new Error("linked-worktree fixture does not share the configured repository identity");
}
// The plugin under test may be uncommitted; the worktree only needs to resolve
// its toplevel, which does not depend on tracked state.

globalThis.__liveConfigGuardTestPaths = {
  log: join(FIXTURES, "guard.log"),
  repo: REPO_ROOT,
};

const { default: buildPlugin } = await import(PLUGIN_PATH);

const plugin = await buildPlugin({ directory: OTHER_PROJECT });
const repoPlugin = await buildPlugin({ directory: REPO_ROOT });
const wtPlugin = await buildPlugin({ directory: WT });

async function expectBlock(p, tool, args, msg) {
  try {
    await p["tool.execute.before"]({ tool }, { args });
    check(false, `${msg} — expected throw`);
  } catch (e) {
    check(String(e.message).startsWith("[LIVE CONFIG GUARD]"), `${msg} — threw guard error`);
  }
}

async function expectPass(p, tool, args, msg) {
  try {
    await p["tool.execute.before"]({ tool }, { args });
    check(true, msg);
  } catch (e) {
    check(false, `${msg} — unexpected throw: ${String(e.message).slice(0, 120)}`);
  }
}

const HOME = process.env.HOME;

// ---- Incident shapes (must BLOCK from a non-repo session) ----
await expectBlock(
  plugin, "bash",
  { command: `cat > $A/home/.config/opencode/opencode.json <<'EOF'\n{"x":1}\nEOF` },
  "incident-2 shape: cat > $A/... heredoc (empty $A)",
);
await expectBlock(
  plugin, "bash",
  { command: `python3 -c "import json; d=json.load(open('$A/home/.config/opencode/opencode.json')); d['plugin']=[]; json.dump(d,open('$A/home/.config/opencode/opencode.json','w'))"` },
  "incident-2 shape: python json.dump rewrite via $A",
);
await expectBlock(
  plugin, "bash",
  { command: `rm -f $A/home/.config/opencode/oh-my-openagent.json` },
  "incident-2 shape: rm via $A",
);
await expectBlock(
  plugin, "bash",
  { command: `echo '{}' > ~/ez-omo-sandbox/home/.config/opencode/oh-my-openagent.json` },
  "sandbox-path redirect containing live substring",
);
await expectBlock(
  plugin, "bash",
  { command: `cat minimal.json | tee ~/.config/opencode/opencode.json` },
  "tee into live config",
);
await expectBlock(
  plugin, "bash",
  { command: `cp /tmp/x.json ~/.config/opencode/opencode.json` },
  "cp over live config",
);
await expectBlock(
  plugin, "bash",
  { command: `sed -i 's/a/b/' ${HOME}/.config/opencode/oh-my-openagent.json` },
  "sed -i on live config",
);
await expectBlock(
  plugin, "bash",
  { command: `rsync -a tmpl/ $A/home/.config/opencode/ && mv /tmp/new.json $A/home/.config/opencode/opencode.json` },
  "mv into live config via $A",
);
await expectBlock(
  plugin, "tmux",
  { tmux_command: `send-keys -t sbx "cat > $A/home/.config/opencode/opencode.json" Enter` },
  "tmux channel write via $A",
);

// ---- Reads (must PASS) ----
await expectPass(
  plugin, "bash",
  { command: `cat ~/.config/opencode/opencode.json | jq '.plugin | length'` },
  "read: cat live config",
);
await expectPass(
  plugin, "bash",
  { command: `python3 -c "import json; c=json.load(open('$A/home/.config/opencode/opencode.json')); print(len(c['plugin']))"` },
  "read: python json.load via $A (no write signal)",
);
await expectPass(
  plugin, "bash",
  { command: `ls -la ~/.config/opencode/` },
  "read: listing config dir",
);
await expectPass(
  plugin, "bash",
  { command: `diff <(cat ~/.config/opencode/opencode.json) /tmp/template.json > /tmp/diff.txt` },
  "read with redirect to unrelated file",
);

// ---- Repo sessions (must PASS — sanctioned path) ----
await expectPass(
  repoPlugin, "bash",
  { command: `cat > ~/.config/opencode/opencode.json <<'EOF'\n{}\nEOF`, workdir: REPO_ROOT },
  "repo session: write via live symlink allowed",
);
await expectPass(
  wtPlugin, "bash",
  { command: `python3 -c "import json; d={}; json.dump(d, open('$HOME/.config/opencode/opencode.json','w'))"` },
  "config-repo worktree session: python write allowed",
);
await expectPass(
  repoPlugin, "write",
  { filePath: `${REPO_ROOT}/configs/opencode/opencode.json` },
  "repo session: write tool on store file allowed",
);

// ---- File tools from non-repo sessions (must BLOCK) ----
await expectBlock(
  plugin, "write",
  { filePath: `${HOME}/.config/opencode/opencode.json` },
  "write tool on live config from other project",
);
await expectBlock(
  plugin, "edit",
  { filePath: `~/.config/opencode/oh-my-openagent.json` },
  "edit tool on live OMO config (tilde path) from other project",
);
await expectBlock(
  plugin, "write",
  { filePath: `${REPO_ROOT}/configs/oh-my-openagent/oh-my-openagent.json` },
  "write tool on store configs/ tree from other project",
);
await expectPass(
  plugin, "write",
  { filePath: `/tmp/harmless.json` },
  "write tool on unrelated path passes",
);
await expectPass(
  plugin, "write",
  { filePath: `${OTHER_PROJECT}/src/app.ts` },
  "write tool on own project file passes",
);

// ---- Non-bash tools / malformed input (fail open) ----
await expectPass(plugin, "read", { filePath: `${HOME}/.config/opencode/opencode.json` }, "read tool untouched");
await expectPass(plugin, "bash", {}, "bash with no command passes");

rmSync(FIXTURES, { recursive: true, force: true });
execFileSync("git", ["-C", REPO_CHECKOUT, "worktree", "remove", "--force", WT]);

console.log(`\nlive-config-guard: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
