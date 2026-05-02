---
patch_id: "ez-omo-config--commit-policy-override"
dependency: "ez-omo-config"
target_file: "AGENTS.md"
target_install_path: "/home/ezotoff/ez-omo-config"
status: "deprecated"
applied_date: "2026-04-28"
dep_version: "current"
upstream_issue: "none"
verification_pattern: "Never commit without explicit user direction"
---

# AGENTS.md Commit Policy Override

## Problem

The base OpenCode/OMO system instruction states: "Only create commits when requested by the user. If unclear, ask first."

However, the built-in `git-master` skill (loaded via `skill(name="git-master")`) instructs agents to "Commit early, commit often" and "Commit and push on every completed todo item or logical task unit."

These instructions are contradictory. Without an explicit override in AGENTS.md, agents may follow the skill advice over the base system instruction, leading to unsolicited commits.

## Patch Description

Added Rule 6 to AGENTS.md "Rules for Agents" section:

> **Never commit without explicit user direction.** The base system instruction "Only create commits when requested by the user" takes precedence over any skill advice (including git-master). If unclear whether to commit, ask first.

This rule explicitly prioritizes the base system instruction over conflicting skill advice.

## Verification

```bash
grep -n "Never commit without explicit user direction" /home/ezotoff/ez-omo-config/AGENTS.md
```

Expected output: a match on the line containing the rule.

## Reapply Instructions

If this patch is lost (e.g., AGENTS.md is regenerated or overwritten):

1. Open `AGENTS.md`
2. Find the "Rules for Agents" section
3. Add as the last rule:
   > **Never commit without explicit user direction.** The base system instruction "Only create commits when requested by the user" takes precedence over any skill advice (including git-master). If unclear whether to commit, ask first.
4. Commit the change (with user direction)

## Durable Alternative

The ideal fix would be upstream in OpenCode/OMO:
- Option A: Remove the "commit early, commit often" advice from the git-master skill, or rephrase it as "commit when user requests"
- Option B: Add a system-level policy mechanism where base instructions always override skill instructions for sensitive operations (commits, pushes, destructive actions)

Status: superseded

## Supersession Note

This patch is **deprecated**. It has been superseded by two new source-level patches that replace the absolute "never commit" AGENTS.md rule with a nuanced local-commit policy:

1. **`opencode--commit-policy-unblock`** — Patches OpenCode system instructions (`bash.txt`, `trinity.txt`, `default.txt`) to replace the blanket "Only create commits when requested" with a safe local-commit policy that respects workflow-authorized commits.

2. **`omo--commit-policy-alignment.md`** — Patches OMO agent instructions and git-master skill to align with the same safe local-commit policy.

The old AGENTS.md rule was a band-aid that enforced an absolute no-commit stance, but it conflicted with active project/skill workflows (git-master, auto-checkpoint) that explicitly authorize local checkpoint/logical-task commits. The new source-level patches resolve the contradiction properly by updating the instructions at their source.
