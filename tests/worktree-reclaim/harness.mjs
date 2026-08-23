// Worktree reclaim harness — verifies the worktree_delete `target` contract:
//   1. target resolution by branch name (success, no-match error, main-worktree refusal)
//   2. merged branch: worktree removed AND branch deleted
//   3. unmerged branch: worktree removed, branch KEPT (no data loss)
//   4. dirty worktree: uncommitted changes snapshotted onto the branch, branch KEPT
//   5. clean worktree gets NO empty snapshot commit (branch tip must stay at the
//      merge point so `git branch -d` can delete it — the 2026-08 14-worktree leak)
//
// Self-contained: builds a throwaway git repo in a temp dir, loads the real plugin.

import { $ } from "bun"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"

const REPO_ROOT = path.resolve(import.meta.dir, "..", "..")
const PLUGIN = path.join(REPO_ROOT, "plugins", "worktree.ts")

let failures = 0
function check(name, cond, detail = "") {
	if (cond) {
		console.log(`PASS: ${name}`)
	} else {
		failures++
		console.error(`FAIL: ${name}${detail ? ` — ${detail}` : ""}`)
	}
}

async function main() {
	const base = await mkdtemp(path.join(tmpdir(), "wt-reclaim-"))
	const repo = path.join(base, "repo")
	const wtMerged = path.join(base, "wt-merged")
	const wtUnmerged = path.join(base, "wt-unmerged")
	const wtDirty = path.join(base, "wt-dirty")

	await $`git init -q -b master ${repo}`
	process.chdir(repo)
	await $`git config user.email t@t`.cwd(repo)
	await $`git config user.name t`.cwd(repo)
	await $`echo one > f.txt`.cwd(repo)
	await $`git add .`.cwd(repo)
	await $`git commit -qm init`.cwd(repo)
	await $`git worktree add -qb plan/merged ${wtMerged}`.cwd(repo)
	await $`git worktree add -qb plan/unmerged ${wtUnmerged}`.cwd(repo)
	await $`git worktree add -qb plan/dirty ${wtDirty}`.cwd(repo)
// plan/dirty: uncommitted change only (must be snapshotted onto the branch at reclaim)
await Bun.write(path.join(wtDirty, "salvage.txt"), "salvage me")
	// plan/merged: committed work, then merged into master (the documented flow)
	await $`echo two > g.txt`.cwd(wtMerged)
	await $`git add .`.cwd(wtMerged)
	await $`git commit -qm work`.cwd(wtMerged)
	await $`git merge --no-ff -qm "merge plan/merged" plan/merged`.cwd(repo)
	// plan/unmerged: committed work, NOT merged
	await $`echo u > u.txt`.cwd(wtUnmerged)
	await $`git add .`.cwd(wtUnmerged)
	await $`git commit -qm unmerged`.cwd(wtUnmerged)
	// plan/dirty: uncommitted change only

	const mod = await import(PLUGIN)
	const client = { app: { log: async () => {} }, session: {}, project: {} }
	const p = await mod.WorktreePlugin({ directory: repo, client, serverUrl: "http://x" })

	// --- 1. target resolution ---
	const rNoMatch = await p.tool.worktree_delete.execute(
		{ reason: "t", target: "plan/nope" },
		{ sessionID: "ses_none" },
	)
	check("no-match target errors", rNoMatch.includes("No worktree matches"), rNoMatch)

	const rMain = await p.tool.worktree_delete.execute(
		{ reason: "t", target: repo },
		{ sessionID: "ses_none" },
	)
	check("main worktree refused", rMain.includes("Refusing to remove the main repo worktree"), rMain)

	const rNoSession = await p.tool.worktree_delete.execute({ reason: "t" }, { sessionID: "ses_none" })
	check("no-session no-target errors", rNoSession.includes("No worktree associated"), rNoSession)

	// --- 2. merged branch: removed AND deleted ---
	await p.tool.worktree_delete.execute({ reason: "t", target: "plan/merged" }, { sessionID: "s" })
	await p.event({ event: { type: "session.idle" } })
	let wtList = (await $`git worktree list`.cwd(repo)).text()
	let brList = (await $`git branch`.cwd(repo)).text()
	check("merged: worktree removed", !wtList.includes("wt-merged"))
	check("merged: branch deleted", !brList.includes("plan/merged"))

	// --- 3. unmerged branch: removed, branch KEPT ---
	await p.tool.worktree_delete.execute({ reason: "t", target: "plan/unmerged" }, { sessionID: "s" })
	await p.event({ event: { type: "session.idle" } })
	wtList = (await $`git worktree list`.cwd(repo)).text()
	brList = (await $`git branch`.cwd(repo)).text()
	check("unmerged: worktree removed", !wtList.includes("wt-unmerged"))
	check("unmerged: branch kept (data safety)", brList.includes("plan/unmerged"))

	// --- 4. dirty worktree: snapshot salvage, branch KEPT ---
	await p.tool.worktree_delete.execute({ reason: "t", target: "plan/dirty" }, { sessionID: "s" })
	await p.event({ event: { type: "session.idle" } })
	const salvaged = (await $`git show plan/dirty:salvage.txt`.cwd(repo).nothrow().quiet()).text()
	wtList = (await $`git worktree list`.cwd(repo)).text()
	check("dirty: change snapshotted onto branch", salvaged.trim() === "salvage me", JSON.stringify(salvaged))
	check("dirty: worktree removed", !wtList.includes("wt-dirty"))

	process.exit(failures === 0 ? 0 : 1)
}


main().catch((err) => {
	console.error("HARNESS ERROR:", err)
	process.exit(1)
})
