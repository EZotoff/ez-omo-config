import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"

// =============================================================================
// TYPES
// =============================================================================

interface OkResult<T> {
	readonly ok: true
	readonly value: T
}
interface ErrResult<E> {
	readonly ok: false
	readonly error: E
}
type Result<T, E> = OkResult<T> | ErrResult<E>

const Result = {
	ok: <T>(value: T): OkResult<T> => ({ ok: true, value }),
	err: <E>(error: E): ErrResult<E> => ({ ok: false, error }),
}

interface GitStatusReport {
	branch: string
	shortSha: string
	modified: string[]
	staged: string[]
	untracked: string[]
	isDirty: boolean
}

// =============================================================================
// GIT MODULE
// =============================================================================

async function git(args: string[], cwd: string): Promise<Result<string, string>> {
	try {
		const proc = Bun.spawn(["git", ...args], {
			cwd,
			stdout: "pipe",
			stderr: "pipe",
		})
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(proc.stdout).text(),
			new Response(proc.stderr).text(),
			proc.exited,
		])
		if (exitCode !== 0) {
			return Result.err(stderr.trim() || `git ${args[0]} failed`)
		}
		return Result.ok(stdout.trim())
	} catch (error) {
		return Result.err(error instanceof Error ? error.message : String(error))
	}
}

async function isInGitRepo(cwd: string): Promise<boolean> {
	const result = await git(["rev-parse", "--is-inside-work-tree"], cwd)
	return result.ok
}

async function gitStatus(cwd: string): Promise<Result<GitStatusReport, string>> {
	const [porcelainResult, branchResult] = await Promise.all([
		git(["status", "--porcelain"], cwd),
		git(["branch", "--show-current"], cwd),
	])

	if (!porcelainResult.ok) return Result.err(porcelainResult.error)
	if (!branchResult.ok) return Result.err(branchResult.error)

	const shaResult = await git(["rev-parse", "--short", "HEAD"], cwd)
	const shortSha = shaResult.ok ? shaResult.value : "(no commits)"

	const modified: string[] = []
	const staged: string[] = []
	const untracked: string[] = []

	const lines = porcelainResult.value.split("\n").filter((l) => l.length > 0)
	for (const line of lines) {
		const indexStatus = line[0]
		const workTreeStatus = line[1]
		const filePath = line.slice(3)

		if (indexStatus === "M" || indexStatus === "A" || indexStatus === "D" || indexStatus === "R") {
			staged.push(filePath)
		}
		if (workTreeStatus === "M") {
			modified.push(filePath)
		}
		if (indexStatus === "?" && workTreeStatus === "?") {
			untracked.push(filePath)
		}
	}

	const isDirty = modified.length > 0 || staged.length > 0 || untracked.length > 0

	return Result.ok({
		branch: branchResult.value,
		shortSha,
		modified,
		staged,
		untracked,
		isDirty,
	})
}

async function gitStashPush(cwd: string, message: string): Promise<Result<string, string>> {
	return git(["stash", "push", "--include-untracked", "-m", message], cwd)
}

// =============================================================================
// DESTRUCTIVE COMMAND DETECTION
// =============================================================================

/**
 * Patterns matching destructive git commands that WILL discard uncommitted work.
 * Each pattern is paired with a human-readable description for error messages.
 */
const DESTRUCTIVE_PATTERNS: ReadonlyArray<{ pattern: RegExp; description: string }> = [
	{ pattern: /git\s+reset\s+--hard/, description: "git reset --hard" },
	{ pattern: /git\s+checkout\s+--\s/, description: "git checkout -- (discard changes)" },
	{ pattern: /git\s+checkout\s+\.\s*($|[;&|])/, description: "git checkout . (discard all changes)" },
	{ pattern: /git\s+restore\s+(?!--staged)/, description: "git restore (discard changes)" },
	{ pattern: /git\s+clean\b.*(-[a-zA-Z]*f|--force)/, description: "git clean -f/--force (delete untracked files)" },
	{ pattern: /git\s+stash\s+drop/, description: "git stash drop" },
	{ pattern: /git\s+checkout\s+\S+\s+--\s+\./, description: "git checkout <ref> -- . (overwrite all)" },
	{ pattern: /git\s+reset\s+HEAD\s+--hard/, description: "git reset HEAD --hard" },
	{ pattern: /git\s+checkout\s+(-f|--force)/, description: "git checkout --force" },
	{ pattern: /git\s+push\s+.*--force(?!-)/, description: "git push --force" },
	{ pattern: /git\s+push\s+.*-f\b/, description: "git push -f (force)" },
	{ pattern: /git\s+rebase\s+.*--force/, description: "git rebase --force" },
	{ pattern: /git\s+branch\s+-D\s/, description: "git branch -D (force delete)" },
]

function detectDestructiveCommand(command: string): { pattern: RegExp; description: string } | undefined {
	return DESTRUCTIVE_PATTERNS.find(({ pattern }) => pattern.test(command))
}

// =============================================================================
// NON-GIT DESTRUCTIVE COMMAND DETECTION
// =============================================================================

/**
 * Patterns matching non-git destructive commands that are ALWAYS blocked.
 * These don't require a dirty-tree check — they're dangerous regardless of git state.
 * Defense-in-depth: some are also blocked by opencode.json permission deny rules.
 */
const ALWAYS_BLOCK_PATTERNS: ReadonlyArray<{ pattern: RegExp; description: string }> = [
	// Bulk file deletion
	{ pattern: /\bfind\b.*\s-delete\b/, description: "find -delete (bulk file deletion)" },

	// Remote code execution via pipe-to-shell
	{ pattern: /\bcurl\b.*\|\s*(bash|sh|zsh)\b/, description: "curl piped to shell (remote code execution)" },
	{ pattern: /\bwget\b.*\|\s*(bash|sh|zsh)\b/, description: "wget piped to shell (remote code execution)" },

	// Docker persistent data destruction
	{ pattern: /\bdocker[\s-]compose\s+down\b.*(-v\b|--volumes\b)/, description: "docker compose down -v (persistent volume deletion)" },

	// Permission destruction
	{ pattern: /\bchmod\s+(-R\s+)?0{2,3}\b/, description: "chmod 000 (remove all permissions)" },
	{ pattern: /\bchmod\s+-R\s+777\b/, description: "chmod -R 777 (global write, security risk)" },

	// Low-level disk/filesystem destruction (defense-in-depth, also in opencode.json)
	{ pattern: /\bdd\b.*\bof=\/dev\/[a-z]/, description: "dd writing to block device" },
	{ pattern: /\bmkfs\b/, description: "mkfs (filesystem format)" },
	{ pattern: /\bshred\b/, description: "shred (secure file destruction)" },
	{ pattern: /\bwipefs\b/, description: "wipefs (filesystem signature wipe)" },
]

/**
 * Known-safe targets for `rm -rf` that agents commonly need during development.
 * If the rm -rf command targets ONLY these directories, it's allowed through.
 */
const RM_SAFE_CLEANUP_TARGETS =
	/\b(node_modules|dist|build|\.cache|__pycache__|\.next|\.nuxt|\.turbo|\.svelte-kit|\.parcel-cache|target|coverage|\.coverage|\.pytest_cache|\.mypy_cache|\.tox|\.venv|venv|\.eggs|tmp|\.tmp|temp|\.temp|\.sass-cache|\.eslintcache|\.angular)\b/

/**
 * Detects dangerous `rm -rf` commands.
 * Requires BOTH -r AND -f flags. Blocks catastrophic targets always,
 * allows known safe cleanup targets, blocks everything else.
 */
function detectDangerousRm(command: string): string | undefined {
	if (!/\brm\b/.test(command)) return undefined

	const hasRecursive = /\s(-[a-zA-Z]*r[a-zA-Z]*\b|--recursive\b)/.test(command)
	const hasForce = /\s(-[a-zA-Z]*f[a-zA-Z]*\b|--force\b)/.test(command)
	if (!hasRecursive || !hasForce) return undefined

	// Catastrophic targets — always block regardless of anything
	const CATASTROPHIC: ReadonlyArray<{ pattern: RegExp; description: string }> = [
		{ pattern: /\s\/(\s|$)/, description: "rm -rf / (root filesystem wipe)" },
		{ pattern: /\s~(\/?\s|\/?\s*$)/, description: "rm -rf ~ (home directory wipe)" },
		{ pattern: /\s\$HOME\b/, description: "rm -rf $HOME (home directory wipe)" },
		{ pattern: /\s\.\s*($|[;&|])/, description: "rm -rf . (project root wipe)" },
		{ pattern: /\s\*\s*($|[;&|])/, description: "rm -rf * (directory contents wipe)" },
		{ pattern: /\s\.\.(\/|\s|$)/, description: "rm -rf .. (parent directory wipe)" },
	]

	for (const { pattern, description } of CATASTROPHIC) {
		if (pattern.test(command)) return description
	}

	// Safe cleanup targets — allow through
	if (RM_SAFE_CLEANUP_TARGETS.test(command)) return undefined

	// Unrecognized target with rm -rf — block and require user approval
	return "rm -rf targeting unrecognized path (requires user approval)"
}

/**
 * Detects any non-git command that should be ALWAYS blocked.
 * Returns the description if blocked, undefined if allowed.
 */
function detectAlwaysBlockCommand(command: string): string | undefined {
	// Check explicit always-block patterns
	for (const { pattern, description } of ALWAYS_BLOCK_PATTERNS) {
		if (pattern.test(command)) return description
	}

	// Check rm -rf guard
	return detectDangerousRm(command)
}

// =============================================================================
// PLUGIN ENTRY
// =============================================================================

export const GitSafetyPlugin: Plugin = async (ctx) => {
	const { directory, client } = ctx

	const log = {
		debug: (msg: string) =>
			client.app.log({ body: { service: "git-safety", level: "debug", message: msg } }).catch(() => {}),
		info: (msg: string) =>
			client.app.log({ body: { service: "git-safety", level: "info", message: msg } }).catch(() => {}),
		warn: (msg: string) =>
			client.app.log({ body: { service: "git-safety", level: "warn", message: msg } }).catch(() => {}),
		error: (msg: string) =>
			client.app.log({ body: { service: "git-safety", level: "error", message: msg } }).catch(() => {}),
	}

	log.info("Command safety plugin initialized (BLOCKING mode) — git + filesystem protection")

	return {
		// =================================================================
		// TOOL: git_safety_check — proactive safety check for agents
		// =================================================================
		tool: {
			git_safety_check: tool({
				description:
					"Check git working tree state and assess safety before operations. Returns status of modified, staged, and untracked files with ownership assessment and recommended protective action.",
				args: {},
				async execute(_args, _toolCtx) {
					const inRepo = await isInGitRepo(directory)
					if (!inRepo) {
						return "Not inside a git repository. Git safety checks are unavailable."
					}

					const statusResult = await gitStatus(directory)
					if (!statusResult.ok) {
						return `Failed to get git status: ${statusResult.error}`
					}

					const status = statusResult.value
					const ownership = status.isDirty ? "user-owned (conservative)" : "clean"
					const timestamp = Math.floor(Date.now() / 1000)
					const stashMessage = `git-safety/pre-operation/${timestamp}`
					const stashCommand = `git stash push --include-untracked -m "${stashMessage}"`
					const recommendedAction = status.isDirty ? stashCommand : "none needed"

					const formatList = (files: string[]): string =>
						files.length > 0 ? files.map((f) => `  - ${f}`).join("\n") : "  none"

					const report = [
						"## Git Safety Report",
						"",
						`**Status**: ${status.isDirty ? "DIRTY - destructive commands will be BLOCKED" : "clean"}`,
						`**Branch**: ${status.branch}`,
						`**SHA**: ${status.shortSha}`,
						"",
						`**Modified files**:`,
						formatList(status.modified),
						"",
						`**Staged files**:`,
						formatList(status.staged),
						"",
						`**Untracked files**:`,
						formatList(status.untracked),
						"",
						`**Ownership**: ${ownership}`,
						`**Recommended action**: ${recommendedAction}`,
					]

					if (status.isDirty) {
						report.push(
							"",
							"**WARNING**: The git-safety plugin will BLOCK any destructive git command",
							"(reset --hard, checkout --, clean -f, push --force, etc.) while the tree is dirty.",
							"Stash or commit your changes first.",
						)
					}

					return report.join("\n")
				},
			}),
		},

		// =================================================================
		// HOOK: tool.execute.before — HARD BLOCK for destructive commands
		// Layer 1: Non-git always-block (no context needed)
		// Layer 2: Git-specific (dirty-tree conditional)
		// =================================================================
		"tool.execute.before": async (input, output) => {
			// Only intercept bash/terminal tools
			const toolName = input.tool
			let command: string | undefined

			if (toolName === "bash" || toolName === "terminal") {
				command = output.args.command as string | undefined
			} else if (toolName === "interactive_bash" || toolName === "tmux") {
				command = output.args.tmux_command as string | undefined
			}

			if (!command || typeof command !== "string") return

			// LAYER 1: Non-git always-block patterns (no context check needed)
			const alwaysBlockMatch = detectAlwaysBlockCommand(command)
			if (alwaysBlockMatch) {
				log.warn(`BLOCKING destructive command (always-block): ${alwaysBlockMatch}`)
				throw new Error(
					`[COMMAND SAFETY] BLOCKED: "${alwaysBlockMatch}"\n\n` +
					`Command: ${command}\n\n` +
					`This command pattern is classified as destructive and has been automatically blocked.\n` +
					`If you need to perform this operation, ASK THE USER for explicit approval.\n` +
					`Do NOT attempt to work around this safety block.`
				)
			}

			// LAYER 2: Git-specific destructive commands (require dirty-tree check)
			const match = detectDestructiveCommand(command)
			if (!match) return

			// It's destructive — now check if we're in a git repo with a dirty tree
			const inRepo = await isInGitRepo(directory)
			if (!inRepo) return

			const statusResult = await gitStatus(directory)
			if (!statusResult.ok) {
				log.error(`Failed to check git status during safety block: ${statusResult.error}`)
				// Fail CLOSED: if we can't verify the tree is clean, block the command
				throw new Error(
					`[GIT SAFETY] BLOCKED: "${match.description}" was attempted but git status check failed (${statusResult.error}). ` +
					`Cannot verify working tree is clean. Refusing to execute destructive command. ` +
					`Please check git status manually and resolve any issues before retrying.`
				)
			}

			const status = statusResult.value

			// Clean tree → allow destructive command
			if (!status.isDirty) {
				log.info(`Destructive command allowed (clean tree): ${match.description}`)
				return
			}

			// DIRTY TREE + DESTRUCTIVE COMMAND → auto-stash then BLOCK
			log.warn(`BLOCKING destructive command on dirty tree: ${command}`)

			// Attempt protective auto-stash before blocking
			const stashMessage = `git-safety/auto-stash/${new Date().toISOString()}`
			const stashResult = await gitStashPush(directory, stashMessage)

			const fileList = [
				...status.modified.map((f) => `  [modified] ${f}`),
				...status.staged.map((f) => `  [staged]   ${f}`),
				...status.untracked.map((f) => `  [new]      ${f}`),
			].join("\n")

			if (stashResult.ok) {
				log.info(`Auto-stash created before block: ${stashMessage}`)
				throw new Error(
					`[GIT SAFETY] BLOCKED: "${match.description}" was attempted while the working tree had uncommitted changes.\n\n` +
					`Protected files:\n${fileList}\n\n` +
					`A protective stash was automatically created: "${stashMessage}"\n` +
					`To recover: git stash pop\n\n` +
					`The working tree is now clean. If you still need to run this destructive command, ` +
					`you may retry it now — but the stash contains the user's work. ` +
					`ASK THE USER before dropping or overwriting the stash.\n\n` +
					`IMPORTANT: You MUST NOT run destructive git commands without explicit user approval ` +
					`when uncommitted changes exist. This is a hard safety constraint.`
				)
			} else {
				log.error(`Auto-stash FAILED: ${stashResult.error}`)
				throw new Error(
					`[GIT SAFETY] BLOCKED: "${match.description}" was attempted while the working tree had uncommitted changes.\n\n` +
					`Protected files:\n${fileList}\n\n` +
					`WARNING: Auto-stash FAILED (${stashResult.error}). The uncommitted work is still in the working tree ` +
					`and is NOT protected by a stash.\n\n` +
					`DO NOT retry the destructive command. Ask the user to manually save their work first.\n\n` +
					`IMPORTANT: You MUST NOT run destructive git commands without explicit user approval ` +
					`when uncommitted changes exist. This is a hard safety constraint.`
				)
			}
		},
	}
}

export default GitSafetyPlugin
