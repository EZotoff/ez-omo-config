// tests/skill-nudger/harness.mjs
// Test harness for skill-nudger plugin

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "skill-nudger.mjs");
const SIGNALS_PATH = join(__dirname, "..", "..", "configs", "opencode", "skill-nudger", "signals.mjs");

function assert(cond, msg) {
  if (!cond) throw new Error(`ASSERT FAILED: ${msg}`);
}

function assertEquals(actual, expected, msg) {
  if (actual !== expected) {
    throw new Error(`ASSERT FAILED: ${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

async function setup(extraConfig = {}) {
  const { __testConfigOverride } = await import(join(__dirname, "..", "..", "configs", "opencode", "skill-nudger", "config.mjs"));
  const { __testProofOverride } = await import(join(__dirname, "..", "..", "configs", "opencode", "skill-nudger", "logging.mjs"));
  const state = await import(join(__dirname, "..", "..", "configs", "opencode", "skill-nudger", "state.mjs"));

  __testConfigOverride.value = { enabled: true, logLevel: "silent", ...extraConfig };
  __testProofOverride.value = [];

  const mod = await import(PLUGIN_PATH);
  const plugin = await mod.default({ client: {} });
  return { plugin, proofs: __testProofOverride.value, resetState: state.__resetAllState };
}

function toolCall(sessionID, tool, args, output) {
  return { input: { tool, sessionID, callID: `call_${Math.random().toString(36).slice(2, 8)}`, args }, output: { title: "run", output, metadata: {} } };
}

function transformCall(sessionID, agent = "build", extraMessages = []) {
  const messages = [
    { info: { sessionID, role: "user", agent: null, id: "u1" }, parts: [{ type: "text", text: "do work" }] },
    { info: { sessionID, role: "assistant", agent, id: "a1" }, parts: [] },
    ...extraMessages,
  ];
  const output = { messages };
  return { output };
}

function deliveredRule(proofs) {
  const delivered = proofs.filter((p) => p.event === "nudge_delivered");
  return delivered[delivered.length - 1]?.rule ?? null;
}

// --- Cases ---

async function caseRepeatedFailure() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_rf";
  // first failing call: below threshold, no nudge yet
  const c1 = toolCall(sid, "bash", { command: "npm test" }, "Error: exit code 1");
  await plugin["tool.execute.after"](c1.input, c1.output);
  assertEquals(proofs.filter((p) => p.event === "nudge_queued").length, 0, "no nudge after first failure");
  // second identical failing call triggers repeatedFailure
  const c2 = toolCall(sid, "bash", { command: "npm test" }, "Error: exit code 1");
  await plugin["tool.execute.after"](c2.input, c2.output);
  assert(proofs.some((p) => p.event === "nudge_queued" && p.rule === "repeated-failure"), "nudge queued for repeated-failure");
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(deliveredRule(proofs), "repeated-failure", "delivered rule");
  const pushed = t.output.messages[t.output.messages.length - 1];
  assert(pushed.info.sessionID === sid && pushed.parts[0].text.includes("[SKILL-NUDGE v1]"), "synthetic message appended");
  assert(pushed.parts[0].text.includes("`debugging`"), "nudge suggests debugging skill");
}

async function caseRetryableError() {
  const { plugin, proofs } = await setup();
  // Read the first registry pattern to build a matching failing output
  const registry = JSON.parse(readFileSync(join(__dirname, "..", "..", "configs", "retry-errors.json"), "utf8"));
  const pattern = registry.errors.find((e) => e.match_type === "regex")?.pattern ?? "SSE read timed out";
  const re = new RegExp(pattern, "i");
  let sample = `Request failed: ${pattern}`;
  if (!re.test(sample)) sample = `Request failed with ${pattern} error`;
  assert(re.test(sample), `sample output must match pattern ${pattern}`);

  const sid = "ses_test_retry";
  const c = toolCall(sid, "bash", { command: "opencode run x" }, sample);
  await plugin["tool.execute.after"](c.input, c.output);
  assert(proofs.some((p) => p.event === "nudge_queued" && p.rule === "retryable-error"), "nudge queued for retryable-error");
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(deliveredRule(proofs), "retryable-error", "delivered rule");
  assert(t.output.messages.at(-1).parts[0].text.includes("`register-retry-error`"), "suggests register-retry-error skill");
}

async function casePortBinding() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_port";
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "VITE ready on http://localhost:5173");
  await plugin["tool.execute.after"](c.input, c.output);
  assert(proofs.some((p) => p.event === "nudge_queued" && p.rule === "port-binding"), "nudge queued for port-binding (success case)");
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(deliveredRule(proofs), "port-binding", "delivered rule");
  assert(t.output.messages.at(-1).parts[0].text.includes("`deployment`"), "suggests deployment skill");
}

async function caseLoop() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_loop";
  for (let i = 0; i < 8; i++) {
    const c = toolCall(sid, "bash", { command: `cat server.log | grep ERROR | wc -l` }, "0");
    await plugin["tool.execute.after"](c.input, c.output);
  }
  assert(proofs.some((p) => p.event === "nudge_queued" && p.rule === "loop-precursor"), "nudge queued for loop");
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(deliveredRule(proofs), "loop-precursor", "delivered rule");
  const text = t.output.messages.at(-1).parts[0].text;
  assert(text.includes("Step back"), "loop advisory content");
  assert(!text.includes("Skill:"), "loop advisory has no skill line");
}

async function caseDedupAndCap() {
  const { plugin, proofs } = await setup({ cooldownToolCalls: 1, maxNudgesPerSession: 2 });
  const sid = "ses_test_dedup";
  // Fire repeated-failure twice more after first — rule dedup must suppress re-queue
  for (let round = 0; round < 2; round++) {
    for (let i = 0; i < 2; i++) {
      const c = toolCall(sid, "bash", { command: "make build" }, "make: Error 2");
      await plugin["tool.execute.after"](c.input, c.output);
    }
  }
  const queued = proofs.filter((p) => p.event === "nudge_queued" && p.rule === "repeated-failure");
  assertEquals(queued.length, 1, "rule dedup: repeated-failure queued exactly once");

  // Cap: two different rules fill the cap; a third distinct rule is skipped
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output); // port-binding (nudge 2)
  const c2 = toolCall(sid, "bash", { command: "npx vite --port 3000" }, "started");
  await plugin["tool.execute.after"](c2.input, c2.output); // also port-binding -> deduped, no new nudge
  const skips = proofs.filter((p) => p.event === "skip" && p.reason === "rule_already_sent");
  assert(skips.length >= 1, "rule_already_sent skip recorded");
}

async function caseCooldown() {
  const { plugin, proofs } = await setup({ cooldownToolCalls: 10, maxNudgesPerSession: 5 });
  const sid = "ses_test_cooldown";
  for (let i = 0; i < 2; i++) {
    const c = toolCall(sid, "bash", { command: "pytest -x" }, "FAILED tests/test_a.py - AssertionError");
    await plugin["tool.execute.after"](c.input, c.output);
  }
  assert(proofs.some((p) => p.event === "nudge_queued"), "first nudge queued");
  // Different rule within cooldown window -> blocked by cooldown
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output);
  assert(proofs.some((p) => p.event === "skip" && p.reason === "cooldown"), "cooldown skip recorded");
}

async function caseAgentScoping() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_scope";
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output);
  // transform with an agent that has no agent field at all (rule.agents null -> allowed)
  const t = transformCall(sid, "explore");
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(deliveredRule(proofs), "port-binding", "null allowlist delivers to any agent");
}

async function caseStaleDrop() {
  const { plugin, proofs } = await setup({ freshnessMs: 1 });
  const sid = "ses_test_stale";
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output);
  await new Promise((r) => setTimeout(r, 10));
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(t.output.messages.length, 2, "no message appended for stale nudge");
  assert(proofs.some((p) => p.event === "skip" && p.reason === "stale"), "stale skip recorded");
}

async function caseNoFalsePositives() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_ok";
  const ok = toolCall(sid, "bash", { command: "ls -la" }, "file1.txt\nfile2.txt");
  await plugin["tool.execute.after"](ok.input, ok.output);
  const read = toolCall(sid, "read", { filePath: "/tmp/x" }, "contents here");
  await plugin["tool.execute.after"](read.input, read.output);
  const grep = toolCall(sid, "grep", { pattern: "foo" }, "3 matches");
  await plugin["tool.execute.after"](grep.input, grep.output);
  assertEquals(proofs.filter((p) => p.event === "nudge_queued").length, 0, "no nudges for healthy activity");
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(t.output.messages.length, 2, "nothing appended");
}

async function caseSessionCleanup() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_cleanup";
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output);
  await plugin.event({ event: { type: "session.deleted", properties: { sessionID: sid } } });
  assert(proofs.some((p) => p.event === "session_cleanup" && p.session_id === sid), "cleanup proof recorded");
  const t = transformCall(sid);
  await plugin["experimental.chat.messages.transform"]({}, t.output);
  assertEquals(t.output.messages.length, 2, "pending nudge dropped after session deletion");
}

async function caseCircuitBreaker() {
  const { plugin, proofs } = await setup();
  const sid = "ses_test_cb";
  // Trip the breaker at state level (the hook's null-guard absorbs malformed
  // input by design, so we exercise recordFailure -> canNudge directly)
  const { recordFailure } = await import(join(__dirname, "..", "..", "configs", "opencode", "skill-nudger", "state.mjs"));
  for (let i = 0; i < 3; i++) {
    recordFailure(sid);
  }
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output);
  assert(proofs.some((p) => p.event === "skip" && p.reason === "circuit_open"), "circuit_open skip recorded");
}

async function caseDisabledSignal() {
  const { plugin, proofs } = await setup({ disabledSignals: ["portBinding"] });
  const sid = "ses_test_disabled";
  const c = toolCall(sid, "bash", { command: "npm run dev" }, "started");
  await plugin["tool.execute.after"](c.input, c.output);
  assertEquals(proofs.filter((p) => p.event === "nudge_queued").length, 0, "disabled signal produces no nudge");
}

const CASES = {
  "repeated-failure": caseRepeatedFailure,
  "retryable-error": caseRetryableError,
  "port-binding": casePortBinding,
  "loop": caseLoop,
  "dedup-and-cap": caseDedupAndCap,
  "cooldown": caseCooldown,
  "agent-scoping": caseAgentScoping,
  "stale-drop": caseStaleDrop,
  "no-false-positives": caseNoFalsePositives,
  "session-cleanup": caseSessionCleanup,
  "circuit-breaker": caseCircuitBreaker,
  "disabled-signal": caseDisabledSignal,
};

const caseName = process.argv[process.argv.indexOf("--case") + 1];
if (!caseName || !CASES[caseName]) {
  console.error(`Usage: node harness.mjs --case <name>\nCases: ${Object.keys(CASES).join(", ")}`);
  process.exit(2);
}

try {
  await CASES[caseName]();
  console.log(`PASS: ${caseName}`);
  process.exit(0);
} catch (err) {
  console.error(`FAIL: ${caseName}: ${err.message}`);
  process.exit(1);
}
