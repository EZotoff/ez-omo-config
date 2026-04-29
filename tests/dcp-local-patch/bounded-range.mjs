// tests/dcp-local-patch/bounded-range.mjs
// Regression harness for bounded-range DCP patches

import { readFileSync } from "node:fs";

const DCP_ROOT = "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist";

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
    `${DCP_ROOT}/lib/compress/range-utils.js`
  );
  const { countTokens } = await import(`${DCP_ROOT}/lib/token-utils.js`);

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
  const { prune } = await import(`${DCP_ROOT}/lib/messages/prune.js`);

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
  const { syncCompressionBlocks } = await import(`${DCP_ROOT}/lib/messages/sync.js`);

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
  const decompressPath = `${DCP_ROOT}/lib/commands/decompress.js`;
  const source = readFileSync(decompressPath, "utf-8");

  const expectedGuard =
    "Compression ${target.displayId} uses bounded archival retention and cannot be decompressed to raw history.";
  if (!source.includes(expectedGuard)) {
    fail(`decompress-archived-rejected: guard string not found in decompress.js`);
  }

  pass("decompress-archived-rejected");
}

// ---------------------------------------------------------------------------
// Main dispatcher
// ---------------------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);
  const caseIdx = args.indexOf("--case");
  const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null;

  if (!testCase) {
    console.error("Usage: npx tsx bounded-range.mjs --case <case-name>");
    console.error(
      "Cases: monotonic-summary-bound, archived-raw-stays-out-of-prompt, persisted-frontier-state, decompress-archived-rejected"
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
