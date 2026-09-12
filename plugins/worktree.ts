/**
 * OCX Worktree Plugin
 *
 * Creates isolated git worktrees for AI development sessions with
 * seamless terminal spawning across macOS, Windows, and Linux.
 *
 * Inspired by opencode-worktree-session by Felix Anhalt
 * https://github.com/felixAnhalt/opencode-worktree-session
 * License: MIT
 *
 * Rewritten for OCX with production-proven patterns.
 */

import { access, copyFile, cp, mkdir, readdir, rm, stat, symlink } from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"
import { type Plugin, tool } from "@opencode-ai/plugin"
import type { Event } from "@opencode-ai/sdk"
import type { OpencodeClient } from "./kdco-primitives/types"

/** Logger interface for structured logging */
interface Logger {
	debug: (msg: string) => void
	info: (msg: string) => void
	warn: (msg: string) => void
	error: (msg: string) => void
}

import { parse as parseJsonc } from "jsonc-parser"
import { z } from "zod"

import { getProjectId } from "./kdco-primitives/get-project-id"
import {
	addSession,
	clearPendingDelete,
	type Database,
	getPendingDelete,
	getSession,
	getWorktreePath,
	initStateDb,
	removeSession,
	setPendingDelete,
} from "./worktree/state"

/** Maximum depth to traverse session parent chain */
const MAX_SESSION_CHAIN_DEPTH = 10

// =============================================================================
// TYPES & SCHEMAS
// =============================================================================

/** Result type for fallible operations */
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

/**
 * Git branch name validation - blocks invalid refs and shell metacharacters
 * Characters blocked: control chars (0x00-0x1f, 0x7f), ~^:?*[]\\, and shell metacharacters
 */
function isValidBranchName(name: string): boolean {
	// Check for control characters
	for (let i = 0; i < name.length; i++) {
		const code = name.charCodeAt(i)
		if (code <= 0x1f || code === 0x7f) return false
	}
	// Check for invalid git ref characters and shell metacharacters
	if (/[~^:?*[\]\\;&|`$()]/.test(name)) return false
	return true
}

const branchNameSchema = z
	.string()
	.min(1, "Branch name cannot be empty")
	.refine((name) => !name.startsWith("-"), {
		message: "Branch name cannot start with '-' (prevents option injection)",
	})
	.refine((name) => !name.startsWith("/") && !name.endsWith("/"), {
		message: "Branch name cannot start or end with '/'",
	})
	.refine((name) => !name.includes("//"), {
		message: "Branch name cannot contain '//'",
	})
	.refine((name) => !name.includes("@{"), {
		message: "Branch name cannot contain '@{' (git reflog syntax)",
	})
	.refine((name) => !name.includes(".."), {
		message: "Branch name cannot contain '..'",
	})
	// biome-ignore lint/suspicious/noControlCharactersInRegex: Control character detection is intentional for security
	.refine((name) => !/[\x00-\x1f\x7f ~^:?*[\]\\]/.test(name), {
		message: "Branch name contains invalid characters",
	})
	.max(255, "Branch name too long")
	.refine((name) => isValidBranchName(name), "Contains invalid git ref characters")
	.refine((name) => !name.startsWith(".") && !name.endsWith("."), "Cannot start or end with dot")
	.refine((name) => !name.endsWith(".lock"), "Cannot end with .lock")

/**
 * Worktree plugin configuration schema.
 * Config file: .opencode/worktree.jsonc
 */
const worktreeConfigSchema = z.object({
	sync: z
		.object({
			/** Files to copy from main worktree (relative paths only) */
			copyFiles: z.array(z.string()).default([]),
			/** Directories to symlink from main worktree (saves disk space) */
			symlinkDirs: z.array(z.string()).default([]),
			/** Patterns to exclude from copying (reserved for future use) */
			exclude: z.array(z.string()).default([]),
		})
		.default(() => ({ copyFiles: [], symlinkDirs: [], exclude: [] })),
	hooks: z
		.object({
			/** Commands to run after worktree creation */
			postCreate: z.array(z.string()).default([]),
			/** Commands to run before worktree deletion */
			preDelete: z.array(z.string()).default([]),
		})
		.default(() => ({ postCreate: [], preDelete: [] })),
})

type WorktreeConfig = z.infer<typeof worktreeConfigSchema>

// =============================================================================
// ERROR TYPES
// =============================================================================

class WorktreeError extends Error {
	constructor(
		message: string,
		public readonly operation: string,
		public readonly cause?: unknown,
	) {
		super(`${operation}: ${message}`)
		this.name = "WorktreeError"
	}
}

// =============================================================================
// SESSION FORKING HELPERS
// =============================================================================

/**
 * Check if a path exists, distinguishing ENOENT from other errors (Law 4)
 */
async function pathExists(filePath: string): Promise<boolean> {
	try {
		await access(filePath)
		return true
	} catch (e: unknown) {
		if (e && typeof e === "object" && "code" in e && e.code === "ENOENT") {
			return false
		}
		throw e // Re-throw permission errors, etc.
	}
}

/**
 * Copy file if source exists. Returns true if copied, false if source doesn't exist.
 * Throws on copy failure (Law 4: Fail Loud)
 */
async function copyIfExists(src: string, dest: string): Promise<boolean> {
	if (!(await pathExists(src))) return false
	await copyFile(src, dest)
	return true
}

/**
 * Copy directory contents if source exists.
 * @param src - Source directory path
 * @param dest - Destination directory path
 * @returns true if copy was performed, false if source doesn't exist
 */
async function copyDirIfExists(src: string, dest: string): Promise<boolean> {
	if (!(await pathExists(src))) return false
	await cp(src, dest, { recursive: true })
	return true
}

interface ForkResult {
	forkedSession: { id: string }
	rootSessionId: string
	planCopied: boolean
	delegationsCopied: boolean
}

/**
 * Fork a session and copy associated plans/delegations.
 * Cleans up forked session on failure (atomic operation).
 */
async function forkWithContext(
	client: OpencodeClient,
	sessionId: string,
	projectId: string,
	getRootSessionIdFn: (sessionId: string) => Promise<string>,
): Promise<ForkResult> {
	// Guard clauses (Law 1)
	if (!client) throw new WorktreeError("client is required", "forkWithContext")
	if (!sessionId) throw new WorktreeError("sessionId is required", "forkWithContext")
	if (!projectId) throw new WorktreeError("projectId is required", "forkWithContext")

	// Get root session ID with error wrapping
	let rootSessionId: string
	try {
		rootSessionId = await getRootSessionIdFn(sessionId)
	} catch (e) {
		throw new WorktreeError("Failed to get root session ID", "forkWithContext", e)
	}

	// Fork session
	const forkedSessionResponse = await client.session.fork({
		path: { id: sessionId },
		body: {},
	})
	const forkedSession = forkedSessionResponse.data
	if (!forkedSession?.id) {
		throw new WorktreeError("Failed to fork session: no session data returned", "forkWithContext")
	}

	// Copy data with cleanup on failure
	let planCopied = false
	let delegationsCopied = false

	try {
		const workspaceBase = path.join(os.homedir(), ".local", "share", "opencode", "workspace")
		const delegationsBase = path.join(os.homedir(), ".local", "share", "opencode", "delegations")

		const destWorkspaceDir = path.join(workspaceBase, projectId, forkedSession.id)
		const destDelegationsDir = path.join(delegationsBase, projectId, forkedSession.id)

		await mkdir(destWorkspaceDir, { recursive: true })
		await mkdir(destDelegationsDir, { recursive: true })

		// Copy plan
		const srcPlan = path.join(workspaceBase, projectId, rootSessionId, "plan.md")
		const destPlan = path.join(destWorkspaceDir, "plan.md")
		planCopied = await copyIfExists(srcPlan, destPlan)

		// Copy delegations
		const srcDelegations = path.join(delegationsBase, projectId, rootSessionId)
		delegationsCopied = await copyDirIfExists(srcDelegations, destDelegationsDir)
	} catch (error) {
		client.app
			.log({
				body: {
					service: "worktree",
					level: "error",
					message: `forkWithContext: Copy failed, cleaning up forked session: ${error}`,
				},
			})
			.catch(() => {})
		// Clean up orphaned directories
		const workspaceBase = path.join(os.homedir(), ".local", "share", "opencode", "workspace")
		const delegationsBase = path.join(os.homedir(), ".local", "share", "opencode", "delegations")
		const destWorkspaceDir = path.join(workspaceBase, projectId, forkedSession.id)
		const destDelegationsDir = path.join(delegationsBase, projectId, forkedSession.id)
		await rm(destWorkspaceDir, { recursive: true, force: true }).catch((e: unknown) => {
			client.app
				.log({
					body: {
						service: "worktree",
						level: "error",
						message: `forkWithContext: Failed to clean up workspace dir ${destWorkspaceDir}: ${e}`,
					},
				})
				.catch(() => {})
		})
		await rm(destDelegationsDir, { recursive: true, force: true }).catch((e: unknown) => {
			client.app
				.log({
					body: {
						service: "worktree",
						level: "error",
						message: `forkWithContext: Failed to clean up delegations dir ${destDelegationsDir}: ${e}`,
					},
				})
				.catch(() => {})
		})
		await client.session.delete({ path: { id: forkedSession.id } }).catch((e: unknown) => {
			client.app
				.log({
					body: {
						service: "worktree",
						level: "error",
						message: `forkWithContext: Failed to clean up forked session ${forkedSession.id}: ${e}`,
					},
				})
				.catch(() => {})
		})
		throw new WorktreeError(
			`Failed to copy session data: ${error instanceof Error ? error.message : String(error)}`,
			"forkWithContext",
			error,
		)
	}

	return { forkedSession, rootSessionId, planCopied, delegationsCopied }
}

// =============================================================================
// MODULE-LEVEL STATE
// =============================================================================

let db: Database | null = null
async function initDb(root: string): Promise<Database> {
	if (db) return db
	db = await initStateDb(root)
	return db
}

// =============================================================================
// GIT MODULE
// =============================================================================

/**
 * Execute a git command safely using Bun.spawn with explicit array.
 * Avoids shell interpolation entirely by passing args as array.
 */
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

async function branchExists(cwd: string, branch: string): Promise<boolean> {
	const result = await git(["rev-parse", "--verify", branch], cwd)
	return result.ok
}

async function createWorktree(
	repoRoot: string,
	branch: string,
	baseBranch?: string,
): Promise<Result<string, string>> {
	const worktreePath = await getWorktreePath(repoRoot, branch)

	// Ensure parent directory exists
	await mkdir(path.dirname(worktreePath), { recursive: true })

	const exists = await branchExists(repoRoot, branch)

	if (exists) {
		// Checkout existing branch into worktree
		const result = await git(["worktree", "add", worktreePath, branch], repoRoot)
		return result.ok ? Result.ok(worktreePath) : result
	} else {
		// Create new branch from base
		const base = baseBranch ?? "HEAD"
		const result = await git(["worktree", "add", "-b", branch, worktreePath, base], repoRoot)
		return result.ok ? Result.ok(worktreePath) : result
	}
}

async function removeWorktree(
	repoRoot: string,
	worktreePath: string,
): Promise<Result<void, string>> {
	const result = await git(["worktree", "remove", "--force", worktreePath], repoRoot)
	return result.ok ? Result.ok(undefined) : Result.err(result.error)
}
/**
 * Resolve a target (branch name like "plan/foo" or absolute worktree path)
 * to its {branch, path} via `git worktree list --porcelain`.
 * Skips detached/malformed entries. Returns null when nothing matches.
 */
function resolveWorktreeTarget(
	porcelain: string,
	target: string,
): { branch: string; path: string } | null {
	for (const block of porcelain.split("\n\n")) {
		const lines = block.split("\n").filter((line) => line.length > 0)
		const wtPath = lines.find((l) => l.startsWith("worktree "))?.slice("worktree ".length)
		const branchRef = lines.find((l) => l.startsWith("branch "))?.slice("branch ".length)
		if (!wtPath || !branchRef) continue
		const branch = branchRef.replace(/^refs\/heads\//, "")
		if (branch === target || wtPath === target) {
			return { branch, path: wtPath }
		}
	}
	return null
}


// =============================================================================
// FILE SYNC MODULE
// =============================================================================

/**
 * Validate that a path is safe (no escape from base directory)
 */
function isPathSafe(filePath: string, baseDir: string, log: Logger): boolean {
	// Reject absolute paths
	if (path.isAbsolute(filePath)) {
		log.warn(`[worktree] Rejected absolute path: ${filePath}`)
		return false
	}
	// Reject obvious path traversal
	if (filePath.includes("..")) {
		log.warn(`[worktree] Rejected path traversal: ${filePath}`)
		return false
	}
	// Verify resolved path stays within base directory
	const resolved = path.resolve(baseDir, filePath)
	if (!resolved.startsWith(baseDir + path.sep) && resolved !== baseDir) {
		log.warn(`[worktree] Path escapes base directory: ${filePath}`)
		return false
	}
	return true
}

/**
 * Copy files from source directory to target directory.
 * Skips missing files silently (production pattern).
 */
async function copyFiles(
	sourceDir: string,
	targetDir: string,
	files: string[],
	log: Logger,
): Promise<void> {
	for (const file of files) {
		if (!isPathSafe(file, sourceDir, log)) continue

		const sourcePath = path.join(sourceDir, file)
		const targetPath = path.join(targetDir, file)

		try {
			const sourceFile = Bun.file(sourcePath)
			if (!(await sourceFile.exists())) {
				log.debug(`[worktree] Skipping missing file: ${file}`)
				continue
			}

			// Ensure target directory exists
			const targetFileDir = path.dirname(targetPath)
			await mkdir(targetFileDir, { recursive: true })

			// Copy file
			await Bun.write(targetPath, sourceFile)
			log.info(`[worktree] Copied: ${file}`)
		} catch (error) {
			const isNotFound =
				error instanceof Error &&
				(error.message.includes("ENOENT") || error.message.includes("no such file"))
			if (isNotFound) {
				log.debug(`[worktree] Skipping missing: ${file}`)
			} else {
				log.warn(`[worktree] Failed to copy ${file}: ${error}`)
			}
		}
	}
}

/**
 * Create symlinks for directories from source to target.
 * Uses absolute paths for symlink targets.
 */
async function symlinkDirs(
	sourceDir: string,
	targetDir: string,
	dirs: string[],
	log: Logger,
): Promise<void> {
	for (const dir of dirs) {
		if (!isPathSafe(dir, sourceDir, log)) continue

		const sourcePath = path.join(sourceDir, dir)
		const targetPath = path.join(targetDir, dir)

		try {
			// Check if source directory exists
			const fileStat = await stat(sourcePath).catch(() => null)
			if (!fileStat || !fileStat.isDirectory()) {
				log.debug(`[worktree] Skipping missing directory: ${dir}`)
				continue
			}

			// Ensure parent directory exists
			const targetParentDir = path.dirname(targetPath)
			await mkdir(targetParentDir, { recursive: true })

			// Remove existing target if it exists (might be empty dir from git)
			await rm(targetPath, { recursive: true, force: true })

			// Create symlink (use absolute path for source)
			await symlink(sourcePath, targetPath, "dir")
			log.info(`[worktree] Symlinked: ${dir}`)
		} catch (error) {
			log.warn(`[worktree] Failed to symlink ${dir}: ${error}`)
		}
	}
}

/**
 * Run hook commands in the worktree directory.
 */
async function runHooks(cwd: string, commands: string[], log: Logger): Promise<void> {
	for (const command of commands) {
		log.info(`[worktree] Running hook: ${command}`)
		try {
			// Use shell to properly handle quoted arguments and complex commands
			const result = Bun.spawnSync(["bash", "-c", command], {
				cwd,
				stdout: "inherit",
				stderr: "pipe",
			})
			if (result.exitCode !== 0) {
				const stderr = result.stderr?.toString() || ""
				log.warn(
					`[worktree] Hook failed (exit ${result.exitCode}): ${command}${stderr ? `\n${stderr}` : ""}`,
				)
			}
		} catch (error) {
			log.warn(`[worktree] Hook error: ${error}`)
		}
	}
}

/**
 * Load worktree-specific configuration from .opencode/worktree.jsonc
 * Auto-creates config file with helpful defaults if it doesn't exist.
 */
async function loadWorktreeConfig(directory: string, log: Logger): Promise<WorktreeConfig> {
	const configPath = path.join(directory, ".opencode", "worktree.jsonc")

	try {
		const file = Bun.file(configPath)
		if (!(await file.exists())) {
			// Auto-create config with helpful defaults and comments
			const defaultConfig = `{
  "$schema": "https://registry.kdco.dev/schemas/worktree.json",

  // Worktree plugin configuration
  // Documentation: https://github.com/kdcokenny/ocx

  "sync": {
    // Files to copy from main worktree to new worktrees
    // Example: [".env", ".env.local", "dev.sqlite"]
    "copyFiles": [],

    // Directories to symlink (saves disk space)
    // Example: ["node_modules"]
    "symlinkDirs": [],

    // Patterns to exclude from copying
    "exclude": []
  },

  "hooks": {
    // Commands to run after worktree creation
    // Example: ["pnpm install", "docker compose up -d"]
    "postCreate": [],

    // Commands to run before worktree deletion
    // Example: ["docker compose down"]
    "preDelete": []
  }
}
			`
			// Ensure .opencode directory exists
			await mkdir(path.join(directory, ".opencode"), { recursive: true })
			await Bun.write(configPath, defaultConfig)
			log.info(`[worktree] Created default config: ${configPath}`)
			return worktreeConfigSchema.parse({})
		}

		const content = await file.text()
		// Use proper JSONC parser (handles comments in strings correctly)
		const parsed = parseJsonc(content)
		if (parsed === undefined) {
			log.error(`[worktree] Invalid worktree.jsonc syntax`)
			return worktreeConfigSchema.parse({})
		}
		return worktreeConfigSchema.parse(parsed)
	} catch (error) {
		log.warn(`[worktree] Failed to load config: ${error}`)
		return worktreeConfigSchema.parse({})
	}
}

type SessionMessage = {
	info?: {
		role?: string
	}
	parts?: Array<{
		type?: string
		text?: string
	}>
}

function normalizeMessages(response: unknown): SessionMessage[] {
	if (Array.isArray(response)) return response as SessionMessage[]
	if (response && typeof response === "object" && "data" in response) {
		const data = (response as { data?: unknown }).data
		if (Array.isArray(data)) return data as SessionMessage[]
	}
	return []
}

function getMessageText(message: SessionMessage): string {
	return (message.parts ?? [])
		.filter((part) => part.type === "text" && typeof part.text === "string")
		.map((part) => part.text ?? "")
		.join("\n")
		.trim()
}

/**
 * Plan directories scanned in order. `.omo/plans/` is the canonical location used by
 * OMO's `/start-work`, atlas, sisyphus, and sisyphus-junior agents. `.sisyphus/plans/` is
 * the legacy location used by older `/prometheus-plan` skills; the bridge helper below
 * copies any plan found only at the legacy location into `.omo/plans/` before `/start-work`
 * runs, so the pipeline works regardless of which location the planner wrote to.
 */
const PLAN_DIRS = [".omo/plans", ".sisyphus/plans"] as const

async function listPlanNames(repoRoot: string): Promise<string[]> {
	const names = new Set<string>()
	for (const dir of PLAN_DIRS) {
		const plansDir = path.join(repoRoot, dir)
		try {
			const entries = await readdir(plansDir, { withFileTypes: true })
			for (const entry of entries) {
				if (entry.isFile() && entry.name.endsWith(".md")) {
					names.add(entry.name.slice(0, -3))
				}
			}
		} catch {
			// directory missing — other dir may still have plans
		}
	}
	return [...names].sort((a, b) => a.localeCompare(b))
}

/**
 * Return the absolute path of the plan file for `planName`, checking PLAN_DIRS in order.
 * Returns null if no matching file exists in any scanned directory.
 */
async function findPlanFile(repoRoot: string, planName: string): Promise<string | null> {
	for (const dir of PLAN_DIRS) {
		const candidate = path.join(repoRoot, dir, `${planName}.md`)
		if (await pathExists(candidate)) return candidate
	}
	return null
}

interface PlanBridgeResult {
	/** Canonical path the plan now exists at (always under `.omo/plans/`). */
	readonly path: string
	/** True if the plan had to be copied from `.sisyphus/plans/` to `.omo/plans/`. */
	readonly bridged: boolean
	/** Original location if `bridged` is true, otherwise null. */
	readonly sourcePath: string | null
}

/**
 * Ensure the plan exists at `.omo/plans/<name>.md` (the canonical location OMO's
 * `/start-work` reads). If the plan only exists at `.sisyphus/plans/<name>.md`, copy it
 * across so `/start-work` — which only looks under `.omo/plans/` — can find it.
 *
 * Returns the bridge result, or null if no source plan was found in any scanned dir.
 */
async function ensurePlanInOmoDir(
	repoRoot: string,
	planName: string,
	log: Logger,
): Promise<PlanBridgeResult | null> {
	const canonicalPath = path.join(repoRoot, ".omo", "plans", `${planName}.md`)
	if (await pathExists(canonicalPath)) {
		return { path: canonicalPath, bridged: false, sourcePath: null }
	}

	const sourcePath = await findPlanFile(repoRoot, planName)
	if (!sourcePath) return null

	await mkdir(path.dirname(canonicalPath), { recursive: true })
	await copyFile(sourcePath, canonicalPath)
	log.info(
		`[worktree] Bridged plan ${planName}: copied ${sourcePath} → ${canonicalPath} so /start-work can find it`,
	)
	return { path: canonicalPath, bridged: true, sourcePath }
}

function matchPlanName(requested: string, planNames: string[]): string | null {
	const lowerName = requested.trim().toLowerCase()
	if (!lowerName) return null
	const exactMatch = planNames.find((plan) => plan.toLowerCase() === lowerName)
	if (exactMatch) return exactMatch
	return planNames.find((plan) => plan.toLowerCase().includes(lowerName)) ?? null
}

function findPlanNameInText(text: string, planNames: string[]): string | null {
	const lowerText = text.toLowerCase()
	const sortedPlans = [...planNames].sort((a, b) => b.length - a.length)
	for (const planName of sortedPlans) {
		if (lowerText.includes(planName.toLowerCase())) return planName
	}
	return null
}

async function resolvePlanName(
	client: OpencodeClient,
	repoRoot: string,
	sessionId: string,
	explicitPlanName?: string,
): Promise<string | null> {
	const planNames = await listPlanNames(repoRoot)
	if (planNames.length === 0) return null
	if (explicitPlanName) return matchPlanName(explicitPlanName, planNames)

	const response = await client.session.messages({ path: { id: sessionId }, query: { limit: 50 } })
	const messages = normalizeMessages(response)
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i]
		if (message.info?.role !== "user") continue
		const text = getMessageText(message)
		if (!text) continue
		const matchedPlan = findPlanNameInText(text, planNames)
		if (matchedPlan) return matchedPlan
	}

	return null
}

function deriveBranchName(planName: string): string {
	const slug = planName
		.toLowerCase()
		.replace(/[^a-z0-9/-]+/g, "-")
		.replace(/-+/g, "-")
		.replace(/^[-/]+|[-/]+$/g, "")
		.slice(0, 200)
	return `plan/${slug || "worktree"}`
}

// =============================================================================
// PLUGIN ENTRY
// =============================================================================

export const WorktreePlugin: Plugin = async (ctx) => {
	const { directory, client, serverUrl } = ctx

	const log = {
		debug: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "debug", message: msg } })
				.catch(() => {}),
		info: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "info", message: msg } })
				.catch(() => {}),
		warn: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "warn", message: msg } })
				.catch(() => {}),
		error: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "error", message: msg } })
				.catch(() => {}),
	}

	// Initialize SQLite database
	const database = await initDb(directory)

	return {
		tool: {
			worktree_start: tool({
				description:
					"Create a worktree, open a new OpenCode session in the current TUI, and auto-run /start-work there. Call it with the plan name, just like /start-work itself.",
				args: {
					planName: tool.schema
						.string()
						.optional()
						.describe("Plan name to start. If omitted, infer from recent user messages."),
					branch: tool.schema
						.string()
						.optional()
						.describe("Branch name for the worktree. Defaults to a slug from the plan name."),
					baseBranch: tool.schema
						.string()
						.optional()
						.describe("Base branch to create from (defaults to HEAD)"),
				},
				async execute(args, toolCtx) {
					const resolvedPlanName = await resolvePlanName(
						client,
						directory,
						toolCtx.sessionID,
						args.planName,
					)

					if (!resolvedPlanName) {
						return "Could not resolve a plan name. Pass a plan name explicitly or mention the plan in the previous message before retrying."
					}

					// Bridge: ensure the plan exists at .omo/plans/ (the canonical OMO location
					// /start-work reads). If it was only at .sisyphus/plans/ (legacy /prometheus-plan
					// default), copy it across. Failure here is non-fatal: log and proceed, since
					// the plan may already be committed in the worktree's git tree.
					const planBridge = await ensurePlanInOmoDir(directory, resolvedPlanName, log)
					if (!planBridge) {
						log.warn(
							`[worktree] resolvePlanName returned "${resolvedPlanName}" but no plan file found in any scanned directory`,
						)
					}

					const branchName = args.branch ?? deriveBranchName(resolvedPlanName)
					const branchResult = branchNameSchema.safeParse(branchName)
					if (!branchResult.success) {
						return `❌ Invalid branch name: ${branchResult.error.issues[0]?.message}`
					}

					if (args.baseBranch) {
						const baseResult = branchNameSchema.safeParse(args.baseBranch)
						if (!baseResult.success) {
							return `❌ Invalid base branch name: ${baseResult.error.issues[0]?.message}`
						}
					}

					const result = await createWorktree(directory, branchName, args.baseBranch)
					if (!result.ok) {
						return `Failed to create worktree: ${result.error}`
					}

					const worktreePath = result.value
					const worktreeConfig = await loadWorktreeConfig(directory, log)
					const mainWorktreePath = directory

					if (worktreeConfig.sync.copyFiles.length > 0) {
						await copyFiles(mainWorktreePath, worktreePath, worktreeConfig.sync.copyFiles, log)
					}

					if (worktreeConfig.sync.symlinkDirs.length > 0) {
						await symlinkDirs(mainWorktreePath, worktreePath, worktreeConfig.sync.symlinkDirs, log)
					}

					if (worktreeConfig.hooks.postCreate.length > 0) {
						await runHooks(worktreePath, worktreeConfig.hooks.postCreate, log)
					}

					// Step 1: Create a new session associated with the main project
					// Use mainWorktreePath so the session is visible in the main project's TUI session list.
					// The worktree path is passed to /start-work via --worktree flag instead.
					let createdSession: { id: string }
					try {
						const created = await client.session.create({
							body: {
								title: resolvedPlanName,
							},
							query: { directory: mainWorktreePath },
						})
						createdSession = created.data ?? created
					} catch (error) {
						const msg = error instanceof Error ? error.message : String(error)
						log.warn(`[worktree] session.create failed: ${msg}`)
						return `Worktree created at ${worktreePath}\n\nFailed to create session: ${msg}`
					}

					addSession(database, {
						id: createdSession.id,
						branch: branchName,
						path: worktreePath,
						createdAt: new Date().toISOString(),
					})

					// Step 2: Navigate the TUI to the new session
					try {
						await new Promise((resolve) => setTimeout(resolve, 500))
						const transport = (client as unknown as Record<string, unknown>)
						const sessionNs = transport.session as Record<string, unknown> | undefined
						const innerClient = sessionNs?._client as Record<string, unknown> | undefined
						const post = innerClient?.post as ((opts: Record<string, unknown>) => Promise<unknown>) | undefined
						if (!post) throw new Error("Could not access SDK transport")
						await post({ url: "/tui/select-session", body: { sessionID: createdSession.id } })
					} catch (error) {
						const msg = error instanceof Error ? error.message : String(error)
						log.warn(`[worktree] tui.selectSession failed: ${msg}`)
						return `Worktree created at ${worktreePath}\nSession ${createdSession.id} created.\n\nFailed to switch TUI: ${msg}`
					}

					// Step 3: Inject the /start-work command into the TUI prompt
					try {
						await new Promise((resolve) => setTimeout(resolve, 1000))
						const promptText = `/start-work ${resolvedPlanName} --worktree ${worktreePath}`
						const innerClient = (client as unknown as Record<string, Record<string, unknown>>).session?._client as Record<string, unknown> | undefined
						const post = innerClient?.post as ((opts: Record<string, unknown>) => Promise<unknown>) | undefined
						if (!post) throw new Error("Could not access SDK transport")
						await post({ url: "/tui/append-prompt", body: { text: promptText } })
						await post({ url: "/tui/submit-prompt", body: {} })
					} catch (error) {
						const msg = error instanceof Error ? error.message : String(error)
						log.warn(`[worktree] session.promptAsync failed: ${msg}`)
						return `Worktree created at ${worktreePath}\nSession ${createdSession.id} created and TUI switched.\n\nFailed to send prompt: ${msg}`
					}

					const bridgeNote = planBridge?.bridged
						? `\n\nNote: plan was at ${planBridge.sourcePath} (legacy location); copied to ${planBridge.path} so /start-work finds it. Future plans should land in .omo/plans/ directly.`
						: ""
					return `Worktree created at ${worktreePath}\n\nA new OpenCode session has been requested and will start ${resolvedPlanName} automatically.${bridgeNote}`
				},
			}),

			worktree_create: tool({
				description:
					"Create a new git worktree for isolated development and switch the TUI to a forked session with full conversation context, ready to continue work in the worktree. No GUI terminal is opened.",
				args: {
					branch: tool.schema
						.string()
						.describe("Branch name for the worktree (e.g., 'feature/dark-mode')"),
					baseBranch: tool.schema
						.string()
						.optional()
						.describe("Base branch to create from (defaults to HEAD)"),
				},
				async execute(args, toolCtx) {
					// Validate branch name at boundary
					const branchResult = branchNameSchema.safeParse(args.branch)
					if (!branchResult.success) {
						return `❌ Invalid branch name: ${branchResult.error.issues[0]?.message}`
					}

					// Validate base branch name at boundary
					if (args.baseBranch) {
						const baseResult = branchNameSchema.safeParse(args.baseBranch)
						if (!baseResult.success) {
							return `❌ Invalid base branch name: ${baseResult.error.issues[0]?.message}`
						}
					}

					// Create worktree
					const result = await createWorktree(directory, args.branch, args.baseBranch)
					if (!result.ok) {
						return `Failed to create worktree: ${result.error}`
					}

					const worktreePath = result.value

					// Sync files from main worktree
					const worktreeConfig = await loadWorktreeConfig(directory, log)
					const mainWorktreePath = directory // The repo root is the main worktree

					// Copy files
					if (worktreeConfig.sync.copyFiles.length > 0) {
						await copyFiles(mainWorktreePath, worktreePath, worktreeConfig.sync.copyFiles, log)
					}

					// Symlink directories
					if (worktreeConfig.sync.symlinkDirs.length > 0) {
						await symlinkDirs(mainWorktreePath, worktreePath, worktreeConfig.sync.symlinkDirs, log)
					}

					// Run postCreate hooks
					if (worktreeConfig.hooks.postCreate.length > 0) {
						await runHooks(worktreePath, worktreeConfig.hooks.postCreate, log)
					}

					// Fork session with context (replaces --session resume)
					const projectId = await getProjectId(worktreePath, client)
					const { forkedSession, planCopied, delegationsCopied } = await forkWithContext(
						client,
						toolCtx.sessionID,
						projectId,
						async (sid) => {
							// Walk up parentID chain to find root session
							let currentId = sid
							for (let depth = 0; depth < MAX_SESSION_CHAIN_DEPTH; depth++) {
								const session = await client.session.get({ path: { id: currentId } })
								if (!session.data?.parentID) return currentId
								currentId = session.data.parentID
							}
							return currentId
						},
					)

					log.debug(
						`Forked session ${forkedSession.id}, plan: ${planCopied}, delegations: ${delegationsCopied}`,
					)

					// Autonomous handoff: switch the TUI to the forked session instead of
					// opening a GUI terminal. The terminal flow silently failed on
					// display-less systemd-launched servers (no DISPLAY) and was never
					// the intent; the forked session lives in the main project directory,
					// so it is visible and attachable from the running TUI.
					await new Promise((resolve) => setTimeout(resolve, 500))
					let handoffError = ""
					try {
						const innerClient = (client as unknown as Record<string, Record<string, unknown>>).session?._client as Record<string, unknown> | undefined
						const post = innerClient?.post as ((opts: Record<string, unknown>) => Promise<unknown>) | undefined
						if (!post) throw new Error("Could not access SDK transport")
						await post({ url: "/tui/select-session", body: { sessionID: forkedSession.id } })
					} catch (error) {
						handoffError = error instanceof Error ? error.message : String(error)
						log.warn(`[worktree] tui.selectSession failed: ${handoffError}`)
					}

					// Record session for tracking (used by delete flow)
					addSession(database, {
						id: forkedSession.id,
						branch: args.branch,
						path: worktreePath,
						createdAt: new Date().toISOString(),
					})

					const handoffNote = handoffError
						? `TUI switch failed (${handoffError}). Resume the session manually: opencode --session ${forkedSession.id}`
						: `The TUI has switched to the forked session — continue working there.`
					return `Worktree created at ${worktreePath}\n\n${handoffNote}`
				},
			}),

			worktree_delete: tool({
				description:
				"Delete a worktree and clean up. Without arguments, deletes the CURRENT session's worktree (it will be removed when this session goes idle). With `target` (branch name like 'plan/foo' or absolute worktree path), reclaims THAT worktree instead — callable from the main session. Uncommitted changes are snapshotted to the branch before removal; the branch is then deleted only if fully merged, otherwise kept for recovery. Refuses to remove the main repo worktree.",
				args: {
					reason: tool.schema
						.string()
						.describe("Brief explanation of why you are calling this tool"),
					target: tool.schema
						.string()
						.optional()
						.describe(
							"Branch name (e.g. 'plan/foo') or absolute path of the worktree to reclaim. Defaults to the current session's worktree.",
					),
				},
				async execute(args, toolCtx) {
					let branch: string
					let worktreePath: string

					if (args.target) {
						const listResult = await git(["worktree", "list", "--porcelain"], directory)
						if (!listResult.ok) {
							return `Failed to list worktrees: ${listResult.error}`
						}
						const resolved = resolveWorktreeTarget(listResult.value, args.target)
						if (!resolved) {
							return `No worktree matches target '${args.target}' (expected a branch name like 'plan/foo' or an absolute worktree path)`
						}
						branch = resolved.branch
						worktreePath = resolved.path
					} else {
						const session = getSession(database, toolCtx?.sessionID ?? "")
						if (!session) {
							return `No worktree associated with this session. Pass a target (branch name or worktree path) to reclaim a specific worktree.`
						}
						branch = session.branch
						worktreePath = session.path
					}

					if (path.resolve(worktreePath) === path.resolve(directory)) {
						return `Refusing to remove the main repo worktree`
					}

					// Set pending delete for session.idle (atomic operation)
					setPendingDelete(database, { branch, path: worktreePath }, client)

					return `Worktree ${branch} marked for cleanup. It will be removed when this session goes idle. Uncommitted changes will be snapshotted to the branch; the branch is deleted only if fully merged.`
				},
			}),
		},

		event: async ({ event }: { event: Event }): Promise<void> => {
			if (event.type !== "session.idle") return

			// Handle pending delete
			const pendingDelete = getPendingDelete(database)
			if (pendingDelete) {
				const { path: worktreePath, branch } = pendingDelete

				// Run preDelete hooks before cleanup
				const config = await loadWorktreeConfig(directory, log)
				if (config.hooks.preDelete.length > 0) {
					await runHooks(worktreePath, config.hooks.preDelete, log)
				}

				// Snapshot uncommitted changes — ONLY when the tree is dirty.
				// An unconditional --allow-empty commit would move the branch tip past
				// the merge point and make `git branch -d` refuse every reclaim (the
				// 2026-08 14-worktree leak, resurrected in contentless form).
				const statusResult = await git(["status", "--porcelain"], worktreePath)
				if (statusResult.ok && statusResult.value.length > 0) {
					const addResult = await git(["add", "-A"], worktreePath)
					if (!addResult.ok) log.warn(`[worktree] git add failed: ${addResult.error}`)

					const commitResult = await git(
						["commit", "-m", "chore(worktree): session snapshot"],
						worktreePath,
					)
					if (!commitResult.ok) log.warn(`[worktree] git commit failed: ${commitResult.error}`)
				}

				// Remove worktree
				const removeResult = await removeWorktree(directory, worktreePath)
				if (!removeResult.ok) {
					log.warn(`[worktree] Failed to remove worktree: ${removeResult.error}`)
				} else {
					// Delete the branch when fully merged (lowercase -d refuses unmerged —
					// a snapshot commit ahead of master stays recoverable on its branch)
					const branchResult = await git(["branch", "-d", branch], directory)
					if (!branchResult.ok) {
						log.info(`[worktree] Branch ${branch} kept (not fully merged): ${branchResult.error}`)
					}
				}

				// Clear pending delete atomically
				clearPendingDelete(database)

				// Remove session from database
				removeSession(database, branch)
			}
		},
	}
}

export default WorktreePlugin
