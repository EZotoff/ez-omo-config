---
patch_id: "oh-my-openagent--external-system-premise-discipline"
dependency: "oh-my-openagent"
target_file: "configs/oh-my-openagent/oh-my-openagent.json"
target_install_path: "/home/ezotoff/ez-omo-config"
status: "active"
applied_date: "2026-08-13"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "External-system premises"
---

# External-System Premise Discipline (Planning + Review Agents)

## Problem
A Prometheus planning session (glm-5.2) authored a work plan whose core design depended on DeepSeek's strict-tool-call mode being reliable ("constrained decoding guarantees validity"). The premise was backed only by a 3-call runtime probe, not by research into DeepSeek V4's documented behavior. It was empirically false: DeepSeek V4 has a documented ~11–25% "fall-through to text mode" failure rate on forced tool calls (deepseek-ai/DeepSeek-V3#1244). Oracle + Momus reviewed the plan's design edges without questioning the empirical foundation, so a well-sharpened wrong plan shipped. The global "Before Modifying Unknown Systems" rule (commit `fc3c3b3`, 2026-08-12 — already live when this plan was written) scopes to **code modification** and sanctions a **probe**; it does not cover planning-time external-provider reliability claims, where a probe samples but does not characterize.

## Patch Description
Added an "External-system premises" discipline to three agent `prompt_append` fields in `oh-my-openagent.json`:

1. **prometheus** (planner, line ~59) — appended: when a plan's core design depends on an external system's behavior (provider API, library guarantee, service contract), RESEARCH it (docs + issues + community) before treating it as settled; a runtime probe samples but cannot characterize failure modes/rates; a clean pass (e.g. 3/3) does not justify a "guarantees X" claim; if undocumented, mark as an UNVERIFIED RISK with a fallback.
2. **momus** (plan reviewer, line ~80) — **added** a `prompt_append` (previously had none): flag any load-bearing external-system premise backed by a probe or theory instead of documentation as a REVIEW BLOCKER until researched or marked as an unverified risk with a fallback.
3. **oracle** (architecture consultant, line ~30) — appended: require external-system dependencies to be backed by documentation or research, not a runtime probe or a theoretical guarantee; flag load-bearing external-system premises presented as settled fact.

Scoped to "external system's behavior" to avoid contradicting the global "Before Modifying Unknown Systems" rule (which covers internal-code understanding via probe). The two rules cover different domains (internal-code vs external-provider) at different lifecycle stages (modification vs planning/review).

## Verification
```bash
# Pattern (necessary, sufficient for this config change — it's a plain JSON edit, not a binary patch):
grep -c "External-system premises" /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json
# Expected: 3  (prometheus + oracle append "## External-system premises"; momus adds "## External-system premise review" — note the grep matches the shared prefix)

# Confirm momus gained a prompt_append:
jq '.agents.momus | has("prompt_append")' /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json
# Expected: true

# Confirm JSON validity:
jq empty /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json
# Expected: exit 0
```

## Reapply Instructions
The repo file is git-tracked and symlinked live (`~/.config/opencode/oh-my-openagent.json` → repo), so **git is the primary restore mechanism**. To reapply after an installer overwrite or accidental revert:

1. `cd /home/ezotoff/ez-omo-config`
2. Find the commit: `git log --oneline --grep="external-system premise discipline" -- configs/oh-my-openagent/oh-my-openagent.json`
3. Restore: `git checkout <commit> -- configs/oh-my-openagent/oh-my-openagent.json`
4. Confirm the live symlink is intact: `readlink -f ~/.config/opencode/oh-my-openagent.json` → must resolve to `/home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json`. If the symlink was replaced by a plain file, re-link: `ln -sf /home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json ~/.config/opencode/oh-my-openagent.json`
5. Re-run the Verification grep.

If reapplying by hand (no git): the three `prompt_append` texts are in this entry's Problem/Patch Description; append them to the `prometheus` and `oracle` fields (string-concatenate with a `\n\n` separator) and add the `momus.prompt_append` field. Use `ensure_ascii=True, indent=2` + trailing newline to match the file's encoding (em-dashes as `\u2014`).

## Durable Alternative
This IS already a **configuration change** (the preferred durable path per the patch-tracker nudge — not a binary/source patch). Git-tracked + symlinked live.

**Long-term fix:** upstream the `prompt_append` defaults to `code-yeongyu/oh-my-openagent` so they ship with the OMO package and survive updates without a local patch entry. Status: **not-yet-pursued**. (The wording would need to be generalized past this machine's specific Prometheus/Momus/Oracle agent names if upstreamed.)
