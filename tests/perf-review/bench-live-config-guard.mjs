// tests/perf-review/bench-live-config-guard.mjs
// Benchmark for the live-config-guard plugin's tool.execute.before hook —
// the hottest interception point (fires on every tool call). Three classes:
//   benign-read-command:   bash read with no protected substring (fast pass)
//   genuine-write-command: bash redirect into the live config (block path)
//   write-edit-tool-call:  write tool on the live config (block path)
// Blocks are the expected verdict on classes 2 and 3; the deliberate guard
// throw is caught inside the workload so it never escapes the benchmark.

import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { asyncBench } from "./lib.mjs";

const PLUGIN_PATH =
  new URL("../../configs/opencode/live-config-guard.mjs", import.meta.url).pathname;

// Route guard logging and repo-exemption checks away from live machine state.
const SANDBOX = mkdtempSync(join(tmpdir(), "bench-live-config-guard-"));
const NON_REPO_DIR = join(SANDBOX, "other-project");
globalThis.__liveConfigGuardTestPaths = {
  log: join(SANDBOX, "guard.log"),
  repo: join(SANDBOX, "not-the-config-repo"),
};

const { default: buildPlugin } = await import(PLUGIN_PATH);
const plugin = await buildPlugin({ directory: NON_REPO_DIR });
const hook = plugin["tool.execute.before"];

// The hook is async; await it inside the timed region so the measured cost
// includes the full classifier + logging work. Deliberate block-throws are
// the expected verdict on the block classes and are caught here.
const runHook = async (tool, args) => {
  try {
    await hook({ tool }, { args });
  } catch {
    // expected block verdict
  }
};

// Sanity: the block path must actually throw the guard error.
let sawBlock = false;
await hook({ tool: "bash" }, { args: { command: "echo '{}' > ~/.config/opencode/opencode.json" } })
  .then(() => {}, (e) => { sawBlock = String(e.message).startsWith("[LIVE CONFIG GUARD]"); });
if (!sawBlock) {
  console.error("bench-live-config-guard: block path did not fire");
  process.exit(1);
}

const READ_CMD = "cat /tmp/notes.txt && jq '.plugins | length' /tmp/notes.txt";
const WRITE_CMD = "echo '{\"plugin\":[]}' > ~/.config/opencode/opencode.json";

console.log(JSON.stringify(await asyncBench("benign-read-command", () => runHook("bash", { command: READ_CMD }))));
console.log(JSON.stringify(await asyncBench("genuine-write-command", () => runHook("bash", { command: WRITE_CMD }))));
console.log(JSON.stringify(await asyncBench("write-edit-tool-call", () => runHook("write", { filePath: "~/.config/opencode/opencode.json" }))));

rmSync(SANDBOX, { recursive: true, force: true });
