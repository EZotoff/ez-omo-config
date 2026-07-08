#!/usr/bin/env node
// Test: provider-connect-retry child-session guard.
//
// Background: A synchronous task() subagent runs in a child session (parentID
// set). When the provider 500'd, the plugin used to skip ALL child sessions
// unconditionally, so the fallback_model never dispatched and the subagent
// died. The fix: child sessions enter the retry path when the matched rule
// has a fallback_model; child sessions are still skipped when the rule has
// no fallback (preserves the original recursion-storm protection).
//
// Cases:
//   1. Child session + rule WITH fallback_model    → fallback dispatched
//   2. Child session + rule WITHOUT fallback_model → skipped (preserved)
//   3. Root session + any rule                     → retry dispatched (regression guard)
//
// The test reads the live registry at ~/.config/opencode/retry-errors.json.
// It relies on two stock rules:
//   - model-token-limit-exceeded (fallback_model: "openai/gpt-5.5", max_retries: 0)
//   - sse-read-timeout (no fallback_model, max_retries: 3, backoff [1000,6000,36000])

import assert from "node:assert";
import { ProviderConnectRetryPlugin } from "../configs/opencode/provider-connect-retry.mjs";

const childSessionID = "ses_child_task_test";
const rootSessionID = "ses_root_test";
const userMessageID = "msg_user_child_1";
const assistantMessageID = "msg_assist_child_1";

function makeMockClient(parentID) {
  const promptAsyncCalls = [];
  const abortCalls = [];
  const client = {
    session: {
      get: async () => ({ data: { parentID } }),
      messages: async () => ({
        data: [
          {
            info: {
              role: "user",
              id: userMessageID,
              parts: [{ type: "text", text: "do the thing" }],
            },
          },
          {
            info: {
              role: "assistant",
              id: assistantMessageID,
              error: "provider failed",
            },
          },
        ],
      }),
      abort: async (input) => abortCalls.push(input),
      promptAsync: async (input) => {
        promptAsyncCalls.push(input);
        return {};
      },
    },
  };
  return { client, promptAsyncCalls, abortCalls };
}

function makeErrorEvent(sessionID, message) {
  return {
    event: {
      type: "session.error",
      properties: {
        sessionID,
        messageID: assistantMessageID,
        error: { message },
      },
    },
  };
}

async function run() {
  // --- Case 1: child session + rule WITH fallback_model → fallback dispatched
  {
    const mock = makeMockClient("ses_parent_root"); // child has parentID
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    // "request exceeded model token limit" matches model-token-limit-exceeded
    // (fallback_model: "openai/gpt-5.5", max_retries: 0 → immediate fallback)
    await plugin.event(makeErrorEvent(childSessionID, "request exceeded model token limit"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      1,
      `Case 1 (child + fallback rule): expected 1 promptAsync call, got ${mock.promptAsyncCalls.length}`,
    );
    assert.ok(
      mock.promptAsyncCalls[0].body.model,
      "Case 1: expected fallback dispatch to carry a model field",
    );
    assert.strictEqual(
      mock.promptAsyncCalls[0].body.model.providerID,
      "openai",
      `Case 1: expected fallback provider "openai", got "${mock.promptAsyncCalls[0].body.model.providerID}"`,
    );
    assert.strictEqual(
      mock.promptAsyncCalls[0].body.model.modelID,
      "gpt-5.5",
      `Case 1: expected fallback model "gpt-5.5", got "${mock.promptAsyncCalls[0].body.model.modelID}"`,
    );
    console.log("PASS case 1: child session + fallback rule → fallback dispatched");
  }

  // --- Case 2: child session + rule WITHOUT fallback_model → skipped
  {
    const mock = makeMockClient("ses_parent_root"); // child has parentID
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    // "SSE read timed out" matches sse-read-timeout (no fallback_model)
    await plugin.event(makeErrorEvent(childSessionID, "SSE read timed out"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      0,
      `Case 2 (child + no-fallback rule): expected 0 promptAsync calls, got ${mock.promptAsyncCalls.length}`,
    );
    assert.strictEqual(
      mock.abortCalls.length,
      0,
      `Case 2: expected 0 abort calls, got ${mock.abortCalls.length}`,
    );
    console.log("PASS case 2: child session + no-fallback rule → skipped (preserved)");
  }

  // --- Case 3: root session + rule without fallback → retry dispatched (regression guard)
  {
    const mock = makeMockClient(undefined); // root session, no parentID
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    // sse-read-timeout: backoff_ms[0] = 1000ms → ~1s wait
    await plugin.event(makeErrorEvent(rootSessionID, "SSE read timed out"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      1,
      `Case 3 (root + any rule): expected 1 promptAsync call, got ${mock.promptAsyncCalls.length}`,
    );
    console.log("PASS case 3: root session retry path unchanged");
  }

  console.log("ALL PASS: provider-connect-retry child-session guard (3/3)");
}

run().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
