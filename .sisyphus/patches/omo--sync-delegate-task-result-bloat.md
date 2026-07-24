---
patch_id: "omo--sync-delegate-task-result-bloat"
dependency: "oh-my-openagent"
target_file: "configs/oh-my-openagent/oh-my-openagent.json"
target_install_path: "/home/ezotoff/ez-omo-config"
status: "active"
applied_date: "2026-07-16"
dep_version: ">=4.12.1"
upstream_issue: "filed 2026-07-16 — tool_output.max_bytes gap in sync-result-fetcher.ts"
verification_pattern: "Subagent Result Bloat Prevention"
---

# Sync delegate_task Result Bloat — Config-Level Mitigation

## Problem

OMO's `delegate_task` sync path (`fetchSyncResult` in `packages/omo-opencode/src/tools/delegate-task/sync-result-fetcher.ts`) returns the subagent's full final assistant message (all text+reasoning parts concatenated) WITHOUT any size truncation. The OpenCode `tool_output.max_bytes` setting (default 51200) does NOT apply to the task tool's own output — it only governs plugin tool outputs via `registry.ts:148`.

When a subagent produces a long final response (e.g., a detailed DoneClaim with file-change summaries, test outputs, and system-reminder blocks), the sync result can exceed 100KB–500KB. Injecting this directly into the parent model's context causes:

1. **Context saturation** — the parent model (especially glm-5.2) receives a massive payload in one turn and produces an empty/degenerate response.
2. **Session halt** — the agent loop exits normally because the model returned no tool calls, but no work was actually done (no verification, no checkbox marking, no next-wave dispatch).
3. **TUI spam** — when the user drills into a subagent session and returns, the TUI re-renders the oversized tool result inline, flooding the screen.

Observed incident: `ses_09b88d5eaffezIacu5K4KFGvi6` (2026-07-16) — two sync task results of 529KB and 535KB caused glm-5.2 to produce an empty response at step 17, halting the session after only 6/23 tasks were complete.

## Mitigations Applied (2026-07-16)

### Layer 1: Prompt-level bloat prevention (dc44caa)

Added a "Subagent Result Bloat Prevention" directive to the `prompt_append` field of the `atlas` and `sisyphus` agents. The directive instructs orchestrators to:
- Use `run_in_background: true` for substantial subagent dispatches (deep, ultrabrain, 3+ file tasks)
- Collect results via `background_output(task_id="...", full_session=false)` — last assistant message only
- Use `full_session=true` with `message_limit=5` and `include_tool_results=false` only for failed-task diagnostics
- Instruct subagents in task prompts to keep final summaries under 2000 characters

### Layer 2: Background output collection protocol

Added "Background Result Collection Protocol" to `atlas` and `sisyphus` `prompt_append`. Orchestrators now:
- Collect ONE background result at a time, process immediately (mark checkbox), then collect next
- On re-collection (if pruned), use `background_output(task_id="...", full_session=true, from_end=true)` to bypass the incremental cursor (OMO #2915)
- Enforce 2000-char summary limit in every `delegate_task` prompt

### Layer 3: Protected background_output from dedup pruning

Added `"background_output"` to `experimental.dynamic_context_pruning.protected_tools` in `oh-my-openagent.json`. Prevents OMO DCP deduplication from truncating duplicate `background_output` calls.

### Layer 4: Widened empty-response detection gate

Changed `provider-connect-retry.mjs` line 508 from `finish === "other"` to `(finish === "other" || finish === "stop")` with `tokens.output === 0`. GLM-5.2 on context saturation returns `finish_reason: "stop"` with 0 tokens — the original 2026-04-18 narrowing (commit 36947f9) excluded this, but legitimate stop completions always have `output > 0`.

## Verification

```bash
# Layer 1+2: prompt directives present
grep -c "Subagent Result Bloat Prevention" /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json
grep -c "Background Result Collection" /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json

# Layer 3: protected_tools includes background_output
python3 -c "import json; d=json.load(open('configs/oh-my-openagent/oh-my-openagent.json')); assert 'background_output' in d['experimental']['dynamic_context_pruning']['protected_tools']"

# Layer 4: widened detection gate
grep 'finish === "other" || finish === "stop"' /home/ezotoff/ez-omo-config/configs/opencode/provider-connect-retry.mjs
```

## Upstream References

- **OMO #1734** (open) — Background Task Output Distillation + Non-Destructive Recovery
- **OMO PR #5458** (open) — do not compact while results are gathered
- **OMO PR #5204** (open) — persist background tasks across restarts
- **OMO #2915** (closed) — cursor not reset after undo (proves incremental retrieval)
- **OpenCode #33650** (open) — background-output synthesis dropped by truncation
- **OpenCode #32515** (closed) — compaction.prune mutates old tool outputs (expected behavior)
- **New issue filed 2026-07-16** — tool_output.max_bytes does not apply to sync delegate_task results

## Durable Alternative

**Code fix in OMO**: Add a size guard in `fetchSyncResult` (`packages/omo-opencode/src/tools/delegate-task/sync-result-fetcher.ts` lines 57-75, 144-163) that truncates `textContent` to a configurable maximum (e.g., 8192 bytes) before returning to the parent. The truncated result should include a pointer: "Use background_output with full_session=true to retrieve the complete output."

Could also be exposed as an OMO config option: `delegate_task.max_sync_result_bytes` (default 8192).

Status: upstream issue filed 2026-07-16
