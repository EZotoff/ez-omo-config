// tests/aspect-dynamics/harness.mjs
// Test harness for aspect-dynamics plugin

import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics.mjs");
const SESSION_STATE_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "session-state.mjs");
const CONTEXT_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics", "context.mjs");

function makeFakeCtx(opts = {}) {
  const messagesStore = opts.messages ?? [
    { id: "msg-1", info: { role: "user", text: "hello" } },
    { id: "msg-2", info: { role: "assistant", text: "hi there" } },
  ];

  let getCallCount = 0;
  let messagesCallCount = 0;

  return {
    directory: "/tmp/fake-project",
    client: {
      session: {
        async messages({ path }) {
          messagesCallCount++;
          if (opts.messagesShouldThrow && messagesCallCount <= opts.messagesShouldThrow) {
            throw new Error("Simulated messages failure");
          }
          return { data: messagesStore };
        },
        async promptAsync({ path, body }) {
          return { data: { id: path.id, status: "ok" } };
        },
        async get({ path }) {
          getCallCount++;
          return { data: { id: path.id, parentID: opts.parentID ?? null } };
        },
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
  const mod = await import(PLUGIN_PATH);
  const plugin = mod.default;
  const { getSessionState, getLastHandledAssistantMessageId } = await import(SESSION_STATE_PATH);

  const messages = [
    { id: "msg-1", info: { role: "user", text: "hello" } },
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

  const state1 = getSessionState("sess-dedup-1");
  if (getLastHandledAssistantMessageId("sess-dedup-1") !== "msg-2") {
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

  if (!logCapture2.hasWarn("already handled assistant message")) {
    fail("Second idle with same assistant message should be skipped with dedup warning");
  }

  pass("dedup-same-assistant — duplicate assistant messages are skipped");
}

async function runCircuitBreaker() {
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

  if (!logCapture.hasWarn("circuit breaker open")) {
    fail("4th idle should be skipped with circuit breaker warning");
  }

  pass("circuit-breaker — circuit opens after 3 failures and skips subsequent events");
}

async function main() {
  const args = process.argv.slice(2);
  const caseIdx = args.indexOf("--case");
  const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null;

  if (!testCase) {
    console.error("Usage: node harness.mjs --case <case-name>");
    console.error("Cases: registration-ok, registration-missing, child-session-ignored, dedup-same-assistant, circuit-breaker");
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
