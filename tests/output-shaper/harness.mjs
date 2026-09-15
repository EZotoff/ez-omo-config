// tests/output-shaper/harness.mjs
// Test harness for output-shaper plugin
//
// Mirrors tests/aspect-dynamics/harness.mjs: makeFakeCtx, pass/fail,
// captureLogs, setTestConfig/clearTestConfig, and a main() dispatcher
// driven by `node harness.mjs --case <name>`.
//
// Config injection: the plugin reads config inside plugin(ctx) via
// loadConfig(), which consults __testConfigOverride first. Each case sets
// an override with setTestConfig() before invoking the plugin and clears it
// with clearTestConfig() afterwards, so no live config is ever touched.
// The bash wrapper additionally runs every case under a throwaway $HOME so
// the fail-closed-no-config case can exercise the real missing-config path.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

import { __testLogOverride } from "../../configs/opencode/output-shaper/logging.mjs";

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "output-shaper.mjs");
const CONFIG_PATH = join(__dirname, "..", "..", "configs", "opencode", "output-shaper", "config.mjs");

function makeFakeCtx(opts = {}) {
  const messagesStore = opts.messages ?? [];

  let messagesCallCount = 0;

  return {
    directory: "/tmp/fake-project",
    client: {
      session: {
        async messages(args = {}) {
          messagesCallCount++;
          if (opts.messagesShouldThrow && messagesCallCount <= opts.messagesShouldThrow) {
            throw new Error("Simulated messages failure");
          }
          return { data: messagesStore };
        },
      },
    },
    __test: {
      getMessagesCallCount() {
        return messagesCallCount;
      },
    },
  };
}

// Resume turn: second-to-last message is assistant with a completed tool part,
// and the last message is the empty assistant message OpenCode creates for
// the current LLM call before chat.params fires.
function resumeMessages() {
  return [
    { id: "msg-1", info: { role: "user" }, parts: [{ type: "text", text: "analyze this" }] },
    { id: "msg-2", info: { role: "assistant" }, parts: [{ type: "tool", state: { status: "completed" } }] },
    { id: "msg-3", info: { role: "assistant" }, parts: [] },
  ];
}

// New question: last message is the empty assistant message for the current
// call; second-to-last is the user's follow-up question.
function newQuestionMessages() {
  return [
    { id: "msg-1", info: { role: "user" }, parts: [{ type: "text", text: "first question" }] },
    { id: "msg-2", info: { role: "assistant" }, parts: [{ type: "text", text: "answer" }] },
    { id: "msg-3", info: { role: "user" }, parts: [{ type: "text", text: "follow-up question" }] },
    { id: "msg-4", info: { role: "assistant" }, parts: [] },
  ];
}

function makeParamsInput(providerID, modelID) {
  return {
    sessionID: "sess-output-shaper-1",
    agent: "sisyphus",
    model: { providerID, id: modelID },
    provider: { id: providerID },
    message: {},
  };
}

function makeParamsOutput() {
  return { temperature: 1, topP: 1, topK: 1, maxOutputTokens: 8192, options: {} };
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function pass(message) {
  console.log(`PASS: ${message}`);
}

function captureLogs() {
  const logs = [];
  __testLogOverride.value = logs;
  return {
    logs,
    restore() {
      __testLogOverride.value = null;
    },
    hasWarn(substr) {
      return logs.some((l) => l.level === "warn" && l.msg.includes(substr));
    },
  };
}

async function setTestConfig(overrides) {
  const configMod = await import(CONFIG_PATH);
  configMod.__testConfigOverride.value = overrides;
}

async function clearTestConfig() {
  const configMod = await import(CONFIG_PATH);
  configMod.__testConfigOverride.value = null;
}

// Shared clamp runner: resume turn on a target provider must set the
// provider-specific option to the expected value via the real chat.params hook.
// `expectedValue` may be an object (e.g. google thinkingConfig) — compared
// by JSON to tolerate key order.
async function runClampCase(caseName, providerID, modelID, expectedField, expectedValue) {
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx({ messages: resumeMessages() });
    const hooks = await plugin(ctx);
    const output = makeParamsOutput();
    await hooks["chat.params"](makeParamsInput(providerID, modelID), output);
    const got = output.options[expectedField];
    const ok =
      typeof expectedValue === "object"
        ? JSON.stringify(got) === JSON.stringify(expectedValue)
        : got === expectedValue;
    if (!ok) {
      fail(
        `${caseName}: expected ${expectedField}=${JSON.stringify(expectedValue)}, got ${JSON.stringify(output.options)}`
      );
    }
    pass(`${caseName} — ${providerID}/${modelID} resume turn clamped ${expectedField}=${JSON.stringify(expectedValue)}`);
  } finally {
    await clearTestConfig();
  }
}

async function runTersenessInjected() {
  await setTestConfig({
    enabled: true,
    logLevel: "silent",
    tersenessInstruction: "Be terse: no preambles.",
  });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const hooks = await plugin(makeFakeCtx());
    const output = { system: [] };
    await hooks["experimental.chat.system.transform"]({}, output);
    if (output.system.length !== 1) {
      fail(`terseness-injected: expected 1 pushed instruction, got ${output.system.length}`);
    }
    if (output.system[0] !== "Be terse: no preambles.") {
      fail(`terseness-injected: expected configured instruction, got ${JSON.stringify(output.system[0])}`);
    }
    pass("terseness-injected — system.transform pushes the configured terseness instruction into output.system");
  } finally {
    await clearTestConfig();
  }
}

async function runTersenessStatic() {
  // No tersenessInstruction override → loadConfig() merges the real
  // DEFAULT_CONFIG instruction. Assert it has no ${} interpolation, which
  // would break the Anthropic/OpenAI cache prefix.
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const hooks = await plugin(makeFakeCtx());
    const output = { system: [] };
    await hooks["experimental.chat.system.transform"]({}, output);
    if (output.system.length !== 1 || typeof output.system[0] !== "string") {
      fail(`terseness-static: expected 1 string instruction, got ${JSON.stringify(output.system)}`);
    }
    if (output.system[0].includes("${")) {
      fail(`terseness-static: instruction contains dynamic interpolation: ${output.system[0]}`);
    }
    pass("terseness-static — default instruction has no ${} dynamic content");
  } finally {
    await clearTestConfig();
  }
}

async function runClaudeResumeNotClamped() {
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx({ messages: resumeMessages() });
    const hooks = await plugin(ctx);
    const output = makeParamsOutput();
    await hooks["chat.params"](makeParamsInput("anthropic", "claude-sonnet-4-5"), output);
    if (Object.keys(output.options).length !== 0) {
      fail(`claude-resume-not-clamped: expected options untouched, got ${JSON.stringify(output.options)}`);
    }
    if (ctx.__test.getMessagesCallCount() !== 0) {
      fail(
        `claude-resume-not-clamped: expected no session.messages call for excluded provider, got ${ctx.__test.getMessagesCallCount()}`
      );
    }
    pass("claude-resume-not-clamped — anthropic resume turn left options untouched");
  } finally {
    await clearTestConfig();
  }
}

async function runCopilotResumeNotClamped() {
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx({ messages: resumeMessages() });
    const hooks = await plugin(ctx);
    const output = makeParamsOutput();
    await hooks["chat.params"](makeParamsInput("github-copilot", "gpt-5-copilot"), output);
    if (Object.keys(output.options).length !== 0) {
      fail(`copilot-resume-not-clamped: expected options untouched, got ${JSON.stringify(output.options)}`);
    }
    if (ctx.__test.getMessagesCallCount() !== 0) {
      fail(
        `copilot-resume-not-clamped: expected no session.messages call for excluded provider, got ${ctx.__test.getMessagesCallCount()}`
      );
    }
    pass("copilot-resume-not-clamped — github-copilot resume turn left options untouched");
  } finally {
    await clearTestConfig();
  }
}

async function runNewQuestionNotClamped() {
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx({ messages: newQuestionMessages() });
    const hooks = await plugin(ctx);
    const output = makeParamsOutput();
    await hooks["chat.params"](makeParamsInput("zai-coding-plan", "glm-5.3"), output);
    if (Object.keys(output.options).length !== 0) {
      fail(`new-question-not-clamped: expected options untouched, got ${JSON.stringify(output.options)}`);
    }
    if (ctx.__test.getMessagesCallCount() !== 1) {
      fail(
        `new-question-not-clamped: expected exactly 1 session.messages call, got ${ctx.__test.getMessagesCallCount()}`
      );
    }
    pass("new-question-not-clamped — target model + new question left options untouched");
  } finally {
    await clearTestConfig();
  }
}

// Regression guard for the 2026-08/09 silent no-op bug: the plugin must use
// the OpenCode providerOptions vocabulary (AI SDK option names), never raw
// HTTP body parameter names. A snake_case `reasoning_effort` option is
// dropped by the @ai-sdk/openai-compatible Zod schema and never reaches the
// provider; a top-level `thinkingLevel` string is dropped for google the
// same way. Every clampable provider must set exactly its vocabulary key.
async function runOptionVocabulary() {
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const cases = [
      { providerID: "zai-coding-plan", modelID: "glm-5.3", field: "reasoningEffort", value: "low" },
      { providerID: "kimi-for-coding-oauth", modelID: "kimi-for-coding", field: "reasoningEffort", value: "low" },
      { providerID: "kimi-for-coding-oauth", modelID: "k3", field: "reasoningEffort", value: "low" },
      { providerID: "deepseek", modelID: "deepseek-flash", field: "reasoningEffort", value: "low" },
      { providerID: "opencode-go", modelID: "deepseek-v4-flash", field: "reasoningEffort", value: "low" },
      { providerID: "ollama-cloud", modelID: "deepseek-v4-pro:0813", field: "reasoningEffort", value: "low" },
      { providerID: "openai", modelID: "gpt-5.6-sol", field: "reasoningEffort", value: "low" },
      { providerID: "google", modelID: "gemini-3.1-pro-preview", field: "thinkingConfig", value: { thinkingLevel: "low" } },
    ];
    const droppedKeys = ["reasoning_effort", "thinking_budget", "thinkingLevel"];

    for (const c of cases) {
      const ctx = makeFakeCtx({ messages: resumeMessages() });
      const hooks = await plugin(ctx);
      const output = makeParamsOutput();
      await hooks["chat.params"](makeParamsInput(c.providerID, c.modelID), output);
      const got = output.options[c.field];
      const ok =
        typeof c.value === "object"
          ? JSON.stringify(got) === JSON.stringify(c.value)
          : got === c.value;
      if (!ok) {
        fail(
          `option-vocabulary: ${c.providerID}/${c.modelID} expected ${c.field}=${JSON.stringify(c.value)}, got ${JSON.stringify(output.options)}`
        );
      }
      for (const k of droppedKeys) {
        if (k in output.options) {
          fail(`option-vocabulary: ${c.providerID}/${c.modelID} set non-vocabulary key ${k}`);
        }
      }
    }
    pass("option-vocabulary — every clampable provider sets only AI-SDK-vocabulary option keys (no snake_case body params)");
  } finally {
    await clearTestConfig();
  }
}

// ollama-cloud carries a model allowlist: minimax-m3 must NOT be clamped
// (live A/B 2026-09-15: reasoning_effort increased its reasoning).
async function runOllamaM3NotClamped() {
  await setTestConfig({ enabled: true, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx({ messages: resumeMessages() });
    const hooks = await plugin(ctx);
    const output = makeParamsOutput();
    await hooks["chat.params"](makeParamsInput("ollama-cloud", "minimax-m3"), output);
    if (Object.keys(output.options).length !== 0) {
      fail(`ollama-m3-not-clamped: expected options untouched, got ${JSON.stringify(output.options)}`);
    }
    pass("ollama-m3-not-clamped — ollama-cloud model outside allowlist left options untouched");
  } finally {
    await clearTestConfig();
  }
}

async function runFailClosedNoConfig() {
  // No test override. The bash wrapper runs this case under a throwaway
  // $HOME so loadConfig()'s read of ~/.config/opencode/oh-my-openagent.json
  // fails and it returns null → plugin returns no-op hooks. This exercises
  // the real missing-config branch without touching the live config.
  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const logCapture = captureLogs();
  let hooks;
  try {
    const ctx = makeFakeCtx({ messages: resumeMessages() });
    hooks = await plugin(ctx);
  } finally {
    logCapture.restore();
  }

  if (
    !hooks ||
    typeof hooks["chat.params"] !== "function" ||
    typeof hooks["experimental.chat.system.transform"] !== "function"
  ) {
    fail("fail-closed-no-config: plugin should return no-op hooks");
  }
  if (!logCapture.hasWarn("config not found")) {
    fail(
      `fail-closed-no-config: expected missing-config warning, got logs=${JSON.stringify(logCapture.logs)}`
    );
  }

  const output = makeParamsOutput();
  await hooks["chat.params"](makeParamsInput("zai-coding-plan", "glm-5.3"), output);
  if (Object.keys(output.options).length !== 0) {
    fail(`fail-closed-no-config: chat.params must be a no-op, got ${JSON.stringify(output.options)}`);
  }

  const sysOut = { system: [] };
  await hooks["experimental.chat.system.transform"]({}, sysOut);
  if (sysOut.system.length !== 0) {
    fail(`fail-closed-no-config: system.transform must be a no-op, got ${sysOut.system.length} items`);
  }

  pass("fail-closed-no-config — missing config returns no-op hooks (warning logged)");
}

async function runDisabledConfig() {
  await setTestConfig({ enabled: false, logLevel: "silent" });
  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx({ messages: resumeMessages() });
    const hooks = await plugin(ctx);
    if (
      !hooks ||
      typeof hooks["chat.params"] !== "function" ||
      typeof hooks["experimental.chat.system.transform"] !== "function"
    ) {
      fail("disabled-config: plugin should return no-op hooks");
    }

    const output = makeParamsOutput();
    await hooks["chat.params"](makeParamsInput("zai-coding-plan", "glm-5.3"), output);
    if (Object.keys(output.options).length !== 0) {
      fail(`disabled-config: chat.params must be a no-op, got ${JSON.stringify(output.options)}`);
    }

    const sysOut = { system: [] };
    await hooks["experimental.chat.system.transform"]({}, sysOut);
    if (sysOut.system.length !== 0) {
      fail(`disabled-config: system.transform must be a no-op, got ${sysOut.system.length} items`);
    }

    if (ctx.__test.getMessagesCallCount() !== 0) {
      fail(
        `disabled-config: no-op hooks must not call session.messages, got ${ctx.__test.getMessagesCallCount()} calls`
      );
    }
    pass("disabled-config — enabled:false returns no-op hooks");
  } finally {
    await clearTestConfig();
  }
}

async function main() {
  const args = process.argv.slice(2);
  const caseIdx = args.indexOf("--case");
  const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null;

  if (!testCase) {
    console.error("Usage: node harness.mjs --case <case-name>");
    console.error(
      "Cases: terseness-injected, terseness-static, glm-resume-clamped, kimi-resume-clamped, gpt-resume-clamped, gemini-resume-clamped, ollama-dsv4-clamped, ollama-m3-not-clamped, deepseek-clamped, opencode-go-clamped, claude-resume-not-clamped, copilot-resume-not-clamped, new-question-not-clamped, option-vocabulary, fail-closed-no-config, disabled-config"
    );
    process.exit(1);
  }

  switch (testCase) {
    case "terseness-injected":
      await runTersenessInjected();
      break;
    case "terseness-static":
      await runTersenessStatic();
      break;
    case "glm-resume-clamped":
      await runClampCase("glm-resume-clamped", "zai-coding-plan", "glm-5.3", "reasoningEffort", "low");
      break;
    case "kimi-resume-clamped":
      await runClampCase("kimi-resume-clamped", "kimi-for-coding-oauth", "kimi-for-coding", "reasoningEffort", "low");
      break;
    case "gpt-resume-clamped":
      await runClampCase("gpt-resume-clamped", "openai", "gpt-5.6-sol", "reasoningEffort", "low");
      break;
    case "gemini-resume-clamped":
      await runClampCase(
        "gemini-resume-clamped", "google", "gemini-3.1-pro-preview", "thinkingConfig", { thinkingLevel: "low" }
      );
      break;
    case "ollama-dsv4-clamped":
      await runClampCase("ollama-dsv4-clamped", "ollama-cloud", "deepseek-v4-pro:0813", "reasoningEffort", "low");
      break;
    case "ollama-m3-not-clamped":
      await runOllamaM3NotClamped();
      break;
    case "deepseek-clamped":
      await runClampCase("deepseek-clamped", "deepseek", "deepseek-flash", "reasoningEffort", "low");
      break;
    case "opencode-go-clamped":
      await runClampCase("opencode-go-clamped", "opencode-go", "deepseek-v4-flash", "reasoningEffort", "low");
      break;
    case "claude-resume-not-clamped":
      await runClaudeResumeNotClamped();
      break;
    case "copilot-resume-not-clamped":
      await runCopilotResumeNotClamped();
      break;
    case "new-question-not-clamped":
      await runNewQuestionNotClamped();
      break;
    case "option-vocabulary":
      await runOptionVocabulary();
      break;
    case "fail-closed-no-config":
      await runFailClosedNoConfig();
      break;
    case "disabled-config":
      await runDisabledConfig();
      break;
    default:
      console.error(`Unknown test case: ${testCase}`);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(`UNEXPECTED ERROR: ${err.message}`);
  console.error(err.stack);
  process.exit(1);
});
