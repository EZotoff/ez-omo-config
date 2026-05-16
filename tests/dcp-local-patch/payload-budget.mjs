// tests/dcp-local-patch/payload-budget.mjs
// Regression harness for byte-budget DCP patches

const SOURCE_DIST_ROOT = "/home/ezotoff/omo-hub/projects/opencode-dynamic-context-pruning/dist/lib";
const INSTALLED_ROOT = "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib";

let DCP_ROOT = INSTALLED_ROOT;

function resolveDcpPath(subpath) {
  return `${DCP_ROOT}/${subpath}`;
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function pass(caseName) {
  console.log(`PASS ${caseName}`);
}

// ---------------------------------------------------------------------------
// Logger stub (sync methods are fine — byte-budget code does not await them)
// ---------------------------------------------------------------------------
function createLogger() {
  const warnings = [];
  const infos = [];
  return {
    warnings,
    infos,
    logger: {
      warn(msg, data) { warnings.push({ msg, data }); },
      info(msg, data) { infos.push({ msg, data }); },
      debug() {},
      error() {},
    },
  };
}

// ---------------------------------------------------------------------------
// Message builders (minimal subset that satisfies pruneByByteBudget)
// ---------------------------------------------------------------------------
const sessionID = "ses_payload_budget";

function textPart(messageID, id, text) {
  return { id, messageID, sessionID, type: "text", text };
}

function toolPartCompleted(messageID, callID, tool, output, input) {
  return {
    id: `${callID}-part`,
    messageID,
    sessionID,
    type: "tool",
    tool,
    callID,
    state: {
      status: "completed",
      input: input ?? { note: tool },
      output,
    },
  };
}

function toolPartError(messageID, callID, tool, error, input) {
  return {
    id: `${callID}-part`,
    messageID,
    sessionID,
    type: "tool",
    tool,
    callID,
    state: {
      status: "error",
      input,
      error,
    },
  };
}

function buildMessage(id, role, created, parts) {
  const info =
    role === "user"
      ? { id, role, sessionID, agent: "assistant", model: { providerID: "test", modelID: "test" }, time: { created } }
      : { id, role, sessionID, agent: "assistant", time: { created } };
  return { info, parts };
}

function assignRefs(state, messages) {
  let nextRef = 1;
  for (const message of messages) {
    const ref = `m${String(nextRef).padStart(4, "0")}`;
    state.messageIds.byRawId.set(message.info.id, ref);
    state.messageIds.byRef.set(ref, message.info.id);
    nextRef++;
  }
  state.messageIds.nextRef = nextRef;
}

// ---------------------------------------------------------------------------
// 1. below-budget-noop
// ---------------------------------------------------------------------------
async function runBelowBudgetNoop() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();
  const messages = [
    buildMessage("msg-1", "assistant", 1, [textPart("msg-1", "p1", "Small assistant message.")]),
    buildMessage("msg-2", "user", 2, [textPart("msg-2", "p2", "Small user message.")]),
  ];

  const startingBytes = measureMessagePayloadBytes(messages);
  const result = pruneByByteBudget(state, logger, messages, { maxPayloadBytes: startingBytes + 1000 });

  if (result.changed !== false) {
    fail(`below-budget-noop: expected changed=false, got ${result.changed}`);
  }
  if (result.endingBytes !== startingBytes) {
    fail(`below-budget-noop: expected endingBytes=${startingBytes}, got ${result.endingBytes}`);
  }
  if (result.failClosedReason !== null) {
    fail(`below-budget-noop: expected failClosedReason=null, got ${result.failClosedReason}`);
  }

  pass("below-budget-noop");
}

// ---------------------------------------------------------------------------
// 2. huge-tool-output-compacts
// ---------------------------------------------------------------------------
async function runHugeToolOutputCompacts() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes, BYTE_BUDGET_DEFAULTS } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();

  const hugeOutput = "line-payload ".repeat(150_000);
  const messages = [
    buildMessage("msg-old", "assistant", 1, [
      toolPartCompleted("msg-old", "call-old", "bash", hugeOutput, { command: "npm test" }),
    ]),
    buildMessage("msg-frontier", "user", 2, [textPart("msg-frontier", "pf", "Keep me.")]),
    buildMessage("msg-frontier-assistant", "assistant", 3, [textPart("msg-frontier-assistant", "pfa", "Ack.")]),
  ];

  assignRefs(state, messages);
  const startingBytes = measureMessagePayloadBytes(messages);

  // maxPayloadBytes > hardLimitBytes triggers clamping to safeClampTargetBytes (1_802_240)
  const result = pruneByByteBudget(state, logger, messages, { maxPayloadBytes: 3_000_000 });

  if (startingBytes <= BYTE_BUDGET_DEFAULTS.safeClampTargetBytes) {
    fail(`huge-tool-output-compacts: fixture too small (${startingBytes} <= ${BYTE_BUDGET_DEFAULTS.safeClampTargetBytes})`);
  }
  if (result.endingBytes > BYTE_BUDGET_DEFAULTS.safeClampTargetBytes) {
    fail(`huge-tool-output-compacts: endingBytes ${result.endingBytes} exceeds safeClampTargetBytes ${BYTE_BUDGET_DEFAULTS.safeClampTargetBytes}`);
  }
  if (!result.changed) {
    fail(`huge-tool-output-compacts: expected changed=true`);
  }

  const oldPart = messages.find((m) => m.info.id === "msg-old")?.parts[0];
  if (!oldPart || oldPart.type !== "tool") {
    fail(`huge-tool-output-compacts: old message tool part missing or wrong type`);
  }
  const outputText = String(oldPart.state.output);
  if (!outputText.includes("Byte budget compacted tool output")) {
    fail(`huge-tool-output-compacts: expected compaction marker in tool output, got: ${outputText.slice(0, 200)}`);
  }

  // Frontier must survive
  if (!messages.some((m) => m.info.id === "msg-frontier")) {
    fail(`huge-tool-output-compacts: frontier user message was removed`);
  }
  if (!messages.some((m) => m.info.id === "msg-frontier-assistant")) {
    fail(`huge-tool-output-compacts: frontier assistant message was removed`);
  }

  pass("huge-tool-output-compacts");
}

// ---------------------------------------------------------------------------
// 3. repeated-scaffold-oldest-first
// ---------------------------------------------------------------------------
async function runRepeatedScaffoldOldestFirst() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();

  const scaffoldText = `/review-work Follow the protocol exactly.\nPROVIDE EXACTLY ONE GOAL. `.repeat(40);
  const messages = [
    buildMessage("msg-scaffold-1", "assistant", 1, [textPart("msg-scaffold-1", "s1", scaffoldText)]),
    buildMessage("msg-scaffold-2", "assistant", 2, [textPart("msg-scaffold-2", "s2", scaffoldText)]),
    buildMessage("msg-scaffold-3", "assistant", 3, [textPart("msg-scaffold-3", "s3", scaffoldText)]),
    buildMessage("msg-frontier", "user", 4, [textPart("msg-frontier", "pf", "Keep me.")]),
  ];

  assignRefs(state, messages);
  const startingBytes = measureMessagePayloadBytes(messages);
  const result = pruneByByteBudget(state, logger, messages, { maxPayloadBytes: startingBytes - 500 });

  // The oldest scaffolds should be collapsed; the newest should stay intact
  const s1 = messages.find((m) => m.info.id === "msg-scaffold-1")?.parts[0];
  const s2 = messages.find((m) => m.info.id === "msg-scaffold-2")?.parts[0];
  const s3 = messages.find((m) => m.info.id === "msg-scaffold-3")?.parts[0];

  if (!s1 || s1.type !== "text" || !s1.text.includes("Older repeated scaffold omitted")) {
    fail(`repeated-scaffold-oldest-first: expected msg-scaffold-1 to be collapsed`);
  }
  if (!s2 || s2.type !== "text" || !s2.text.includes("Older repeated scaffold omitted")) {
    fail(`repeated-scaffold-oldest-first: expected msg-scaffold-2 to be collapsed`);
  }
  if (!s3 || s3.type !== "text" || s3.text.includes("Older repeated scaffold omitted")) {
    fail(`repeated-scaffold-oldest-first: expected msg-scaffold-3 to stay intact`);
  }

  pass("repeated-scaffold-oldest-first");
}

// ---------------------------------------------------------------------------
// 4. repeated-provider-errors-oldest-first
// ---------------------------------------------------------------------------
async function runRepeatedProviderErrorsOldestFirst() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();

  const errorText = "ERROR timeout while fetching https://example.com/api from /tmp/project/huge.log";
  const input = { filePath: "/tmp/project/huge.log", payload: "E".repeat(10_000) };

  const messages = [
    buildMessage("msg-error-1", "assistant", 1, [
      toolPartError("msg-error-1", "call-error-1", "bash", errorText, input),
    ]),
    buildMessage("msg-error-2", "assistant", 2, [
      toolPartError("msg-error-2", "call-error-2", "bash", errorText, input),
    ]),
    buildMessage("msg-error-3", "assistant", 3, [
      toolPartError("msg-error-3", "call-error-3", "bash", errorText, input),
    ]),
    buildMessage("msg-frontier", "user", 4, [textPart("msg-frontier", "pf", "Keep me.")]),
  ];

  assignRefs(state, messages);
  const startingBytes = measureMessagePayloadBytes(messages);
  const result = pruneByByteBudget(state, logger, messages, { maxPayloadBytes: startingBytes - 500 });

  const e1 = messages.find((m) => m.info.id === "msg-error-1")?.parts[0];
  const e2 = messages.find((m) => m.info.id === "msg-error-2")?.parts[0];
  const e3 = messages.find((m) => m.info.id === "msg-error-3")?.parts[0];

  if (!e1 || e1.type !== "tool" || !String(e1.state.error).includes("Repeated error loop omitted")) {
    fail(`repeated-provider-errors-oldest-first: expected msg-error-1 to be collapsed`);
  }
  if (!e2 || e2.type !== "tool" || !String(e2.state.error).includes("Repeated error loop omitted")) {
    fail(`repeated-provider-errors-oldest-first: expected msg-error-2 to be collapsed`);
  }
  // The newest error keeps a preview (not "Repeated error loop omitted")
  if (!e3 || e3.type !== "tool" || String(e3.state.error).includes("Repeated error loop omitted")) {
    fail(`repeated-provider-errors-oldest-first: expected msg-error-3 to keep a preview`);
  }

  pass("repeated-provider-errors-oldest-first");
}

// ---------------------------------------------------------------------------
// 5. latest-todo-preserved
// ---------------------------------------------------------------------------
async function runLatestTodoPreserved() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();

  const todoSnapshot = JSON.stringify(
    { todos: Array.from({ length: 30 }, (_, i) => ({ content: `todo-${i}`, status: i === 29 ? "in_progress" : "completed" })) },
    null,
    2,
  );

  const messages = [
    buildMessage("msg-todo-1", "assistant", 1, [
      toolPartCompleted("msg-todo-1", "call-todo-1", "todowrite", todoSnapshot),
    ]),
    buildMessage("msg-todo-2", "assistant", 2, [
      toolPartCompleted("msg-todo-2", "call-todo-2", "todowrite", todoSnapshot),
    ]),
    buildMessage("msg-todo-3", "assistant", 3, [
      toolPartCompleted("msg-todo-3", "call-todo-3", "todowrite", todoSnapshot),
    ]),
    buildMessage("msg-frontier", "user", 4, [textPart("msg-frontier", "pf", "Keep me.")]),
  ];

  assignRefs(state, messages);
  const startingBytes = measureMessagePayloadBytes(messages);
  const result = pruneByByteBudget(state, logger, messages, { maxPayloadBytes: startingBytes - 500 });

  const t1 = messages.find((m) => m.info.id === "msg-todo-1")?.parts[0];
  const t2 = messages.find((m) => m.info.id === "msg-todo-2")?.parts[0];
  const t3 = messages.find((m) => m.info.id === "msg-todo-3")?.parts[0];

  if (!t1 || t1.type !== "tool" || !String(t1.state.output).includes("Older todo snapshot omitted")) {
    fail(`latest-todo-preserved: expected msg-todo-1 to be collapsed`);
  }
  if (!t2 || t2.type !== "tool" || !String(t2.state.output).includes("Older todo snapshot omitted")) {
    fail(`latest-todo-preserved: expected msg-todo-2 to be collapsed`);
  }
  if (!t3 || t3.type !== "tool" || String(t3.state.output).includes("Older todo snapshot omitted")) {
    fail(`latest-todo-preserved: expected msg-todo-3 (latest) to stay intact`);
  }

  pass("latest-todo-preserved");
}

// ---------------------------------------------------------------------------
// 6. compressed-placeholder-survives
// ---------------------------------------------------------------------------
async function runCompressedPlaceholderSurvives() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();

  const bulkText = "filler ".repeat(20_000);
  const messages = [
    buildMessage("msg-placeholder", "assistant", 1, [
      textPart("msg-placeholder", "pp", "[Compressed conversation section]"),
    ]),
    buildMessage("msg-bulk-1", "assistant", 2, [textPart("msg-bulk-1", "b1", bulkText)]),
    buildMessage("msg-bulk-2", "assistant", 3, [textPart("msg-bulk-2", "b2", bulkText)]),
    buildMessage("msg-frontier", "user", 4, [textPart("msg-frontier", "pf", "Keep me.")]),
  ];

  assignRefs(state, messages);
  const startingBytes = measureMessagePayloadBytes(messages);
  const result = pruneByByteBudget(state, logger, messages, { maxPayloadBytes: startingBytes - 500 });

  // The compressed-placeholder message must NOT be removed
  if (!messages.some((m) => m.info.id === "msg-placeholder")) {
    fail(`compressed-placeholder-survives: msg-placeholder was removed`);
  }

  // The bulk messages should have been removed or compacted
  const endingBytes = measureMessagePayloadBytes(messages);
  if (endingBytes >= startingBytes) {
    fail(`compressed-placeholder-survives: expected payload to shrink, got ${endingBytes} >= ${startingBytes}`);
  }

  pass("compressed-placeholder-survives");
}

// ---------------------------------------------------------------------------
// 7. multibyte-cjk-emoji
// ---------------------------------------------------------------------------
async function runMultibyteCjkEmoji() {
  const { measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const cjkText = "\u4e2d\u6587\u6d4b\u8bd5\u6587\u672c"; // 中文测试文本
  const emojiText = "\ud83d\ude80\ud83c\udf89\ud83d\udc4d"; // 🚀🎉👍
  const mixed = `${cjkText} ${emojiText}`;

  const messages = [
    buildMessage("msg-cjk", "assistant", 1, [textPart("msg-cjk", "pc", mixed)]),
  ];

  const measured = measureMessagePayloadBytes(messages);
  const expected = Buffer.byteLength(JSON.stringify(messages), "utf8");

  if (measured !== expected) {
    fail(`multibyte-cjk-emoji: measured ${measured} !== expected ${expected} (UTF-8 bytes)`);
  }

  // CJK chars are 3 bytes each in UTF-8, emojis are 4 bytes each
  const rawBytes = Buffer.byteLength(mixed, "utf8");
  if (rawBytes !== 31) {
    fail(`multibyte-cjk-emoji: raw byte length sanity check failed (${rawBytes})`);
  }

  pass("multibyte-cjk-emoji");
}

// ---------------------------------------------------------------------------
// 8. exact-threshold-and-one-byte-over
// ---------------------------------------------------------------------------
async function runExactThresholdAndOneByteOver() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger } = createLogger();

  // Build a payload where we can control the exact byte count
  let text = "x";
  let messages = [buildMessage("msg-1", "assistant", 1, [textPart("msg-1", "p1", text)])];
  let baseBytes = measureMessagePayloadBytes(messages);

  // Grow text until we have a stable baseline
  while (baseBytes < 500) {
    text += "x";
    messages = [buildMessage("msg-1", "assistant", 1, [textPart("msg-1", "p1", text)])];
    baseBytes = measureMessagePayloadBytes(messages);
  }

  // exact-threshold: maxPayloadBytes == baseBytes → no-op
  const resultExact = pruneByByteBudget(state, logger, JSON.parse(JSON.stringify(messages)), {
    maxPayloadBytes: baseBytes,
  });
  if (resultExact.changed !== false) {
    fail(`exact-threshold: expected changed=false at exact threshold (${baseBytes}), got changed=${resultExact.changed}`);
  }
  if (resultExact.endingBytes !== baseBytes) {
    fail(`exact-threshold: expected endingBytes=${baseBytes}, got ${resultExact.endingBytes}`);
  }

  // one-byte-over: old assistant + small frontier user message, total = maxPayloadBytes + 1
  // The old assistant should be removed since it is non-protected and before the frontier.
  const oldText = text;
  const messagesOver = [
    buildMessage("msg-old", "assistant", 1, [textPart("msg-old", "po", oldText)]),
    buildMessage("msg-frontier", "user", 2, [textPart("msg-frontier", "pf", "f")]),
  ];
  const overBytes = measureMessagePayloadBytes(messagesOver);
  const targetBudget = overBytes - 1;

  const resultOver = pruneByByteBudget(state, logger, messagesOver, {
    maxPayloadBytes: targetBudget,
  });

  if (resultOver.changed !== true) {
    fail(`one-byte-over: expected changed=true, got ${resultOver.changed}`);
  }
  if (resultOver.endingBytes >= overBytes) {
    fail(`one-byte-over: expected endingBytes < ${overBytes}, got ${resultOver.endingBytes}`);
  }
  // The old assistant message should have been removed
  if (messagesOver.some((m) => m.info.id === "msg-old")) {
    fail(`one-byte-over: expected msg-old to be removed`);
  }
  // The frontier user message must survive
  if (!messagesOver.some((m) => m.info.id === "msg-frontier")) {
    fail(`one-byte-over: expected msg-frontier to survive`);
  }

  pass("exact-threshold-and-one-byte-over");
}

// ---------------------------------------------------------------------------
// 9. protected-frontier-over-limit
// ---------------------------------------------------------------------------
async function runProtectedFrontierOverLimit() {
  const { createSessionState } = await import(resolveDcpPath("state/state.js"));
  const { pruneByByteBudget, measureMessagePayloadBytes, BYTE_BUDGET_DEFAULTS } = await import(resolveDcpPath("messages/byte-budget.js"));

  const state = createSessionState();
  const { logger, warnings } = createLogger();

  const largeFrontierText = "frontier ".repeat(260_000);
  const messages = [
    buildMessage("msg-frontier-user-only", "user", 1, [
      textPart("msg-frontier-user-only", "frontier-only", largeFrontierText),
    ]),
  ];

  const beforeBytes = measureMessagePayloadBytes(messages);
  const result = pruneByByteBudget(state, logger, messages, {
    maxPayloadBytes: BYTE_BUDGET_DEFAULTS.safeClampTargetBytes,
  });

  if (result.startingBytes !== beforeBytes) {
    fail(`protected-frontier-over-limit: startingBytes mismatch`);
  }
  if (result.endingBytes !== beforeBytes) {
    fail(`protected-frontier-over-limit: endingBytes should equal startingBytes when fail-closed`);
  }
  if (!result.diagnostics.includes("protected frontier exceeds maxPayloadBytes")) {
    fail(`protected-frontier-over-limit: expected diagnostic "protected frontier exceeds maxPayloadBytes"`);
  }
  if (!warnings.some((w) => w.msg === "protected frontier exceeds maxPayloadBytes")) {
    fail(`protected-frontier-over-limit: expected logger warning`);
  }

  pass("protected-frontier-over-limit");
}

// ---------------------------------------------------------------------------
// Main dispatcher
// ---------------------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);

  let mode = "installed";
  let testCase = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--mode" && i + 1 < args.length) {
      mode = args[i + 1];
      i++;
    } else if (args[i] === "--case" && i + 1 < args.length) {
      testCase = args[i + 1];
      i++;
    } else if (!args[i].startsWith("-") && !testCase) {
      testCase = args[i];
    }
  }

  if (mode === "source-dist") {
    DCP_ROOT = SOURCE_DIST_ROOT;
  } else {
    DCP_ROOT = INSTALLED_ROOT;
  }

  if (!testCase) {
    console.error("Usage: npx tsx payload-budget.mjs [--mode source-dist|installed] [--case] <case-name>");
    console.error(
      "Cases: below-budget-noop, huge-tool-output-compacts, repeated-scaffold-oldest-first, " +
      "repeated-provider-errors-oldest-first, latest-todo-preserved, compressed-placeholder-survives, " +
      "multibyte-cjk-emoji, exact-threshold-and-one-byte-over, protected-frontier-over-limit"
    );
    process.exit(1);
  }

  switch (testCase) {
    case "below-budget-noop":
      await runBelowBudgetNoop();
      break;
    case "huge-tool-output-compacts":
      await runHugeToolOutputCompacts();
      break;
    case "repeated-scaffold-oldest-first":
      await runRepeatedScaffoldOldestFirst();
      break;
    case "repeated-provider-errors-oldest-first":
      await runRepeatedProviderErrorsOldestFirst();
      break;
    case "latest-todo-preserved":
      await runLatestTodoPreserved();
      break;
    case "compressed-placeholder-survives":
      await runCompressedPlaceholderSurvives();
      break;
    case "multibyte-cjk-emoji":
      await runMultibyteCjkEmoji();
      break;
    case "exact-threshold-and-one-byte-over":
      await runExactThresholdAndOneByteOver();
      break;
    case "protected-frontier-over-limit":
      await runProtectedFrontierOverLimit();
      break;
    default:
      console.error(`Unknown scenario: ${testCase}`);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(`UNEXPECTED ERROR: ${err.message}`);
  console.error(err.stack);
  process.exit(1);
});
