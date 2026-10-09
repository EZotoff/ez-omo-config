#!/usr/bin/env bash

# Test fallback-watch.mjs plugin + scripts/fallback-spend-report.sh contract.
# Usage: bash tests/test_fallback_watch.sh

set -uo pipefail

cd "$(dirname "$0")/.."
source tests/helpers.sh

PLUGIN="configs/opencode/fallback-watch.mjs"
REPORT="scripts/fallback-spend-report.sh"

assert_file_exists "$PLUGIN"
assert_file_exists "$REPORT"

# Loader constraint: ONLY function exports (the getLegacyPlugins incident).
assert_grep 'export const FallbackWatchPlugin = async' "$PLUGIN"
if grep -qE '^export (const|let|var) [A-Za-z]+ *= *\{' "$PLUGIN" || grep -qE '^export default \{' "$PLUGIN"; then
    echo "FAIL: non-function top-level export found in $PLUGIN (breaks plugin loader)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# No console.* CALLS (TUI/journald spam regression class); comments are fine.
if grep -qE '^[[:space:]]*console\.' "$PLUGIN"; then
    echo "FAIL: console.* call found in $PLUGIN"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Syntax check.
if node --check "$PLUGIN" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: node --check $PLUGIN"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---- Functional test: fixture configs + simulated events ----
TMPDIR_FW="$(mktemp -d /tmp/opencode/fallback-watch-test.XXXXXX)"
trap 'rm -rf "$TMPDIR_FW"' EXIT

cat > "$TMPDIR_FW/oh-my-openagent.json" << 'EOF'
{
  "agents": {
    "oracle": {
      "model": "mimo/mimo-v2.6-pro",
      "fallback_models": ["zai-coding-plan/glm-5.3", "kimi-for-coding-oauth/k3"]
    },
    "sisyphus": {
      "model": "zai-coding-plan/glm-5.3-flash",
      "fallback_models": ["ollama-cloud/deepseek-v4.1-flash"]
    }
  },
  "categories": {
    "quick": {
      "model": "kimi-for-coding-oauth/k3",
      "fallback_models": ["zai-coding-plan/glm-5.3-flash"]
    }
  }
}
EOF
cat > "$TMPDIR_FW/opencode.json" << 'EOF'
{ "small_model": "ollama-cloud/deepseek-v4.1-flash" }
EOF
cat > "$TMPDIR_FW/retry-errors.json" << 'EOF'
{ "compaction_fallback_models": ["opencode-go/deepseek-v4.1-flash", "zai-coding-plan/glm-5.3"] }
EOF
: > "$TMPDIR_FW/fallback-watch.log"

HARNESS="$TMPDIR_FW/harness.mjs"
cat > "$HARNESS" << 'EOF'
import assert from "node:assert";

// Test-path isolation BEFORE any call: path helpers read globalThis lazily.
const TP = process.env.FW_TP;
globalThis.__fallbackWatchTestPaths = {
  omoConfig: TP + "/oh-my-openagent.json",
  opencodeConfig: TP + "/opencode.json",
  retryRegistry: TP + "/retry-errors.json",
  log: TP + "/fallback-watch.log",
};

const { buildDeclaredSets, classifyAgentTurn, FallbackWatchPlugin } = await import(process.argv[2]);

const declared = buildDeclaredSets();
// Declared: primary, agent fallback, category model, small model, compaction chain.
assert.strictEqual(classifyAgentTurn({ agentName: "oracle", model: { providerID: "mimo", modelID: "mimo-v2.6-pro" } }, declared), undefined);
assert.strictEqual(classifyAgentTurn({ agentName: "oracle", model: { providerID: "zai-coding-plan", modelID: "glm-5.3" } }, declared), undefined);
assert.strictEqual(classifyAgentTurn({ agentName: "Sisyphus", model: { providerID: "ollama-cloud", modelID: "deepseek-v4.1-flash" } }, declared), undefined, "small_model must be allowed");
// Case-insensitive agent lookup.
assert.strictEqual(classifyAgentTurn({ agentName: "ORACLE", model: { providerID: "kimi-for-coding-oauth", modelID: "k3" } }, declared), undefined);
// Unknown agent: still judged by the pool — build on a declared-nowhere model is out-of-band.
assert.strictEqual(classifyAgentTurn({ agentName: "build", model: { providerID: "google", modelID: "gemini-3.1-pro-preview" } }, declared), "google/gemini-3.1-pro-preview");
// Unknown agent on a declared model: allowed.
assert.strictEqual(classifyAgentTurn({ agentName: "build", model: { providerID: "kimi-for-coding-oauth", modelID: "k3" } }, declared), undefined);
// Out-of-band: declared nowhere.
assert.strictEqual(classifyAgentTurn({ agentName: "oracle", model: { providerID: "google", modelID: "gemini-3.1-pro-preview" } }, declared), "google/gemini-3.1-pro-preview");

// End-to-end: plugin event handler logs + toasts out-of-band, stays silent otherwise.
let toasts = 0;
const ctx = {
  client: { tui: { showToast: async () => { toasts += 1; } } },
  directory: "/tmp",
};
const plugin = await FallbackWatchPlugin(ctx);
const evt = (id, agent, modelID, providerID = "google") => ({
  type: "message.updated",
  properties: { info: { id, role: "assistant", agent, sessionID: "ses_test", providerID, modelID, tokens: { input: 10, output: 1, cache: { read: 0 } }, cost: 0.01 } },
});
await plugin.event({ event: evt("msg_1", "oracle", "gemini-3.1-pro-preview") });
await plugin.event({ event: evt("msg_1", "oracle", "gemini-3.1-pro-preview") }); // deduped
await plugin.event({ event: evt("msg_2", "oracle", "mimo-v2.6-pro", "mimo") }); // declared: silent
await plugin.event({ event: evt("msg_3", "oracle", "gemini-3.1-pro-preview") }); // same session+model: logged, no 2nd toast
await plugin.event({ event: evt("msg_4", "build", "gemini-3.1-pro-preview") }); // unknown agent: silent
assert.strictEqual(toasts, 1, `expected exactly 1 toast, got ${toasts}`);
console.log("HARNESS-OK");
EOF

if LOGOUT=$(FW_TP="$TMPDIR_FW" node "$HARNESS" "$(pwd)/$PLUGIN" 2>&1) && grep -q 'HARNESS-OK' <<< "$LOGOUT"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: plugin harness:"; echo "$LOGOUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Log line actually written to the ISOLATED log (not the live one).
if grep -q 'out_of_band_fallback' "$TMPDIR_FW/fallback-watch.log"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: out_of_band_fallback log line missing from isolated log"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---- Report script: fixture DB end-to-end ----
FDB="$TMPDIR_FW/opencode.db"
python3 - "$FDB" << 'PYEOF'
import json, sqlite3, sys, time
db = sqlite3.connect(sys.argv[1])
db.executescript("""
create table session (id text primary key, parent_id text, title text, directory text);
create table message (id text primary key, session_id text, time_created integer, data text);
""")
now_ms = int(time.time() * 1000)
db.execute("insert into session values ('ses_1', 'ses_p', 'Oracle review', '/tmp/proj')")
db.execute("insert into session values ('ses_2', null, 'Top session', '/tmp/proj')")
gem = {"role": "assistant", "agent": "oracle", "providerID": "google", "modelID": "gemini-3.1-pro-preview",
       "tokens": {"input": 1000, "output": 50, "cache": {"read": 4000}}, "cost": 0.02}
ok = {"role": "assistant", "agent": "oracle", "providerID": "mimo", "modelID": "mimo-v2.6-pro",
      "tokens": {"input": 500, "output": 10, "cache": {"read": 100}}, "cost": 0.0}
db.execute("insert into message values ('m1','ses_1',?,?)", (now_ms, json.dumps(gem)))
db.execute("insert into message values ('m2','ses_2',?,?)", (now_ms, json.dumps(ok)))
db.commit()
PYEOF

REPORT_OUT="$(OPENCODE_DB="$FDB" OMO_CONFIG="$TMPDIR_FW/oh-my-openagent.json" \
    OPENCODE_CONFIG="$TMPDIR_FW/opencode.json" RETRY_REGISTRY="$TMPDIR_FW/retry-errors.json" \
    bash "$REPORT" 7)"
if grep -q 'google/gemini-3.1-pro-preview' <<< "$REPORT_OUT" \
    && grep -q 'TOTAL out-of-band: 5,050 tokens' <<< "$REPORT_OUT" \
    && ! grep -q 'mimo-v2.6-pro' <<< "$REPORT_OUT"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: report output unexpected:"; echo "$REPORT_OUT"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Live-DB smoke: report runs read-only against the real DB without error.
if bash "$REPORT" 7 > /dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: report failed against live DB"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
