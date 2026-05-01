/**
 * Vera Runtime Plugin — Workspace supervision for Vera semantic code search.
 *
 * Manages per-workspace Vera watcher state, tracking indexing status,
 * active watch processes, and session associations. Fail-open: if vera
 * binary or skill is missing, logs and continues without blocking.
 *
 * State location: ~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/
 * Log location:   ~/.opencode/plugin/vera-runtime/<workspace-key>.log
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import * as crypto from "node:crypto"
import type { Plugin } from "@opencode-ai/plugin"

// =============================================================================
// TYPES
// =============================================================================

/** Vera watcher status values */
type VeraWatcherStatus =
	| "indexed"
	| "running"
	| "stale"
	| "stopped"
	| "missing-binary"
	| "index-failed"
	| "watch-failed"

/** Vera watcher state file schema */
interface VeraWatcherState {
	workspaceKey: string
	workspacePath: string
	projectId: string
	pid: number | null
	status: VeraWatcherStatus
	sessionIds: string[]
	indexPath: string
	watchLogPath: string
	lastIndexedAt: string | null
	startedAt: string | null
	lastVerifiedAt: string | null
	lastFailureAt: string | null
	lastFailureReason: string | null
}

// =============================================================================
// CONSTANTS
// =============================================================================

const BASE_STATE_DIR = `${process.env.HOME}/.local/share/opencode/worktree-state`
const BASE_LOG_DIR = `${process.env.HOME}/.opencode/plugin/vera-runtime`

// =============================================================================
// HELPERS — Workspace Key & Paths
// =============================================================================

/**
 * Compute the project ID from a workspace path.
 * Uses `basename "$(git rev-parse --show-toplevel)"` — same as worktree scripts.
 */
function computeProjectId(workspacePath: string): string {
	try {
		const proc = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], {
			cwd: workspacePath,
			env: process.env,
		})
		if (proc.success) {
			const gitRoot = new TextDecoder().decode(proc.stdout).trim()
			if (gitRoot) {
				return gitRoot.split("/").pop() || "unknown"
			}
		}
	} catch {
		// fall through to path basename
	}
	return workspacePath.split("/").pop() || "unknown"
}

/**
 * Compute the workspace key: `<workspace-basename>-<sha1-8(realpath(workspacePath))>`
 */
function computeWorkspaceKey(workspacePath: string): string {
	const realPath = (() => {
		try {
			const proc = Bun.spawnSync(["realpath", workspacePath], {
				env: process.env,
			})
			if (proc.success) {
				return new TextDecoder().decode(proc.stdout).trim()
			}
		} catch {
			// fall through
		}
		return workspacePath
	})()

	const basename = realPath.split("/").pop() || "workspace"
	const hash = crypto.createHash("sha1").update(realPath).digest("hex").slice(0, 8)
	return `${basename}-${hash}`
}

/** Directory for vera-watchers state files for a given project */
function getWatchersDir(projectId: string): string {
	return `${BASE_STATE_DIR}/${projectId}/vera-watchers`
}

/** Full path to a watcher state file */
function getStateFilePath(workspaceKey: string, projectId: string): string {
	return `${getWatchersDir(projectId)}/${workspaceKey}.json`
}

/** Full path to a watcher log file */
function getLogPath(workspaceKey: string): string {
	return `${BASE_LOG_DIR}/${workspaceKey}.log`
}

// =============================================================================
// HELPERS — State File I/O
// =============================================================================

/**
 * Read a watcher state file. Returns null if missing or unreadable.
 * Fail-open: never throws.
 */
function readWatcherState(workspaceKey: string, projectId: string): VeraWatcherState | null {
	const path = getStateFilePath(workspaceKey, projectId)
	try {
		const raw = readFileSync(path, "utf-8")
		return JSON.parse(raw) as VeraWatcherState
	} catch {
		return null
	}
}

/**
 * Write a watcher state file atomically (write + sync).
 * Fail-open: logs error but never throws.
 */
function writeWatcherState(state: VeraWatcherState): void {
	const path = getStateFilePath(state.workspaceKey, state.projectId)
	try {
		mkdirSync(dirname(path), { recursive: true })
		writeFileSync(path, JSON.stringify(state, null, 2), "utf-8")
	} catch (err) {
		log("error", `Failed to write state to ${path}: ${err}`)
	}
}

/** Create a fresh default state for a workspace */
function createDefaultState(workspacePath: string, projectId: string): VeraWatcherState {
	const workspaceKey = computeWorkspaceKey(workspacePath)
	return {
		workspaceKey,
		workspacePath,
		projectId,
		pid: null,
		status: "stopped",
		sessionIds: [],
		indexPath: `${workspacePath}/.vera`,
		watchLogPath: getLogPath(workspaceKey),
		lastIndexedAt: null,
		startedAt: null,
		lastVerifiedAt: null,
		lastFailureAt: null,
		lastFailureReason: null,
	}
}

// =============================================================================
// HELPERS — Logging
// =============================================================================

/** Best-effort file log — never throws */
function log(level: string, message: string): void {
	const timestamp = new Date().toISOString()
	const line = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`
	try {
		mkdirSync(BASE_LOG_DIR, { recursive: true })
		const logPath = `${BASE_LOG_DIR}/runtime.log`
		writeFileSync(logPath, line, { flag: "a" })
	} catch {
		// intentionally swallowed — fail-open
	}
}

/** Best-effort per-workspace log — never throws */
function logWorkspace(workspaceKey: string, level: string, message: string): void {
	const timestamp = new Date().toISOString()
	const line = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`
	try {
		const logPath = getLogPath(workspaceKey)
		mkdirSync(dirname(logPath), { recursive: true })
		writeFileSync(logPath, line, { flag: "a" })
	} catch {
		// intentionally swallowed — fail-open
	}
}

// =============================================================================
// PLUGIN
// =============================================================================

const VeraRuntimePlugin: Plugin = async (ctx) => {
	const { client } = ctx

	const appLog = (level: "info" | "debug" | "warn" | "error", msg: string) =>
		client.app
			.log({ body: { service: "vera-runtime", level, message: msg } })
			.catch(() => {})

	log("info", "Vera runtime plugin initialized")
	appLog("info", "Vera runtime plugin initialized")

	return {
		// -------------------------------------------------------------------------
		// Session created — ensure watcher state exists for the workspace
		// -------------------------------------------------------------------------
		"session.created": async (event) => {
			const workspacePath = event.workspace?.path ?? process.cwd()
			const projectId = computeProjectId(workspacePath)
			const workspaceKey = computeWorkspaceKey(workspacePath)

			log("debug", `session.created — workspaceKey=${workspaceKey}, projectId=${projectId}`)

			let state = readWatcherState(workspaceKey, projectId)
			if (!state) {
				state = createDefaultState(workspacePath, projectId)
				writeWatcherState(state)
				logWorkspace(workspaceKey, "info", `Created initial watcher state for ${workspacePath}`)
			}

			const sessionId = event.sessionID
			if (sessionId && !state.sessionIds.includes(sessionId)) {
				state.sessionIds.push(sessionId)
				writeWatcherState(state)
			}

			// TODO(task-7): Check if vera binary exists, start watcher if needed
			// TODO(task-7): Verify index freshness, trigger re-index if stale
		},

		// -------------------------------------------------------------------------
		// Session deleted — clean up session association, stop watcher if no sessions
		// -------------------------------------------------------------------------
		"session.deleted": async (event) => {
			const workspacePath = event.workspace?.path ?? process.cwd()
			const projectId = computeProjectId(workspacePath)
			const workspaceKey = computeWorkspaceKey(workspacePath)

			log("debug", `session.deleted — workspaceKey=${workspaceKey}, projectId=${projectId}`)

			const state = readWatcherState(workspaceKey, projectId)
			if (!state) {
				logWorkspace(workspaceKey, "warn", "No watcher state found for deleted session")
				return
			}

			const sessionId = event.sessionID
			if (sessionId) {
				state.sessionIds = state.sessionIds.filter((id) => id !== sessionId)
				writeWatcherState(state)
			}

			if (state.sessionIds.length === 0) {
				state.status = "stopped"
				state.pid = null
				writeWatcherState(state)
				logWorkspace(workspaceKey, "info", "Last session removed — watcher stopped")
			}

			// TODO(task-7): Actually stop the vera watch process if running
		},

		// -------------------------------------------------------------------------
		// Tool execute before — intercept vera-related tool calls if needed
		// -------------------------------------------------------------------------
		"tool.execute.before": async (input, _output) => {
			// TODO(task-7): Intercept vera index/watch commands to update state
			// TODO(task-7): Inject workspace context into vera CLI calls
			// TODO(task-7): Handle vera binary absence gracefully (status = "missing-binary")
			// Fail-open: do nothing for now, let tool execute normally
		},
	}
}

export default VeraRuntimePlugin
