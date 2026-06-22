// tests/dcp-local-patch/bounded-range.mjs
// Regression harness for bounded-range DCP patches.
// v3.1.13+ uses tsup bundling (single dist/index.js), so functional tests
// import TypeScript source directly via tsx. Marker checks in the shell
// scripts verify patch presence in the installed bundle.

import { readFileSync } from "node:fs";

const DCP_SRC_ROOT = "/home/ezotoff/opencode-dynamic-context-pruning-v3.1.13";
const DCP_CONFIG_PATH = "/home/ezotoff/ez-omo-config/configs/opencode/dcp.jsonc";
const BOUNDED_TRUNCATION_MARKER = "Older archived detail omitted.";

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function pass(caseName) {
  console.log(`PASS ${caseName}`);
}

// ---------------------------------------------------------------------------
// 1. monotonic-summary-bound
// ---------------------------------------------------------------------------
async function runMonotonicSummaryBound() {
  const { normalizeBoundedRangeSummary } = await import(
    `${DCP_SRC_ROOT}/lib/compress/range-utils.ts`
  );
  const { countTokens } = await import(`${DCP_SRC_ROOT}/lib/token-utils.ts`);

  // Build a long summary that exceeds 1200 tokens and contains placeholders
  const longSummary =
    "This is a deliberately long summary used for testing token budget enforcement. ".repeat(300) +
    " (b1) {block_2} ";

  const result = normalizeBoundedRangeSummary(longSummary, 1200);

  const tokens = countTokens(result);
  if (tokens > 1200) {
    fail(`monotonic-summary-bound: token count ${tokens} exceeds budget 1200`);
  }

  if (/\(b\d+\)|\{block_\d+\}/.test(result)) {
    fail(`monotonic-summary-bound: result still contains block placeholders`);
  }

  pass("monotonic-summary-bound");
}

// ---------------------------------------------------------------------------
// 2. archived-raw-stays-out-of-prompt
// ---------------------------------------------------------------------------
async function runArchivedRawStaysOutOfPrompt() {
  // filterCompressedRanges is not exported directly; exercise it via prune()
  const { prune } = await import(`${DCP_SRC_ROOT}/lib/messages/prune.ts`);

  const logger = {
    warn: () => {},
    info: () => {},
    debug: () => {},
  };

  const config = {
    compress: {
      mode: "summary",
    },
  };

  const state = {
    prune: {
      messages: {
        byMessageId: new Map([
          ["msg-archived", { activeBlockIds: [], archivedBlockIds: [1] }],
          ["msg-normal",   { activeBlockIds: [], archivedBlockIds: [] }],
        ]),
        activeByAnchorMessageId: new Map(),
        blocksById: new Map(),
      },
      tools: new Set(),
    },
  };

  const messages = [
    { info: { id: "msg-archived" }, parts: [] },
    { info: { id: "msg-normal" },   parts: [] },
  ];

  prune(state, logger, config, messages);

  const remainingIds = messages.map((m) => m.info.id);
  if (remainingIds.includes("msg-archived")) {
    fail(`archived-raw-stays-out-of-prompt: msg-archived was not filtered out`);
  }
  if (!remainingIds.includes("msg-normal")) {
    fail(`archived-raw-stays-out-of-prompt: msg-normal was unexpectedly removed`);
  }

  pass("archived-raw-stays-out-of-prompt");
}

// ---------------------------------------------------------------------------
// 3. persisted-frontier-state
// ---------------------------------------------------------------------------
async function runPersistedFrontierState() {
  const { syncCompressionBlocks } = await import(`${DCP_SRC_ROOT}/lib/messages/sync.ts`);

  const logger = {
    warn: () => {},
    info: () => {},
    debug: () => {},
  };

  const state = {
    prune: {
      messages: {
        blocksById: new Map([
          [
            1,
            {
              blockId: 1,
              createdAt: 1000,
              active: true,
              archiveRawMessages: true,
              anchorMessageId: "msg-anchor",
              compressMessageId: "msg-compress",
              consumedBlockIds: [],
            },
          ],
        ]),
        byMessageId: new Map([
          ["msg-1", { allBlockIds: [1], activeBlockIds: [], archivedBlockIds: [] }],
        ]),
        activeBlockIds: new Set(),
        activeByAnchorMessageId: new Map(),
      },
    },
  };

  const messages = [{ info: { id: "msg-anchor" } }];

  syncCompressionBlocks(state, logger, messages);

  const entry = state.prune.messages.byMessageId.get("msg-1");
  if (!entry) {
    fail(`persisted-frontier-state: byMessageId entry for msg-1 missing after sync`);
  }
  if (!entry.archivedBlockIds.includes(1)) {
    fail(
      `persisted-frontier-state: expected archivedBlockIds to contain 1, got ${JSON.stringify(
        entry.archivedBlockIds
      )}`
    );
  }
  if (!entry.activeBlockIds.includes(1)) {
    fail(
      `persisted-frontier-state: expected activeBlockIds to contain 1, got ${JSON.stringify(
        entry.activeBlockIds
      )}`
    );
  }

  const block = state.prune.messages.blocksById.get(1);
  if (!block || block.active !== true) {
    fail(`persisted-frontier-state: bounded block is not active after sync`);
  }

  pass("persisted-frontier-state");
}

// ---------------------------------------------------------------------------
// 4. decompress-archived-rejected
// ---------------------------------------------------------------------------
async function runDecompressArchivedRejected() {
  const decompressPath = `${DCP_SRC_ROOT}/lib/commands/decompress.ts`;
  const source = readFileSync(decompressPath, "utf-8");

  const expectedGuardSuffix =
    "uses bounded archival retention and cannot be decompressed to raw history.";
  if (!source.includes(expectedGuardSuffix) || !source.includes("target.displayId")) {
    fail(`decompress-archived-rejected: guard string not found in decompress.ts`);
  }

  pass("decompress-archived-rejected");
}

// ---------------------------------------------------------------------------
// 5. bounded-runtime-proof-metadata
// ---------------------------------------------------------------------------
async function runBoundedRuntimeProofMetadata() {
  const { parse } = await import(
    "/home/ezotoff/.config/opencode/node_modules/jsonc-parser/lib/esm/main.js"
  );
  const { normalizeBoundedRangeSummary } = await import(
    `${DCP_SRC_ROOT}/lib/compress/range-utils.ts`
  );
  const {
    allocateBlockId,
    allocateRunId,
    applyCompressionState,
    wrapCompressedSummary,
  } = await import(`${DCP_SRC_ROOT}/lib/compress/state.ts`);
  const { syncCompressionBlocks } = await import(`${DCP_SRC_ROOT}/lib/messages/sync.ts`);
  const { createPruneMessagesState } = await import(`${DCP_SRC_ROOT}/lib/state/utils.ts`);
  const { countTokens } = await import(`${DCP_SRC_ROOT}/lib/token-utils.ts`);

  const dcpConfig = parse(readFileSync(DCP_CONFIG_PATH, "utf-8"));
  const compressConfig = dcpConfig?.compress;

  if (!compressConfig || typeof compressConfig !== "object") {
    fail(`bounded-runtime-proof-metadata: failed to load compress config from dcp.jsonc`);
  }

  if (compressConfig.mode !== "range") {
    fail(
      `bounded-runtime-proof-metadata: expected compress.mode=range, got ${JSON.stringify(
        compressConfig.mode
      )}`
    );
  }

  if (compressConfig.retentionMode !== "bounded") {
    fail(
      `bounded-runtime-proof-metadata: expected retentionMode=bounded, got ${JSON.stringify(
        compressConfig.retentionMode
      )}`
    );
  }

  if (
    typeof compressConfig.maxArchivedSummaryTokens !== "number" ||
    !Number.isFinite(compressConfig.maxArchivedSummaryTokens) ||
    compressConfig.maxArchivedSummaryTokens < 1
  ) {
    fail(
      `bounded-runtime-proof-metadata: invalid maxArchivedSummaryTokens ${JSON.stringify(
        compressConfig.maxArchivedSummaryTokens
      )}`
    );
  }

  const maxArchivedSummaryTokens = compressConfig.maxArchivedSummaryTokens;
  const messageIds = ["msg-1", "msg-2", "msg-3", "msg-4", "msg-5"];

  const state = {
    prune: {
      messages: createPruneMessagesState(),
    },
    stats: {
      pruneTokenCounter: 0,
      totalPruneTokens: 0,
    },
  };

  const messageTokenById = new Map(
    messageIds.map((messageId, index) => [messageId, 60 + index * 5])
  );
  const selection = {
    messageIds,
    messageTokenById,
    toolIds: [],
  };

  const longSummary = `${"Bounded runtime proof metadata should keep archive summaries within the configured token budget while preserving key context for future reasoning. ".repeat(
    600
  )} (b1) {block_2} `;

  const normalizedSummary = normalizeBoundedRangeSummary(
    longSummary,
    maxArchivedSummaryTokens
  );
  const normalizedSummaryTokenCount = countTokens(normalizedSummary);
  const truncationOccurred = normalizedSummary.includes(BOUNDED_TRUNCATION_MARKER);

  if (!truncationOccurred) {
    fail(`bounded-runtime-proof-metadata: expected summary truncation marker`);
  }
  if (normalizedSummaryTokenCount > maxArchivedSummaryTokens) {
    fail(
      `bounded-runtime-proof-metadata: normalized summary token count ${normalizedSummaryTokenCount} exceeds budget ${maxArchivedSummaryTokens}`
    );
  }

  const blockId = allocateBlockId(state);
  const runId = allocateRunId(state);
  const wrappedSummary = wrapCompressedSummary(blockId, normalizedSummary);

  applyCompressionState(
    state,
    {
      topic: "bounded-runtime-proof",
      batchTopic: "bounded-runtime-proof",
      startId: "m0001",
      endId: "m0005",
      mode: "range",
      runId,
      compressMessageId: "msg-compress-proof",
      compressCallId: "call-runtime-proof",
      summaryTokens: countTokens(wrappedSummary),
      retentionMode: compressConfig.retentionMode,
    },
    selection,
    messageIds[0],
    blockId,
    wrappedSummary,
    []
  );

  const logger = {
    warn: () => {},
    info: () => {},
    debug: () => {},
  };
  const messages = messageIds.map((id) => ({ info: { id } }));
  syncCompressionBlocks(state, logger, messages);

  const block = state.prune.messages.blocksById.get(blockId);
  if (!block) {
    fail(`bounded-runtime-proof-metadata: missing archived block ${blockId}`);
  }

  const archivedMessageCoverage = [];
  for (const [messageId, entry] of state.prune.messages.byMessageId.entries()) {
    if (entry.archivedBlockIds?.includes(blockId)) {
      archivedMessageCoverage.push(messageId);
    }
  }

  const proof = {
    retentionMode: block.retentionMode,
    archiveRawMessages: block.archiveRawMessages,
    maxArchivedSummaryTokens,
    archivedBlockId: block.blockId,
    rawMessageCoverageCount: block.effectiveMessageIds.length,
    rawMessageCoverage: block.effectiveMessageIds,
    archivedMessageCoverageCount: archivedMessageCoverage.length,
    normalizedSummaryTokenCount,
    truncationOccurred,
  };

  if (proof.retentionMode !== "bounded") {
    fail(
      `bounded-runtime-proof-metadata: expected block retentionMode=bounded, got ${JSON.stringify(
        proof.retentionMode
      )}`
    );
  }
  if (proof.archiveRawMessages !== true) {
    fail(`bounded-runtime-proof-metadata: expected archiveRawMessages=true`);
  }
  if (!Number.isInteger(proof.archivedBlockId) || proof.archivedBlockId < 1) {
    fail(
      `bounded-runtime-proof-metadata: invalid archived block id ${JSON.stringify(
        proof.archivedBlockId
      )}`
    );
  }
  if (proof.rawMessageCoverageCount !== messageIds.length) {
    fail(
      `bounded-runtime-proof-metadata: expected raw coverage ${messageIds.length}, got ${proof.rawMessageCoverageCount}`
    );
  }
  if (proof.archivedMessageCoverageCount !== messageIds.length) {
    fail(
      `bounded-runtime-proof-metadata: expected archived coverage ${messageIds.length}, got ${proof.archivedMessageCoverageCount}`
    );
  }
  if (proof.normalizedSummaryTokenCount > proof.maxArchivedSummaryTokens) {
    fail(
      `bounded-runtime-proof-metadata: normalized summary token count ${proof.normalizedSummaryTokenCount} exceeds maxArchivedSummaryTokens ${proof.maxArchivedSummaryTokens}`
    );
  }

  pass("bounded-runtime-proof-metadata");
}

// ---------------------------------------------------------------------------
// Main dispatcher
// ---------------------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);

  let testCase = null;
  const caseIdx = args.indexOf("--case");
  if (caseIdx >= 0) {
    testCase = args[caseIdx + 1];
  } else if (args.length > 0 && !args[0].startsWith("-")) {
    testCase = args[0];
  }

  if (!testCase) {
    console.error("Usage: npx tsx bounded-range.mjs [--case] <case-name>");
    console.error(
      "Cases: monotonic-summary-bound, archived-raw-stays-out-of-prompt, persisted-frontier-state, decompress-archived-rejected, bounded-runtime-proof-metadata"
    );
    process.exit(1);
  }

  switch (testCase) {
    case "monotonic-summary-bound":
      await runMonotonicSummaryBound();
      break;
    case "archived-raw-stays-out-of-prompt":
      await runArchivedRawStaysOutOfPrompt();
      break;
    case "persisted-frontier-state":
      await runPersistedFrontierState();
      break;
    case "decompress-archived-rejected":
      await runDecompressArchivedRejected();
      break;
    case "bounded-runtime-proof-metadata":
      await runBoundedRuntimeProofMetadata();
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
