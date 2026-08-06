#!/usr/bin/env node
// Test: provider-connect-retry child-session gate + unified agent-chain fallback.
//
// Background: A synchronous task() subagent runs in a child session (parentID
// set). Originally the plugin skipped ALL child sessions unconditionally, so
// fallback never dispatched and the subagent died. The first fix gated on a
// per-rule fallback_model field. The 2026-08-05 unification removed per-rule
// fallback_model entirely — fallback is now resolved from the failing
// session's agent fallback_models chain in oh-my-openagent.json (one source of
// truth, self-fallback-proof). This test validates the new gate.
//
// Cases:
//   1. Child session + agent WITH a usable fallback chain   → fallback dispatched from the agent chain
//   2. Child session + NO usable fallback chain (unknown agent/model) → skipped (recursion-storm protection)
//   3. Root session + any rule                               → retry dispatched (regression guard)
//
// The test reads the live configs at ~/.config/opencode/{retry-errors.json,
// oh-my-openagent.json} and derives expected values from them, so it resists
// chain drift on rebalances. It asserts structural properties (fallback
// provider ≠ failing provider; fallback ∈ agent's chain) rather than hardcoded
// model ids.

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
  // --- Case 1: child session + agent WITH usable fallback chain → fallback dispatched from chain
  {
    const mock = makeMockClient("ses_parent_root", {
      agent: "prometheus",
      providerID: prometheusPrimaryProvider,
      modelID: prometheusPrimaryModelID,
    });
    const plugin = await ProviderConnectRetryPlugin({ client: mock.client, directory: "/tmp" });
    // "request exceeded model token limit" matches model-token-limit-exceeded
    // (max_retries: 0 → immediate fallback, no retry loop)
    await plugin.event(makeErrorEvent(childSessionID, "request exceeded model token limit"));

    assert.strictEqual(
      mock.promptAsyncCalls.length,
      1,
      `Case 1 (child + agent chain): expected 1 promptAsync call, got ${mock.promptAsyncCalls.length}`,
    );
    assert.ok(
      mock.promptAsyncCalls[0].body.model,
      "Case 1: expected fallback dispatch to carry a model field",
    );
    const dispatched = mock.promptAsyncCalls[0].body.model;
    assert.notStrictEqual(
      dispatched.providerID,
      prometheusPrimaryProvider,
      `Case 1: fallback provider must differ from failing provider "${prometheusPrimaryProvider}" (no self-fallback), got "${dispatched.providerID}"`,
    );
    assert.ok(
      prometheus.fallback_models.includes(`${dispatched.providerID}/${dispatched.modelID}`),
      `Case 1: dispatched "${dispatched.providerID}/${dispatched.modelID}" must be in prometheus.fallback_models ${JSON.stringify(prometheus.fallback_models)}`,
    );
    assert.strictEqual(
      dispatched.providerID,
      expectedFallbackProvider,
      `Case 1: expected first eligible chain entry provider "${expectedFallbackProvider}", got "${dispatched.providerID}"`,
    );
    console.log(`PASS case 1: child + prometheus chain → fallback ${expectedFallbackProvider}/${expectedFallbackModelID} dispatched (failing=${prometheusPrimaryProvider})`);
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
