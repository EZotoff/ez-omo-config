---
patch_id: "omo--sync-delegate-task-result-bloat"
dependency: "oh-my-openagent"
target_file: "configs/oh-my-openagent/oh-my-openagent.json"
target_install_path: "/home/ezotoff/ez-omo-config"
status: "active"
applied_date: "2026-07-16"
dep_version: ">=4.12.1"
upstream_issue: "none"
verification_pattern: "Subagent Result Bloat Prevention"
---

# Sync delegate_task Result Bloat — Config-Level Mitigation

## Problem

OMO's `delegate_task` sync path (`fetchSyncResult` in `dist/index.js`) returns the subagent's full final assistant message (all text+reasoning parts concatenated) WITHOUT any size truncation. The OpenCode `tool_output.max_bytes` setting (default 51200) does NOT apply to the task tool's own output — it only governs plugin tool outputs via `registry.ts:148`.

When a subagent produces a long final response (e.g., a detailed DoneClaim with file-change summaries, test outputs, and system-reminder blocks), the sync result can exceed 100KB–500KB. Injecting this directly into the parent model's context causes:

1. **Context saturation** — the parent model (especially glm-5.2) receives a massive payload in one turn and produces an empty/degenerate response.
2. **Session halt** — the agent loop exits normally because the model returned no tool calls, but no work was actually done (no verification, no checkbox marking, no next-wave dispatch).
3. **TUI spam** — when the user drills into a subagent session and returns, the TUI re-renders the oversized tool result inline, flooding the screen.

Observed incident: `ses_09b88d5eaffezIacu5K4KFGvi6` (2026-07-16) — two sync task results of 529KB and 535KB caused glm-5.2 to produce an empty response at step 17, halting the session after only 6/23 tasks were complete.

## Patch Description

**This is a config-level mitigation, not a code patch.** Added a "Subagent Result Bloat Prevention" directive to the `prompt_append` field of the `atlas` and `sisyphus` agents in `configs/oh-my-openagent/oh-my-openagent.json`.

The directive instructs the orchestrator to:
- Use `run_in_background: true` for substantial subagent dispatches (deep, ultrabrain, 3+ file tasks)
- Collect results via `background_output(task_id="...", full_session=false)` — which returns only the last assistant message by default
- Use `full_session=true` with `message_limit=5` and `include_tool_results=false` only for failed-task diagnostics
- Instruct subagents in task prompts to keep final summaries under 2000 characters

The `quick` category (single-file trivial tasks) is exempted — sync mode remains acceptable there.

## Verification

```bash
grep -c "Subagent Result Bloat Prevention" /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json
```
Expected: `2` (one match each in the `sisyphus` and `atlas` prompt_append values).

## Reapply Instructions

1. Open `configs/oh-my-openagent/oh-my-openagent.json`
2. In the `agents.atlas.prompt_append` value, append after the evidence-state paragraph:
   - The "## Subagent Result Bloat Prevention" section with the background-mode rule, the session-halt root-cause reference, and the 2000-char summary instruction
3. In the `agents.sisyphus.prompt_append` value, append a shorter version of the same directive (without the session-halt reference)
4. Validate JSON: `python3 -c "import json; json.load(open('configs/oh-my-openagent/oh-my-openagent.json'))"`

## Durable Alternative

**Code fix in OMO**: Add a size guard in `fetchSyncResult` (~line 105745 in `dist/index.js`) or `executeSyncTask` (~line 106870) that truncates `textContent` to a configurable maximum (e.g., 8192 bytes) before returning to the parent. The truncated result should include a pointer: "Use background_output with full_session=true to retrieve the complete output."

This would be the proper fix because:
- It's a hard ceiling the model can't forget to apply
- It protects all agents, not just those with the prompt_append directive
- The full transcript remains accessible via `background_output`

Could also be exposed as an OMO config option: `delegate_task.max_sync_result_bytes` (default 8192).

Status: not-yet-pursued
