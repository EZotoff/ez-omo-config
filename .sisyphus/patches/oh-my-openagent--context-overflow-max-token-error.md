---
patch_id: "oh-my-openagent--context-overflow-max-token-error"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/hooks/todo-continuation-enforcer/token-limit-detection.ts, packages/omo-opencode/src/hooks/anthropic-context-window-limit-recovery/parser.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "active"
applied_date: "2026-05-14"
dep_version: "4.12.1"
upstream_issue: "https://github.com/anomalyco/opencode/issues/27519"
verification_pattern: "isRequestTokenOverflowMessage"
note: "v4.12.1 REGRESSED: upstream re-added 'max_tokens' to TOKEN_LIMIT_KEYWORDS (the false-positive this patch removes). Patch is MORE necessary on v4.12.1. Surrounding parser.ts code refactored with isRecord/readStringProperty/parseJsonOrNull helpers from @oh-my-opencode/utils."
---

# Max Token Request Overflow Detection

## Problem
When a provider returns an error like "tokens in request more than max tokens allowed", OMO did not recognize it as a context-window overflow. The existing `TOKEN_LIMIT_FALLBACK_PATTERNS` relied on broad substring matches (e.g., `max_tokens`) which also matched unrelated output-limit errors like `max_tokens must be less than or equal to 4096`. This caused either:
- False negatives: request-token overflows were ignored, leading to continuation loops, or
- False positives: output-setting errors triggered unnecessary compaction.

## Patch Description
Added conservative, ordered-phrase detection for request-token overflow messages in two files:

1. **src/hooks/todo-continuation-enforcer/token-limit-detection.ts**
   - Added `REQUEST_TOKEN_SCOPE_PHRASES` (e.g., "tokens in request", "input tokens")
   - Added `REQUEST_TOKEN_COMPARISON_PHRASES` (e.g., "more than", "exceeds")
   - Added `REQUEST_TOKEN_MAX_PHRASES` (e.g., "max tokens", "maximum tokens")
   - Added `isRequestTokenOverflowMessage()` which normalizes text and checks for ordered sequence: scope phrase → comparison phrase → max phrase
   - Integrated into `isTokenLimitError()` so the todo-continuation enforcer triggers compaction instead of looping

2. **src/hooks/anthropic-context-window-limit-recovery/parser.ts**
   - Added the same three phrase arrays and `isRequestTokenOverflowText()`
   - Removed "max_tokens" from `TOKEN_LIMIT_KEYWORDS` to prevent false-positive matches on output-limit validation messages

Before: Only broad `TOKEN_LIMIT_FALLBACK_PATTERNS` + `TOKEN_LIMIT_KEYWORDS` (including "max_tokens").
After: Narrow ordered-phrase detection specifically for request/input/prompt/context token overflows, plus preserved fallback patterns for other overflow variants.

## Verification
```bash
grep -n "isRequestTokenOverflowMessage" /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/token-limit-detection.ts && echo "APPLIED" || echo "STALE"
```
Expected: Two matches — function declaration and call site in `isTokenLimitError()`.

Secondary check on parser file:
```bash
grep -n "isRequestTokenOverflowText" /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/anthropic-context-window-limit-recovery/parser.ts && echo "APPLIED" || echo "STALE"
```
Expected: Two matches — function declaration and call site in `isTokenLimitError()`.

## Reapply Instructions
1. Open `src/hooks/todo-continuation-enforcer/token-limit-detection.ts`
2. Add the three phrase arrays and `isRequestTokenOverflowMessage()` function (see current file for exact code)
3. In `isTokenLimitError()`, add the call to `isRequestTokenOverflowMessage(error.message)` alongside existing fallback checks
4. Open `src/hooks/anthropic-context-window-limit-recovery/parser.ts`
5. Add the same phrase arrays and `isRequestTokenOverflowText()` function
6. Remove "max_tokens" from `TOKEN_LIMIT_KEYWORDS` if present
7. In `isTokenLimitError()`, add the call to `isRequestTokenOverflowText(text)` before the fallback keyword check
8. Run `bun run build` to regenerate dist artifacts
9. Restart OpenCode to load the rebuilt OMO plugin

## Durable Alternative
Upstream PR #27524 to anomalyco/opencode adds the same conservative overflow detection to the core provider error classifier. Once merged, OMO can rely on the upstream classifier and potentially remove this local patch.
Status: pursued
