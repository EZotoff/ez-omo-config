// tests/provider-connect-retry-min-output/harness.mjs
// Unit harness for the near-empty detection logic in provider-connect-retry.mjs.
//
// Drives the plugin's `event` handler directly with a stub `ctx`:
//   - message.updated  → detection site (zero-token branch + near-empty branch)
//   - session.idle     → retry dispatch site
//
// Each scenario constructs a FRESH plugin instance so closure-scoped state
// (attemptsBySession, inFlightSessions, handledErrorsBySession,
// childSessionVerdictCache) starts clean.
//
// The registry is read live from ~/.config/opencode/retry-errors.json
// (symlinked to configs/retry-errors.json, which has min_output_tokens=5 on
// the glm-unknown-api-rejection rule). Scenarios H1-H4 and H6 use this real
// registry. Scenario H5 monkey-patches fs.readFileSync to swap in a registry
// with min_output_tokens=0, proving the near-empty branch can be disabled.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PLUGIN_PATH = join(__dirname, "..", "..", "configs", "opencode", "provider-connect-retry.mjs");
const REGISTRY_PATH = path.join(os.homedir(), ".config", "opencode", "retry-errors.json");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function pass(message) {
  console.log(`PASS: ${message}`);
}

// Build a stub ctx. `parentID` controls whether session.get reports a child
// session (string) or a root session (undefined). `messages` is returned by
// session.messages() during the idle/dispatch phase.
function makeStubCtx({ parentID, messages }) {
  let promptAsyncCallCount = 0;
  let lastPromptBody = null;

  return {
    directory: "/tmp/fake-project",
    client: {
      session: {
        async get({ path }) {
          return {
            data: {
              id: path.id,
              parentID: typeof parentID === "string" && parentID.length > 0 ? parentID : null,
            },
          };
        },
        async messages() {
          return { data: messages ?? [] };
        },
        async promptAsync({ path, body }) {
          promptAsyncCallCount++;
          lastPromptBody = body;
          return { data: { id: path.id, status: "ok" } };
        },
        async abort() {
          return { data: { status: "ok" } };
        },
      },
      tui: {
        async showToast() {
          // no-op recorder; tests do not assert on toasts
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

// Synthetic message.updated payload for an assistant completion event.
function makeCompletionEvent({ sessionID, finish, outputTokens, messageID, parts }) {
  return {
    event: {
      type: "message.updated",
      properties: {
        sessionID,
        info: {
          id: messageID,
          role: "assistant",
          finish,
          tokens: { output: outputTokens },
          ...(parts !== undefined ? { parts } : {}),
        },
      },
    },
  };
}

// Synthetic session.idle payload.
function makeIdleEvent(sessionID) {
  return {
    event: {
      type: "session.idle",
      properties: { sessionID },
    },
  };
}

// Build the messages array returned by session.messages() during the idle
// dispatch phase. The assistant message MUST carry the same id and token count
// as the completion event, otherwise the idle guard clears state.
function buildDispatchMessages({ sessionID, completionMsgID, finish, outputTokens, assistantParts }) {
  const userMsgID = `msg-${sessionID}-user`;
  const userParts = [{ type: "text", text: "do the thing" }];
  return [
    {
      id: userMsgID,
      info: { role: "user", parts: userParts },
      parts: userParts,
    },
    {
      id: completionMsgID,
      info: {
        id: completionMsgID,
        role: "assistant",
        tokens: { output: outputTokens },
        finish,
        parts: assistantParts,
      },
      parts: assistantParts,
    },
  ];
}

// Monkey-patch fs.readFileSync so the plugin's loadRegistry() reads a temp
// registry with the given min_output_tokens on the empty-response rule.
// All other file reads pass through unchanged. Restore in a finally block.
function patchRegistryMinTokens(minTokens) {
  const originalReadFileSync = fs.readFileSync;
  const realContent = originalReadFileSync.call(fs, REGISTRY_PATH, "utf8");
  const realJson = JSON.parse(realContent);
  const modified = {
    ...realJson,
    errors: realJson.errors.map((entry) =>
      entry && entry.detect_empty_response
        ? { ...entry, min_output_tokens: minTokens }
        : entry
    ),
  };
  const modifiedContent = JSON.stringify(modified);
  fs.readFileSync = function patchedReadFileSync(p, ...rest) {
    if (p === REGISTRY_PATH) return modifiedContent;
    return originalReadFileSync.call(this, p, ...rest);
  };
  return {
    restore() {
      fs.readFileSync = originalReadFileSync;
    },
  };
}

// Drive one full scenario: construct fresh plugin, fire detection (message.updated),
// then dispatch (session.idle), and assert the retry outcome.
//
// opts:
//   label            — scenario name shown in output
//   parentID         — undefined = root session; string = child session
//   finish           — "stop" | "other" | "tool-calls"
//   outputTokens     — info.tokens.output value
//   assistantParts   — parts array on the assistant message (default: empty)
//   minTokensOverride— if set, monkey-patch the registry's min_output_tokens
//   expectRetry      — boolean: should exactly one promptAsync dispatch occur?
async function driveScenario(opts) {
  const {
    label,
    parentID,
    finish,
    outputTokens,
    assistantParts = [],
    minTokensOverride,
    expectRetry,
  } = opts;

  const sessionID = `sess-${label}`;
  const completionMsgID = `msg-${sessionID}-asst`;

  const messages = buildDispatchMessages({
    sessionID,
    completionMsgID,
    finish,
    outputTokens,
    assistantParts,
  });

  let fsPatch = null;
  if (minTokensOverride !== undefined) {
    fsPatch = patchRegistryMinTokens(minTokensOverride);
  }

  try {
    const mod = await import(PLUGIN_PATH);
    const pluginFactory = mod.ProviderConnectRetryPlugin;
    if (typeof pluginFactory !== "function") {
      fail(`${label}: ProviderConnectRetryPlugin export is not a function (got ${typeof pluginFactory})`);
    }

    const ctx = makeStubCtx({ parentID, messages });
    const hooks = await pluginFactory(ctx);
    if (!hooks || typeof hooks.event !== "function") {
      fail(`${label}: plugin did not return an object with an event function`);
    }

    // Step 1: detection — fire the completion event.
    await hooks.event(
      makeCompletionEvent({
        sessionID,
        finish,
        outputTokens,
        messageID: completionMsgID,
        parts: assistantParts,
      })
    );

    // Step 2: dispatch — fire session.idle.
    await hooks.event(makeIdleEvent(sessionID));

    const dispatchCount = ctx.__test.getPromptAsyncCallCount();
    const lastBody = ctx.__test.getLastPromptBody();

    if (expectRetry) {
      if (dispatchCount !== 1) {
        fail(`${label}: expected exactly 1 retry dispatch, got ${dispatchCount}`);
      }
      if (!lastBody || !Array.isArray(lastBody.parts) || lastBody.parts.length === 0) {
        fail(`${label}: retry dispatched without non-empty parts`);
      }
    } else {
      if (dispatchCount !== 0) {
        fail(`${label}: expected 0 retry dispatches, got ${dispatchCount}`);
      }
    }
  } finally {
    if (fsPatch) fsPatch.restore();
  }
}

// H1: Zero-token completion (finish="stop", output=0) on a ROOT session
// → retry IS dispatched. The zero-token branch fires unconditionally
// regardless of parentID (existing behavior preserved by todo 1).
async function runH1() {
  await driveScenario({
    label: "H1",
    parentID: undefined,
    finish: "stop",
    outputTokens: 0,
    assistantParts: [],
    expectRetry: true,
  });
  pass("H1 — zero-token completion on root session dispatches retry (existing behavior preserved)");
}

// H2: Child session (parentID set), finish="stop", output=3, threshold=5
// → exactly ONE retry dispatched with non-empty parts.
async function runH2() {
  await driveScenario({
    label: "H2",
    parentID: "parent-H2",
    finish: "stop",
    outputTokens: 3,
    assistantParts: [{ type: "text", text: "ok" }],
    expectRetry: true,
  });
  pass("H2 — child near-empty completion (output=3, threshold=5) dispatches exactly one retry");
}

// H3: Child session, output=100 (well above threshold)
// → NO retry, flag cleared.
async function runH3() {
  await driveScenario({
    label: "H3",
    parentID: "parent-H3",
    finish: "stop",
    outputTokens: 100,
    assistantParts: [{ type: "text", text: "Here is a full response with substantial content." }],
    expectRetry: false,
  });
  pass("H3 — child completion well above threshold (output=100) does not dispatch retry");
}

// H4: Root session (no parentID), output=3 (near-empty candidate)
// → NO retry, skip logged at debug level (isChildSession resolves false).
async function runH4() {
  await driveScenario({
    label: "H4",
    parentID: undefined,
    finish: "stop",
    outputTokens: 3,
    assistantParts: [{ type: "text", text: "ok" }],
    expectRetry: false,
  });
  pass("H4 — root near-empty candidate (output=3, no parentID) skips retry");
}

// H5: min_output_tokens=0 (near-empty branch disabled), child session, output=3
// → NO retry. With threshold 0, isNearEmpty=false, so the inner else clears state.
async function runH5() {
  await driveScenario({
    label: "H5",
    parentID: "parent-H5",
    finish: "stop",
    outputTokens: 3,
    assistantParts: [{ type: "text", text: "ok" }],
    minTokensOverride: 0,
    expectRetry: false,
  });
  pass("H5 — min_output_tokens=0 disables near-empty branch (child output=3 does not retry)");
}

// H6: Child session, output=5 (=threshold, boundary)
// → retry dispatched. The comparison is outputTokens <= minTokens.
async function runH6() {
  await driveScenario({
    label: "H6",
    parentID: "parent-H6",
    finish: "stop",
    outputTokens: 5,
    assistantParts: [{ type: "text", text: "ok" }],
    expectRetry: true,
  });
  pass("H6 — child completion at threshold boundary (output=5, threshold=5) dispatches retry");
}

async function main() {
  const args = process.argv.slice(2);
  const caseIdx = args.indexOf("--case");
  const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null;

  if (!testCase) {
    console.error("Usage: node harness.mjs --case <case-name>");
    console.error("Cases: H1-zero-token-root, H2-child-near-empty, H3-child-above-threshold, H4-root-near-empty-no-dispatch, H5-min-tokens-zero-disabled, H6-child-at-threshold");
    process.exit(1);
  }

  switch (testCase) {
    case "H1-zero-token-root":
      await runH1();
      break;
    case "H2-child-near-empty":
      await runH2();
      break;
    case "H3-child-above-threshold":
      await runH3();
      break;
    case "H4-root-near-empty-no-dispatch":
      await runH4();
      break;
    case "H5-min-tokens-zero-disabled":
      await runH5();
      break;
    case "H6-child-at-threshold":
      await runH6();
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
