import { appendFileSync, existsSync, mkdirSync, unlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join, posix, resolve } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"
import { Mutex } from "./kdco-primitives/mutex.ts"

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
	/** Maximum session parent-chain walk depth when resolving root sessions */
	maxSessionChainDepth: 32,
	/** v1 semantic checkpoint scaffolding constants */
	semantic: {
		helperSessionTitlePrefix: "[auto-checkpoint helper]",
		helperTimeoutMs: 45_000,
		helperPollIntervalMs: 1_000,
		proposalMaxDiffBytes: 120_000,
		maxCandidateFiles: 40,
		model: "github-copilot/gpt-5.4-mini",
	},
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
	title?: string
	cwd: string
	repoRoot?: string
	rootSessionId: string
	parentId?: string
	childIds: Set<string>
	lastToolAt: number
	lastIdleAt: number
	lastCommitAt: number
	lastCommitSha?: string
	baselineCaptured: boolean
	baselineDirtyPaths: Set<string>
	ownedPaths: Map<string, string>
	conflictPaths: Set<string>
	pendingToolSnapshot?: {
		at: number
		tool: string
		sessionId: string
		rootSessionId: string
		repoRoot: string
		beforeDirtyPaths: Set<string>
	}
	lastSemanticSkipReason?: string
	timer?: Timer
}

interface GitStatus {
	isDirty: boolean
	shortSha: string
	branch: string
}

interface DirtyPathSnapshot {
	repoRoot: string
	paths: Set<string>
	entries: PorcelainStatusEntry[]
	renamePairs: RenamePair[]
}

type PorcelainEntryKind =
	| "modified"
	| "added"
	| "deleted"
	| "renamed"
	| "copied"
	| "untracked"
	| "unknown"

interface RenamePair {
	oldPath: string
	newPath: string
}

interface PorcelainStatusEntry {
	indexStatus: string
	workTreeStatus: string
	kind: PorcelainEntryKind
	path: string
	paths: string[]
	oldPath?: string
	newPath?: string
}

interface CandidatePathCollection {
	repoRoot: string
	paths: string[]
	renamePairs: RenamePair[]
}

interface CandidateDiffPayload extends CandidatePathCollection {
	skipped: boolean
	skipReason?: string
	diffText: string
	diffBytes: number
}

type EventInput = {
	event: { type: string; properties?: Record<string, unknown> }
}

type RootSessionClient = {
	session: {
		get: (args: { path: { id: string } }) => Promise<{ data?: { parentID?: string | null } }>
	}
}

type AutoCheckpointClient = {
	app: {
		log: (args: { body: { service: string; level: string; message: string } }) => Promise<unknown>
	}
	session: {
		get: (args: { path: { id: string } }) => Promise<{ data?: { parentID?: string | null } }>
		create: (args: {
			path?: Record<string, never>
			body: { title: string; directory: string }
		}) => Promise<{ data?: { id?: string } } | { id?: string }>
		promptAsync: (args: {
			path: { id: string }
			body: { agent: string; model: string; parts: Array<{ text: string }> }
		}) => Promise<unknown>
		messages: (args: { path: { id: string }; query?: { limit?: number } }) => Promise<{ data?: unknown } | unknown>
		delete: (args: { path: { id: string } }) => Promise<unknown>
	}
}

interface SemanticProposal {
	confidence: "high"
	files: string[]
	summary: string
}

interface SemanticHelperSession {
	id: string
	title: string
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

function extractSessionId(event: { type: string; properties?: Record<string, unknown>; id?: string; session_id?: string; sessionId?: string; sessionID?: string }): string {
	const props = event.properties ?? {}
	return (
		(event.id as string) ??
		(event.session_id as string) ??
		(event.sessionId as string) ??
		(event.sessionID as string) ??
		(props.session_id as string) ??
		(props.sessionId as string) ??
		(props.sessionID as string) ??
		(props.id as string) ??
		""
	)
}

function extractSessionTitle(event: { properties?: Record<string, unknown> }): string {
	const props = event.properties ?? {}
	return ((props.title as string) ?? (props.sessionTitle as string) ?? "").trim()
}

function extractParentSessionId(properties?: Record<string, unknown>): string | undefined {
	if (!properties) return undefined
	return (
		(properties.parentSessionId as string) ??
		(properties.parentID as string) ??
		(properties.parentId as string) ??
		undefined
	)
}

function isHelperSession(title: string): boolean {
	return title.startsWith(CONFIG.semantic.helperSessionTitlePrefix)
}

function shouldIgnoreHelperSession(sessionId: string, title: string): boolean {
	if (helperSessionIds.has(sessionId)) {
		return true
	}

	if (!title || !isHelperSession(title)) {
		return false
	}

	helperSessionIds.add(sessionId)
	return true
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

async function git(
	args: string[],
	cwd: string,
	env?: Record<string, string>,
): Promise<Result<string, string>> {
	try {
		const proc = Bun.spawn(["git", ...args], {
			cwd,
			stdout: "pipe",
			stderr: "pipe",
			env: env ? { ...process.env, ...env } : undefined,
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
		git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], cwd),
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

function normalizeRepoRelativePath(filePath: string): string {
	let normalized = filePath.trim()

	const renameArrow = normalized.indexOf(" -> ")
	if (renameArrow >= 0) {
		normalized = normalized.slice(renameArrow + 4)
	}

	if (normalized.startsWith('"') && normalized.endsWith('"') && normalized.length >= 2) {
		normalized = normalized.slice(1, -1)
		normalized = normalized.replace(/\\(["\\])/g, "$1")
	}

	normalized = normalized.replaceAll("\\", "/")
	while (normalized.startsWith("./")) {
		normalized = normalized.slice(2)
	}

	return posix.normalize(normalized)
}

function classifyPorcelainEntryKind(indexStatus: string, workTreeStatus: string): PorcelainEntryKind {
	if (indexStatus === "?" && workTreeStatus === "?") {
		return "untracked"
	}

	if (indexStatus === "R" || workTreeStatus === "R") {
		return "renamed"
	}

	if (indexStatus === "C" || workTreeStatus === "C") {
		return "copied"
	}

	if (indexStatus === "A" || workTreeStatus === "A") {
		return "added"
	}

	if (indexStatus === "D" || workTreeStatus === "D") {
		return "deleted"
	}

	if (indexStatus === "M" || workTreeStatus === "M") {
		return "modified"
	}

	return "unknown"
}

function parsePorcelainV1Z(porcelainOutput: string): {
	paths: Set<string>
	entries: PorcelainStatusEntry[]
	renamePairs: RenamePair[]
} {
	const paths = new Set<string>()
	const entries: PorcelainStatusEntry[] = []
	const renamePairs: RenamePair[] = []
	const records = porcelainOutput.split("\0")

	for (let idx = 0; idx < records.length; idx++) {
		const record = records[idx]
		if (!record || record.length < 3) {
			continue
		}

		const indexStatus = record[0]
		const workTreeStatus = record[1]
		const pathStartIndex = record[2] === " " ? 3 : 2
		const primaryRawPath = record.slice(pathStartIndex)
		const kind = classifyPorcelainEntryKind(indexStatus, workTreeStatus)
		const hasSecondaryPath =
			indexStatus === "R" || workTreeStatus === "R" || indexStatus === "C" || workTreeStatus === "C"

		if (hasSecondaryPath) {
			const secondaryRawPath = records[idx + 1] ?? ""
			idx += 1

			// porcelain=v1 -z reports rename/copy path tokens in reverse order
			// relative to human-readable "old -> new" output: first token is
			// destination path and second token is source path.
			const newPath = normalizeRepoRelativePath(primaryRawPath)
			const oldPath = normalizeRepoRelativePath(secondaryRawPath)
			const relatedPaths = [oldPath, newPath].filter(
				(candidate): candidate is string => Boolean(candidate) && candidate !== ".",
			)

			if (relatedPaths.length === 0) {
				continue
			}

			for (const path of relatedPaths) {
				paths.add(path)
			}

			if (oldPath && oldPath !== "." && newPath && newPath !== ".") {
				renamePairs.push({ oldPath, newPath })
			}

			entries.push({
				indexStatus,
				workTreeStatus,
				kind,
				path: newPath || oldPath,
				paths: relatedPaths,
				oldPath: oldPath || undefined,
				newPath: newPath || undefined,
			})
			continue
		}

		const normalized = normalizeRepoRelativePath(primaryRawPath)
		if (!normalized || normalized === ".") {
			continue
		}

		paths.add(normalized)
		entries.push({
			indexStatus,
			workTreeStatus,
			kind,
			path: normalized,
			paths: [normalized],
		})
	}

	return { paths, entries, renamePairs }
}

async function getDirtyPathSnapshot(cwd: string): Promise<Result<DirtyPathSnapshot, string>> {
	const repoRootResult = await git(["rev-parse", "--show-toplevel"], cwd)
	if (!repoRootResult.ok) {
		return Result.err(repoRootResult.error)
	}

	const repoRoot = resolve(repoRootResult.value)
	const porcelainResult = await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], repoRoot)
	if (!porcelainResult.ok) {
		return Result.err(porcelainResult.error)
	}

	const parsedStatus = parsePorcelainV1Z(porcelainResult.value)

	return Result.ok({
		repoRoot,
		paths: parsedStatus.paths,
		entries: parsedStatus.entries,
		renamePairs: parsedStatus.renamePairs,
	})
}

function buildRootCandidatePathSet(rootState: SessionState, snapshot: DirtyPathSnapshot): Set<string> {
	const candidatePaths = new Set<string>()

	for (const dirtyPath of snapshot.paths) {
		if (rootState.ownedPaths.get(dirtyPath) === rootState.sessionId) {
			candidatePaths.add(dirtyPath)
		}
	}

	for (const baselinePath of rootState.baselineDirtyPaths) {
		candidatePaths.delete(baselinePath)
	}

	for (const conflictPath of rootState.conflictPaths) {
		candidatePaths.delete(conflictPath)
	}

	for (const conflictPath of getRepoConflictPathSet(snapshot.repoRoot)) {
		candidatePaths.delete(conflictPath)
	}

	return candidatePaths
}

function collectCandidateRenamePairs(
	renamePairs: RenamePair[],
	candidatePaths: Set<string>,
): RenamePair[] {
	const linkedPairs: RenamePair[] = []

	for (const pair of renamePairs) {
		if (candidatePaths.has(pair.oldPath) || candidatePaths.has(pair.newPath)) {
			linkedPairs.push(pair)
		}
	}

	return linkedPairs
}

function parseNumstatEntries(output: string): Array<{ added: string; deleted: string; path: string }> {
	if (!output) {
		return []
	}

	const rows = output.split("\n")
	const parsed: Array<{ added: string; deleted: string; path: string }> = []

	for (const row of rows) {
		if (!row) continue
		const [added, deleted, ...pathParts] = row.split("\t")
		if (!added || !deleted || pathParts.length === 0) {
			continue
		}
		parsed.push({
			added,
			deleted,
			path: pathParts.join("\t"),
		})
	}

	return parsed
}

async function hasBinaryOrUnreadableCandidates(
	repoRoot: string,
	candidatePaths: string[],
): Promise<Result<boolean, string>> {
	if (candidatePaths.length === 0) {
		return Result.ok(false)
	}

	const diffTargets = [
		["diff", "--numstat", "--", ...candidatePaths],
		["diff", "--numstat", "--cached", "--", ...candidatePaths],
	] as const

	for (const args of diffTargets) {
		const result = await git([...args], repoRoot)
		if (!result.ok) {
			return Result.err(result.error)
		}

		const numstatEntries = parseNumstatEntries(result.value)
		if (numstatEntries.some((entry) => entry.added === "-" && entry.deleted === "-")) {
			return Result.ok(true)
		}
	}

	return Result.ok(false)
}

async function collectCandidateDiffText(repoRoot: string, candidatePaths: string[]): Promise<Result<string, string>> {
	if (candidatePaths.length === 0) {
		return Result.ok("")
	}

	const outputs: string[] = []
	const diffTargets = [
		["diff", "--no-color", "--", ...candidatePaths],
		["diff", "--no-color", "--cached", "--", ...candidatePaths],
	] as const

	for (const args of diffTargets) {
		const result = await git([...args], repoRoot)
		if (!result.ok) {
			return Result.err(result.error)
		}
		if (result.value) {
			outputs.push(result.value)
		}
	}

	return Result.ok(outputs.join("\n\n"))
}

export async function getCandidatePaths(rootSessionId: string): Promise<Result<CandidatePathCollection, string>> {
	const trackedRootId = resolveTrackedSessionId(rootSessionId)
	const rootState = sessions.get(trackedRootId)
	if (!rootState) {
		return Result.err(`unknown root session: ${trackedRootId}`)
	}

	const snapshotResult = await getDirtyPathSnapshot(rootState.cwd)
	if (!snapshotResult.ok) {
		return Result.err(snapshotResult.error)
	}

	const snapshot = snapshotResult.value
	rootState.repoRoot = snapshot.repoRoot
	const candidatePathSet = buildRootCandidatePathSet(rootState, snapshot)

	return Result.ok({
		repoRoot: snapshot.repoRoot,
		paths: [...candidatePathSet].sort(),
		renamePairs: collectCandidateRenamePairs(snapshot.renamePairs, candidatePathSet),
	})
}

export async function getCandidateDiffPayload(
	rootSessionId: string,
): Promise<Result<CandidateDiffPayload, string>> {
	const candidatePathsResult = await getCandidatePaths(rootSessionId)
	if (!candidatePathsResult.ok) {
		return candidatePathsResult
	}

	const candidatePaths = candidatePathsResult.value.paths
	const payloadBase = {
		repoRoot: candidatePathsResult.value.repoRoot,
		paths: candidatePaths,
		renamePairs: candidatePathsResult.value.renamePairs,
		diffText: "",
		diffBytes: 0,
	}

	if (candidatePaths.length === 0) {
		return Result.ok({
			...payloadBase,
			skipped: true,
			skipReason: "no-candidates",
		})
	}

	if (candidatePaths.length > CONFIG.semantic.maxCandidateFiles) {
		return Result.ok({
			...payloadBase,
			skipped: true,
			skipReason: "candidate-count-overflow",
		})
	}

	const binaryCheckResult = await hasBinaryOrUnreadableCandidates(
		candidatePathsResult.value.repoRoot,
		candidatePaths,
	)
	if (!binaryCheckResult.ok) {
		return Result.ok({
			...payloadBase,
			skipped: true,
			skipReason: "candidate-unreadable",
		})
	}

	if (binaryCheckResult.value) {
		return Result.ok({
			...payloadBase,
			skipped: true,
			skipReason: "binary-candidate",
		})
	}

	const diffResult = await collectCandidateDiffText(candidatePathsResult.value.repoRoot, candidatePaths)
	if (!diffResult.ok) {
		return Result.ok({
			...payloadBase,
			skipped: true,
			skipReason: "candidate-unreadable",
		})
	}

	const diffText = diffResult.value
	const diffBytes = new TextEncoder().encode(diffText).byteLength
	if (diffBytes > CONFIG.semantic.proposalMaxDiffBytes) {
		return Result.ok({
			...payloadBase,
			diffText,
			diffBytes,
			skipped: true,
			skipReason: "diff-budget-overflow",
		})
	}

	return Result.ok({
		...payloadBase,
		diffText,
		diffBytes,
		skipped: false,
	})
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms))
}

function normalizeSessionMessages(response: unknown): SessionMessage[] {
	if (Array.isArray(response)) return response as SessionMessage[]
	if (response && typeof response === "object" && "data" in response) {
		const data = (response as { data?: unknown }).data
		if (Array.isArray(data)) return data as SessionMessage[]
	}
	return []
}

function getLatestAssistantText(messages: SessionMessage[]): string | undefined {
	for (let idx = messages.length - 1; idx >= 0; idx--) {
		const message = messages[idx]
		if (message.info?.role !== "assistant") continue
		const text = (message.parts ?? [])
			.filter((part) => part.type === "text" && typeof part.text === "string")
			.map((part) => part.text ?? "")
			.join("\n")
			.trim()
		if (text) return text
	}
	return undefined
}

function isRepoRelativeNormalizedPath(filePath: string): boolean {
	if (!filePath || filePath.includes("\\")) {
		return false
	}
	if (filePath.startsWith("/") || filePath.startsWith("../") || filePath === "..") {
		return false
	}
	if (filePath.includes("/../") || filePath.includes("/./")) {
		return false
	}
	const normalized = normalizeRepoRelativePath(filePath)
	return normalized === filePath && normalized !== "." && !normalized.startsWith("../")
}

function isSafeCheckpointSummary(summary: string): boolean {
	if (!summary.trim()) {
		return false
	}
	if (/[\r\n]/.test(summary)) {
		return false
	}
	for (const character of summary) {
		const codePoint = character.codePointAt(0)
		if (typeof codePoint !== "number") continue
		if ((codePoint >= 0 && codePoint <= 31) || codePoint === 127) {
			return false
		}
	}
	return true
}

function normalizeSessionCreateResponseID(response: unknown): string | undefined {
	if (!response || typeof response !== "object") return undefined
	const data = (response as { data?: { id?: string }; id?: string }).data
	if (typeof data?.id === "string" && data.id) return data.id
	const fallback = (response as { id?: string }).id
	if (typeof fallback === "string" && fallback) return fallback
	return undefined
}

function buildSemanticProposalPrompt(args: {
	rootSessionTitle: string
	rootShortID: string
	candidatePaths: string[]
	diffPayload: string
}): string {
	const schema = '{ "confidence": "high|medium|low", "files": ["path1", "path2"], "summary": "brief description" }'
	return [
		"Return ONLY raw JSON. No markdown, no prose, no code fences.",
		"Choose files only from candidatePaths; never include out-of-scope files.",
		`rootSessionTitle=${JSON.stringify(args.rootSessionTitle)}`,
		`rootShortId=${JSON.stringify(args.rootShortID)}`,
		`candidatePaths=${JSON.stringify(args.candidatePaths)}`,
		`diffPayload=${JSON.stringify(args.diffPayload)}`,
		`responseSchema=${schema}`,
	].join("\n")
}

export async function createSemanticHelperSession(args: {
	client: AutoCheckpointClient
	rootSessionId: string
	rootSessionTitle: string
	rootDirectory: string
}): Promise<Result<SemanticHelperSession, string>> {
	const compactRootTitle = (args.rootSessionTitle || "checkpoint").replace(/[\r\n\t]/g, " ").replace(/\s+/g, " ").trim() || "checkpoint"
	const rootShortID = (args.rootSessionId || "unknown").slice(0, 8)
	const helperTitle = `${CONFIG.semantic.helperSessionTitlePrefix} ${rootShortID} ${compactRootTitle}`

	try {
		const response = await args.client.session.create({
			path: {},
			body: {
				title: helperTitle,
				directory: args.rootDirectory,
			},
		})
		const id = normalizeSessionCreateResponseID(response)
		if (!id) {
			return Result.err("helper-session-create-missing-id")
		}

		return Result.ok({ id, title: helperTitle })
	} catch (error) {
		return Result.err(error instanceof Error ? error.message : String(error))
	}
}

export async function sendSemanticProposal(args: {
	client: AutoCheckpointClient
	helperSessionId: string
	rootSessionTitle: string
	rootShortID: string
	candidatePaths: string[]
	diffPayload: string
}): Promise<Result<void, string>> {
	const promptText = buildSemanticProposalPrompt({
		rootSessionTitle: args.rootSessionTitle,
		rootShortID: args.rootShortID,
		candidatePaths: args.candidatePaths,
		diffPayload: args.diffPayload,
	})

	try {
		await args.client.session.promptAsync({
			path: { id: args.helperSessionId },
			body: {
				agent: "auto-checkpoint",
				model: CONFIG.semantic.model,
				parts: [{ text: promptText }],
			},
		})
		return Result.ok(undefined)
	} catch (error) {
		return Result.err(error instanceof Error ? error.message : String(error))
	}
}

export async function pollForHelperResponse(args: {
	client: AutoCheckpointClient
	helperSessionId: string
}): Promise<Result<string, string>> {
	const startedAt = Date.now()
	while (Date.now() - startedAt < CONFIG.semantic.helperTimeoutMs) {
		try {
			const messagesResponse = await args.client.session.messages({
				path: { id: args.helperSessionId },
				query: { limit: 100 },
			})
			const assistantText = getLatestAssistantText(normalizeSessionMessages(messagesResponse))
			if (assistantText) {
				return Result.ok(assistantText)
			}
		} catch (error) {
			return Result.err(error instanceof Error ? error.message : String(error))
		}

		await sleep(CONFIG.semantic.helperPollIntervalMs)
	}

	return Result.err("helper-timeout")
}

export function validateSemanticProposal(args: {
	responseText: string
	candidatePaths: string[]
	conflictPaths: Set<string>
}): Result<SemanticProposal, string> {
	let parsed: unknown
	try {
		parsed = JSON.parse(args.responseText)
	} catch {
		return Result.err("invalid-json")
	}

	if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
		return Result.err("invalid-shape")
	}

	const proposal = parsed as {
		confidence?: unknown
		files?: unknown
		summary?: unknown
	}

	if (proposal.confidence !== "high") {
		return Result.err("confidence-not-high")
	}

	if (!Array.isArray(proposal.files) || proposal.files.length === 0) {
		return Result.err("files-empty")
	}

	const candidateSet = new Set(args.candidatePaths)
	const uniqueFiles = new Set<string>()

	for (const candidate of proposal.files) {
		if (typeof candidate !== "string") {
			return Result.err("file-invalid-type")
		}

		const normalized = normalizeRepoRelativePath(candidate)
		if (!isRepoRelativeNormalizedPath(normalized) || normalized !== candidate.trim()) {
			return Result.err("file-not-normalized")
		}

		if (!candidateSet.has(normalized)) {
			return Result.err("file-out-of-scope")
		}

		if (args.conflictPaths.has(normalized)) {
			return Result.err("file-conflicted")
		}

		if (uniqueFiles.has(normalized)) {
			return Result.err("files-not-unique")
		}

		uniqueFiles.add(normalized)
	}

	const summary = typeof proposal.summary === "string" ? proposal.summary.trim() : ""
	if (!isSafeCheckpointSummary(summary)) {
		return Result.err("summary-unsafe")
	}

	return Result.ok({
		confidence: "high",
		files: [...uniqueFiles],
		summary,
	})
}

export async function resolveSemanticProposal(args: {
	client: AutoCheckpointClient
	rootState: SessionState
	rootSessionId: string
	rootTitle: string
	payload: CandidateDiffPayload
}): Promise<Result<SemanticProposal, string>> {
	const helperSession = await createSemanticHelperSession({
		client: args.client,
		rootSessionId: args.rootSessionId,
		rootSessionTitle: args.rootTitle,
		rootDirectory: args.rootState.cwd,
	})

	if (!helperSession.ok) {
		return helperSession
	}

	helperSessionIds.add(helperSession.value.id)

	try {
		const sendResult = await sendSemanticProposal({
			client: args.client,
			helperSessionId: helperSession.value.id,
			rootSessionTitle: args.rootTitle,
			rootShortID: (args.rootSessionId || "unknown").slice(0, 8),
			candidatePaths: args.payload.paths,
			diffPayload: args.payload.diffText,
		})
		if (!sendResult.ok) {
			return sendResult
		}

		const responseResult = await pollForHelperResponse({
			client: args.client,
			helperSessionId: helperSession.value.id,
		})
		if (!responseResult.ok) {
			return responseResult
		}

		const conflictPaths = new Set<string>([
			...args.rootState.conflictPaths,
			...getRepoConflictPathSet(args.payload.repoRoot),
		])
		return validateSemanticProposal({
			responseText: responseResult.value,
			candidatePaths: args.payload.paths,
			conflictPaths,
		})
	} finally {
		await args.client.session.delete({ path: { id: helperSession.value.id } }).catch((error) => {
			const errorMessage = error instanceof Error ? error.message : String(error)
			log("warn", `helper session delete failed — session=${helperSession.value.id}, error=${errorMessage}`)
		})
		helperSessionIds.delete(helperSession.value.id)
	}
}

async function isGitOperationInProgress(cwd: string): Promise<boolean> {
	const checks = await Promise.all([
		git(["rev-parse", "--git-path", "rebase-merge"], cwd),
		git(["rev-parse", "--git-path", "rebase-apply"], cwd),
		git(["rev-parse", "--git-path", "MERGE_HEAD"], cwd),
		git(["rev-parse", "--git-path", "CHERRY_PICK_HEAD"], cwd),
	])

	// git rev-parse --git-path resolves paths but does NOT check existence.
	// Without the existsSync check, this guard fires on every evaluation
	// because the resolved path is always non-empty even when no operation
	// is in progress.
	return checks.some((r) => {
		if (!r.ok || !r.value) return false
		return existsSync(resolve(cwd, r.value))
	})
}

async function createCheckpointCommit(
	cwd: string,
	semanticProposal: SemanticProposal,
	sessionId: string,
): Promise<Result<string, string>> {
	const tmpIndexPath = join(
		tmpdir(),
		`auto-checkpoint-index-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
	)
	const tmpPathspecPath = join(
		tmpdir(),
		`auto-checkpoint-pathspec-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
	)

	try {
		const readTreeResult = await git(["read-tree", "HEAD"], cwd, {
			GIT_INDEX_FILE: tmpIndexPath,
		})
		if (!readTreeResult.ok) {
			return Result.err(`git read-tree failed: ${readTreeResult.error}`)
		}

		writeFileSync(
			tmpPathspecPath,
			Buffer.from(`${semanticProposal.files.join("\0")}\0`, "utf8"),
		)

		const addResult = await git(
			["add", "--pathspec-from-file", tmpPathspecPath, "--pathspec-file-nul"],
			cwd,
			{ GIT_INDEX_FILE: tmpIndexPath },
		)
		if (!addResult.ok) {
			return Result.err(`git add failed: ${addResult.error}`)
		}

		const stagedResult = await git(
			["diff", "--cached", "--name-only", "-z"],
			cwd,
			{ GIT_INDEX_FILE: tmpIndexPath },
		)
		if (!stagedResult.ok) {
			return Result.err(`git diff --cached failed: ${stagedResult.error}`)
		}

		const stagedFiles = stagedResult.value
			.split("\0")
			.filter((f) => f.length > 0)
			.sort()
		const expectedFiles = [...semanticProposal.files].sort()

		if (JSON.stringify(stagedFiles) !== JSON.stringify(expectedFiles)) {
			return Result.err(
				`staged set mismatch: expected ${JSON.stringify(expectedFiles)}, got ${JSON.stringify(stagedFiles)}`,
			)
		}

		const timestamp = new Date().toISOString()
		const summary = semanticProposal.summary || "checkpoint"
		const message = `checkpoint(agent): ${summary} [session=${sessionId.slice(0, 8)}] [${timestamp}]`

		const headTreeResult = await git(["rev-parse", "HEAD^{tree}"], cwd)
		if (!headTreeResult.ok) {
			return Result.err(`git rev-parse HEAD^{tree} failed: ${headTreeResult.error}`)
		}
		const headTreeSha = headTreeResult.value

		const writeTreeResult = await git(["write-tree"], cwd, {
			GIT_INDEX_FILE: tmpIndexPath,
		})
		if (!writeTreeResult.ok) {
			return Result.err(`git write-tree failed: ${writeTreeResult.error}`)
		}
		const treeSha = writeTreeResult.value

		if (treeSha === headTreeSha) {
			return Result.ok("no changes")
		}

		const commitTreeResult = await git(
			["commit-tree", treeSha, "-p", "HEAD", "-m", message],
			cwd,
		)
		if (!commitTreeResult.ok) {
			return Result.err(`git commit-tree failed: ${commitTreeResult.error}`)
		}
		const commitSha = commitTreeResult.value

		const updateRefResult = await git(["update-ref", "HEAD", commitSha], cwd)
		if (!updateRefResult.ok) {
			return Result.err(`git update-ref failed: ${updateRefResult.error}`)
		}

		return Result.ok(message)
	} finally {
		try {
			unlinkSync(tmpIndexPath)
		} catch {
			// intentionally swallowed
		}
		try {
			unlinkSync(tmpPathspecPath)
		} catch {
			// intentionally swallowed
		}
	}
}

// =============================================================================
// SESSION STATE MANAGEMENT
// =============================================================================

const sessions = new Map<string, SessionState>()
const worktreeMutexes = new Map<string, Mutex>()
const helperSessionIds = new Set<string>()
const repoOwnedPaths = new Map<string, Map<string, string>>()
const repoConflictPaths = new Map<string, Set<string>>()

function getRepoOwnedPathMap(repoRoot: string): Map<string, string> {
	let map = repoOwnedPaths.get(repoRoot)
	if (!map) {
		map = new Map<string, string>()
		repoOwnedPaths.set(repoRoot, map)
	}
	return map
}

function getRepoConflictPathSet(repoRoot: string): Set<string> {
	let set = repoConflictPaths.get(repoRoot)
	if (!set) {
		set = new Set<string>()
		repoConflictPaths.set(repoRoot, set)
	}
	return set
}

function markPathConflicted(repoRoot: string, filePath: string, roots: string[], reason: string): void {
	const owners = getRepoOwnedPathMap(repoRoot)
	const conflicts = getRepoConflictPathSet(repoRoot)

	owners.delete(filePath)
	conflicts.add(filePath)

	for (const rootSessionId of roots) {
		const rootState = sessions.get(rootSessionId)
		if (!rootState) continue
		rootState.conflictPaths.add(filePath)
		rootState.ownedPaths.delete(filePath)
	}

	log(
		"debug",
		`path attribution conflict — path=${filePath}, repo=${repoRoot}, reason=${reason}, roots=${roots.join(",")}`,
	)
}

function attributePathsForRoot(
	rootState: SessionState,
	repoRoot: string,
	newDirtyPaths: Set<string>,
): void {
	const owners = getRepoOwnedPathMap(repoRoot)
	const conflicts = getRepoConflictPathSet(repoRoot)

	for (const filePath of newDirtyPaths) {
		if (rootState.baselineDirtyPaths.has(filePath)) {
			markPathConflicted(repoRoot, filePath, [rootState.sessionId], "baseline-dirty")
			continue
		}

		if (conflicts.has(filePath)) {
			rootState.conflictPaths.add(filePath)
			rootState.ownedPaths.delete(filePath)
			log(
				"debug",
				`path attribution skip — path=${filePath}, root=${rootState.sessionId}, reason=already-conflicted`,
			)
			continue
		}

		const existingOwner = owners.get(filePath)
		if (!existingOwner) {
			owners.set(filePath, rootState.sessionId)
			rootState.ownedPaths.set(filePath, rootState.sessionId)
			rootState.conflictPaths.delete(filePath)
			log("debug", `path attributed — path=${filePath}, root=${rootState.sessionId}`)
			continue
		}

		if (existingOwner !== rootState.sessionId) {
			markPathConflicted(repoRoot, filePath, [existingOwner, rootState.sessionId], "owned-by-another-root")
			continue
		}

		rootState.ownedPaths.set(filePath, rootState.sessionId)
		rootState.conflictPaths.delete(filePath)
		log("debug", `path remains root-owned — path=${filePath}, root=${rootState.sessionId}`)
	}
}

async function ensureRootBaselineSnapshot(rootState: SessionState): Promise<void> {
	if (rootState.baselineCaptured) {
		return
	}

	const snapshotResult = await getDirtyPathSnapshot(rootState.cwd)
	if (!snapshotResult.ok) {
		log(
			"warn",
			`baseline snapshot skipped — root=${rootState.sessionId}, cwd=${rootState.cwd}, error=${snapshotResult.error}`,
		)
		return
	}

	const snapshot = snapshotResult.value
	rootState.repoRoot = snapshot.repoRoot
	rootState.baselineDirtyPaths = new Set(snapshot.paths)
	rootState.baselineCaptured = true

	log(
		"debug",
		`baseline snapshot captured — root=${rootState.sessionId}, repo=${snapshot.repoRoot}, paths=${snapshot.paths.size}`,
	)
}

async function resolveRootSessionId(client: RootSessionClient, sessionId: string): Promise<string> {
	let currentId = sessionId
	for (let depth = 0; depth < CONFIG.maxSessionChainDepth; depth++) {
		const session = await client.session.get({ path: { id: currentId } })
		const parentID = session.data?.parentID
		if (!parentID) return currentId
		currentId = parentID
	}
	return currentId
}

function getWorktreeMutex(cwd: string): Mutex {
	let mutex = worktreeMutexes.get(cwd)
	if (!mutex) {
		mutex = new Mutex()
		worktreeMutexes.set(cwd, mutex)
	}
	return mutex
}

function getSession(sessionId: string, cwd: string, rootSessionId = sessionId): SessionState {
	let state = sessions.get(sessionId)
	if (!state) {
		state = {
			sessionId,
			cwd,
			rootSessionId,
			childIds: new Set(),
			lastToolAt: 0,
			lastIdleAt: 0,
			lastCommitAt: 0,
			baselineCaptured: false,
			baselineDirtyPaths: new Set(),
			ownedPaths: new Map(),
			conflictPaths: new Set(),
		}
		sessions.set(sessionId, state)
	} else {
		state.rootSessionId = rootSessionId
		state.cwd = cwd
	}
	if (state.rootSessionId === state.sessionId) {
		state.rootSessionId = state.sessionId
	}
	return state
}

function resolveTrackedSessionId(sessionId: string): string {
	const state = sessions.get(sessionId)
	if (!state) return sessionId
	return state.rootSessionId
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
	client: AutoCheckpointClient,
): Promise<void> {
	const trackedSessionId = resolveTrackedSessionId(sessionId)
	const state = sessions.get(trackedSessionId)
	if (!state) {
		log("debug", `evaluateCheckpoint: no state for session ${trackedSessionId}`)
		return
	}

	if (helperSessionIds.has(trackedSessionId)) {
		state.lastSemanticSkipReason = "helper-session"
		log("debug", `SKIP (helper session) — session=${trackedSessionId}`)
		return
	}

	const now = Date.now()

	// Guard: not idle long enough
	if (now - state.lastIdleAt < CONFIG.idleMs) {
		state.lastSemanticSkipReason = "not-idle-long-enough"
		log("debug", `SKIP (not idle long enough) — session=${trackedSessionId}`)
		return
	}

	// Guard: not quiet long enough
	if (now - state.lastToolAt < CONFIG.quietMs) {
		state.lastSemanticSkipReason = "not-quiet-long-enough"
		log("debug", `SKIP (not quiet long enough) — session=${trackedSessionId}`)
		return
	}

	// Guard: has active descendant sessions
	if (hasActiveDescendants(trackedSessionId)) {
		state.lastSemanticSkipReason = "has-active-descendants"
		log("debug", `SKIP (has active descendants) — session=${trackedSessionId}`)
		return
	}

	// Guard: cooldown
	if (now - state.lastCommitAt < CONFIG.cooldownMs) {
		state.lastSemanticSkipReason = "cooldown"
		log("debug", `SKIP (cooldown) — session=${trackedSessionId}`)
		return
	}

	const cwd = state.cwd

	// Guard: not in git repo
	const inRepo = await isInGitRepo(cwd)
	if (!inRepo) {
		state.lastSemanticSkipReason = "not-in-git-repo"
		log("debug", `SKIP (not in git repo) — session=${trackedSessionId}`)
		return
	}

	// Guard: git operation in progress
	if (await isGitOperationInProgress(cwd)) {
		state.lastSemanticSkipReason = "git-operation-in-progress"
		log("info", `SKIP (git operation in progress) — session=${trackedSessionId}`)
		return
	}

	// Get git status (pre-mutex snapshot for SHA revalidation)
	const preMutexStatusResult = await getGitStatus(cwd)
	if (!preMutexStatusResult.ok) {
		state.lastSemanticSkipReason = "git-status-failed"
		log("warn", `SKIP (git status failed) — ${preMutexStatusResult.error}`)
		return
	}

	const preMutexStatus = preMutexStatusResult.value

	// Guard: tree is clean
	if (!preMutexStatus.isDirty) {
		state.lastSemanticSkipReason = "tree-clean"
		log("debug", `SKIP (tree clean) — session=${trackedSessionId}`)
		return
	}

	// Guard: dedup — same SHA as last commit
	if (state.lastCommitSha && state.lastCommitSha === preMutexStatus.shortSha) {
		state.lastSemanticSkipReason = "dedup-same-sha"
		log("debug", `SKIP (dedup — same SHA) — session=${trackedSessionId}`)
		return
	}

	// Acquire worktree mutex — all expensive work happens inside
	const mutex = getWorktreeMutex(cwd)
	const committed = await mutex.runExclusive(async () => {
		// Revalidate: still idle long enough (use captured `now` because Date.now()
		// may have been restored by test infrastructure before the async mutex
		// callback resumes; in production the difference is negligible.)
		if (now - state.lastIdleAt < CONFIG.idleMs) {
			state.lastSemanticSkipReason = "not-idle-long-enough"
			log("debug", `SKIP (not idle long enough) — session=${trackedSessionId}`)
			return false
		}

		// Revalidate: still quiet long enough
		if (now - state.lastToolAt < CONFIG.quietMs) {
			state.lastSemanticSkipReason = "not-quiet-long-enough"
			log("debug", `SKIP (not quiet long enough) — session=${trackedSessionId}`)
			return false
		}

		// Revalidate: git operation still not in progress
		if (await isGitOperationInProgress(cwd)) {
			state.lastSemanticSkipReason = "git-operation-in-progress"
			log("info", `SKIP (git operation in progress) — session=${trackedSessionId}`)
			return false
		}

		// Revalidate: tree still dirty and SHA unchanged
		const statusResult = await getGitStatus(cwd)
		if (!statusResult.ok) {
			state.lastSemanticSkipReason = "git-status-failed"
			log("warn", `SKIP (git status failed) — ${statusResult.error}`)
			return false
		}

		const status = statusResult.value

		if (!status.isDirty) {
			state.lastSemanticSkipReason = "tree-clean"
			log("debug", `SKIP (tree clean) — session=${trackedSessionId}`)
			return false
		}

		if (preMutexStatus.shortSha !== status.shortSha) {
			state.lastSemanticSkipReason = "sha-changed-since-pre-check"
			log("debug", `SKIP (SHA changed since pre-mutex check) — session=${trackedSessionId}`)
			return false
		}

		if (state.lastCommitSha && state.lastCommitSha === status.shortSha) {
			state.lastSemanticSkipReason = "dedup-same-sha"
			log("debug", `SKIP (dedup — same SHA) — session=${trackedSessionId}`)
			return false
		}

		// Expensive: collect candidate diff payload
		const payloadResult = await getCandidateDiffPayload(trackedSessionId)
		if (!payloadResult.ok) {
			state.lastSemanticSkipReason = "semantic-candidate-collection-failed"
			log("warn", `SKIP (semantic candidate collection failed) — ${payloadResult.error}`)
			return false
		}

		const payload = payloadResult.value
		if (payload.skipped) {
			state.lastSemanticSkipReason = payload.skipReason ?? "semantic-candidate-skipped"
			log("debug", `SKIP (semantic payload skipped) — session=${trackedSessionId}, reason=${state.lastSemanticSkipReason}`)
			return false
		}

		// Expensive: resolve semantic proposal
		const semanticResult = await resolveSemanticProposal({
			client,
			rootState: state,
			rootSessionId: trackedSessionId,
			rootTitle: state.title || sessionTitle,
			payload,
		})

		if (!semanticResult.ok) {
			state.lastSemanticSkipReason = `semantic-${semanticResult.error}`
			log("debug", `SKIP (semantic proposal rejected) — session=${trackedSessionId}, reason=${semanticResult.error}`)
			return false
		}

		const semanticProposal = semanticResult.value

		log("info", `CHECKPOINT — session=${trackedSessionId}, cwd=${cwd}, branch=${status.branch}`)

		const result = await createCheckpointCommit(cwd, semanticProposal, trackedSessionId)

		if (result.ok) {
			// Get new HEAD SHA after successful commit
			const newHeadResult = await git(["rev-parse", "--short", "HEAD"], cwd)
			const newHeadSha = newHeadResult.ok ? newHeadResult.value : status.shortSha

			state.lastCommitAt = Date.now()
			state.lastCommitSha = newHeadSha
			state.lastSemanticSkipReason = undefined
			log("info", `COMMITTED — ${result.value}`)
			await client.app.log({
				body: {
					service: "auto-checkpoint",
					level: "info",
					message: `Checkpoint created: ${result.value}; files=${semanticProposal.files.join(",")}`,
				},
			}).catch(() => {})
			return true
		}

		// Map specific commit errors to skip reasons
		if (result.error.includes("staged set mismatch")) {
			state.lastSemanticSkipReason = "staged-set-mismatch"
		} else {
			state.lastSemanticSkipReason = "commit-failed"
		}
		log("error", `COMMIT FAILED — ${result.error}`)
		await client.app.log({
			body: {
				service: "auto-checkpoint",
				level: "warn",
				message: `Checkpoint failed: ${result.error}`,
			},
		}).catch(() => {})
		return false
	})

	if (committed) {
		log("info", `Checkpoint complete for session ${trackedSessionId}`)
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
				const { event } = input
				const sessionID = extractSessionId(event)
				if (!sessionID) return
				const title = extractSessionTitle(event)

			try {
				if (event.type === "session.created") {
					const props = event.properties || {}
					const parentId = extractParentSessionId(props)
					const cwd = (props.directory as string) || directory

					if (shouldIgnoreHelperSession(sessionID, title)) {
						log("info", `session.created — ${sessionID} (helper ignored)`)
						return
					}

					const rootSessionId = await resolveRootSessionId(client, sessionID)

					const state = getSession(sessionID, cwd, rootSessionId)
					state.parentId = parentId
					state.title = title
					state.lastSemanticSkipReason = undefined

					const rootState = getSession(rootSessionId, cwd, rootSessionId)
					if (!rootState.title) {
						rootState.title = title
					}
					rootState.lastSemanticSkipReason = undefined
					if (!parentId) {
						await ensureRootBaselineSnapshot(rootState)
					}

					if (parentId) {
						const parent = getSession(parentId, cwd, rootSessionId)
						parent.childIds.add(sessionID)
						log(
							"info",
							`session.created — ${sessionID} (child of ${parentId}, root=${rootSessionId})`,
						)
					} else {
						log("info", `session.created — ${sessionID} (root session)`)
					}
					return
				}

				if (event.type === "session.deleted") {
					if (shouldIgnoreHelperSession(sessionID, title)) {
						helperSessionIds.delete(sessionID)
						log("info", `session.deleted — ${sessionID} (helper ignored)`)
						return
					}

					const state = sessions.get(sessionID)
					if (state) {
						if (state.parentId) {
							const parent = sessions.get(state.parentId)
							if (parent) {
								parent.childIds.delete(sessionID)
							}
						}
						if (state.timer) {
							clearTimeout(state.timer)
						}
						sessions.delete(sessionID)
						log("info", `session.deleted — ${sessionID}`)
					}
					return
				}

				if (event.type === "session.idle" || event.type === "session.status") {
					if (shouldIgnoreHelperSession(sessionID, title)) {
						return
					}

					const props = event.properties || {}
					const cwd = (props.directory as string) || directory
					const rootSessionId = await resolveRootSessionId(client, sessionID)
					const sessionState = getSession(sessionID, cwd, rootSessionId)
					const rootState = getSession(rootSessionId, cwd, rootSessionId)
					const now = Date.now()

					sessionState.lastIdleAt = now
					if (rootState.sessionId !== sessionState.sessionId) {
						rootState.lastIdleAt = now
					}

					if (rootState.timer) {
						clearTimeout(rootState.timer)
					}

					rootState.timer = setTimeout(() => {
						evaluateCheckpoint(rootSessionId, title, client as unknown as AutoCheckpointClient)
					}, CONFIG.idleMs + CONFIG.quietMs)

					if (sessionState.timer && sessionState.timer !== rootState.timer) {
						clearTimeout(sessionState.timer)
						sessionState.timer = undefined
					}

					return
				}
			} catch (err) {
				const errMsg = err instanceof Error ? err.message : String(err)
				log("error", `Unhandled error in event hook — ${errMsg}`)
			}
		},

		// =================================================================
		// HOOK: tool.execute.before — snapshot dirty paths before tool runs
		// =================================================================
		"tool.execute.before": async (input, _output) => {
			try {
				const sessionId = input.sessionID
				if (!sessionId || helperSessionIds.has(sessionId)) {
					return
				}

				const existingState = sessions.get(sessionId)
				const cwd = existingState?.cwd ?? directory
				const rootSessionId = await resolveRootSessionId(client, sessionId)
				const state = getSession(sessionId, cwd, rootSessionId)
				const rootState = getSession(rootSessionId, cwd, rootSessionId)

				const snapshotResult = await getDirtyPathSnapshot(rootState.cwd)
				if (!snapshotResult.ok) {
					rootState.pendingToolSnapshot = undefined
					log(
						"debug",
						`tool before snapshot skipped — session=${sessionId}, root=${rootState.sessionId}, error=${snapshotResult.error}`,
					)
					return
				}

				const snapshot = snapshotResult.value
				rootState.repoRoot = snapshot.repoRoot

				if (!rootState.baselineCaptured) {
					rootState.baselineDirtyPaths = new Set(snapshot.paths)
					rootState.baselineCaptured = true
					log(
						"debug",
						`baseline snapshot captured — root=${rootState.sessionId}, repo=${snapshot.repoRoot}, paths=${snapshot.paths.size}`,
					)
				}

				const now = Date.now()
				rootState.pendingToolSnapshot = {
					at: now,
					tool: input.tool,
					sessionId,
					rootSessionId: rootState.sessionId,
					repoRoot: snapshot.repoRoot,
					beforeDirtyPaths: new Set(snapshot.paths),
				}

				if (rootState.sessionId !== state.sessionId) {
					log(
						"debug",
						`tool before snapshot rolled up — session=${state.sessionId}, root=${rootState.sessionId}, paths=${snapshot.paths.size}`,
					)
				}
			} catch (err) {
				const errMsg = err instanceof Error ? err.message : String(err)
				log("error", `Unhandled error in tool.execute.before — ${errMsg}`)
			}
		},

		// =================================================================
		// HOOK: tool.execute.after — track tool completions
		// =================================================================
		"tool.execute.after": async (input, output) => {
			try {
				const sessionId = input.sessionID
				if (!sessionId || helperSessionIds.has(sessionId)) {
					return
				}

				const existingState = sessions.get(sessionId)
				const cwd = existingState?.cwd ?? directory
				const rootSessionId = await resolveRootSessionId(client, sessionId)
				const state = getSession(sessionId, cwd, rootSessionId)
				const rootState = getSession(rootSessionId, cwd, rootSessionId)
				const now = Date.now()
				const pendingSnapshot = rootState.pendingToolSnapshot

				rootState.lastToolAt = now
				if (rootState.sessionId !== sessionId) {
					log(
						"debug",
						`tool activity rolled up — session=${sessionId}, root=${rootState.sessionId}`,
					)
				}

				state.lastToolAt = now

				if (
					pendingSnapshot &&
					pendingSnapshot.rootSessionId === rootState.sessionId &&
					pendingSnapshot.sessionId === sessionId &&
					pendingSnapshot.tool === input.tool
				) {
					const afterSnapshotResult = await getDirtyPathSnapshot(rootState.cwd)
					if (!afterSnapshotResult.ok) {
						log(
							"warn",
							`tool after snapshot failed — session=${sessionId}, root=${rootState.sessionId}, error=${afterSnapshotResult.error}`,
						)
					} else {
						const afterSnapshot = afterSnapshotResult.value
						rootState.repoRoot = afterSnapshot.repoRoot

						if (!rootState.baselineCaptured) {
							rootState.baselineDirtyPaths = new Set(pendingSnapshot.beforeDirtyPaths)
							rootState.baselineCaptured = true
							log(
								"debug",
								`baseline snapshot captured — root=${rootState.sessionId}, repo=${pendingSnapshot.repoRoot}, paths=${pendingSnapshot.beforeDirtyPaths.size}`,
							)
						}

						if (afterSnapshot.repoRoot !== pendingSnapshot.repoRoot) {
							log(
								"warn",
								`tool snapshot repo mismatch — session=${sessionId}, root=${rootState.sessionId}, before=${pendingSnapshot.repoRoot}, after=${afterSnapshot.repoRoot}`,
							)
						} else {
							const newDirtyPaths = new Set<string>()
							for (const filePath of afterSnapshot.paths) {
								if (!pendingSnapshot.beforeDirtyPaths.has(filePath)) {
									newDirtyPaths.add(filePath)
								}
							}

							attributePathsForRoot(rootState, pendingSnapshot.repoRoot, newDirtyPaths)
						}
					}
				} else if (!rootState.baselineCaptured) {
					await ensureRootBaselineSnapshot(rootState)
				}

				rootState.pendingToolSnapshot = undefined

				// For task() tool, register child session from metadata
				if (input.tool === "task") {
					const metadata = output.metadata as { sessionId?: string } | undefined
					if (metadata?.sessionId) {
						const childSessionId = metadata.sessionId
						const parentState = sessions.get(sessionId)
						if (parentState) {
							if (helperSessionIds.has(childSessionId)) {
								return
							}

							// Register child with parent's cwd (inherited directory)
							const childState = getSession(
								childSessionId,
								parentState.cwd,
								parentState.rootSessionId,
							)
							childState.parentId = sessionId
							parentState.childIds.add(childSessionId)
							log(
								"info",
								`task launched — child=${childSessionId}, parent=${sessionId}, root=${parentState.rootSessionId}`,
							)
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
