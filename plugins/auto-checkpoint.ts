import { appendFileSync, mkdirSync } from "node:fs"
import { dirname } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"
import { Mutex } from "./kdco-primitives/mutex"

/**
 * Auto-Checkpoint Plugin — automatically creates git checkpoint commits
 * when sessions become idle or tasks complete.
 *
 * Design principles:
 * - Commits directly via git (no AI prompting)
 * - Quiescence-based: only commits when session tree appears quiet
 * - Non-blocking: errors are logged, never interrupt agent execution
 * - Deduplication: tracks last committed SHA to avoid empty commits
 *
 * Safety guards:
 * - Never commits if tree is clean
 * - Never commits during git operations (rebase, merge, cherry-pick)
 * - Skips if commit is already in flight (mutex)
 * - Debounces rapid-fire idle events
 */

// =============================================================================
// CONFIGURATION
// =============================================================================

const CONFIG = {
	/** Minimum idle time before considering a checkpoint (ms) */
	idleMs: 10_000,
	/** Minimum quiet time since last tool activity (ms) */
	quietMs: 5_000,
	/** Minimum time between checkpoints (ms) */
	cooldownMs: 30_000,
	/** Include untracked files in checkpoints */
	includeUntracked: true,
	/** Skip checkpoint if these git operations are in progress */
	skipGitOps: ["rebase", "merge", "cherry-pick"] as const,
} as const

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

interface SessionState {
	sessionId: string
	cwd: string
	parentId?: string
	childIds: Set<string>
	lastToolAt: number
	lastIdleAt: number
	lastCommitAt: number
	lastCommitSha?: string
	timer?: Timer
}

interface GitStatus {
	isDirty: boolean
	shortSha: string
	branch: string
}

type EventInput = {
	event: { type: string; properties?: Record<string, unknown> }
	sessionID: string
}

// =============================================================================
// LOGGING
// =============================================================================

const LOG_PATH = `${process.env.HOME}/.opencode/plugin/auto-checkpoint.log`

function log(level: string, message: string): void {
	const timestamp = new Date().toISOString()
	const line = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`
	try {
		mkdirSync(dirname(LOG_PATH), { recursive: true })
		appendFileSync(LOG_PATH, line)
	} catch {
		// intentionally swallowed
	}
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
	return result.ok && result.value === "true"
}

async function getGitStatus(cwd: string): Promise<Result<GitStatus, string>> {
	const [porcelainResult, branchResult, shaResult] = await Promise.all([
		git(["status", "--porcelain"], cwd),
		git(["branch", "--show-current"], cwd),
		git(["rev-parse", "--short", "HEAD"], cwd),
	])

	if (!porcelainResult.ok) return Result.err(porcelainResult.error)
	if (!branchResult.ok) return Result.err(branchResult.error)

	const isDirty = porcelainResult.value.length > 0
	const shortSha = shaResult.ok ? shaResult.value : "(no commits)"

	return Result.ok({
		isDirty,
		shortSha,
		branch: branchResult.value,
	})
}

async function isGitOperationInProgress(cwd: string): Promise<boolean> {
	const checks = await Promise.all([
		git(["rev-parse", "--git-path", "rebase-merge"], cwd),
		git(["rev-parse", "--git-path", "rebase-apply"], cwd),
		git(["rev-parse", "--git-path", "MERGE_HEAD"], cwd),
		git(["rev-parse", "--git-path", "CHERRY_PICK_HEAD"], cwd),
	])

	return checks.some((r) => r.ok && r.value.length > 0)
}

async function createCheckpointCommit(
	cwd: string,
	sessionTitle: string,
	sessionId: string,
): Promise<Result<string, string>> {
	const addArgs = CONFIG.includeUntracked
		? ["add", "-A"]
		: ["add", "-u"]

	const addResult = await git(addArgs, cwd)
	if (!addResult.ok) {
		return Result.err(`git add failed: ${addResult.error}`)
	}

	const timestamp = new Date().toISOString()
	const title = sessionTitle || "checkpoint"
	const message = `checkpoint(agent): ${title} [session=${sessionId.slice(0, 8)}] [${timestamp}]`

	const commitResult = await git(["commit", "-m", message], cwd)
	if (!commitResult.ok) {
		// "nothing to commit" is not an error
		if (commitResult.error.includes("nothing to commit")) {
			return Result.ok("no changes")
		}
		return Result.err(`git commit failed: ${commitResult.error}`)
	}

	return Result.ok(message)
}

// =============================================================================
// SESSION STATE MANAGEMENT
// =============================================================================

const sessions = new Map<string, SessionState>()
const worktreeMutexes = new Map<string, Mutex>()

function getWorktreeMutex(cwd: string): Mutex {
	let mutex = worktreeMutexes.get(cwd)
	if (!mutex) {
		mutex = new Mutex()
		worktreeMutexes.set(cwd, mutex)
	}
	return mutex
}

function getSession(sessionId: string, cwd: string): SessionState {
	let state = sessions.get(sessionId)
	if (!state) {
		state = {
			sessionId,
			cwd,
			childIds: new Set(),
			lastToolAt: 0,
			lastIdleAt: 0,
			lastCommitAt: 0,
		}
		sessions.set(sessionId, state)
	}
	return state
}

function hasActiveDescendants(sessionId: string): boolean {
	const state = sessions.get(sessionId)
	if (!state) return false

	for (const childId of state.childIds) {
		const child = sessions.get(childId)
		if (child) {
			// Consider a child "active" if it was idle recently
			const timeSinceIdle = Date.now() - child.lastIdleAt
			if (timeSinceIdle < CONFIG.idleMs * 2) {
				return true
			}
		}
	}
	return false
}

// =============================================================================
// CHECKPOINT EVALUATION
// =============================================================================

async function evaluateCheckpoint(
	sessionId: string,
	sessionTitle: string,
	clientApp: { log: (body: { service: string; level: string; message: string }) => Promise<void> },
): Promise<void> {
	const state = sessions.get(sessionId)
	if (!state) {
		log("debug", `evaluateCheckpoint: no state for session ${sessionId}`)
		return
	}

	const now = Date.now()

	// Guard: commit already in flight (checked via mutex later)
	// Guard: not idle long enough
	if (now - state.lastIdleAt < CONFIG.idleMs) {
		log("debug", `SKIP (not idle long enough) — session=${sessionId}`)
		return
	}

	// Guard: not quiet long enough
	if (now - state.lastToolAt < CONFIG.quietMs) {
		log("debug", `SKIP (not quiet long enough) — session=${sessionId}`)
		return
	}

	// Guard: has active descendant sessions
	if (hasActiveDescendants(sessionId)) {
		log("debug", `SKIP (has active descendants) — session=${sessionId}`)
		return
	}

	// Guard: cooldown
	if (now - state.lastCommitAt < CONFIG.cooldownMs) {
		log("debug", `SKIP (cooldown) — session=${sessionId}`)
		return
	}

	const cwd = state.cwd

	// Guard: not in git repo
	const inRepo = await isInGitRepo(cwd)
	if (!inRepo) {
		log("debug", `SKIP (not in git repo) — session=${sessionId}`)
		return
	}

	// Guard: git operation in progress
	if (await isGitOperationInProgress(cwd)) {
		log("info", `SKIP (git operation in progress) — session=${sessionId}`)
		return
	}

	// Get git status
	const statusResult = await getGitStatus(cwd)
	if (!statusResult.ok) {
		log("warn", `SKIP (git status failed) — ${statusResult.error}`)
		return
	}

	const status = statusResult.value

	// Guard: tree is clean
	if (!status.isDirty) {
		log("debug", `SKIP (tree clean) — session=${sessionId}`)
		return
	}

	// Guard: dedup — same SHA as last commit
	if (state.lastCommitSha && state.lastCommitSha === status.shortSha) {
		log("debug", `SKIP (dedup — same SHA) — session=${sessionId}`)
		return
	}

	// Acquire worktree mutex and commit
	const mutex = getWorktreeMutex(cwd)
	const committed = await mutex.runExclusive(async () => {
		log("info", `CHECKPOINT — session=${sessionId}, cwd=${cwd}, branch=${status.branch}`)
		
		const result = await createCheckpointCommit(cwd, sessionTitle, sessionId)
		
		if (result.ok) {
			state.lastCommitAt = now
			state.lastCommitSha = status.shortSha
			log("info", `COMMITTED — ${result.value}`)
			await clientApp.log({
				service: "auto-checkpoint",
				level: "info",
				message: `Checkpoint created: ${result.value}`,
			}).catch(() => {})
		} else {
			log("error", `COMMIT FAILED — ${result.error}`)
			await clientApp.log({
				service: "auto-checkpoint",
				level: "warn",
				message: `Checkpoint failed: ${result.error}`,
			}).catch(() => {})
		}
		
		return result.ok
	})

	if (committed) {
		log("info", `Checkpoint complete for session ${sessionId}`)
	}
}

// =============================================================================
// PLUGIN ENTRY
// =============================================================================

export const AutoCheckpointPlugin: Plugin = async (ctx) => {
	const { directory, client } = ctx

	const appLog = (level: "info" | "debug" | "warn" | "error", msg: string) =>
		client.app
			.log({ body: { service: "auto-checkpoint", level, message: msg } })
			.catch(() => {})

	appLog("info", "Auto-checkpoint plugin initialized")
	log("info", "Plugin initialized")

	return {
		// =================================================================
		// HOOK: event — session lifecycle events
		// =================================================================
		event: async (input: EventInput) => {
			const { event, sessionID } = input

			try {
				// session.created — register session
				if (event.type === "session.created") {
					const props = event.properties || {}
					const parentId = props.parentSessionId as string | undefined
					const cwd = (props.directory as string) || directory

					const state = getSession(sessionID, cwd)
					state.parentId = parentId

					// Link to parent if this is a subagent
					if (parentId) {
						const parent = sessions.get(parentId)
						if (parent) {
							parent.childIds.add(sessionID)
							log("info", `session.created — ${sessionID} (child of ${parentId})`)
						}
					} else {
						log("info", `session.created — ${sessionID} (root session)`)
					}
					return
				}

				// session.deleted — cleanup session
				if (event.type === "session.deleted") {
					const state = sessions.get(sessionID)
					if (state) {
						// Remove from parent's child set
						if (state.parentId) {
							const parent = sessions.get(state.parentId)
							if (parent) {
								parent.childIds.delete(sessionID)
							}
						}
						// Clear any pending timer
						if (state.timer) {
							clearTimeout(state.timer)
						}
						sessions.delete(sessionID)
						log("info", `session.deleted — ${sessionID}`)
					}
					return
				}

				// session.idle / session.status — schedule checkpoint evaluation
				if (event.type === "session.idle" || event.type === "session.status") {
					const state = sessions.get(sessionID)
					if (!state) {
						// Auto-register with default directory if not seen before
						getSession(sessionID, directory)
					}

					const sessionState = sessions.get(sessionID)
					if (sessionState) {
						sessionState.lastIdleAt = Date.now()

						// Clear existing timer
						if (sessionState.timer) {
							clearTimeout(sessionState.timer)
						}

						// Schedule debounced evaluation
						sessionState.timer = setTimeout(() => {
							const props = event.properties || {}
							const title = (props.title as string) || ""
							evaluateCheckpoint(sessionID, title, client.app)
						}, CONFIG.idleMs + CONFIG.quietMs)
					}
					return
				}
			} catch (err) {
				const errMsg = err instanceof Error ? err.message : String(err)
				log("error", `Unhandled error in event hook — ${errMsg}`)
			}
		},

		// =================================================================
		// HOOK: tool.execute.after — track tool completions
		// =================================================================
		"tool.execute.after": async (input, output) => {
			try {
				const state = sessions.get(input.sessionID)
				if (state) {
					state.lastToolAt = Date.now()
				}

				// For task() tool, register child session from metadata
				if (input.tool === "task") {
					const metadata = output.metadata as { sessionId?: string } | undefined
					if (metadata?.sessionId) {
						const childSessionId = metadata.sessionId
						const parentState = sessions.get(input.sessionID)
						if (parentState) {
							// Register child with parent's cwd (inherited directory)
							const childState = getSession(childSessionId, parentState.cwd)
							childState.parentId = input.sessionID
							parentState.childIds.add(childSessionId)
							log("info", `task launched — child=${childSessionId}, parent=${input.sessionID}`)
						}
					}
				}
			} catch (err) {
				const errMsg = err instanceof Error ? err.message : String(err)
				log("error", `Unhandled error in tool.execute.after — ${errMsg}`)
			}
		},
	}
}

export default AutoCheckpointPlugin
