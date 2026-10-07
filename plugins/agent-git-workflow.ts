/**
 * Agent Git Workflow Plugin
 *
 * Injects a parallel-agent git coordination procedure on every session
 * (root + subagent, all agents, all models) via experimental.chat.system.transform.
 *
 * Why: the commit-policy patches (opencode--commit-policy-unblock,
 * omo--commit-policy-alignment) removed the "never commit without asking"
 * block, and the auto-checkpoint plugin provides idle-timeout safety-net
 * commits. Neither tells the agent HOW to coordinate with other agents
 * Neither tells the agent HOW to coordinate with other agents
 * working in the same repo: when to branch, when to sync, how to handle
 * merge conflicts, or how to reclaim worktrees/branches when the unit is
 * done (allocation is automated; reclamation must be too, or worktrees leak).
 * Nor did either say WHEN pushing is pre-authorized: a bare "ask first"
 * gate (pre-2026-10-05) stranded 100+ unpushed commits per active repo.
 * Push is backup; authorization is pre-granted by remote ownership +
 * branch class (tiers below, amended 2026-10-05).
 *
 * Attribution (author identity, co-author trailers, footers) is intentionally
 * NOT handled here — owned by the active Git config and OMO git_master setting.
 *
 * This plugin supplies that procedure. It is intentionally short (hot path
 * — fires once per LLM round-trip per session) and concrete (reflexes with
 * exact commands, not abstract principles).
 *
 * Hook: experimental.chat.system.transform — mutates output.system (string[])
 * before it is sent to the LLM. Fail-open: a throw is caught by the plugin host.
 */

import type { Plugin } from "@opencode-ai/plugin"

const INSTRUCTION = `## Agent Git Workflow (parallel-agent coordination)

You operate in a multi-agent environment where other agents (Sisyphus, atlas, sisyphus-junior, etc.) may edit the same repo concurrently. History is for AGENT parsing, not human aesthetics — commits are cheap, merge conflicts are expected, and you resolve them directly without asking.

### Commit reflex
After every logical unit of work (bug fixed, refactor step done, feature slice complete, tests written for a change, file moved/renamed): stage explicit paths and commit immediately. Do NOT ask — your base prompt grants explicit permission. Do NOT bundle unrelated changes into one commit. Do NOT wait for auto-checkpoint; it is a safety net, not the primary history.

### Commit format
- Subject: \`type(scope): subject\` — Conventional Commits, lowercase type and scope, imperative mood, ≤72 chars. Examples: \`feat(retry): detect near-empty completions\`, \`fix(worktree): portable timeout\`, \`refactor(wisdom): route date through portable helper\`.
- Do NOT override commit identity (\`-c user.name\`, \`-c user.email\`) or add attribution metadata (co-author trailers, \`Session:\` trailers, footers, agent tags). Commit author and attribution are governed by the active Git configuration and git-master policy — leave them alone.
- Example: \`git commit -m "fix(retry): handle null tokens"\`

### Branching reflex (parallel isolation)
At the start of any non-trivial work (3+ tool calls expected) in a tracked repo, detect concurrent agent activity:
\`\`\`
git log --since='2 hours ago' --all --oneline
git branch -a
\`\`\`
- If another agent's recent commits or branches touch files you will edit → create a branch:
  \`git checkout -b agent/<your-agent-name>/<task-scope>\`
  Example: \`git checkout -b agent/sisyphus/retry-empty-detect\`
- Otherwise (solo work, no overlap) → working on master/trunk is fine.

### Sync protocol (avoid stale-base conflicts)
If your branch is older than 30 minutes, before any non-trivial edit batch:
\`\`\`
git fetch
git rebase origin/master   # or: git merge origin/master — your call
\`\`\`
Resolve any conflicts directly without asking. Never commit conflict markers (\`<<<<<<<\`, \`=======\`, \`>>>>>>>\`).

### Branch lifecycle (worktree-aware)
Short-lived agent branches are disposable. When the logical unit is complete, merge AND reclaim — a worktree left behind is leaked work, not a safety net:
\`\`\`
# from the MAIN repo worktree — never from inside the worktree being reclaimed:
git merge --no-ff <branch>        # preserve the branch's commits as a group
git worktree remove <path>        # REQUIRED before branch delete (git refuses to delete a checked-out branch)
git branch -d <branch>            # lowercase -d ONLY (merged-safe); -D is blocked by git-safety
\`\`\`
If the branch lives in a worktree, prefer the \`worktree_delete\` tool (optionally with a \`target\`) — it runs pre-delete hooks (port freeing, state cleanup) and snapshots uncommitted changes before removal.
If a completed worktree is dirty: diff it against master first, port unique work into the merge or a branch, THEN remove — never silently discard uncommitted work. If the work is genuinely worthless, say so explicitly in the final report instead.
Plain in-repo branches (no worktree): \`git checkout master && git merge --no-ff <branch> && git branch -d <branch>\`.

### Push discipline (tiered, standing authorization)
Push is backup — the operator PRE-AUTHORIZES pushes by remote ownership + branch class (2026-10-05). Do not ask per-push; do report what you pushed in your final report.

- **Tier A — pre-authorized**: remotes the operator owns (URL owner matches the operator's GitHub account, e.g. \`EZotoff/*\`). Push \`agent/*\` and \`type/scope\` branches freely; push \`master\`/\`main\` only when fast-forwardable. A rejected non-fast-forward push means the branch diverged — report it, never force.
- **Tier B — fork-only**: remotes owned by others (collaborator/upstream repos). Push agent branches to the operator's fork remote only; never push \`master\`/\`main\` to a remote the operator doesn't own.
- **NEVER**: force-push (blocked by git-safety anyway); pushing secrets — \`auth.json\` and machine-local keys stay local.
- **No remote?** Flag it in your final report ("commits here are machine-local — one disk failure from loss") instead of silently accumulating.
- **Session-end rule**: after your final merge in any repo you worked in, push (Tier A/B) or state the unpushed commit count explicitly in your final report. Unpushed work that survives only on this machine is incomplete work.

### Out of scope (handled elsewhere)
- **Idle-timeout safety-net commits**: auto-checkpoint plugin handles these (every ~5 min with \`checkpoint(agent):\` prefix). Don't duplicate.
- **Multi-agent worktree orchestration** (one coordinator spawning many workers): use the \`parallel-dev\` skill.
- **Complex merges with state tracking and rollback**: use the \`merge-agent\` skill.`

const AgentGitWorkflowPlugin: Plugin = async () => {
	return {
		"experimental.chat.system.transform": async (_input, output) => {
			if (Array.isArray(output.system)) {
				output.system.push(INSTRUCTION)
			}
		},
	}
}

export default AgentGitWorkflowPlugin
