// tests/agent-default-guard/harness.mjs
// Unit harness for the agent-default-guard config-layer plugin.
//
// Contract under test:
//   - chat.message with input.agent === "build" rewrites output.message.agent
//     to the default_agent pinned in the sibling opencode.json, but ONLY when
//     the live agent registry shows build as demoted (hidden/subagent) and the
//     target as a visible primary.
//   - Fail-open: no rewrite when build is a visible primary (OMO absent),
//     when default_agent is unset, when the target is missing from the
//     registry, or when the registry fetch throws.
//   - Non-build agents and messages without output.message are untouched.

import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PLUGIN_PATH = new URL("../../configs/opencode/agent-default-guard.mjs", import.meta.url).pathname;

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

const FIXTURES = mkdtempSync(join(tmpdir(), "agent-default-guard-"));
const CONFIG_WITH_PIN = join(FIXTURES, "opencode.json");
const CONFIG_WITHOUT_PIN = join(FIXTURES, "opencode-no-default.json");
const LOG = join(FIXTURES, "guard.log");
writeFileSync(CONFIG_WITH_PIN, JSON.stringify({ default_agent: "Sisyphus" }));
writeFileSync(CONFIG_WITHOUT_PIN, JSON.stringify({}));

globalThis.__agentDefaultGuardTestPaths = { config: CONFIG_WITH_PIN, log: LOG };

const { default: buildPlugin } = await import(PLUGIN_PATH);

function makeCtx(registry, { throwOnAgents = false } = {}) {
  return {
    client: {
      app: {
        agents: async () => {
          if (throwOnAgents) throw new Error("registry unreachable");
          return { data: registry };
        },
      },
    },
  };
}

// Registry shapes
const OMO_REGISTRY = [
  { name: "Sisyphus", mode: "primary", hidden: null },
  { name: "Hephaestus", mode: "primary", hidden: null },
  { name: "build", mode: "subagent", hidden: true },
];
const NO_OMO_REGISTRY = [
  { name: "build", mode: "primary", hidden: null },
  { name: "plan", mode: "primary", hidden: null },
];

async function run(plugin, { agent, registry, throwOnAgents, message = { id: "m1", agent: "build" } } = {}) {
  const input = { sessionID: "s1", agent };
  const output = { message, parts: [] };
  const hooks = await plugin(makeCtx(registry, { throwOnAgents }));
  await hooks["chat.message"](input, output);
  return output.message.agent;
}

// 1. Core rewrite: build -> pinned default when OMO demotes build
{
  const plugin = buildPlugin;
  const result = await run(plugin, { agent: "build", registry: OMO_REGISTRY });
  check(result === "Sisyphus", `build rewritten to pinned default (got ${result})`);
}

// 2. New plugin instance uses cache but still guards: second call within TTL rewrites too
{
  const plugin = buildPlugin;
  // The cache lives inside ONE factory invocation (OpenCode calls the factory
  // once per process). Feed the first fetch a healthy registry, then make the
  // fetcher serve a broken/empty list — the cached registry must keep
  // rewriting without a refetch.
  let fetchCount = 0;
  const ctx = {
    client: {
      app: {
        agents: async () => {
          fetchCount++;
          return { data: fetchCount === 1 ? OMO_REGISTRY : [] };
        },
      },
    },
  };
  const hooks = await buildPlugin(ctx);
  const msg1 = { id: "m1", agent: "build" };
  const msg2 = { id: "m2", agent: "build" };
  await hooks["chat.message"]({ sessionID: "s1", agent: "build" }, { message: msg1, parts: [] });
  await hooks["chat.message"]({ sessionID: "s1", agent: "build" }, { message: msg2, parts: [] });
  check(
    msg1.agent === "Sisyphus" && msg2.agent === "Sisyphus" && fetchCount === 1,
    `cached registry keeps rewriting without refetch (agents ${msg1.agent}/${msg2.agent}, fetches ${fetchCount})`,
  );
}

// 3. Fail-open: build is a visible primary (OMO absent) -> untouched
{
  const plugin = buildPlugin;
  const result = await run(plugin, { agent: "build", registry: NO_OMO_REGISTRY });
  check(result === "build", `visible-primary build left untouched (got ${result})`);
}

// 4. Non-build agent untouched
{
  const plugin = buildPlugin;
  const result = await run(plugin, { agent: "Sisyphus", registry: OMO_REGISTRY, message: { id: "m2", agent: "Sisyphus" } });
  check(result === "Sisyphus", `non-build agent untouched (got ${result})`);
}

// 5. No default_agent configured -> untouched
{
  globalThis.__agentDefaultGuardTestPaths = { config: CONFIG_WITHOUT_PIN, log: LOG };
  const plugin = buildPlugin;
  const result = await run(plugin, { agent: "build", registry: OMO_REGISTRY });
  check(result === "build", `missing default_agent leaves build (got ${result})`);
  globalThis.__agentDefaultGuardTestPaths = { config: CONFIG_WITH_PIN, log: LOG };
}

// 6. Target agent missing from registry -> untouched
{
  const plugin = buildPlugin;
  const registryNoTarget = [
    { name: "Atlas", mode: "primary", hidden: null },
    { name: "build", mode: "subagent", hidden: true },
  ];
  const result = await run(plugin, { agent: "build", registry: registryNoTarget });
  check(result === "build", `missing target agent leaves build (got ${result})`);
}

// 7. Registry fetch throws -> untouched
{
  const plugin = buildPlugin;
  const result = await run(plugin, { agent: "build", registry: OMO_REGISTRY, throwOnAgents: true });
  check(result === "build", `registry failure fails open (got ${result})`);
}

// 8. Missing output.message -> no crash
{
  const plugin = buildPlugin;
  let threw = false;
  try {
    const hooks = await plugin(makeCtx(OMO_REGISTRY));
    await hooks["chat.message"]({ sessionID: "s1", agent: "build" }, {});
  } catch {
    threw = true;
  }
  check(!threw, "missing output.message does not throw");
}

// 9. Rewrite is logged
{
  const plugin = buildPlugin;
  await run(plugin, { agent: "build", registry: OMO_REGISTRY, message: { id: "m3", agent: "build" } });
  const logContent = readFileSync(LOG, "utf8");
  check(logContent.includes('rewrote message agent "build" -> "Sisyphus"'), "rewrite is logged to the plugin log file");
}

rmSync(FIXTURES, { recursive: true, force: true });
console.log(`\nagent-default-guard: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
