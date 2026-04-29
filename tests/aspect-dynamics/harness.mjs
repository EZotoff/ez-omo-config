// tests/aspect-dynamics/harness.mjs
// Test harness for aspect-dynamics plugin

import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "aspect-dynamics.mjs");

function makeFakeCtx() {
  const messagesStore = [
    { id: "msg-1", info: { role: "user", text: "hello" } },
    { id: "msg-2", info: { role: "assistant", text: "hi there" } },
  ];

  return {
    directory: "/tmp/fake-project",
    client: {
      session: {
        async messages({ path }) {
          return { data: messagesStore };
        },
        async promptAsync({ path, body }) {
          return { data: { id: path.id, status: "ok" } };
        },
        async get({ path }) {
          return { data: { id: path.id, parentID: null } };
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

async function main() {
  const args = process.argv.slice(2);
  const caseIdx = args.indexOf("--case");
  const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null;

  if (!testCase) {
    console.error("Usage: node harness.mjs --case <case-name>");
    console.error("Cases: registration-ok, registration-missing");
    process.exit(1);
  }

  switch (testCase) {
    case "registration-ok":
      await runRegistrationOk();
      break;
    case "registration-missing":
      await runRegistrationMissing();
      break;
    default:
      console.error(`Unknown test case: ${testCase}`);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(`UNEXPECTED ERROR: ${err.message}`);
  process.exit(1);
});
