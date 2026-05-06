/**
 * Vera Runtime Plugin
 *
 * Manages per-workspace Vera watcher state under the worktree-state directory.
 * Fail-open: silently no-ops if the vera binary or skill is unavailable.
 */

import * as crypto from "node:crypto"
import {
	appendFileSync,
	mkdirSync,
	readFileSync,
	renameSync,
	unlinkSync,
	writeFileSync,
} from "node:fs"
import { basename, dirname } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

export interface VeraWatcherState {
	workspaceKey: string
	workspacePath: string
	projectId: string
	pid: number | null
	status: "indexed" | "running" | "stale" | "stopped" | "missing-binary" | "index-failed" | "watch-failed"
	sessionIds: string[]
	indexPath: string
	watchLogPath: string
	lastIndexedAt: string | null
	startedAt: string | null
	lastVerifiedAt: string | null
	lastFailureAt: string | null
	lastFailureReason: string | null
	restartAttempts?: number
	lastRestartAttemptAt?: string | null
	hygieneStatus?: string | null
	lastHygieneCheckAt?: string | null
}

const STATE_BASE = `${process.env.HOME}/.local/share/opencode/worktree-state`
const LOG_PATH = `${process.env.HOME}/.opencode/plugin/vera-runtime.log`
const STALENESS_MS = 5 * 60 * 1000
const HEALTH_CHECK_INTERVAL_MS = 60 * 1000
const KILL_WAIT_SECONDS = 5
const MAX_RESTART_ATTEMPTS = 3
const RESTART_WINDOW_MS = 10 * 60 * 1000
const watcherStateWriteLocks = new Set<string>()
const healthCheckTimers = new Map<string, ReturnType<typeof setInterval>>()

function veraAvailable(): boolean {
	try {
		const proc = Bun.spawnSync(["bash", "-c", "command -v vera"])
		return proc.success && proc.stdout.toString().trim().length > 0
	} catch {
		return false
	}
}

function log(level: string, message: string): void {
	const timestamp = new Date().toISOString()
	const line = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`
	try {
		mkdirSync(dirname(LOG_PATH), { recursive: true })
		appendFileSync(LOG_PATH, line)
	} catch {
		/* intentionally swallowed */
	}
}

function computeProjectId(): string {
	try {
		const proc = Bun.spawnSync([
			"bash",
			"-c",
			'git rev-parse --show-toplevel 2>/dev/null | xargs basename',
		])
		if (proc.success) {
			const id = proc.stdout.toString().trim()
			if (id) return id
		}
	} catch {
		/* intentionally ignored */
	}
	return "unknown-project"
}

function computeWorkspaceKey(workspacePath: string): string {
	try {
		const proc = Bun.spawnSync(["realpath", workspacePath])
		const real = proc.success ? proc.stdout.toString().trim() : workspacePath
		const base = basename(real)
		const hash = crypto.createHash("sha1").update(real).digest("hex").slice(0, 8)
		return `${base}-${hash}`
	} catch {
		const base = basename(workspacePath)
		const hash = crypto.createHash("sha1").update(workspacePath).digest("hex").slice(0, 8)
		return `${base}-${hash}`
	}
}

function getWatchersDir(): string {
	const projectId = computeProjectId()
	return `${STATE_BASE}/${projectId}/vera-watchers`
}

function getStateFilePath(workspacePath: string): string {
	const key = computeWorkspaceKey(workspacePath)
	return `${getWatchersDir()}/${key}.json`
}

function getLogPath(workspacePath: string): string {
	const key = computeWorkspaceKey(workspacePath)
	return `${getWatchersDir()}/${key}.log`
}

function readWatcherState(workspacePath: string): VeraWatcherState | null {
	const path = getStateFilePath(workspacePath)
	try {
		const raw = readFileSync(path, "utf-8")
		return JSON.parse(raw) as VeraWatcherState
	} catch {
		return null
	}
}

function writeWatcherState(workspacePath: string, state: VeraWatcherState): void {
	const path = getStateFilePath(workspacePath)
	if (watcherStateWriteLocks.has(path)) {
		log("debug", `[${workspacePath}] writeWatcherState: write lock already held, skipping`)
		return
	}

	const tempPath = `${path}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`
	try {
		watcherStateWriteLocks.add(path)
		mkdirSync(dirname(path), { recursive: true })
		writeFileSync(tempPath, JSON.stringify(state, null, 2), "utf-8")
		renameSync(tempPath, path)
	} catch {
		try {
			unlinkSync(tempPath)
		} catch {
			/* intentionally swallowed */
		}
		/* best-effort: silently ignore write failures */
	} finally {
		watcherStateWriteLocks.delete(path)
	}
}

function createInitialState(workspacePath: string): VeraWatcherState {
	const workspaceKey = computeWorkspaceKey(workspacePath)
	return {
		workspaceKey,
		workspacePath,
		projectId: computeProjectId(),
		pid: null,
		status: "stopped",
		sessionIds: [],
		indexPath: `${workspacePath}/.vera`,
		watchLogPath: getLogPath(workspacePath),
		lastIndexedAt: null,
		startedAt: null,
		lastVerifiedAt: null,
		lastFailureAt: null,
		lastFailureReason: null,
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null
}

function getString(record: Record<string, unknown>, key: string): string | null {
	const value = record[key]
	return typeof value === "string" ? value : null
}

function extractSessionId(input: unknown): string {
	if (!isRecord(input)) {
		return ""
	}

	const directProperties = isRecord(input.properties) ? input.properties : null
	const eventRecord = isRecord(input.event) ? input.event : null
	const eventProperties = eventRecord && isRecord(eventRecord.properties) ? eventRecord.properties : null
	const props = directProperties ?? eventProperties ?? input

	return getString(props, "session_id") ?? getString(props, "sessionId") ?? getString(props, "id") ?? ""
}

function isPidAlive(pid: number): boolean {
	try {
		const proc = Bun.spawnSync(["bash", "-c", `kill -0 ${pid} 2>/dev/null`])
		return proc.success === true
	} catch {
		return false
	}
}

function validatePidOwnership(pid: number, workspacePath: string): boolean {
	try {
		const cmdline = readFileSync(`/proc/${pid}/cmdline`, "utf-8").replace(/\0/g, " ").trim()
		if (!cmdline) return false

		const hasVeraWatch = cmdline.includes("vera watch") || (cmdline.includes("vera") && cmdline.includes("watch"))
		const hasWorkspacePath = cmdline.includes(workspacePath)
		return hasVeraWatch && hasWorkspacePath
	} catch {
		return false
	}
}

function isVeraIndexNonEmpty(workspacePath: string): boolean {
	try {
		log("info", `[${workspacePath}] Checking vera index non-empty`)
		const proc = Bun.spawnSync(["vera", "overview"], {
			cwd: workspacePath,
			stdout: "pipe",
			stderr: "pipe",
		})
		if (!proc.success) {
			log("warn", `[${workspacePath}] vera overview failed`)
			return false
		}
		const output = proc.stdout.toString()
		const filesMatch = output.match(/Files:\s*(\d+)/)
		const chunksMatch = output.match(/Chunks:\s*(\d+)/)
		if (!filesMatch || !chunksMatch) {
			log("warn", `[${workspacePath}] vera overview parse failure`)
			return false
		}
		const files = parseInt(filesMatch[1], 10)
		const chunks = parseInt(chunksMatch[1], 10)
		const nonEmpty = files > 0 && chunks > 0
		log("info", `[${workspacePath}] index non-empty=${nonEmpty} (files=${files}, chunks=${chunks})`)
		return nonEmpty
	} catch (err) {
		const reason = err instanceof Error ? err.message : String(err)
		log("error", `[${workspacePath}] isVeraIndexNonEmpty exception: ${reason}`)
		return false
	}
}

function runVeraHygieneCheck(workspacePath: string): boolean {
	const scriptPath = `${process.env.HOME}/.sisyphus/scripts/vera-hygiene.sh`
	try {
		log("info", `[${workspacePath}] hygiene check`)
		const proc = Bun.spawnSync(["bash", scriptPath, "--project", workspacePath, "--check"], {
			stdout: "pipe",
			stderr: "pipe",
		})
		if (proc.success) {
			log("info", `[${workspacePath}] hygiene check passed`)
			return true
		}
		const err = proc.stderr?.toString().trim() || "hygiene check failed"
		log("warn", `[${workspacePath}] hygiene check failed: ${err}`)
		return false
	} catch (err) {
		const reason = err instanceof Error ? err.message : String(err)
		log("warn", `[${workspacePath}] hygiene check unavailable (${scriptPath}): ${reason}`)
		return false
	}
}

function canAttemptRestart(state: VeraWatcherState): boolean {
	const now = Date.now()
	const attempts = state.restartAttempts ?? 0
	const lastAttempt = state.lastRestartAttemptAt ? new Date(state.lastRestartAttemptAt).getTime() : 0
	if (attempts >= MAX_RESTART_ATTEMPTS && lastAttempt && now - lastAttempt < RESTART_WINDOW_MS) {
		log("warn", `[${state.workspacePath}] restart cooldown: attempts=${attempts}, last=${state.lastRestartAttemptAt}`)
		return false
	}
	if (lastAttempt && now - lastAttempt >= RESTART_WINDOW_MS) {
		state.restartAttempts = 0
	}
	return true
}

function recordRestartAttempt(state: VeraWatcherState): void {
	state.restartAttempts = (state.restartAttempts ?? 0) + 1
	state.lastRestartAttemptAt = new Date().toISOString()
}

function resetRestartAttempts(state: VeraWatcherState): void {
	state.restartAttempts = 0
	state.lastRestartAttemptAt = null
}

function runVeraIndex(workspacePath: string): boolean {
	try {
		log("info", `[${workspacePath}] Running vera index .`)
		const proc = Bun.spawnSync(["vera", "index", "."], {
			cwd: workspacePath,
			stdout: "pipe",
			stderr: "pipe",
		})
		if (proc.success) {
			log("info", `[${workspacePath}] vera index . succeeded`)
			return true
		}
		const err = proc.stderr?.toString().trim() || "unknown error"
		log("error", `[${workspacePath}] vera index . failed: ${err}`)
		return false
	} catch (err) {
		const reason = err instanceof Error ? err.message : String(err)
		log("error", `[${workspacePath}] vera index . exception: ${reason}`)
		return false
	}
}

function startVeraWatch(workspacePath: string): { pid: number } | null {
	try {
		log("info", `[${workspacePath}] Starting vera watch ${workspacePath}`)
		const proc = Bun.spawn(["vera", "watch", workspacePath], {
			cwd: workspacePath,
			stdout: "inherit",
			stderr: "inherit",
		})
		const pid = proc.pid
		if (!pid) {
			log("error", `[${workspacePath}] vera watch ${workspacePath} spawned but no pid returned`)
			return null
		}
		log("info", `[${workspacePath}] watcher started pid=${pid}`)
		return { pid }
	} catch (err) {
		const reason = err instanceof Error ? err.message : String(err)
		log("error", `[${workspacePath}] vera watch . exception: ${reason}`)
		return null
	}
}

function runVeraUpdate(workspacePath: string): boolean {
	try {
		log("info", `[${workspacePath}] Running vera update .`)
		const proc = Bun.spawnSync(["vera", "update", "."], {
			cwd: workspacePath,
			stdout: "pipe",
			stderr: "pipe",
		})
		if (proc.success) {
			log("info", `[${workspacePath}] vera update . succeeded`)
			return true
		}
		const err = proc.stderr?.toString().trim() || "unknown error"
		log("error", `[${workspacePath}] vera update . failed: ${err}`)
		return false
	} catch (err) {
		const reason = err instanceof Error ? err.message : String(err)
		log("error", `[${workspacePath}] vera update . exception: ${reason}`)
		return false
	}
}

function performSafeRestart(workspacePath: string, state: VeraWatcherState): boolean {
	if (!canAttemptRestart(state)) {
		state.status = "watch-failed"
		state.lastFailureAt = new Date().toISOString()
		state.lastFailureReason = `Restart limit reached (${MAX_RESTART_ATTEMPTS} attempts in ${RESTART_WINDOW_MS / 60000} minutes). Run vera-hygiene --apply if blockers persist.`
		writeWatcherState(workspacePath, state)
		log("error", `[${workspacePath}] safe restart aborted: limit reached`)
		return false
	}

	recordRestartAttempt(state)

	if (!isVeraIndexNonEmpty(workspacePath)) {
		const hygienePassed = runVeraHygieneCheck(workspacePath)
		state.hygieneStatus = hygienePassed ? "passed" : "failed"
		state.lastHygieneCheckAt = new Date().toISOString()

		if (!hygienePassed) {
			state.status = "index-failed"
			state.lastFailureAt = new Date().toISOString()
			state.lastFailureReason = "Vera index is hollow/has blockers. Run vera-hygiene --apply to resolve."
			writeWatcherState(workspacePath, state)
			log("error", `[${workspacePath}] safe restart aborted: hollow index with hygiene blockers`)
			return false
		}

		const indexed = runVeraIndex(workspacePath)
		if (!indexed) {
			state.status = "index-failed"
			state.lastFailureAt = new Date().toISOString()
			state.lastFailureReason = "vera index . failed during safe restart"
			writeWatcherState(workspacePath, state)
			log("error", `[${workspacePath}] safe restart aborted: vera index failed`)
			return false
		}
		state.lastIndexedAt = new Date().toISOString()
	}

	const watchResult = startVeraWatch(workspacePath)
	if (!watchResult) {
		state.status = "watch-failed"
		state.lastFailureAt = new Date().toISOString()
		state.lastFailureReason = "vera watch . failed to start during safe restart"
		writeWatcherState(workspacePath, state)
		log("error", `[${workspacePath}] safe restart aborted: vera watch failed`)
		return false
	}

	state.pid = watchResult.pid
	state.status = "running"
	state.startedAt = new Date().toISOString()
	state.lastVerifiedAt = new Date().toISOString()
	state.lastFailureAt = null
	state.lastFailureReason = null
	resetRestartAttempts(state)
	writeWatcherState(workspacePath, state)
	log("info", `[${workspacePath}] safe restart succeeded pid=${state.pid}`)
	return true
}

const VeraRuntimePlugin: Plugin = async (ctx) => {
	const { directory } = ctx

	if (!veraAvailable()) {
		log("error", "[vera-runtime] Vera binary not found; plugin disabled (fail-open).")
		log("warn", `Vera binary not found for ${directory}; plugin disabled`)
		try {
			let state = readWatcherState(directory)
			if (!state) {
				state = createInitialState(directory)
			}
			state.status = "missing-binary"
			state.lastFailureAt = new Date().toISOString()
			state.lastFailureReason = "vera binary not available"
			writeWatcherState(directory, state)
		} catch {
			/* fail-open */
		}
		return {}
	}

	log("info", `Vera runtime plugin initialized for ${directory}`)

	const existingTimer = healthCheckTimers.get(directory)
	if (existingTimer) {
		clearInterval(existingTimer)
		healthCheckTimers.delete(directory)
		log("debug", `[${directory}] Cleared existing health check timer before re-init`)
	}

	// -----------------------------------------------------------------
	// Health check loop
	// -----------------------------------------------------------------
	const healthCheckTimer = setInterval(() => {
		try {
			const state = readWatcherState(directory)
			if (!state) return
			if (state.status !== "running") return
			if (state.sessionIds.length === 0) return
			if (!state.pid) return

			const alive = isPidAlive(state.pid)
			const owned = alive ? validatePidOwnership(state.pid, directory) : false
			if (alive && owned) {
				state.lastVerifiedAt = new Date().toISOString()
				resetRestartAttempts(state)
				writeWatcherState(directory, state)
				log("debug", `[${directory}] health check pid=${state.pid} alive`)
			} else {
				log("warn", `[${directory}] health check: pid=${state.pid} ${alive ? "unowned" : "dead"}, attempting safe restart`)
				const restarted = performSafeRestart(directory, state)
				if (!restarted) {
					log("error", `[${directory}] health check: safe restart failed, status=${state.status}`)
				}
			}
		} catch (err) {
			const reason = err instanceof Error ? err.message : String(err)
			log("error", `[${directory}] Health check loop error: ${reason}`)
		}
	}, HEALTH_CHECK_INTERVAL_MS)
	healthCheckTimers.set(directory, healthCheckTimer)

	return {
		// =============================================================
		// session.created — bootstrap vera watcher for this workspace
		// =============================================================
		"session.created": (_input, _output) => {
			const sessionId = extractSessionId(_input)
			if (!sessionId) {
				log("warn", `[${directory}] session.created: no sessionId extracted`)
			}

			try {
				let state = readWatcherState(directory)
				if (!state) {
					state = createInitialState(directory)
				}

				if (sessionId && !state.sessionIds.includes(sessionId)) {
					state.sessionIds.push(sessionId)
				}

				log("info", `[${directory}] session.created`)

				const needsBootstrap =
					state.status === "stopped" ||
					state.status === "missing-binary" ||
					state.status === "index-failed" ||
					state.status === "watch-failed" ||
					!state.status

				if (needsBootstrap) {
					if (!veraAvailable()) {
						state.status = "missing-binary"
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = "vera binary not available"
						writeWatcherState(directory, state)
						log("warn", `[${directory}] session.created: vera not available, status=missing-binary`)
						return
					}

					const indexed = runVeraIndex(directory)
					if (!indexed) {
						state.status = "index-failed"
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = "vera index . failed"
						writeWatcherState(directory, state)
						log("error", `[${directory}] session.created: vera index failed`)
						return
					}
					state.lastIndexedAt = new Date().toISOString()

					if (!isVeraIndexNonEmpty(directory)) {
						const hygienePassed = runVeraHygieneCheck(directory)
						state.hygieneStatus = hygienePassed ? "passed" : "failed"
						state.lastHygieneCheckAt = new Date().toISOString()
						if (!hygienePassed) {
							state.status = "index-failed"
							state.lastFailureAt = new Date().toISOString()
							state.lastFailureReason = "Vera index is hollow/has blockers. Run vera-hygiene --apply to resolve."
							writeWatcherState(directory, state)
							log("error", `[${directory}] session.created: hollow index with hygiene blockers`)
							return
						}
						const reindexed = runVeraIndex(directory)
						if (!reindexed || !isVeraIndexNonEmpty(directory)) {
							state.status = "index-failed"
							state.lastFailureAt = new Date().toISOString()
							state.lastFailureReason = "vera index . still hollow after hygiene and reindex"
							writeWatcherState(directory, state)
							log("error", `[${directory}] session.created: index still hollow after reindex`)
							return
						}
						state.lastIndexedAt = new Date().toISOString()
					}

					const watchResult = startVeraWatch(directory)
					if (!watchResult) {
						state.status = "watch-failed"
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = "vera watch . failed to start"
						writeWatcherState(directory, state)
						log("error", `[${directory}] session.created: vera watch failed to start`)
						return
					}

					state.pid = watchResult.pid
					state.status = "running"
					state.startedAt = new Date().toISOString()
					state.lastVerifiedAt = new Date().toISOString()
					resetRestartAttempts(state)
					log("info", `[${directory}] watcher started pid=${state.pid}`)
				} else if (state.status === "indexed") {
					if (!veraAvailable()) {
						state.status = "missing-binary"
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = "vera binary not available"
						writeWatcherState(directory, state)
						log("warn", `[${directory}] session.created: vera not available, status=missing-binary`)
						return
					}

					if (!isVeraIndexNonEmpty(directory)) {
						const hygienePassed = runVeraHygieneCheck(directory)
						state.hygieneStatus = hygienePassed ? "passed" : "failed"
						state.lastHygieneCheckAt = new Date().toISOString()
						if (!hygienePassed) {
							state.status = "index-failed"
							state.lastFailureAt = new Date().toISOString()
							state.lastFailureReason = "Vera index is hollow/has blockers. Run vera-hygiene --apply to resolve."
							writeWatcherState(directory, state)
							log("error", `[${directory}] session.created: hollow index with hygiene blockers`)
							return
						}
						const reindexed = runVeraIndex(directory)
						if (!reindexed || !isVeraIndexNonEmpty(directory)) {
							state.status = "index-failed"
							state.lastFailureAt = new Date().toISOString()
							state.lastFailureReason = "vera index . still hollow after hygiene and reindex"
							writeWatcherState(directory, state)
							log("error", `[${directory}] session.created: index still hollow after reindex`)
							return
						}
						state.lastIndexedAt = new Date().toISOString()
					}

					const watchResult = startVeraWatch(directory)
					if (!watchResult) {
						state.status = "watch-failed"
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = "vera watch . failed to start"
						writeWatcherState(directory, state)
						log("error", `[${directory}] session.created: vera watch failed to start`)
						return
					}

					state.pid = watchResult.pid
					state.status = "running"
					state.startedAt = new Date().toISOString()
					state.lastVerifiedAt = new Date().toISOString()
					resetRestartAttempts(state)
					log("info", `[${directory}] watcher started pid=${state.pid}`)
				} else if (state.status === "running") {
					if (state.pid && isPidAlive(state.pid) && validatePidOwnership(state.pid, directory)) {
						state.lastVerifiedAt = new Date().toISOString()
						resetRestartAttempts(state)
						log("info", `[${directory}] session.created: watcher already running pid=${state.pid}`)
					} else {
						log("warn", `[${directory}] session.created: existing pid=${state.pid} unavailable or unowned, attempting safe restart`)
						const restarted = performSafeRestart(directory, state)
						if (!restarted) {
							log("error", `[${directory}] session.created: safe restart failed, status=${state.status}`)
						}
					}
				} else if (state.status === "stale") {
					log("info", `[${directory}] session.created: recovering stale watcher`)
					const restarted = performSafeRestart(directory, state)
					if (!restarted) {
						log("error", `[${directory}] session.created: stale recovery failed, status=${state.status}`)
					}
				}

				writeWatcherState(directory, state)
			} catch (err) {
				const reason = err instanceof Error ? err.message : String(err)
				log("error", `[${directory}] session.created error: ${reason}`)
				try {
					const state = readWatcherState(directory) || createInitialState(directory)
					state.lastFailureAt = new Date().toISOString()
					state.lastFailureReason = `session.created exception: ${reason}`
					writeWatcherState(directory, state)
				} catch {
					/* fail-open */
				}
			}
		},

		// =============================================================
		// session.deleted — stop watcher if last session
		// =============================================================
		"session.deleted": async (_input, _output) => {
			const sessionId = extractSessionId(_input)
			if (!sessionId) {
				log("warn", `[${directory}] session.deleted: no sessionId extracted`)
			}

			try {
				const state = readWatcherState(directory)
				if (!state) {
					log("debug", `[${directory}] session.deleted: no state found`)
					return
				}

				state.sessionIds = state.sessionIds.filter((id) => id !== sessionId)

				if (state.sessionIds.length === 0) {
					const timer = healthCheckTimers.get(directory)
					if (timer) {
						clearInterval(timer)
						healthCheckTimers.delete(directory)
						log("debug", `[${directory}] session.deleted: cleared health check timer`)
					}

					if (state.status === "running" && state.pid) {
						log("info", `[${directory}] session.deleted: last session gone, stopping watcher pid=${state.pid}`)

						if (validatePidOwnership(state.pid, directory)) {
							try {
								Bun.spawnSync(["kill", String(state.pid)])
								log("info", `[${directory}] Sent kill to pid=${state.pid}`)
							} catch (err) {
								const reason = err instanceof Error ? err.message : String(err)
								log("warn", `[${directory}] kill ${state.pid} failed: ${reason}`)
							}

							let alive = true
							for (let i = 0; i < KILL_WAIT_SECONDS; i++) {
								await Bun.sleep(1000)
								alive = isPidAlive(state.pid) && validatePidOwnership(state.pid, directory)
								if (!alive) {
									log("info", `[${directory}] Watcher pid=${state.pid} exited gracefully`)
									break
								}
							}

							if (alive && validatePidOwnership(state.pid, directory)) {
								try {
									Bun.spawnSync(["kill", "-9", String(state.pid)])
									log("warn", `[${directory}] Sent kill -9 to pid=${state.pid}`)
								} catch (err) {
									const reason = err instanceof Error ? err.message : String(err)
									log("warn", `[${directory}] kill -9 ${state.pid} failed: ${reason}`)
								}
							}
						} else {
							log(
								"warn",
								`[${directory}] session.deleted: pid=${state.pid} ownership validation failed, refusing to kill`,
							)
						}
					}

					state.status = "stopped"
					state.pid = null
					log("info", `[${directory}] Watcher stopped`)

					const statePath = getStateFilePath(directory)
					try {
						unlinkSync(statePath)
						log("info", `[${directory}] Removed watcher state file ${statePath}`)
						return
					} catch (err) {
						const reason = err instanceof Error ? err.message : String(err)
						log("warn", `[${directory}] Failed to remove state file ${statePath}: ${reason}`)
						writeWatcherState(directory, state)
						return
					}
				}

				writeWatcherState(directory, state)
			} catch (err) {
				const reason = err instanceof Error ? err.message : String(err)
				log("error", `[${directory}] session.deleted error: ${reason}`)
				try {
					const state = readWatcherState(directory)
					if (state) {
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = `session.deleted exception: ${reason}`
						writeWatcherState(directory, state)
					}
				} catch {
					/* fail-open */
				}
			}
		},

		// =============================================================
		// tool.execute.before — trigger index update for heavy tools
		// =============================================================
		"tool.execute.before": (input, _output) => {
			const toolName = input.tool
			if (toolName !== "task" && toolName !== "search") {
				return
			}

			try {
				const state = readWatcherState(directory)
				if (!state) {
					log("debug", `[${directory}] tool.execute.before (${toolName}): no state, skipping`)
					return
				}
				if (state.status !== "running") {
					log("debug", `[${directory}] tool.execute.before (${toolName}): status=${state.status}, skipping`)
					return
				}

				const now = Date.now()
				const lastIndexed = state.lastIndexedAt ? new Date(state.lastIndexedAt).getTime() : 0
				const isStale = !lastIndexed || now - lastIndexed > STALENESS_MS

				if (isStale) {
					log("info", `[${directory}] tool.execute.before (${toolName}): index stale, triggering vera update .`)
					const updated = runVeraUpdate(directory)
					if (updated) {
						state.lastIndexedAt = new Date().toISOString()
						log("info", `[${directory}] tool.execute.before: vera update completed`)
					} else {
						state.lastFailureAt = new Date().toISOString()
						state.lastFailureReason = "vera update . failed during tool.execute.before"
						log("error", `[${directory}] tool.execute.before: vera update failed`)
					}
					writeWatcherState(directory, state)
				}
			} catch (err) {
				const reason = err instanceof Error ? err.message : String(err)
				log("error", `[${directory}] tool.execute.before error: ${reason}`)
			}
		},
	}
}

export default VeraRuntimePlugin
