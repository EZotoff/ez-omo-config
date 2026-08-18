// tests/provider-connect-retry/harness.mjs
// Test harness for provider-connect-retry plugin — compaction fallback branch.
//
// Contract under test:
//   - Compaction-mode failures (failed assistant message has mode "compaction";
//     the compaction user message carries only a {type:"compaction"} part, so
//     sanitizePromptParts yields nothing) must be routed to the dedicated
//     compaction_fallback_models chain via ctx.client.session.summarize,
//     NOT to the chat promptAsync fallback path.
//   - Root sessions only (child sessions stay owned by OMO runtime-fallback).
//   - Per-episode chain advancement with resets on success / new user turn.
//   - Non-compaction failures keep the existing promptAsync fallback behavior.

import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "provider-connect-retry.mjs");

function assert(cond, msg) {
  if (!cond) throw new Error(`ASSERT FAILED: ${msg}`);
}

function assertEquals(actual, expected, msg) {
  if (actual !== expected) {
    throw new Error(`ASSERT FAILED: ${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

const REGISTRY_FIXTURE = {
  errors: [
    {
      id: "provider-usage-limit-reached",
      pattern: "usage limit",
      match_type: "regex",
      max_retries: 0,
      backoff_ms: [1000],
      retry_after_tool_execution: false,
    },
  ],
  compaction_fallback_models: [
    "deepseek/deepseek-v4-flash",
    "zai-coding-plan/glm-5.3",
    "openai/gpt-5.6-sol",
  ],
};

const OMO_CONFIG_FIXTURE = {
  agents: {
    sisyphus: {
      model: "zai-coding-plan/glm-5.3",
      fallback_models: ["openai/gpt-5.6-sol"],
    },
  },
};

async function setup({ parentID } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "retry-plugin-test-"));
  const registryPath = join(dir, "retry-errors.json");
  const logPath = join(dir, "retry-plugin.log");
  const omoConfigPath = join(dir, "oh-my-openagent.json");
  writeFileSync(registryPath, JSON.stringify(REGISTRY_FIXTURE));
  writeFileSync(omoConfigPath, JSON.stringify(OMO_CONFIG_FIXTURE));

  const calls = { summarize: [], promptAsync: [], aborts: 0, toasts: [] };
  let messages = [];

  const ctx = {
    client: {
      session: {
        get: async () => ({ data: { parentID } }),
        messages: async () => ({ data: messages }),
        abort: async () => {
          calls.aborts += 1;
        },
        promptAsync: async (options) => {
          calls.promptAsync.push(options);
        },
        summarize: async (options) => {
          calls.summarize.push(options);
          return { data: true };
        },
      },
      tui: {
        showToast: async (options) => {
          calls.toasts.push(options);
        },
      },
    },
  };

  const mod = await import(PLUGIN_PATH);
  if (!mod.__testPathOverride) {
    throw new Error("Plugin does not export __testPathOverride — test isolation unavailable");
  }
  mod.__testPathOverride.registry = registryPath;
  mod.__testPathOverride.log = logPath;
  mod.__testPathOverride.omoConfig = omoConfigPath;

  const plugin = await mod.default(ctx);
  return {
    plugin,
    calls,
    setMessages: (next) => {
      messages = next;
    },
    cleanup: () => rmSync(dir, { recursive: true, force: true }),
  };
}

// --- Fixtures ---

function failedCompactionMessages({ sessionID, assistantID, providerID, modelID, auto = true }) {
  return [
    {
      info: { id: "u_chat", role: "user", agent: "sisyphus", sessionID, providerID, modelID },
      parts: [{ type: "text", text: "hello, work on something" }],
    },
    {
      info: { id: "a_chat", role: "assistant", agent: "sisyphus", sessionID, providerID, modelID, finish: "stop", tokens: { output: 100 } },
      parts: [{ type: "text", text: "sure" }],
    },
    {
      info: { id: "u_comp", role: "user", agent: "sisyphus", sessionID, providerID, modelID },
      parts: [{ type: "compaction", auto }],
    },
    {
      info: { id: assistantID, role: "assistant", mode: "compaction", agent: "compaction", sessionID, providerID, modelID, error: { message: "Monthly usage limit reached on gateway" } },
      parts: [],
    },
  ];
}

function failedChatMessages({ sessionID, providerID = "zai-coding-plan", modelID = "glm-5.3" }) {
  return [
    {
      info: { id: "u_chat", role: "user", agent: "sisyphus", sessionID, providerID, modelID },
      parts: [{ type: "text", text: "hello, work on something" }],
    },
    {
      info: { id: "a_chat", role: "assistant", agent: "sisyphus", sessionID, providerID, modelID, error: { message: "Monthly usage limit reached on gateway" } },
      parts: [],
    },
  ];
}

function sessionErrorEvent(sessionID) {
  return { type: "session.error", properties: { sessionID, error: "Monthly usage limit reached on gateway" } };
}

function messageUpdatedErrorEvent(sessionID, assistantID) {
  return {
    type: "message.updated",
    properties: {
      sessionID,
      info: {
        id: assistantID,
        role: "assistant",
        mode: "compaction",
        agent: "compaction",
        sessionID,
        providerID: "zai-coding-plan",
        modelID: "glm-5.3",
        error: { message: "Monthly usage limit reached on gateway" },
      },
    },
  };
}

function compactionSuccessEvent(sessionID) {
  return {
    type: "message.updated",
    properties: {
      sessionID,
      info: {
        id: "a_ok",
        role: "assistant",
        mode: "compaction",
        agent: "compaction",
        sessionID,
        providerID: "deepseek",
        modelID: "deepseek-v4-flash",
        finish: "stop",
        tokens: { output: 812 },
      },
    },
  };
}

function newUserTextEvent(sessionID) {
  return {
    type: "message.updated",
    properties: {
      sessionID,
      info: { id: "u_new", role: "user", agent: "sisyphus", sessionID },
      parts: [{ type: "text", text: "next task please" }],
    },
  };
}

// --- Cases ---

async function caseCompactionDispatch() {
  const s = await setup();
  try {
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t1", assistantID: "a1", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t1") });

    assertEquals(s.calls.summarize.length, 1, "compaction failure must dispatch exactly one summarize");
    const call = s.calls.summarize[0];
    assertEquals(call.path.id, "ses_t1", "summarize must target the failing session");
    assertEquals(call.body.providerID, "deepseek", "first eligible chain entry skips failing provider (zai) → deepseek");
    assertEquals(call.body.modelID, "deepseek-v4-flash", "chain entry 1 model");
    assertEquals(call.body.auto, true, "auto flag preserved from original compaction part");
    assertEquals(s.calls.promptAsync.length, 0, "compaction failure must NOT use the chat promptAsync path");
    assert(s.calls.aborts >= 1, "session must be aborted before summarize dispatch");
  } finally {
    s.cleanup();
  }
}

async function caseChainAdvanceAndExhaustion() {
  const s = await setup();
  try {
    // Failure 1: zai fails -> deepseek
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t2", assistantID: "a1", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t2") });
    assertEquals(s.calls.summarize.length, 1, "failure 1 dispatches");
    assertEquals(s.calls.summarize[0].body.providerID, "deepseek", "failure 1 → deepseek");

    // Failure 2: deepseek fails -> zai (glm) — deepseek entries skipped, zai not yet tried
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t2", assistantID: "a2", providerID: "deepseek", modelID: "deepseek-v4-flash" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t2") });
    assertEquals(s.calls.summarize.length, 2, "failure 2 dispatches");
    assertEquals(s.calls.summarize[1].body.providerID, "zai-coding-plan", "failure 2 → zai glm");
    assertEquals(s.calls.summarize[1].body.modelID, "glm-5.3", "failure 2 model");

    // Failure 3: zai fails again -> openai (only untried, non-zai entry)
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t2", assistantID: "a3", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t2") });
    assertEquals(s.calls.summarize.length, 3, "failure 3 dispatches");
    assertEquals(s.calls.summarize[2].body.providerID, "openai", "failure 3 → openai sol");

    // Failure 4: openai fails -> chain exhausted: toast, no dispatch
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t2", assistantID: "a4", providerID: "openai", modelID: "gpt-5.6-sol" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t2") });
    assertEquals(s.calls.summarize.length, 3, "exhausted chain must not dispatch again");
    assertEquals(s.calls.toasts.length, 1, "exhaustion must surface exactly one toast");
    assert(String(s.calls.toasts[0]?.body?.message ?? "").includes("compaction"), "toast must mention compaction");
  } finally {
    s.cleanup();
  }
}

async function caseDualEventDedup() {
  const s = await setup();
  try {
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t3", assistantID: "a1", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    // OpenCode emits BOTH session.error and message.updated(error) for one failure
    await s.plugin.event({ event: sessionErrorEvent("ses_t3") });
    await s.plugin.event({ event: messageUpdatedErrorEvent("ses_t3", "a1") });
    assertEquals(s.calls.summarize.length, 1, "dual events for the same failed message must dispatch exactly once");
  } finally {
    s.cleanup();
  }
}

async function caseChatFailureUnchanged() {
  const s = await setup();
  try {
    s.setMessages(failedChatMessages({ sessionID: "ses_t4" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t4") });
    assertEquals(s.calls.summarize.length, 0, "non-compaction failure must not touch summarize");
    assertEquals(s.calls.promptAsync.length, 1, "chat failure keeps promptAsync fallback");
    assertEquals(s.calls.promptAsync[0].body.model.providerID, "openai", "chat fallback resolves agent chain");
    assertEquals(s.calls.promptAsync[0].body.model.modelID, "gpt-5.6-sol", "chat fallback model");
  } finally {
    s.cleanup();
  }
}

async function caseChildSessionGate() {
  const s = await setup({ parentID: "ses_parent" });
  try {
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t5", assistantID: "a1", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t5") });
    assertEquals(s.calls.summarize.length, 0, "child-session compaction failures stay with OMO runtime-fallback");
    assertEquals(s.calls.promptAsync.length, 0, "child-session compaction failures must not promptAsync either");
  } finally {
    s.cleanup();
  }
}

async function caseSuccessResetsChain() {
  const s = await setup();
  try {
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t6", assistantID: "a1", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t6") });
    assertEquals(s.calls.summarize[0].body.providerID, "deepseek", "first dispatch → deepseek");

    // Compaction completes successfully on the fallback model
    await s.plugin.event({ event: compactionSuccessEvent("ses_t6") });

    // Later episode: zai fails again → chain must start fresh (deepseek, not glm)
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t6", assistantID: "a5", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t6") });
    assertEquals(s.calls.summarize.length, 2, "post-success failure dispatches");
    assertEquals(s.calls.summarize[1].body.providerID, "deepseek", "success resets tried-chain for the next episode");
  } finally {
    s.cleanup();
  }
}

async function caseUserMessageResetsChain() {
  const s = await setup();
  try {
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t7", assistantID: "a1", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t7") });
    assertEquals(s.calls.summarize[0].body.providerID, "deepseek", "first dispatch → deepseek");

    // User sends a new chat turn
    await s.plugin.event({ event: newUserTextEvent("ses_t7") });

    // New compaction episode fails on zai again → fresh chain
    s.setMessages(failedCompactionMessages({ sessionID: "ses_t7", assistantID: "a6", providerID: "zai-coding-plan", modelID: "glm-5.3" }));
    await s.plugin.event({ event: sessionErrorEvent("ses_t7") });
    assertEquals(s.calls.summarize.length, 2, "post-user-turn failure dispatches");
    assertEquals(s.calls.summarize[1].body.providerID, "deepseek", "new user turn resets tried-chain");
  } finally {
    s.cleanup();
  }
}

// --- Runner ---

const CASES = {
  "compaction-dispatch": caseCompactionDispatch,
  "chain-advance-exhaustion": caseChainAdvanceAndExhaustion,
  "dual-event-dedup": caseDualEventDedup,
  "chat-failure-unchanged": caseChatFailureUnchanged,
  "child-session-gate": caseChildSessionGate,
  "success-resets-chain": caseSuccessResetsChain,
  "user-message-resets-chain": caseUserMessageResetsChain,
};

const caseArg = process.argv[process.argv.indexOf("--case") + 1];
if (!caseArg || !CASES[caseArg]) {
  console.error(`Usage: node harness.mjs --case <${Object.keys(CASES).join("|")}>`);
  process.exit(2);
}

try {
  await CASES[caseArg]();
  console.log(`PASS: ${caseArg}`);
  process.exit(0);
} catch (error) {
  console.error(`FAIL: ${caseArg}: ${error?.message ?? error}`);
  process.exit(1);
}
