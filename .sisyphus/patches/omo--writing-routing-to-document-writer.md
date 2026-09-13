---
patch_id: "omo--writing-routing-to-document-writer"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/agents/sisyphus/gpt-5-5.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-13"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "subagent_type=\"document-writer\""
runtime_effective: false
note: "Source patch (fork commit 87bae6856 + syntax repair 8c0f9963f, branch fix/custom-patches-v4.19.2) + config-layer description override on categories.writing (this repo, configs/oh-my-openagent/oh-my-openagent.json). Soft-deprecation: writing category stays defined-but-unrouted; docs route to the document-writer subagent. Evidence: ez-omo-bench ledger L034 (event EV016, 2026-09-12)."
---

# Sisyphus Docs Routing Repointed to document-writer Subagent

## Problem

The gpt-5-5.ts domain-guess row routed documentation, prose, and technical writing to the `writing` category. Bench ledger L034, with verdict event EV016 on 2026-09-12, shows the document-writer subagent is quality-equivalent, 0.996 versus 0.9863, and about ten times faster, about 65 seconds versus 65 to 790 seconds. The operator decided on 2026-09-12 that the subagent is the one routed door and the category remains dormant.

## Patch Description

Edit 1 repoints the line 104 row to the `document-writer` subagent via `task(subagent_type="document-writer")`. Edit 2 removes `writing` from the line 166 fallback enumeration. The changes are fork commits 87bae6856 and 8c0f9963f, the latter repairing backtick escaping with identical rendered text. The config layer adds a `categories.writing.description` deprecation override, which also rewrites the live GLM orchestrator's dynamic category row through `builtin-agents.ts` `AvailableCategory.description`.

## Verification

```bash
# Source (post-repair, escaped backticks): routing row at line 104 targets document-writer; no writing row remains.
grep -n 'Documentation, prose, technical writing' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/sisyphus/gpt-5-5.ts   # 1 hit, line 104, contains document-writer
grep -c 'subagent_type="document-writer"' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/sisyphus/gpt-5-5.ts   # 1
sed -n '166p' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/sisyphus/gpt-5-5.ts | grep -c writing   # 0
grep -rn 'technical writing' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/hephaestus/delegation-table-contract.test.ts   # no output (no test locks the old row)

# Rebuilt bundle after bun run build.
grep -c 'subagent_type="document-writer"' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js  # 1
bash /home/ezotoff/ez-omo-config/scripts/verify-live-patches.sh  # exit 0: 23 total | 22 applied | 1 acknowledged-drift pre-existing
```

## Runtime Verification

Pending Task 6 probe, a docs-task routing probe on live sisyphus. On PASS, flip `runtime_effective: true` and add `## Runtime Status` with the observation timestamp and probe session ID.

## Reapply Instructions

On the next-version patch branch, cherry-pick 87bae6856 and 8c0f9963f if the repair is not already an ancestor. Run `bun run build`, then re-apply the dist-level patches according to their own entries. Run `bash /home/ezotoff/ez-omo-config/scripts/verify-live-patches.sh` and require green output. For the config layer, restore the description override from the git history of `configs/oh-my-openagent/oh-my-openagent.json`.

## Durable Alternative

An upstream PR to code-yeongyu/oh-my-openagent could repoint the gpt-5-5.ts routing row to the document-writer pattern, using named subagents for specialist domains. Status: not-yet-pursued. This is follow-up work and out of scope here.
