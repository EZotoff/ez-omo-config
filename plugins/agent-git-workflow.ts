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
 * working in the same repo: when to branch, when to sync, how to handle
 * merge conflicts.
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

### Branch lifecycle
Short-lived agent branches are disposable. When the logical unit is complete:
\`\`\`
git checkout master
git merge --no-ff <branch>   # preserve the branch's commits as a group
git branch -D <branch>
\`\`\`
Push to remote only when explicitly authorized by the user.

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
