#!/usr/bin/env node
// Test: provider-connect-retry ignores provider/OpenCode retry telemetry.
//
// Scenario: GLM/Z.AI emits a session.status retry event with
// "Rate limit reached for requests". That event is retry progress telemetry,
// not a terminal failure. The plugin must not abort, promptAsync, inject a
// nudge, re-send the user's message, or fall back from that event alone.

import assert from "node:assert";
import { ProviderConnectRetryPlugin } from "../configs/opencode/provider-connect-retry.mjs";

const sessionID = "ses_test_provider_connect_retry_session_status";
const userMessageID = "msg_user_1";
const assistantMessageID = "msg_assist_1";

async function run() {
  const promptAsyncCalls = [];
  const abortCalls = [];

  const mockClient = {
    session: {
      get: async () => ({ data: { parentID: undefined } }),
      messages: async () => ({
        data: [
          {
            info: {
              role: "user",
              id: userMessageID,
              parts: [{ type: "text", text: "investigate the Paperclip system architecture" }],
            },
          },
          {
            info: {
              role: "assistant",
              id: assistantMessageID,
            },
          },
        ],
      }),
      abort: async (input) => {
        abortCalls.push(input);
      },
      promptAsync: async (input) => {
        promptAsyncCalls.push(input);
        return {};
      },
    },
  };

  const plugin = await ProviderConnectRetryPlugin({
    client: mockClient,
    directory: "/tmp",
  });

  await plugin.event({
    event: {
      type: "session.status",
      properties: {
        sessionID,
        providerID: "zai-coding-plan",
        modelID: "glm-5.2",
        status: {
          type: "retry",
          message: "Rate limit reached for requests",
          attempt: 1,
        },
      },
    },
  });

  // 1. session.status retry telemetry must not abort the turn.
  assert.strictEqual(
    abortCalls.length,
    0,
    `expected 0 abort calls, got ${abortCalls.length}`,
  );

  // 2. It must not inject a nudge, replay the user message, or fallback.
  assert.strictEqual(
    promptAsyncCalls.length,
    0,
    `expected 0 promptAsync calls, got ${promptAsyncCalls.length}`,
  );

  console.log("PASS: provider-connect-retry ignores session.status retry telemetry");
}

run().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
