#!/usr/bin/env node
// Test: provider-connect-retry retries on the SAME Z.AI model via nudge before falling back.
//
// Scenario: GLM/Z.AI emits a session.status retry event with
// "Rate limit reached for requests". The plugin should retry on the same
// zai-coding-plan/glm-5.2 model using a minimal nudge prompt, NOT immediately
// fall back to openai/gpt-5.5 and NOT re-inject the original user message.

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

  // 1. The plugin should abort the failed turn before retrying.
  assert.strictEqual(
    abortCalls.length,
    1,
    `expected 1 abort call, got ${abortCalls.length}`,
  );

  // 2. Exactly one promptAsync call (the retry on the same model).
  assert.strictEqual(
    promptAsyncCalls.length,
    1,
    `expected exactly 1 retry dispatch, got ${promptAsyncCalls.length}`,
  );

  const retryCall = promptAsyncCalls[0];

  // 3. The retry must stay on the SAME Z.AI model, not fall back to openai.
  assert.strictEqual(
    retryCall.body.model?.providerID,
    "zai-coding-plan",
    `expected retry on zai-coding-plan, got provider ${retryCall.body.model?.providerID}`,
  );
  assert.strictEqual(
    retryCall.body.model?.modelID,
    "glm-5.2",
    `expected retry on glm-5.2, got model ${retryCall.body.model?.modelID}`,
  );

  // 4. The retry must send a nudge, NOT the original user message.
  //    This prevents the TUI duplication bug where the user's message
  //    gets appended to the existing message bubble.
  assert.ok(
    Array.isArray(retryCall.body.parts) && retryCall.body.parts.length > 0,
    "retry must dispatch with parts",
  );
  const retryText = retryCall.body.parts.map((p) => p.text || "").join("");
  assert.ok(
    retryText.includes("Continue"),
    `expected nudge prompt containing "Continue", got "${retryText}"`,
  );
  assert.ok(
    !retryText.includes("investigate the Paperclip"),
    "retry must NOT re-inject the original user message text",
  );

  // 5. The retry must NOT pass the original user messageID (causes TUI duplication).
  assert.strictEqual(
    retryCall.body.messageID,
    undefined,
    "retry must not pass messageID — it causes TUI message duplication",
  );

  // 6. No fallback calls to openai/gpt-5.5 on the first rate-limit hit.
  const fallbackCalls = promptAsyncCalls.filter(
    (call) =>
      call?.body?.model?.providerID === "openai" &&
      call?.body?.model?.modelID === "gpt-5.5",
  );
  assert.strictEqual(
    fallbackCalls.length,
    0,
    `expected 0 fallback dispatches on first attempt, got ${fallbackCalls.length}`,
  );

  console.log("PASS: provider-connect-retry retries on same Z.AI model via nudge before fallback");
}

run().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
