import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import * as os from "node:os"
import * as path from "node:path"
import { z } from "../../../.opencode/node_modules/zod/index.js"
import type { OpencodeClient } from "../kdco-primitives"
import { getProjectId, logWarn } from "../kdco-primitives"

export interface Database {
	filePath: string
}

export interface Session {
	id: string
	branch: string
	path: string
	createdAt: string
}

export interface PendingSpawn {
	branch: string
	path: string
	sessionId: string
}

export interface PendingDelete {
	branch: string
	path: string
}

export interface PendingStart {
	branch: string
	path: string
	planName: string
	sessionId: string | null
}

const sessionSchema = z.object({
	id: z.string().min(1),
	branch: z.string().min(1),
	path: z.string().min(1),
	createdAt: z.string().min(1),
})

const pendingSpawnSchema = z.object({
	branch: z.string().min(1),
	path: z.string().min(1),
	sessionId: z.string().min(1),
})

const pendingDeleteSchema = z.object({
	branch: z.string().min(1),
	path: z.string().min(1),
})

const pendingStartSchema = z.object({
	branch: z.string().min(1),
	path: z.string().min(1),
	planName: z.string().min(1),
	sessionId: z.string().min(1).nullable(),
})

const stateFileSchema = z.object({
	sessions: z.array(sessionSchema),
	pendingOperation: z
		.object({
			type: z.enum(["spawn", "delete"]),
			branch: z.string().min(1),
			path: z.string().min(1),
			sessionId: z.string().min(1).nullable().optional(),
		})
		.nullable(),
	pendingStarts: z.array(pendingStartSchema),
})

type StateFile = z.infer<typeof stateFileSchema>

function createEmptyState(): StateFile {
	return {
		sessions: [],
		pendingOperation: null,
		pendingStarts: [],
	}
}

export async function getWorktreePath(projectRoot: string, branch: string): Promise<string> {
	if (!branch || typeof branch !== "string") {
		throw new Error("branch is required")
	}
	const projectId = await getProjectId(projectRoot)
	return path.join(os.homedir(), ".local", "share", "opencode", "worktree", projectId, branch)
}

function getStateDirectory(): string {
	return path.join(os.homedir(), ".local", "share", "opencode", "plugins", "worktree")
}

async function getStatePath(projectRoot: string): Promise<string> {
	const projectId = await getProjectId(projectRoot)
	return path.join(getStateDirectory(), `${projectId}.json`)
}

function readState(db: Database): StateFile {
	try {
		const content = readFileSync(db.filePath, "utf-8")
		const parsed = JSON.parse(content)
		return stateFileSchema.parse(parsed)
	} catch {
		return createEmptyState()
	}
}

function writeState(db: Database, state: StateFile): void {
	const validated = stateFileSchema.parse(state)
	const dir = path.dirname(db.filePath)
	mkdirSync(dir, { recursive: true })
	const tmpPath = `${db.filePath}.tmp`
	writeFileSync(tmpPath, `${JSON.stringify(validated, null, 2)}\n`, "utf-8")
	renameSync(tmpPath, db.filePath)
}

export async function initStateDb(projectRoot: string): Promise<Database> {
	if (!projectRoot || typeof projectRoot !== "string") {
		throw new Error("initStateDb requires a valid project root path")
	}
	const filePath = await getStatePath(projectRoot)
	mkdirSync(path.dirname(filePath), { recursive: true })
	if (!safeExists(filePath)) {
		writeFileSync(filePath, `${JSON.stringify(createEmptyState(), null, 2)}\n`, "utf-8")
	}
	return { filePath }
}

function safeExists(filePath: string): boolean {
	try {
		readFileSync(filePath, "utf-8")
		return true
	} catch {
		return false
	}
}

export function addSession(db: Database, session: Session): void {
	const parsed = sessionSchema.parse(session)
	const state = readState(db)
	state.sessions = [
		...state.sessions.filter((item) => item.id !== parsed.id),
		parsed,
	]
	writeState(db, state)
}

export function getSession(db: Database, sessionId: string): Session | null {
	if (!sessionId) return null
	const state = readState(db)
	return state.sessions.find((session) => session.id === sessionId) ?? null
}

export function removeSession(db: Database, branch: string): void {
	if (!branch) return
	const state = readState(db)
	state.sessions = state.sessions.filter((session) => session.branch !== branch)
	writeState(db, state)
}

export function getAllSessions(db: Database): Session[] {
	return readState(db).sessions
}

export function setPendingSpawn(db: Database, spawn: PendingSpawn, client?: OpencodeClient): void {
	const parsed = pendingSpawnSchema.parse(spawn)
	const state = readState(db)
	const existingSpawn = getPendingSpawn(db)
	const existingDelete = getPendingDelete(db)

	if (existingSpawn) {
		logWarn(client, "worktree", `Replacing pending spawn: "${existingSpawn.branch}" → "${parsed.branch}"`)
	} else if (existingDelete) {
		logWarn(client, "worktree", `Pending spawn replacing pending delete for: "${existingDelete.branch}"`)
	}

	state.pendingOperation = {
		type: "spawn",
		branch: parsed.branch,
		path: parsed.path,
		sessionId: parsed.sessionId,
	}
	writeState(db, state)
}

export function getPendingSpawn(db: Database): PendingSpawn | null {
	const pendingOperation = readState(db).pendingOperation
	if (!pendingOperation || pendingOperation.type !== "spawn" || !pendingOperation.sessionId) {
		return null
	}
	return {
		branch: pendingOperation.branch,
		path: pendingOperation.path,
		sessionId: pendingOperation.sessionId,
	}
}

export function clearPendingSpawn(db: Database): void {
	const state = readState(db)
	if (state.pendingOperation?.type === "spawn") {
		state.pendingOperation = null
		writeState(db, state)
	}
}

export function setPendingDelete(db: Database, del: PendingDelete, client?: OpencodeClient): void {
	const parsed = pendingDeleteSchema.parse(del)
	const state = readState(db)
	const existingDelete = getPendingDelete(db)
	const existingSpawn = getPendingSpawn(db)

	if (existingDelete) {
		logWarn(client, "worktree", `Replacing pending delete: "${existingDelete.branch}" → "${parsed.branch}"`)
	} else if (existingSpawn) {
		logWarn(client, "worktree", `Pending delete replacing pending spawn for: "${existingSpawn.branch}"`)
	}

	state.pendingOperation = {
		type: "delete",
		branch: parsed.branch,
		path: parsed.path,
		sessionId: null,
	}
	writeState(db, state)
}

export function getPendingDelete(db: Database): PendingDelete | null {
	const pendingOperation = readState(db).pendingOperation
	if (!pendingOperation || pendingOperation.type !== "delete") return null
	return {
		branch: pendingOperation.branch,
		path: pendingOperation.path,
	}
}

export function clearPendingDelete(db: Database): void {
	const state = readState(db)
	if (state.pendingOperation?.type === "delete") {
		state.pendingOperation = null
		writeState(db, state)
	}
}

export function setPendingStart(db: Database, pendingStart: PendingStart): void {
	const parsed = pendingStartSchema.parse(pendingStart)
	const state = readState(db)
	state.pendingStarts = [
		...state.pendingStarts.filter((item) => item.path !== parsed.path),
		parsed,
	]
	writeState(db, state)
}

export function getPendingStartByPath(db: Database, worktreePath: string): PendingStart | null {
	if (!worktreePath) return null
	const state = readState(db)
	return state.pendingStarts.find((item) => item.path === worktreePath) ?? null
}

export function attachPendingStartSession(db: Database, worktreePath: string, sessionId: string): void {
	const state = readState(db)
	state.pendingStarts = state.pendingStarts.map((item) =>
		item.path === worktreePath ? { ...item, sessionId } : item,
	)
	writeState(db, state)
}

export function getPendingStartBySession(db: Database, sessionId: string): PendingStart | null {
	if (!sessionId) return null
	const state = readState(db)
	return state.pendingStarts.find((item) => item.sessionId === sessionId) ?? null
}

export function clearPendingStartByPath(db: Database, worktreePath: string): void {
	const state = readState(db)
	state.pendingStarts = state.pendingStarts.filter((item) => item.path !== worktreePath)
	writeState(db, state)
}

export function clearPendingStartBySession(db: Database, sessionId: string): void {
	const state = readState(db)
	state.pendingStarts = state.pendingStarts.filter((item) => item.sessionId !== sessionId)
	writeState(db, state)
}
