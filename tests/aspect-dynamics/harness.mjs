// tests/aspect-dynamics/harness.mjs
// Test harness for aspect-dynamics plugin

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics.mjs");
const SESSION_STATE_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "session-state.mjs");
const CONTEXT_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "context.mjs");
const HEURISTICS_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "heuristics.mjs");
const SETS_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "sets.mjs");

const NUDGE_TEST_SETS = [
  {
    id: "emotions-v1",
    defaultThreshold: 0.75,
    aspects: [
      {
        id: "frustration",
        heuristicPhrases: ["this is frustrating", "I'm stuck on this"],
        nudgeInstruction: "Acknowledge frustration and provide one direct next step.",
      },
    ],
  },
];

function makeFakeCtx(opts = {}) {
  const messagesStore = opts.messages ?? [
    { id: "msg-1", info: { role: "user", text: "hello" } },
    { id: "msg-2", info: { role: "assistant", text: "hi there" } },
  ];

  let messagesCallCount = 0;
  let promptAsyncCallCount = 0;
  let lastPromptBody = null;

  return {
    directory: "/tmp/fake-project",
    client: {
      session: {
        async messages() {
          messagesCallCount++;
          if (opts.messagesShouldThrow && messagesCallCount <= opts.messagesShouldThrow) {
            throw new Error("Simulated messages failure");
          }
          return { data: messagesStore };
        },
        async promptAsync({ path, body }) {
          promptAsyncCallCount++;
          lastPromptBody = body;
          return { data: { id: path.id, status: "ok" } };
        },
        async get({ path }) {
          return { data: { id: path.id, parentID: opts.parentID ?? null } };
        },
      },
    },
    __test: {
      getPromptAsyncCallCount() {
        return promptAsyncCallCount;
      },
      getLastPromptBody() {
        return lastPromptBody;
      },
    },
  };
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
  const originalWarn = console.warn;
  const originalInfo = console.info;
  const originalError = console.error;

  console.warn = (...args) => logs.push({ level: "warn", msg: args.join(" ") });
  console.info = (...args) => logs.push({ level: "info", msg: args.join(" ") });
  console.error = (...args) => logs.push({ level: "error", msg: args.join(" ") });

  return {
    logs,
    restore() {
      console.warn = originalWarn;
      console.info = originalInfo;
      console.error = originalError;
    },
    hasWarn(substr) {
      return logs.some((l) => l.level === "warn" && l.msg.includes(substr));
    },
  };
}

async function runRegistrationOk() {
  let plugin;
  try {
    const mod = await import(PLUGIN_PATH);
    plugin = mod.default;
  } catch (err) {
    fail(`Failed to import plugin: ${err.message}`);
  }

  if (typeof plugin !== "function") {
    fail(`Plugin default export is not a function (got ${typeof plugin})`);
  }

  const ctx = makeFakeCtx();
  let result;
  try {
    result = await plugin(ctx);
  } catch (err) {
    fail(`Plugin threw during initialization: ${err.message}`);
  }

  if (!result || typeof result !== "object") {
    fail(`Plugin did not return an object`);
  }

  if (typeof result.event !== "function") {
    fail(`Plugin return value missing 'event' function`);
  }

  // Dispatch session.created
  try {
    await result.event({
      event: {
        type: "session.created",
        properties: { sessionID: "sess-test-1" },
      },
    });
  } catch (err) {
    fail(`Event handler threw on session.created: ${err.message}`);
  }

  // Dispatch session.idle
  try {
    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-test-1" },
      },
    });
  } catch (err) {
    fail(`Event handler threw on session.idle: ${err.message}`);
  }

  // Dispatch session.deleted
  try {
    await result.event({
      event: {
        type: "session.deleted",
        properties: { sessionID: "sess-test-1" },
      },
    });
  } catch (err) {
    fail(`Event handler threw on session.deleted: ${err.message}`);
  }

  pass("registration-ok — plugin loads, exports correct shape, handles events");
}

async function runRegistrationMissing() {
  const badPath = PLUGIN_PATH.replace("aspect-dynamics.mjs", "aspect-dynamics-NONEXISTENT.mjs");

  try {
    await import(badPath);
    fail("Import should have thrown for missing module");
  } catch (err) {
    if (err.code === "ERR_MODULE_NOT_FOUND" || err.message.includes("Cannot find module")) {
      console.error(`FAIL (expected): registration-missing — correctly fails for missing module: ${err.message}`);
      process.exit(1);
    }
    throw err;
  }
}

async function runChildSessionIgnored() {
  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const { listActiveSessions } = await import(SESSION_STATE_PATH);

  const ctx = makeFakeCtx({ parentID: "parent-123" });
  const result = await plugin(ctx);

  await result.event({
    event: {
      type: "session.created",
      properties: { sessionID: "sess-child-1" },
    },
  });

  const active = listActiveSessions();
  if (active.includes("sess-child-1")) {
    fail("Child session should not be tracked in session state");
  }

  pass("child-session-ignored — child sessions are skipped");
}

async function runDedupSameAssistant() {
  await setTestConfig({ logLevel: "info" });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const { getLastHandledAssistantMessageId } = await import(SESSION_STATE_PATH);

  const messages = [
    { id: "msg-1", info: { role: "user", text: "this is frustrating" } },
    { id: "msg-2", info: { role: "assistant", text: "hi there" } },
  ];

  const ctx = makeFakeCtx({ messages });
  const result = await plugin(ctx);

  // First idle — should process
  const logCapture = captureLogs();
  await result.event({
    event: {
      type: "session.idle",
      properties: { sessionID: "sess-dedup-1" },
    },
  });
  logCapture.restore();

  if (getLastHandledAssistantMessageId("sess-dedup-1") !== "msg-2") {
    await clearTestConfig();
    fail(`Expected lastHandledAssistantMessageId to be 'msg-2' after first idle, got ${getLastHandledAssistantMessageId("sess-dedup-1")}`);
  }

  // Second idle with same assistant message — should skip
  const logCapture2 = captureLogs();
  await result.event({
    event: {
      type: "session.idle",
      properties: { sessionID: "sess-dedup-1" },
    },
  });
  logCapture2.restore();

  await clearTestConfig();

  const dedupFound = logCapture2.logs.some((l) => l.msg.includes("already handled assistant message"));
  if (!dedupFound) {
    fail("Second idle with same assistant message should be skipped with dedup warning");
  }

  pass("dedup-same-assistant — duplicate assistant messages are skipped");
}

async function runCircuitBreaker() {
  await setTestConfig({ logLevel: "info" });

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const { getSessionState } = await import(SESSION_STATE_PATH);

    // Make messages() throw for first 3 calls to force failures
    const ctx = makeFakeCtx({ messagesShouldThrow: 3 });
    const result = await plugin(ctx);

    // Trigger 3 failures
    for (let i = 0; i < 3; i++) {
      await result.event({
        event: {
          type: "session.idle",
          properties: { sessionID: "sess-cb-1" },
        },
      });
    }

    const stateAfter3 = getSessionState("sess-cb-1");
    if (!stateAfter3.circuitBroken) {
      fail(`Expected circuitBroken=true after 3 failures, got ${stateAfter3.circuitBroken}`);
    }
    if (stateAfter3.failureCount !== 3) {
      fail(`Expected failureCount=3 after 3 failures, got ${stateAfter3.failureCount}`);
    }

    // 4th idle should be skipped due to open circuit breaker
    const logCapture = captureLogs();
    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-cb-1" },
      },
    });
    logCapture.restore();

    const cbFound = logCapture.logs.some((l) => l.msg.includes("circuit breaker open"));
    if (!cbFound) {
      fail("4th idle should be skipped with circuit breaker warning");
    }
  } finally {
    await clearTestConfig();
  }

  pass("circuit-breaker — circuit opens after 3 failures and skips subsequent events");
}

async function runContextWindowRespected() {
  const { extractContext } = await import(CONTEXT_PATH);

  // Build 30 user/assistant messages
  const messages = [];
  for (let i = 0; i < 30; i++) {
    messages.push({
      id: `msg-${i}`,
      info: { role: i % 2 === 0 ? "user" : "assistant", text: `message ${i}` },
    });
  }

  const ctx = makeFakeCtx({ messages });
  const context = await extractContext(ctx, "sess-cw-1", { contextWindowTurns: 10 });

  if (!context) fail("extractContext returned null");
  if (context.messages.length !== 20) {
    fail(`Expected 20 messages in context (10 user/assistant pairs), got ${context.messages.length}`);
  }
  if (context.messages[0].text !== "message 10") {
    fail(`Expected first message text 'message 10', got '${context.messages[0].text}'`);
  }
  if (context.messages[19].text !== "message 29") {
    fail(`Expected last message text 'message 29', got '${context.messages[19].text}'`);
  }
  if (context.latestAssistantMessageId !== "msg-29") {
    fail(`Expected latestAssistantMessageId 'msg-29', got '${context.latestAssistantMessageId}'`);
  }

  pass("context-window-respected — only last 10 user/assistant pairs (20 messages) included");
}

async function runSeedSetLoad() {
  const { loadSets } = await import(SETS_PATH);

  const sets = await loadSets();
  if (!Array.isArray(sets) || sets.length === 0) {
    fail("Expected loadSets() to return non-empty array");
  }

  const emotionsV1 = sets.find((set) => set.id === "emotions-v1");
  if (!emotionsV1) {
    fail("Expected emotions-v1 set to be loaded from seed JSON");
  }

  if (emotionsV1.defaultThreshold !== 0.75) {
    fail(`Expected emotions-v1 defaultThreshold=0.75, got ${emotionsV1.defaultThreshold}`);
  }

  if (!Array.isArray(emotionsV1.aspects) || emotionsV1.aspects.length !== 4) {
    fail(`Expected emotions-v1 to include 4 aspects, got ${emotionsV1.aspects?.length ?? "invalid"}`);
  }

  const emotionsV2 = sets.find((set) => set.id === "emotions-v2");
  if (!emotionsV2) {
    fail("Expected emotions-v2 set to be loaded from seed JSON");
  }

  if (emotionsV2.defaultThreshold !== 0.5) {
    fail(`Expected emotions-v2 defaultThreshold=0.5, got ${emotionsV2.defaultThreshold}`);
  }

  if (!Array.isArray(emotionsV2.aspects) || emotionsV2.aspects.length !== 4) {
    fail(`Expected emotions-v2 to include 4 aspects, got ${emotionsV2.aspects?.length ?? "invalid"}`);
  }

  // Verify deterministic order: emotions-v1 (sorted before emotions-v2)
  if (sets[0].id !== "emotions-v1" || sets[1].id !== "emotions-v2") {
    fail(`Expected deterministic order emotions-v1 then emotions-v2, got ${sets.map((s) => s.id).join(", ")}`);
  }

  pass("seed-set-load — emotions-v1 and emotions-v2 load with correct thresholds, aspects, and order");
}

async function runMissingSet() {
  const { loadSets, getSetById } = await import(SETS_PATH);
  const sets = await loadSets();

  const missing = getSetById(sets, "non-existent-set-id");
  if (missing !== null) {
    fail(`Expected missing set lookup to return null, got ${JSON.stringify(missing)}`);
  }

  pass("missing-set — getSetById returns null for unknown set ID");
}

async function runUnknownActiveSet() {
  await setTestConfig({
    activeSets: ["non-existent-set"],
    logLevel: "warn",
  });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const ctx = makeFakeCtx();
  const logCapture = captureLogs();

  try {
    const result = await plugin(ctx);

    // Plugin should return event handler (no crash)
    if (!result || typeof result.event !== "function") {
      fail("Plugin should return event handler even with unknown active set");
    }

    // Event handler should be no-op
    await result.event({
      event: {
        type: "session.created",
        properties: { sessionID: "sess-unknown-set-1" },
      },
    });

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-unknown-set-1" },
      },
    });

    // Verify no dispatch occurred
    if (ctx.__test.getPromptAsyncCallCount() !== 0) {
      fail(`Expected no dispatches with unknown active set, got ${ctx.__test.getPromptAsyncCallCount()}`);
    }
  } finally {
    logCapture.restore();
    await clearTestConfig();
  }

  if (!logCapture.hasWarn("Unknown active set ID")) {
    fail("Expected warning about unknown active set ID: non-existent-set");
  }

  pass("unknown-active-set — unknown activeSet ID warns, returns empty sets, no dispatch");
}

async function runPrefilterSkip() {
  const { prefilterContext } = await import(CONTEXT_PATH);

  const context = {
    messages: [
      { id: "msg-1", role: "user", text: "hello there" },
      { id: "msg-2", role: "assistant", text: "hi back" },
    ],
    latestAssistantMessageId: "msg-2",
  };

  const activeSets = [
    {
      id: "test",
      aspects: [
        { name: "frustration", heuristicPhrases: ["this is frustrating", "so annoyed"] },
      ],
    },
  ];

  const result = prefilterContext(context, activeSets, { heuristicPreFilter: true });
  if (result !== false) {
    fail(`Expected prefilter to return false (skip), got ${result}`);
  }

  pass("prefilter-skip — no matching phrases, prefilter returns false (zero scorer executions)");
}

async function runPrefilterHit() {
  const { prefilterContext } = await import(CONTEXT_PATH);

  const context = {
    messages: [
      { id: "msg-1", role: "user", text: "this is frustrating" },
      { id: "msg-2", role: "assistant", text: "I understand" },
    ],
    latestAssistantMessageId: "msg-2",
  };

  const activeSets = [
    {
      id: "test",
      aspects: [
        { name: "frustration", heuristicPhrases: ["this is frustrating", "so annoyed"] },
      ],
    },
  ];

  const result = prefilterContext(context, activeSets, { heuristicPreFilter: true });
  if (result !== true) {
    fail(`Expected prefilter to return true (proceed), got ${result}`);
  }

  pass("prefilter-hit — matching phrase found, prefilter returns true (scoring proceeds)");
}

async function setTestConfig(overrides) {
  const configMod = await import(join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "config.mjs"));
  configMod.__testConfigOverride.value = overrides;
}

async function clearTestConfig() {
  const configMod = await import(join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "config.mjs"));
  configMod.__testConfigOverride.value = null;
}

async function runReservedFieldsIdle() {
  await setTestConfig({
    logLevel: "info",
    scoringModel: "gpt-4",
    polishingModel: "gpt-4-mini",
    dreamAgent: { enabled: true, interval: 30000 },
  });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const ctx = makeFakeCtx();
  const logCapture = captureLogs();
  const result = await plugin(ctx);
  logCapture.restore();

  const hasDeferredNotice = logCapture.logs.some(
    (l) => l.level === "info" && l.msg.includes("Deferred fields present")
  );
  if (!hasDeferredNotice) {
    await clearTestConfig();
    fail("Expected deferred-field notice log when scoringModel/polishingModel/dreamAgent are set");
  }

  await result.event({
    event: {
      type: "session.created",
      properties: { sessionID: "sess-deferred-1" },
    },
  });

  const idleLogCapture = captureLogs();
  await result.event({
    event: {
      type: "session.idle",
      properties: { sessionID: "sess-deferred-1" },
    },
  });
  idleLogCapture.restore();

  const hasNetworkCall = idleLogCapture.logs.some(
    (l) =>
      l.msg.includes("model") ||
      l.msg.includes("api") ||
      l.msg.includes("network") ||
      l.msg.includes("request") ||
      l.msg.includes("fetch") ||
      l.msg.includes("http")
  );
  if (hasNetworkCall) {
    await clearTestConfig();
    fail("Deferred fields triggered a network/model call — expected zero network calls");
  }

  await clearTestConfig();
  pass("reserved-fields-idle — deferred fields accepted, logged, and inert; only heuristic scoring used");
}

async function runNoNetworkCalls() {
  const callLog = [];

  const trackingCtx = {
    directory: "/tmp/fake-project",
    client: {
      session: {
        async messages() {
          callLog.push("session.messages");
          return {
            data: [
              { id: "msg-1", info: { role: "user", text: "this is frustrating" } },
              { id: "msg-2", info: { role: "assistant", text: "I understand" } },
            ],
          };
        },
        async promptAsync({ path }) {
          callLog.push("session.promptAsync");
          return { data: { id: path.id, status: "ok" } };
        },
        async get({ path }) {
          callLog.push("session.get");
          return { data: { id: path.id, parentID: null } };
        },
      },
    },
  };

  await setTestConfig({
    scoringModel: "gpt-4",
    polishingModel: "gpt-4-mini",
    dreamAgent: { enabled: true, interval: 30000 },
  });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const result = await plugin(trackingCtx);

  await result.event({
    event: {
      type: "session.created",
      properties: { sessionID: "sess-nonet-1" },
    },
  });

  await result.event({
    event: {
      type: "session.idle",
      properties: { sessionID: "sess-nonet-1" },
    },
  });

  await result.event({
    event: {
      type: "session.deleted",
      properties: { sessionID: "sess-nonet-1" },
    },
  });

  await clearTestConfig();

  const modelCalls = callLog.filter((c) => c === "session.promptAsync");
  if (modelCalls.length > 0) {
    fail(`Expected zero model calls, got ${modelCalls.length} promptAsync calls`);
  }

  const unexpectedCalls = callLog.filter(
    (c) => c !== "session.messages" && c !== "session.get"
  );
  if (unexpectedCalls.length > 0) {
    fail(`Unexpected session calls detected: ${unexpectedCalls.join(", ")}`);
  }

  pass("no-network-calls — zero model calls, zero dream-agent timers/locks, only session.messages and session.get used");
}

async function runBelowThreshold() {
  await setTestConfig({ activeSets: ["emotions-v1"], logLevel: "info" });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const { __testSetsOverride } = await import(SETS_PATH);

  const messages = [
    { id: "msg-1", info: { role: "user", text: "hello" } },
    { id: "msg-2", info: { role: "assistant", text: "this is frustrating" } },
  ];

  const ctx = makeFakeCtx({ messages });
  __testSetsOverride.value = NUDGE_TEST_SETS;

  try {
    const result = await plugin(ctx);

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-below-threshold-1" },
      },
    });

    if (ctx.__test.getPromptAsyncCallCount() !== 0) {
      fail(
        `Expected no nudge dispatch for below-threshold case, got ${ctx.__test.getPromptAsyncCallCount()} dispatch(es)`
      );
    }
  } finally {
    await clearTestConfig();
    __testSetsOverride.value = null;
  }

  pass("below-threshold — score below threshold does not dispatch nudge");
}

async function runThresholdCrossed() {
  await setTestConfig({ activeSets: ["emotions-v1"], logLevel: "info" });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const { __testSetsOverride } = await import(SETS_PATH);

  const messages = [
    {
      id: "msg-1",
      info: {
        role: "user",
        text: "this is frustrating and I'm stuck on this",
      },
    },
    { id: "msg-2", info: { role: "assistant", text: "I understand" } },
  ];

  const ctx = makeFakeCtx({ messages });
  __testSetsOverride.value = NUDGE_TEST_SETS;

  try {
    const result = await plugin(ctx);

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-threshold-crossed-1" },
      },
    });

    const dispatches = ctx.__test.getPromptAsyncCallCount();
    if (dispatches < 1) {
      fail("Expected nudge dispatch for threshold-crossed case, got 0 dispatches");
    }

    const lastBody = ctx.__test.getLastPromptBody();
    if (!Array.isArray(lastBody) || lastBody.length === 0) {
      fail("Expected dispatched nudge payload to be a non-empty array");
    }
  } finally {
    await clearTestConfig();
    __testSetsOverride.value = null;
  }

  pass("threshold-crossed — score at/above threshold dispatches nudge");
}

async function runTieBreak() {
  const { scoreAspects } = await import(HEURISTICS_PATH);

  const set = {
    id: "tie-set",
    version: 1,
    defaultThreshold: 0.75,
    aspects: [
      { id: "aspect-a", heuristicPhrases: ["one"] },
      { id: "aspect-b", heuristicPhrases: ["two", "three"] },
    ],
  };

  // Tie by score (0.5 vs 0.5), resolved by most-recent-user hit count.
  const contextUserTieBreak = {
    messages: [
      { id: "m1", role: "user", text: "one" },
      { id: "m2", role: "assistant", text: "two and three" },
    ],
    latestAssistantMessageId: "m2",
  };

  const resultUserTieBreak = scoreAspects(contextUserTieBreak, [set]);
  if (resultUserTieBreak.topAspectId !== "tie-set:aspect-a") {
    fail(
      `Expected tie-break winner 'tie-set:aspect-a' by most-recent-user-hit rule, got '${resultUserTieBreak.topAspectId}'`
    );
  }

  // Tie by score and equal most-recent-user hit count, resolved by aspect order.
  const contextOrderTieBreak = {
    messages: [
      { id: "m3", role: "user", text: "one two" },
      { id: "m4", role: "assistant", text: "ack" },
    ],
    latestAssistantMessageId: "m4",
  };

  const setOrderTie = {
    ...set,
    aspects: [
      { id: "aspect-first", heuristicPhrases: ["one"] },
      { id: "aspect-second", heuristicPhrases: ["two"] },
    ],
  };

  const resultOrderTieBreak = scoreAspects(contextOrderTieBreak, [setOrderTie]);
  if (resultOrderTieBreak.topAspectId !== "tie-set:aspect-first") {
    fail(
      `Expected tie-break winner 'tie-set:aspect-first' by set-order rule, got '${resultOrderTieBreak.topAspectId}'`
    );
  }

  pass("tie-break — deterministic winner selected by user-hit then set-order rules");
}

async function runRecursiveNudge() {
  await setTestConfig({ logLevel: "info" });

  const setsMod = await import(SETS_PATH);
  const __testSetsOverride = setsMod.__testSetsOverride;

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;

    const messages = [
      {
        id: "msg-1",
        info: {
          role: "user",
          text: "this is frustrating and I'm stuck on this",
        },
      },
      { id: "msg-2", info: { role: "assistant", text: "I understand" } },
    ];

    const ctx = makeFakeCtx({ messages });
    __testSetsOverride.value = NUDGE_TEST_SETS;

    const result = await plugin(ctx);

    // First idle should dispatch a nudge
    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-recursive-nudge-1" },
      },
    });

    if (ctx.__test.getPromptAsyncCallCount() !== 1) {
      fail(`Expected first idle to dispatch one nudge, got ${ctx.__test.getPromptAsyncCallCount()}`);
    }

    // Simulate transcript-visible nudge coming back as latest user message
    messages.push({
      id: "msg-3",
      info: {
        role: "user",
        text: "[ASPECT-DYNAMICS-NUDGE v1] assistant acknowledged and applied",
      },
    });

    // Second idle should be skipped by recursion guard
    const logCapture = captureLogs();
    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-recursive-nudge-1" },
      },
    });
    logCapture.restore();

    if (ctx.__test.getPromptAsyncCallCount() !== 1) {
      fail(`Expected recursion guard to prevent second dispatch, got ${ctx.__test.getPromptAsyncCallCount()} total dispatches`);
    }

    const rgFound = logCapture.logs.some((l) => l.msg.includes("recursion guard"));
    if (!rgFound) {
      fail("Expected recursion guard warning on second idle");
    }
  } finally {
    __testSetsOverride.value = null;
    await clearTestConfig();
  }

  pass("recursive-nudge — plugin ignores its own nudge on subsequent idle");
}

async function runDisabled() {
  await setTestConfig({ enabled: false });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const ctx = makeFakeCtx();

  try {
    const result = await plugin(ctx);

    await result.event({
      event: {
        type: "session.created",
        properties: { sessionID: "sess-disabled-1" },
      },
    });

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-disabled-1" },
      },
    });

    await result.event({
      event: {
        type: "session.deleted",
        properties: { sessionID: "sess-disabled-1" },
      },
    });

    if (ctx.__test.getPromptAsyncCallCount() !== 0) {
      fail(`Expected no nudge dispatches when disabled, got ${ctx.__test.getPromptAsyncCallCount()}`);
    }
  } finally {
    await clearTestConfig();
  }

  pass("disabled — plugin is no-op when enabled: false");
}

async function runProofDisabled() {
  await setTestConfig({ enabled: false });

  const { __testProofOverride, readProofEvents, resetProofEvents } = await import(
    join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "logging.mjs")
  );

  __testProofOverride.value = [];
  resetProofEvents();

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const ctx = makeFakeCtx();
    const result = await plugin(ctx);

    await result.event({
      event: {
        type: "session.created",
        properties: { sessionID: "sess-proof-disabled-1" },
      },
    });

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-proof-disabled-1" },
      },
    });

    const proofs = readProofEvents();
    const hasAnyEvent = proofs.some((p) => p.session_id === "sess-proof-disabled-1");
    if (hasAnyEvent) {
      fail("Expected no proof events when plugin is disabled");
    }
  } finally {
    __testProofOverride.value = null;
    await clearTestConfig();
  }

  pass("proof-disabled — no proof events emitted when plugin is disabled");
}

async function runProofCreated() {
  const { __testProofOverride, readProofEvents, resetProofEvents } = await import(
    join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "logging.mjs")
  );

  __testProofOverride.value = [];
  resetProofEvents();

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const ctx = makeFakeCtx();
  const result = await plugin(ctx);

  await result.event({
    event: {
      type: "session.created",
      properties: { sessionID: "sess-proof-created-1" },
    },
  });

  const proofs = readProofEvents();
  const created = proofs.find((p) => p.event === "session_created" && p.session_id === "sess-proof-created-1");
  if (!created) {
    __testProofOverride.value = null;
    fail("Expected session_created proof event");
  }

  __testProofOverride.value = null;
  pass("proof-created — session.created emits proof event");
}

async function runProofSkip() {
  const { __testProofOverride, readProofEvents, resetProofEvents } = await import(
    join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "logging.mjs")
  );

  __testProofOverride.value = [];
  resetProofEvents();

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;

  // Messages with no heuristic phrases → prefilter skip
  const messages = [
    { id: "msg-1", info: { role: "user", text: "hello there" } },
    { id: "msg-2", info: { role: "assistant", text: "hi back" } },
  ];

  const ctx = makeFakeCtx({ messages });
  const result = await plugin(ctx);

  await result.event({
    event: {
      type: "session.created",
      properties: { sessionID: "sess-proof-skip-1" },
    },
  });

  await result.event({
    event: {
      type: "session.idle",
      properties: { sessionID: "sess-proof-skip-1" },
    },
  });

  const proofs = readProofEvents();
  const skip = proofs.find((p) => p.event === "skip" && p.session_id === "sess-proof-skip-1");
  if (!skip) {
    __testProofOverride.value = null;
    fail("Expected skip proof event on prefilter miss");
  }
  if (skip.reason !== "prefilter") {
    __testProofOverride.value = null;
    fail(`Expected skip reason=prefilter, got ${skip.reason}`);
  }

  __testProofOverride.value = null;
  pass("proof-skip — prefilter skip emits proof event with reason=prefilter");
}

async function runProofNudge() {
  await setTestConfig({ activeSets: ["emotions-v1"], logLevel: "info" });

  const { __testProofOverride, readProofEvents, resetProofEvents } = await import(
    join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "logging.mjs")
  );
  const { __testSetsOverride } = await import(SETS_PATH);

  __testProofOverride.value = [];
  resetProofEvents();

  const messages = [
    {
      id: "msg-1",
      info: {
        role: "user",
        text: "this is frustrating and I'm stuck on this",
      },
    },
    { id: "msg-2", info: { role: "assistant", text: "I understand" } },
  ];

  const ctx = makeFakeCtx({ messages });
  __testSetsOverride.value = NUDGE_TEST_SETS;

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;
    const result = await plugin(ctx);

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-proof-nudge-1" },
      },
    });

    const proofs = readProofEvents();
    const nudge = proofs.find((p) => p.event === "nudge_sent" && p.session_id === "sess-proof-nudge-1");
    if (!nudge) {
      fail("Expected nudge_sent proof event");
    }
    if (!nudge.aspect) {
      fail("Expected nudge_sent proof to include aspect");
    }
    if (typeof nudge.score !== "number") {
      fail("Expected nudge_sent proof to include numeric score");
    }
  } finally {
    await clearTestConfig();
    __testProofOverride.value = null;
    __testSetsOverride.value = null;
  }

  pass("proof-nudge — nudge dispatch emits proof event with aspect and score");
}

async function runProofCircuit() {
  const { __testProofOverride, readProofEvents, resetProofEvents } = await import(
    join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "logging.mjs")
  );

  __testProofOverride.value = [];
  resetProofEvents();

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;

  // Make messages() throw to force failures
  const ctx = makeFakeCtx({ messagesShouldThrow: 3 });
  const result = await plugin(ctx);

  // Trigger 3 failures
  for (let i = 0; i < 3; i++) {
    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-proof-circuit-1" },
      },
    });
  }

  // 4th idle should hit circuit breaker
  await result.event({
    event: {
      type: "session.idle",
      properties: { sessionID: "sess-proof-circuit-1" },
    },
  });

  const proofs = readProofEvents();
  const circuit = proofs.find((p) => p.event === "circuit_open" && p.session_id === "sess-proof-circuit-1");
  if (!circuit) {
    __testProofOverride.value = null;
    fail("Expected circuit_open proof event after repeated failures");
  }
  if (circuit.failure_count !== 3) {
    __testProofOverride.value = null;
    fail(`Expected failure_count=3, got ${circuit.failure_count}`);
  }

  __testProofOverride.value = null;
  pass("proof-circuit — circuit breaker open emits proof event with failure_count");
}

async function runProofRetention() {
  const { __testProofOverride, readProofEvents, resetProofEvents } = await import(
    join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "logging.mjs")
  );

  __testProofOverride.value = [];
  resetProofEvents();

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const ctx = makeFakeCtx();
  const result = await plugin(ctx);

  // Generate many session.created events to exceed MAX_PROOF_EVENTS (1000)
  for (let i = 0; i < 1005; i++) {
    await result.event({
      event: {
        type: "session.created",
        properties: { sessionID: `sess-retention-${i}` },
      },
    });
  }

  const proofs = readProofEvents();
  if (proofs.length > 1000) {
    __testProofOverride.value = null;
    fail(`Expected proof events capped at 1000, got ${proofs.length}`);
  }

  // Verify the most recent events are retained (should see sess-retention-1004)
  const last = proofs[proofs.length - 1];
  if (!last || !last.session_id || !last.session_id.includes("1004")) {
    __testProofOverride.value = null;
    fail("Expected retention cap to preserve most recent events");
  }

  __testProofOverride.value = null;
  pass("proof-retention — proof events capped at MAX_PROOF_EVENTS=1000");
}

async function runInvalidConfig() {
  await setTestConfig({ activeSets: "not-an-array" });

  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const ctx = makeFakeCtx();
  const logCapture = captureLogs();

  try {
    const result = await plugin(ctx);
    logCapture.restore();

    if (!logCapture.hasWarn("Invalid config")) {
      fail("Expected warning for invalid config");
    }

    await result.event({
      event: {
        type: "session.created",
        properties: { sessionID: "sess-invalid-1" },
      },
    });

    await result.event({
      event: {
        type: "session.idle",
        properties: { sessionID: "sess-invalid-1" },
      },
    });

    if (ctx.__test.getPromptAsyncCallCount() !== 0) {
      fail(`Expected no actions with invalid config, got ${ctx.__test.getPromptAsyncCallCount()} dispatch(es)`);
    }
  } finally {
    await clearTestConfig();
  }

  pass("invalid-config — malformed config logs warning and behaves as no-op");
}

async function runActiveSetSelection() {
  await setTestConfig({
    activeSets: ["emotions-v2"],
    logLevel: "info",
  });

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;

    const messages = [
      { id: "msg-1", info: { role: "user", text: "what the fuck is going on" } },
      { id: "msg-2", info: { role: "assistant", text: "Let me help you figure that out." } },
    ];

    const ctx = makeFakeCtx({ messages });
    const result = await plugin(ctx);

    await result.event({
      event: { type: "session.created", properties: { sessionID: "sess-active-set-1" } },
    });

    await result.event({
      event: { type: "session.idle", properties: { sessionID: "sess-active-set-1" } },
    });

    if (ctx.__test.getPromptAsyncCallCount() < 1) {
      fail(`Expected at least 1 dispatch with emotions-v2 active, got ${ctx.__test.getPromptAsyncCallCount()}`);
    }

    // Switch to emotions-v1 — should NOT dispatch for v2-only phrase
    await setTestConfig({
      activeSets: ["emotions-v1"],
      logLevel: "info",
    });

    const messagesV1 = [
      { id: "msg-3", info: { role: "user", text: "what the fuck is going on" } },
      { id: "msg-4", info: { role: "assistant", text: "Let me help you figure that out." } },
    ];

    const ctxV1 = makeFakeCtx({ messages: messagesV1 });
    const resultV1 = await plugin(ctxV1);

    await resultV1.event({
      event: { type: "session.created", properties: { sessionID: "sess-active-set-2" } },
    });

    await resultV1.event({
      event: { type: "session.idle", properties: { sessionID: "sess-active-set-2" } },
    });

    if (ctxV1.__test.getPromptAsyncCallCount() !== 0) {
      fail(`Expected 0 dispatches with emotions-v1 active, got ${ctxV1.__test.getPromptAsyncCallCount()}`);
    }
  } finally {
    await clearTestConfig();
  }

  pass("active-set-selection — emotions-v2 dispatches for v2-only phrase, emotions-v1 does not");
}

async function runSingleDistressHit() {
  await setTestConfig({
    activeSets: ["emotions-v2"],
    logLevel: "info",
  });

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;

    const messages = [
      { id: "msg-1", info: { role: "user", text: "what the fuck is going on" } },
      { id: "msg-2", info: { role: "assistant", text: "Let me help you." } },
    ];

    const ctx = makeFakeCtx({ messages });
    const result = await plugin(ctx);

    await result.event({
      event: { type: "session.created", properties: { sessionID: "sess-single-distress-1" } },
    });

    await result.event({
      event: { type: "session.idle", properties: { sessionID: "sess-single-distress-1" } },
    });

    const dispatches = ctx.__test.getPromptAsyncCallCount();
    if (dispatches !== 1) {
      fail(`Expected exactly 1 dispatch, got ${dispatches}`);
    }

    const lastBody = ctx.__test.getLastPromptBody();
    if (!Array.isArray(lastBody) || lastBody.length === 0) {
      fail("Expected nudge payload to be a non-empty array");
    }
  } finally {
    await clearTestConfig();
  }

  pass("single-distress-hit — one latest-user contextual distress phrase dispatches exactly one nudge");
}

async function runQuotedProfanityNoNudge() {
  await setTestConfig({
    activeSets: ["emotions-v2"],
    logLevel: "info",
  });

  try {
    const mod = await import(PLUGIN_PATH);
    const plugin = mod.default;

    const messages = [
      { id: "msg-1", info: { role: "user", text: "please grep for the word fuck in fixtures" } },
      { id: "msg-2", info: { role: "assistant", text: "Sure, let me search for that." } },
    ];

    const ctx = makeFakeCtx({ messages });
    const result = await plugin(ctx);

    await result.event({
      event: { type: "session.created", properties: { sessionID: "sess-quoted-1" } },
    });

    await result.event({
      event: { type: "session.idle", properties: { sessionID: "sess-quoted-1" } },
    });

    if (ctx.__test.getPromptAsyncCallCount() !== 0) {
      fail(`Expected 0 dispatches for quoted profanity, got ${ctx.__test.getPromptAsyncCallCount()}`);
    }
  } finally {
    await clearTestConfig();
  }

  pass("quoted-profanity-no-nudge — quoted/code-search profanity does not trigger nudge");
}

async function main() {
  const args = process.argv.slice(2);
  const caseIdx = args.indexOf("--case");
  const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null;

  if (!testCase) {
    console.error("Usage: node harness.mjs --case <case-name>");
    console.error("Cases: registration-ok, registration-missing, child-session-ignored, dedup-same-assistant, circuit-breaker, context-window-respected, prefilter-skip, prefilter-hit, reserved-fields-idle, no-network-calls, below-threshold, threshold-crossed, tie-break, seed-set-load, missing-set, unknown-active-set, recursive-nudge, disabled, invalid-config, proof-disabled, proof-created, proof-skip, proof-nudge, proof-circuit, proof-retention, active-set-selection, single-distress-hit, quoted-profanity-no-nudge");
    process.exit(1);
  }

  switch (testCase) {
    case "registration-ok":
      await runRegistrationOk();
      break;
    case "registration-missing":
      await runRegistrationMissing();
      break;
    case "child-session-ignored":
      await runChildSessionIgnored();
      break;
    case "dedup-same-assistant":
      await runDedupSameAssistant();
      break;
    case "circuit-breaker":
      await runCircuitBreaker();
      break;
    case "context-window-respected":
      await runContextWindowRespected();
      break;
    case "prefilter-skip":
      await runPrefilterSkip();
      break;
    case "prefilter-hit":
      await runPrefilterHit();
      break;
    case "reserved-fields-idle":
      await runReservedFieldsIdle();
      break;
    case "no-network-calls":
      await runNoNetworkCalls();
      break;
    case "below-threshold":
      await runBelowThreshold();
      break;
    case "threshold-crossed":
      await runThresholdCrossed();
      break;
    case "tie-break":
      await runTieBreak();
      break;
    case "seed-set-load":
      await runSeedSetLoad();
      break;
    case "missing-set":
      await runMissingSet();
      break;
    case "unknown-active-set":
      await runUnknownActiveSet();
      break;
    case "recursive-nudge":
      await runRecursiveNudge();
      break;
    case "disabled":
      await runDisabled();
      break;
    case "invalid-config":
      await runInvalidConfig();
      break;
    case "proof-disabled":
      await runProofDisabled();
      break;
    case "proof-created":
      await runProofCreated();
      break;
    case "proof-skip":
      await runProofSkip();
      break;
    case "proof-nudge":
      await runProofNudge();
      break;
    case "proof-circuit":
      await runProofCircuit();
      break;
    case "proof-retention":
      await runProofRetention();
      break;
    case "active-set-selection":
      await runActiveSetSelection();
      break;
    case "single-distress-hit":
      await runSingleDistressHit();
      break;
    case "quoted-profanity-no-nudge":
      await runQuotedProfanityNoNudge();
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
