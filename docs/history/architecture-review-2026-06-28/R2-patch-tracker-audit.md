# Patch Tracker Audit — ez-omo-config

Audit date: 2026-06-28

Scope:
- Patch registry files read: `.sisyphus/patches/*.md` in `/home/ezotoff/ez-omo-config` (14 patch entries + `TEMPLATE.md`).
- Patch-tracker skill read: `skills/patch-tracker/SKILL.md`.
- Source trees checked: `/home/ezotoff/src/opencode` and `/home/ezotoff/oh-my-openagent-v4.12.1`.
- Wisdom searched with three patch/update/failure queries; all returned `[]`.

This report is findings-only and intentionally contains no architecture recommendation.

## Executive findings

- The registry currently contains 14 non-template patch documents.
- Documented statuses are not constrained to the skill's declared lifecycle values. The skill allows only `active`, `upstreamed`, and `deprecated`, but existing docs also use `retired`, `rolled_back`, and `superseded`.
- Status counts by field: 7 `active`, 3 `retired`, 1 `rolled_back`, 1 `superseded`, 1 `upstreamed`, 1 `deprecated`.
- Verified source state does not match documented state in several places:
  - `opencode--commit-policy-unblock` claims `status: active` but its source markers are absent from `/home/ezotoff/src/opencode`.
  - `omo--exclude-selected-auto-slash-commands` claims `status: active` and its broad verification regex passes, but the current source only contains `vera` and `gad-experiment`; `session-info`, `session-id`, and `vscode` are absent from `EXCLUDED_COMMANDS`.
  - Several inactive patches have stale/missing target paths because upstream source layout changed, but the docs' `target_file` fields were not normalized.
- The patch-tracker is a documentation and manual verification system. It has no observed automation that enforces patch presence, blocks updates, rewrites status, or runs verification without an operator invoking the skill/scripts manually.

## Patch registry table

Legend:
- `applied in source/target`: verification marker present in the documented target tree.
- `partial`: enough marker evidence exists to show some patch content is present, but a target-file-specific check found missing expected content.
- `missing/stale`: target file exists but marker is absent, or the documented target path is obsolete.
- `working tree`: marker exists only in uncommitted dependency working-tree changes, not in `HEAD`.
- `committed/head`: marker is present in dependency `HEAD`.

| Patch | Dependency | Status field | Applied date | Target files | Verified state |
|---|---|---:|---:|---|---|
| `opencode--command-hook-cancellation` | `opencode` | `active` | 2026-06-26 | `packages/plugin/src/index.ts`; `packages/opencode/src/session/prompt.ts`; `packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts` | Applied in `/home/ezotoff/src/opencode`, but all markers are uncommitted working-tree changes. `HEAD` lacks `cancelled: boolean`, `commandOutput.cancelled`, and `HttpServerResponse.empty()`. |
| `opencode--commit-policy-unblock` | `opencode` | `active` | 2026-05-02 | `packages/opencode/src/tool/shell/shell.txt`; `packages/opencode/src/session/prompt/default.txt`; `packages/opencode/src/session/prompt/trinity.txt` | **Missing/stale despite `active`**. All three target files exist, but none contains `may create local commits freely`. `HEAD` also lacks it. |
| `omo--commit-policy-alignment` | `oh-my-openagent` | `active` | 2026-05-02 | `AGENTS.md`; `packages/omo-opencode/src/agents/sisyphus/default.ts`; `packages/omo-opencode/src/agents/sisyphus/gpt-5-4.ts`; `packages/omo-opencode/src/agents/sisyphus/kimi-k2-6.ts`; `packages/omo-opencode/src/agents/sisyphus-dynamic-prompt-execution.ts` | Applied in `/home/ezotoff/oh-my-openagent-v4.12.1`, but all checked markers are uncommitted working-tree changes. `HEAD` lacks the policy text. |
| `omo--clean-agent-display-names` | `oh-my-openagent` | `active` | 2026-04-30 | `packages/omo-opencode/src/shared/agent-display-names.ts`; `packages/omo-opencode/src/features/claude-code-session-state/state.ts`; `packages/omo-opencode/src/cli/run/event-message-handlers.ts` | Applied in working tree. Target-specific checks found `sisyphus: "Sisyphus"`, `normalizeAgentForPrompt` in state, and `normalizeAgentForPrompt` in event-message handling. Markers are uncommitted, not in `HEAD`. |
| `oh-my-openagent--context-overflow-max-token-error` | `oh-my-openagent` | `active` | 2026-05-14 | `packages/omo-opencode/src/hooks/todo-continuation-enforcer/token-limit-detection.ts`; `packages/omo-opencode/src/hooks/anthropic-context-window-limit-recovery/parser.ts` | Applied in working tree. Target-specific checks found `isRequestTokenOverflowMessage`, `isRequestTokenOverflowText`, and no remaining literal `"max_tokens"` in parser. Markers are uncommitted, not in `HEAD`. |
| `omo--exclude-selected-auto-slash-commands` | `oh-my-openagent` | `active` | 2026-05-14 | `packages/skills-loader-core/src/hooks/auto-slash-command/constants.ts`; `packages/omo-opencode/src/hooks/auto-slash-command/hook.ts` | **Partial**. Working tree contains `vera`, `gad-experiment`, and `EXCLUDED_COMMANDS.has`; it does **not** contain `session-info`, `session-id`, or `vscode` in `EXCLUDED_COMMANDS`, although the registry `verification_pattern` includes them and the patch title lists them. Broad regex gives a false positive because it matches any one listed command. |
| `omo--glm-preemptive-compaction-threshold` | `oh-my-openagent` | `active` | 2026-04-10 | `packages/omo-opencode/src/hooks/preemptive-compaction-trigger.ts` | Applied in working tree. `GLM_PREEMPTIVE_COMPACTION_THRESHOLD` and `isGlmModel` are present. Markers are uncommitted, not in `HEAD`. |
| `omo--parent-wake-sync-mode-for-tui-render` | `oh-my-openagent` | `rolled_back` | 2026-06-24 | `dist/index.js` | Not applied, matching rollback note. `dist/index.js` exists, but `forceNoReply !== true && input.latestWake.shouldReply ? "sync"` is absent. Status value is outside skill's allowed status set. |
| `omo--remove-activity-stagnation-bypass` | `oh-my-openagent` | `upstreamed` | 2026-04-10 | documented as `src/hooks/todo-continuation-enforcer/session-state.ts` | Documented target path is obsolete/missing. Actual v4.12.1 file is `packages/omo-opencode/src/hooks/todo-continuation-enforcer/session-state.ts`; it contains `progressSource: "none" | "todo"` and no `recordActivity`/`hasObservedExternalActivity`/`allowActivityProgress` matches in the grep result, consistent with upstreamed/removal state. |
| `omo--boulder-worktree-authoritative-state` | `oh-my-openagent` | `superseded` | 2026-05-19 | documented as `src/hooks/atlas/resolve-active-boulder-session.ts` | Documented target path is obsolete/missing. Actual v4.12.1 file is `packages/omo-opencode/src/hooks/atlas/resolve-active-boulder-session.ts`; grep found `getWorkForSession` and `works` map usage, consistent with the doc's supersession note. Status value is outside skill's allowed status set. |
| `opencode-dcp--bounded-range-archive-mode` | `@tarquinen/opencode-dcp` | `retired` | 2026-04-30 | `dist/index.js` across multiple install/cache paths | Mixed/inactive. Markers were present only in snap/XDG DCP copies under `/home/ezotoff/snap/alacritty/common/.cache/opencode/...`; native `~/.config/opencode`, native `~/.cache/opencode`, native package caches, and existing Bun cache copies lacked the marker. Status is retired, but status value is outside skill's allowed status set. |
| `opencode-dcp--byte-budget` | `@tarquinen/opencode-dcp` | `retired` | 2026-05-16 | `dist/index.js` across multiple install/cache paths | Mixed/inactive. Markers were present only in snap/XDG DCP copies under `/home/ezotoff/snap/alacritty/common/.cache/opencode/...`; native `~/.config/opencode`, native `~/.cache/opencode`, native package caches, and existing Bun cache copies lacked the marker. Status is retired, but status value is outside skill's allowed status set. |
| `opencode-dcp--compress-tool-prompt-contract` | `@tarquinen/opencode-dcp` | `retired` | 2026-05-17 | `/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js` | Not applied in documented target. `dist/index.js` exists but lacks `Do NOT announce that you will compress`. Status is retired, outside skill's allowed status set. |
| `ez-omo-config--commit-policy-override` | `ez-omo-config` | `deprecated` | 2026-04-28 | `AGENTS.md` | Not applied, consistent with deprecated/superseded doc. `/home/ezotoff/ez-omo-config/AGENTS.md` lacks `Never commit without explicit user direction`. |

## Source-tree git status findings

### `/home/ezotoff/src/opencode`

Git status:

```text
## fix/sse-directory-filter-v1.17.9
 M packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts
 M packages/opencode/src/session/prompt.ts
 M packages/opencode/test/session/prompt.test.ts
 M packages/plugin/src/index.ts
```

Branch and recent history:

```text
branch: fix/sse-directory-filter-v1.17.9
HEAD: c73249fe1 fix(event): remove directory filter from SSE stream
parent release commit: 5c23e8841 release: v1.17.9
```

Working-tree patch state:

- `opencode--command-hook-cancellation` is present only in uncommitted working-tree changes:
  - `packages/plugin/src/index.ts` has `cancelled: boolean` in working tree, not in `HEAD`.
  - `packages/opencode/src/session/prompt.ts` has `commandOutput.cancelled` in working tree, not in `HEAD`.
  - `packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts` has `HttpServerResponse.empty()` in working tree, not in `HEAD`.
- `packages/opencode/test/session/prompt.test.ts` is also modified in the same working tree, but it is not listed as a target file in the patch frontmatter.
- `opencode--commit-policy-unblock` is missing from both working tree and `HEAD` for all documented source files.

Committed/local patch state:

- The source tree also contains one committed local patch not represented by any `.sisyphus/patches/*.md` entry found in this audit:
  - `c73249fe1 fix(event): remove directory filter from SSE stream`
  - File changed versus release commit: `packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts`.

### `/home/ezotoff/oh-my-openagent-v4.12.1`

Git status:

```text
## HEAD (no branch)
 M AGENTS.md
 M packages/omo-codex/scripts/install-dist/install-local.mjs
 M packages/omo-opencode/src/agents/sisyphus-dynamic-prompt-execution.ts
 M packages/omo-opencode/src/agents/sisyphus/default.ts
 M packages/omo-opencode/src/agents/sisyphus/gpt-5-4.ts
 M packages/omo-opencode/src/agents/sisyphus/kimi-k2-6.ts
 M packages/omo-opencode/src/cli/run/event-message-handlers.ts
 M packages/omo-opencode/src/features/claude-code-session-state/state.ts
 M packages/omo-opencode/src/hooks/anthropic-context-window-limit-recovery/parser.ts
 M packages/omo-opencode/src/hooks/auto-slash-command/hook.ts
 M packages/omo-opencode/src/hooks/preemptive-compaction-trigger.ts
 M packages/omo-opencode/src/hooks/todo-continuation-enforcer/token-limit-detection.ts
 M packages/omo-opencode/src/shared/agent-display-names.ts
 M packages/skills-loader-core/src/hooks/auto-slash-command/constants.ts
```

Recent history:

```text
HEAD: d0dc6f6 Merge pull request #5452 from code-yeongyu/release/v4.12.1-source-state
state: detached HEAD
```

Working-tree patch state:

- All source markers for the following documented active OMO patches are uncommitted working-tree changes, not committed in `HEAD`:
  - `omo--commit-policy-alignment`
  - `omo--clean-agent-display-names`
  - `oh-my-openagent--context-overflow-max-token-error`
  - `omo--exclude-selected-auto-slash-commands` (partial as noted above)
  - `omo--glm-preemptive-compaction-threshold`
- `packages/omo-codex/scripts/install-dist/install-local.mjs` is modified but no matching patch document was found in `.sisyphus/patches/`.

Committed/upstream state:

- `omo--remove-activity-stagnation-bypass` appears incorporated by upstream v4.12.1 behavior at the actual package path, although its frontmatter target path is stale.
- `omo--boulder-worktree-authoritative-state` appears superseded by upstream v4.12.1 `works`/`getWorkForSession` architecture at the actual package path, although its frontmatter target path is stale.

## Patch-tracker skill lifecycle model

The skill defines a manual CRUD lifecycle:

- Create: evaluate alternatives, gather frontmatter/body fields, create `.sisyphus/patches/{patch_id}.md`, and run a grep verification command.
- Read: list patch docs and summarize status counts.
- Update: edit frontmatter/body when a patch changes.
- Deprecate: change `status` to `upstreamed` or `deprecated`, never delete entries.
- Verify: for each `status == "active"`, resolve target path, grep `verification_pattern`, report `applied`, `stale`, or `missing-target`; surface reapply instructions for stale/missing entries.

The declared validation rules require:

- `status` must be one of `active`, `upstreamed`, `deprecated`.
- `target_file` must be relative.
- `verification_pattern` must be grep-compatible.
- Filename must match `patch_id`.
- All required body sections must exist.

Observed drift from that model:

- Existing docs use statuses the skill declares invalid: `retired`, `rolled_back`, and `superseded`.
- Some docs use `target_install_paths` instead of the template's singular `target_install_path`.
- Some docs have stale target paths after the v4.12.1 monorepo restructure (`src/...` instead of `packages/omo-opencode/src/...`).
- Some verification patterns are too broad for multi-file patches. `omo--exclude-selected-auto-slash-commands` is the clearest case: the regex passes if any one listed command appears, masking the absence of `session-info`, `session-id`, and `vscode`.
- The skill says stale active patches should be reported and may have status updated, but this audit made no registry changes; current docs still claim active for at least one missing patch (`opencode--commit-policy-unblock`).

## Wisdom search findings

Commands run through the Wisdom skill's documented search script:

```text
~/.sisyphus/scripts/wisdom-search.sh "patch tracker patches update stale missing reapply" --scope all --limit 20 --json
~/.sisyphus/scripts/wisdom-search.sh "OpenCode OMO patch-tracker failure patches lost update" --scope all --limit 20 --json
~/.sisyphus/scripts/wisdom-search.sh "DCP patch stale missing target OpenCode OMO update" --scope all --limit 20 --json
```

All three searches returned `[]`. Per the Wisdom skill's authority rules, there is no documented Wisdom knowledge found for patch-tracker failures, update patch loss, or patch reapply evidence in this search set.

## Status gaps and failure/success evidence

### Claimed active but absent/stale

- `opencode--commit-policy-unblock`: `status: active`, but the marker `may create local commits freely` is absent from all three documented OpenCode source files in both working tree and `HEAD`.

### Claimed active but only partially applied

- `omo--exclude-selected-auto-slash-commands`: `status: active`, but only `vera` and `gad-experiment` are currently in `EXCLUDED_COMMANDS`; `session-info`, `session-id`, and `vscode` are absent. Hook guard exists. The registry verification pattern masks this partial loss.

### Claimed active and present only as uncommitted dependency changes

- `opencode--command-hook-cancellation` is present in `/home/ezotoff/src/opencode` working tree only.
- `omo--commit-policy-alignment`, `omo--clean-agent-display-names`, `oh-my-openagent--context-overflow-max-token-error`, `omo--exclude-selected-auto-slash-commands`, and `omo--glm-preemptive-compaction-threshold` are present in `/home/ezotoff/oh-my-openagent-v4.12.1` working tree only.

### Inactive docs with accurate non-application or upstream/superseded evidence

- `omo--parent-wake-sync-mode-for-tui-render`: rolled back; marker absent from `dist/index.js`, matching doc note.
- `ez-omo-config--commit-policy-override`: deprecated; old marker absent from `AGENTS.md`, matching supersession note.
- `omo--remove-activity-stagnation-bypass`: upstreamed; actual v4.12.1 source at package path has `progressSource: "none" | "todo"` and lacks activity-bypass markers.
- `omo--boulder-worktree-authoritative-state`: superseded; actual v4.12.1 source at package path uses `getWorkForSession`/`works` map architecture.

### Retired DCP patch evidence

- DCP patches are marked retired, but the installation landscape is mixed:
  - Snap/XDG cache copies still contain bounded-range and byte-budget markers.
  - Native `~/.config/opencode`, native `~/.cache/opencode`, native package-cache, and existing Bun cache copies checked by the script lack those markers.
  - The compress-tool prompt contract marker is absent from its documented reference target.
- Because these patches are retired, this is not an active-patch failure, but it shows that historical patch state can remain partially present across cache planes.

## Tracking vs enforcement assessment

Based on the skill and observed repository/source state, patch-tracker is a tracking/documentation system, not an enforcement system.

Evidence:

- Patch state lives in markdown files under `.sisyphus/patches/`.
- Verification is described as an operator workflow using grep commands.
- No observed hook blocks dependency updates when active patches are stale.
- No observed automatic CI/check script was run or referenced by the skill to verify all active patches continuously.
- No observed mechanism reconciles patch docs with dependency git working trees after updates.
- No observed mechanism detects unregistered dependency changes; current source trees contain at least two examples: OpenCode committed `fix(event): remove directory filter from SSE stream`, and OMO's modified `packages/omo-codex/scripts/install-dist/install-local.mjs`.
- No observed status schema enforcement prevents invalid statuses or stale target paths.

What's missing for enforcement, as a factual gap list:

- Machine-readable patch registry schema with accepted lifecycle states matching real usage.
- Deterministic verifier that checks all active patches against exact per-file expectations, not broad OR-regex markers.
- Integration point that runs the verifier after OpenCode/OMO/DCP updates.
- Integration point that fails/blocks or at least produces a hard warning when active patches are stale/missing.
- Detection/reporting for dependency working-tree changes that lack a patch document.
- A way to distinguish source-applied, built-binary-applied, live-file-installed, runtime-loaded, and real-project-behavior-proven states per patch.

## Verification commands used for this audit

- Listed patch docs with `glob` for `.sisyphus/patches/*.md`.
- Read all 14 patch docs plus `TEMPLATE.md`.
- Read `skills/patch-tracker/SKILL.md`.
- Ran `git status --short --branch`, `git log --oneline`, `git diff --name-status`, and `git diff --stat` in both source trees.
- Ran marker checks against documented target paths and target-specific marker checks for multi-file active patches.
- Searched Wisdom with three patch/update/failure queries; all returned empty JSON arrays.
