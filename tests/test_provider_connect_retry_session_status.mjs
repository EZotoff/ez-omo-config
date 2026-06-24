#!/usr/bin/env node
// Test: provider-connect-retry handles session.status retry signals and falls back.
//
// Scenario: GLM/Z.AI emits a session.status retry event with
// "Rate limit reached for requests". The plugin should immediately dispatch
// the large-context fallback model (openai/gpt-5.5), without retrying the same
// rate-limited GLM request.

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
              parts: [{ type: "text", text: "continue the task" }],
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

  assert.strictEqual(
    abortCalls.length,
    1,
    `expected 1 abort call, got ${abortCalls.length}`,
  );

  const fallbackCalls = promptAsyncCalls.filter(
    (call) =>
      call?.body?.model?.providerID === "openai" &&
      call?.body?.model?.modelID === "gpt-5.5",
  );

  assert.strictEqual(
    fallbackCalls.length,
    1,
    `expected exactly 1 fallback dispatch to openai/gpt-5.5, got ${fallbackCalls.length}`,
  );

  const fallbackCall = fallbackCalls[0];
  assert.strictEqual(fallbackCall.path.id, sessionID);
  assert.strictEqual(fallbackCall.body.messageID, userMessageID);
  assert.deepStrictEqual(fallbackCall.body.parts, [
    { type: "text", text: "continue the task" },
  ]);

  assert.strictEqual(
    promptAsyncCalls.length,
    1,
    `expected no same-model retry calls, got ${promptAsyncCalls.length} promptAsync calls`,
  );

  console.log("PASS: provider-connect-retry handles session.status rate-limit fallback");
}

run().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
