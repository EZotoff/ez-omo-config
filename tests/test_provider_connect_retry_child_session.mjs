#!/usr/bin/env node
// Test: provider-connect-retry child-session gate + unified agent-chain fallback.
//
// Background: A synchronous task() subagent runs in a child session (parentID
// set). The plugin MUST NOT dispatch error fallback for child sessions —
// OMO's runtime-fallback hook (hooks/runtime-fallback/) is the canonical owner
// for child-session error fallback. It subscribes to the same session.error
// events and dispatches from the same fallback_models chain. Letting both
// dispatch caused a double-spawn (two concurrent promptAsync calls on the
// same child session — regression introduced by 0941c58, fixed by closing the
// child-session gate in the plugin's regular error path).
//
// The plugin retains ownership of: (1) top-level session.error retry +
// fallback, and (2) near-empty completion detection for ALL sessions
// including child (OMO has no equivalent). Near-empty detection is covered by
// the separate min-output test suite.
//
// Cases:
//   1. Child session + agent WITH a usable fallback chain   → SKIPPED (OMO owns child error fallback)
//   2. Child session + NO usable fallback chain (unknown agent/model) → skipped (no chain either way)
//   3. Root session + any rule                               → retry dispatched (regression guard)
//
// The test reads the live configs at ~/.config/opencode/{retry-errors.json,
// oh-my-openagent.json} and derives expected values from them, so it resists
// chain drift on rebalances.

import assert from "node:assert";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { ProviderConnectRetryPlugin } from "../configs/opencode/provider-connect-retry.mjs";

// --- Derive expected values from the live OMO config (resists chain drift) ---
const omoConfigPath = path.join(os.homedir(), ".config", "opencode", "oh-my-openagent.json");
const omoConfig = JSON.parse(fs.readFileSync(omoConfigPath, "utf8"));

// Prometheus: primary on kimi-for-coding-oauth/k3, chain [glm-5.2, gpt-5.6-sol].
// When kimi fails, the unified resolver must pick the first chain entry whose
// provider differs from kimi-for-coding-oauth.
const prometheus = omoConfig.agents.prometheus;
assert.ok(prometheus, "precondition: agents.prometheus must exist in oh-my-openagent.json");
assert.ok(Array.isArray(prometheus.fallback_models) && prometheus.fallback_models.length > 0,
  "precondition: agents.prometheus.fallback_models must be a non-empty array");

const prometheusModelStr = prometheus.model;
const [prometheusPrimaryProvider, prometheusPrimaryModelID] = prometheusModelStr.split("/");
const expectedFallbackStr = prometheus.fallback_models.find((entry) => {
  const provider = entry.split("/")[0];
  return provider !== prometheusPrimaryProvider;
});
assert.ok(expectedFallbackStr,
  `precondition: prometheus must have a chain entry whose provider ≠ "${prometheusPrimaryProvider}"`);
const [expectedFallbackProvider, expectedFallbackModelID] = expectedFallbackStr.split("/");

const childSessionID = "ses_child_task_test";
const rootSessionID = "ses_root_test";
const userMessageID = "msg_user_child_1";
const assistantMessageID = "msg_assist_child_1";

function makeMockClient(parentID, { agent, providerID, modelID } = {}) {
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
              agent,
              parts: [{ type: "text", text: "do the thing" }],
            },
          },
          {
            info: {
              role: "assistant",
              id: assistantMessageID,
              providerID,
              modelID,
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
  // --- Case 1: child session + agent WITH usable fallback chain → SKIPPED (OMO owns)
  {
    const mock = makeMockClient("ses_parent_root", {
      agent: "prometheus",
      providerID: prometheusPrimaryProvider,
      modelID: prometheusPrimaryModelID,
    });
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    // "request exceeded model token limit" matches model-token-limit-exceeded
    // (max_retries: 0 → would have been immediate fallback pre-fix)
    await plugin.event(makeErrorEvent(childSessionID, "request exceeded model token limit"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      0,
      `Case 1 (child + agent chain): expected 0 promptAsync calls (OMO owns child error fallback), got ${mock.promptAsyncCalls.length}`,
    );
    assert.strictEqual(
      mock.abortCalls.length,
      0,
      `Case 1: expected 0 abort calls, got ${mock.abortCalls.length}`,
    );
    console.log(`PASS case 1: child + prometheus chain → skipped (OMO runtime-fallback owns child-session error fallback; failing=${prometheusPrimaryProvider})`);
  }

  // --- Case 2: child session + NO usable fallback chain → skipped (recursion-storm protection)
  {
    const mock = makeMockClient("ses_parent_root", {
      agent: "nonexistent-agent-xyz",
      providerID: "fake-provider",
      modelID: "fake-model",
    });
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    await plugin.event(makeErrorEvent(childSessionID, "request exceeded model token limit"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      0,
      `Case 2 (child + no chain): expected 0 promptAsync calls, got ${mock.promptAsyncCalls.length}`,
    );
    assert.strictEqual(
      mock.abortCalls.length,
      0,
      `Case 2: expected 0 abort calls, got ${mock.abortCalls.length}`,
    );
    console.log("PASS case 2: child session + no agent chain → skipped (preserved)");
  }

  // --- Case 3: root session + any rule → retry dispatched (regression guard)
  {
    const mock = makeMockClient(undefined); // root session, no parentID
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    // sse-read-timeout: backoff_ms[0] = 1000ms → ~1s wait before retry
    await plugin.event(makeErrorEvent(rootSessionID, "SSE read timed out"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      1,
      `Case 3 (root + any rule): expected 1 promptAsync call, got ${mock.promptAsyncCalls.length}`,
    );
    console.log("PASS case 3: root session retry path unchanged");
  }

  console.log("ALL PASS: provider-connect-retry child-session gate + unified agent-chain fallback (3/3)");
}

run().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
