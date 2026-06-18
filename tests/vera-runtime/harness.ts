import { createHash } from "node:crypto"
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, unlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { basename, join } from "node:path"

const PLUGIN_PATH = join(import.meta.dir, "..", "..", "plugins", "vera-runtime.ts")

let nextFakePid = 50000
let spawnSyncCommands: string[] = []
let pluginImportCounter = 0

function setEnvFlag(name: string, enabled: boolean | undefined): void {
	if (enabled) {
		process.env[name] = "1"
		return
	}
	delete process.env[name]
}

function setupTempHome(options: { autostart?: boolean; toolUpdate?: boolean } = {}): {
	tempHome: string
	originalHome: string | undefined
	originalAutostart: string | undefined
	originalToolUpdate: string | undefined
} {
	const originalHome = process.env.HOME
	const originalAutostart = process.env.OMO_VERA_RUNTIME_AUTOSTART
	const originalToolUpdate = process.env.OMO_VERA_RUNTIME_TOOL_UPDATE
	const tempHome = mkdtempSync(join(tmpdir(), "vera-runtime-test-"))
	process.env.HOME = tempHome
	setEnvFlag("OMO_VERA_RUNTIME_AUTOSTART", options.autostart)
	setEnvFlag("OMO_VERA_RUNTIME_TOOL_UPDATE", options.toolUpdate)
	return { tempHome, originalHome, originalAutostart, originalToolUpdate }
}

function mockBunSpawnSync(overrides: {
	veraAvailable?: boolean
	pidAlive?: boolean
	veraIndexSuccess?: boolean
	veraUpdateSuccess?: boolean
	projectId?: string
	indexNonEmpty?: boolean
} = {}): () => void {
	const original = Bun.spawnSync
	Bun.spawnSync = function (cmd: any, opts?: any) {
		const cmdArray = Array.isArray(cmd) ? cmd : [String(cmd)]
		const cmdStr = cmdArray.join(" ")
		spawnSyncCommands.push(cmdStr)

		if (cmdStr.includes("command -v vera")) {
			const available = overrides.veraAvailable ?? true
			const stdout = available ? Buffer.from("/usr/bin/vera") : Buffer.from("")
			return { success: available, exitCode: available ? 0 : 1, stdout, stderr: Buffer.from("") } as any
		}

		if (cmdStr.includes("rev-parse --show-toplevel")) {
			const pid = overrides.projectId
			const stdout = pid ? Buffer.from(pid) : Buffer.from("")
			return { success: !!pid, exitCode: pid ? 0 : 1, stdout, stderr: Buffer.from("") } as any
		}

		if (cmdStr.startsWith("realpath")) {
			const path = cmdArray[1] || ""
			return { success: true, exitCode: 0, stdout: Buffer.from(path), stderr: Buffer.from("") } as any
		}

		if (cmdStr.includes("kill -0")) {
			const alive = overrides.pidAlive ?? false
			return { success: alive, exitCode: alive ? 0 : 1, stdout: Buffer.from(""), stderr: Buffer.from("") } as any
		}

		if (cmdStr.includes("vera overview")) {
			const nonEmpty = overrides.indexNonEmpty ?? true
			const stdout = nonEmpty ? Buffer.from("Files: 42\nChunks: 128") : Buffer.from("Files: 0\nChunks: 0")
			return { success: nonEmpty, exitCode: nonEmpty ? 0 : 1, stdout, stderr: Buffer.from("") } as any
		}

		if (cmdStr.includes("vera index")) {
			const success = overrides.veraIndexSuccess ?? true
			return { success, exitCode: success ? 0 : 1, stdout: Buffer.from(""), stderr: Buffer.from("") } as any
		}

		if (cmdStr.includes("vera update")) {
			const success = overrides.veraUpdateSuccess ?? true
			return { success, exitCode: success ? 0 : 1, stdout: Buffer.from(""), stderr: Buffer.from("") } as any
		}

		return original(cmd, opts)
	}
	return () => {
		Bun.spawnSync = original
	}
}

function mockBunSpawn(): () => void {
	const original = Bun.spawn
	Bun.spawn = function (cmd: any, opts?: any) {
		const cmdStr = Array.isArray(cmd) ? cmd.join(" ") : String(cmd)
		if (cmdStr.includes("vera watch")) {
			const pid = nextFakePid++
			return { pid, success: true } as any
		}
		return original(cmd, opts)
	}
	return () => {
		Bun.spawn = original
	}
}

function restoreEnv(name: string, value: string | undefined): void {
	if (value === undefined) {
		delete process.env[name]
		return
	}
	process.env[name] = value
}

function cleanup(
	tempHome: string,
	originalHome: string | undefined,
	originalAutostart: string | undefined,
	originalToolUpdate: string | undefined,
) {
	try {
		rmSync(tempHome, { recursive: true, force: true })
	} catch {}
	if (originalHome !== undefined) {
		process.env.HOME = originalHome
	}
	restoreEnv("OMO_VERA_RUNTIME_AUTOSTART", originalAutostart)
	restoreEnv("OMO_VERA_RUNTIME_TOOL_UPDATE", originalToolUpdate)
}

function installTermIgnoringVera(home: string): () => void {
	const originalPath = process.env.PATH
	const binDir = join(home, "bin")
	const veraPath = join(binDir, "vera")
	mkdirSync(binDir, { recursive: true })
	writeFileSync(
		veraPath,
		[
			"#!/usr/bin/env bash",
			"set -eo pipefail",
			"case \"$1\" in",
			"  watch)",
			"    trap '' TERM",
			"    while true; do sleep 1; done",
			"    ;;",
			"  *)",
			"    exit 0",
			"    ;;",
			"esac",
			"",
		].join("\n"),
		"utf-8",
	)
	chmodSync(veraPath, 0o755)
	process.env.PATH = `${binDir}:${originalPath ?? ""}`
	return () => restoreEnv("PATH", originalPath)
}

function fail(caseName: string, reason: string): never {
	console.error(`FAIL: ${caseName}: ${reason}`)
	process.exit(1)
}

function pass(caseName: string) {
	console.log(`PASS: ${caseName}`)
}

function createTempWorkspace(home: string): string {
	const wsDir = mkdtempSync(join(home, "workspace-"))
	return wsDir
}

function getWatchersDir(projectId: string): string {
	return join(process.env.HOME!, ".local", "share", "opencode", "worktree-state", projectId, "vera-watchers")
}

async function importPlugin(directory: string) {
	pluginImportCounter += 1
	const mod = await import(`${PLUGIN_PATH}?${Date.now()}-${pluginImportCounter}`)
	const pluginFn = mod.default
	return await pluginFn({ directory })
}

// ---------------------------------------------------------------------------
// Harness-local state helpers (replicates plugin internals for test access)
// ---------------------------------------------------------------------------

function harnessComputeWorkspaceKey(workspacePath: string): string {
	const base = basename(workspacePath)
	const hash = createHash("sha1").update(workspacePath).digest("hex").slice(0, 8)
	return `${base}-${hash}`
}

function harnessReadStateFile(workspacePath: string, projectId: string): any {
	const key = harnessComputeWorkspaceKey(workspacePath)
	const statePath = join(process.env.HOME!, ".local", "share", "opencode", "worktree-state", projectId, "vera-watchers", `${key}.json`)
	try {
		const raw = readFileSync(statePath, "utf-8")
		return JSON.parse(raw)
	} catch {
		return null
	}
}

function harnessWriteStateFile(workspacePath: string, projectId: string, state: any): void {
	const key = harnessComputeWorkspaceKey(workspacePath)
	const stateDir = join(process.env.HOME!, ".local", "share", "opencode", "worktree-state", projectId, "vera-watchers")
	const statePath = join(stateDir, `${key}.json`)
	const tempPath = `${statePath}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`
	try {
		mkdirSync(stateDir, { recursive: true })
		writeFileSync(tempPath, JSON.stringify(state, null, 2), "utf-8")
		renameSync(tempPath, statePath)
	} catch {
		try { unlinkSync(tempPath) } catch {}
	}
}

function harnessGetStateFilePath(workspacePath: string, projectId: string): string {
	const key = harnessComputeWorkspaceKey(workspacePath)
	return join(process.env.HOME!, ".local", "share", "opencode", "worktree-state", projectId, "vera-watchers", `${key}.json`)
}

// ---------------------------------------------------------------------------
// Event dispatch helpers — replace old plugin["session.created"] calls
// ---------------------------------------------------------------------------

function dispatchCreated(plugin: any, id: string, extra: Record<string, any> = {}) {
	return plugin.event({ event: { type: "session.created", properties: { session_id: id, ...extra } } })
}

function dispatchDeleted(plugin: any, id: string, extra: Record<string, any> = {}) {
	return plugin.event({ event: { type: "session.deleted", properties: { session_id: id, ...extra } } })
}

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------

async function runEventSessionCreatedBootstrap() {
	const caseName = "event-session-created-bootstrap"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		await plugin.event({ event: { type: "session.created", properties: { info: { id: "sess-bootstrap-1" } } } })

		const state = harnessReadStateFile(wsDir, "test-project")

		if (!state) {
			fail(caseName, "No state file found after session.created")
		}
		if (state.status !== "running") {
			fail(caseName, `Expected status=running, got ${state.status}`)
		}
		if (!state.pid) {
			fail(caseName, `Expected non-null pid, got ${state.pid}`)
		}
		if (!state.sessionIds.includes("sess-bootstrap-1")) {
			fail(caseName, "sessionId 'sess-bootstrap-1' not found in state")
		}

		await plugin.event({ event: { type: "session.deleted", properties: { info: { id: "sess-bootstrap-1" } } } })
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runEventSessionDeletedCleanup() {
	const caseName = "event-session-deleted-cleanup"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		await plugin.event({ event: { type: "session.created", properties: { info: { id: "sess-cleanup-1" } } } })

		const stateBefore = harnessReadStateFile(wsDir, "test-project")
		if (!stateBefore) {
			fail(caseName, "No state before deletion")
		}

		await plugin.event({ event: { type: "session.deleted", properties: { info: { id: "sess-cleanup-1" } } } })

		const stateAfter = harnessReadStateFile(wsDir, "test-project")
		if (stateAfter) {
			fail(caseName, "State file still exists after last session deleted")
		}

		const watchersDir = getWatchersDir("test-project")
		const files = readdirSync(watchersDir)
		const jsonFiles = files.filter((f: string) => f.endsWith(".json"))
		if (jsonFiles.length !== 0) {
			fail(caseName, `Expected 0 state files, found ${jsonFiles.length}`)
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runSessionDeletedEscalatesToSigkill() {
	const caseName = "session-deleted-escalates-to-sigkill"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restorePath = installTermIgnoringVera(tempHome)
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	let watcherPid: number | null = null

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		await dispatchCreated(plugin, "sess-sigkill-1")

		const stateBefore = harnessReadStateFile(wsDir, "test-project")
		if (!stateBefore?.pid) {
			fail(caseName, "No watcher PID found after session.created")
		}
		watcherPid = stateBefore.pid

		await dispatchDeleted(plugin, "sess-sigkill-1")
		await Bun.sleep(200)

		try {
			process.kill(watcherPid, 0)
			fail(caseName, `Watcher pid=${watcherPid} survived SIGKILL escalation`)
		} catch {
			// Expected: SIGTERM was ignored, SIGKILL removed the process.
		}

		const stateAfter = harnessReadStateFile(wsDir, "test-project")
		if (stateAfter) {
			fail(caseName, "State file still exists after SIGKILL cleanup")
		}
	} finally {
		if (watcherPid !== null) {
			try { process.kill(watcherPid, "SIGKILL") } catch {}
		}
		restoreSpawnSync()
		restorePath()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runSameWorkspaceDedupe() {
	const caseName = "same-workspace-dedupe"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		await dispatchCreated(plugin, "sess-1")
		await dispatchCreated(plugin, "sess-2")

		const state = harnessReadStateFile(wsDir, "test-project")

		if (!state) {
			fail(caseName, "No state file found after session.created calls")
		}

		if (state.sessionIds.length !== 2) {
			fail(caseName, `Expected 2 sessionIds, got ${state.sessionIds.length}`)
		}

		if (!state.sessionIds.includes("sess-1")) {
			fail(caseName, "sess-1 not in sessionIds")
		}

		if (!state.sessionIds.includes("sess-2")) {
			fail(caseName, "sess-2 not in sessionIds")
		}

		const watchersDir = getWatchersDir("test-project")
		const files = readdirSync(watchersDir)
		const jsonFiles = files.filter((f: string) => f.endsWith(".json"))

		if (jsonFiles.length !== 1) {
			fail(caseName, `Expected exactly 1 state file, found ${jsonFiles.length}`)
		}

		await dispatchDeleted(plugin, "sess-1")
		await dispatchDeleted(plugin, "sess-2")
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runCrossWorkspaceIsolation() {
	const caseName = "cross-workspace-isolation"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsA = createTempWorkspace(tempHome)
		const wsB = createTempWorkspace(tempHome)

		const pluginA = await importPlugin(wsA)
		const pluginB = await importPlugin(wsB)

		await dispatchCreated(pluginA, "sess-a-1")
		await dispatchCreated(pluginB, "sess-b-1")

		const stateA = harnessReadStateFile(wsA, "test-project")
		const stateB = harnessReadStateFile(wsB, "test-project")

		if (!stateA) {
			fail(caseName, "No state file found for workspace A")
		}
		if (!stateB) {
			fail(caseName, "No state file found for workspace B")
		}

		if (stateA.pid === stateB.pid) {
			fail(caseName, `Workspaces A and B have same pid: ${stateA.pid}`)
		}

		if (stateA.status !== "running") {
			fail(caseName, `Workspace A: expected status=running, got ${stateA.status}`)
		}
		if (stateB.status !== "running") {
			fail(caseName, `Workspace B: expected status=running, got ${stateB.status}`)
		}

		const watchersDir = getWatchersDir("test-project")
		const files = readdirSync(watchersDir)
		const jsonFiles = files.filter((f: string) => f.endsWith(".json"))

		if (jsonFiles.length !== 2) {
			fail(caseName, `Expected exactly 2 state files, found ${jsonFiles.length}`)
		}

		await dispatchDeleted(pluginA, "sess-a-1")
		await dispatchDeleted(pluginB, "sess-b-1")
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runStalePidRecovery() {
	const caseName = "stale-pid-recovery"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: false })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)

		const key = harnessComputeWorkspaceKey(wsDir)
		const initialState = {
			workspaceKey: key,
			workspacePath: wsDir,
			projectId: "test-project",
			pid: 99999,
			status: "running",
			sessionIds: ["sess-stale-1"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: `${harnessGetStateFilePath(wsDir, "test-project").replace(/\.json$/, ".log")}`,
			lastIndexedAt: new Date().toISOString(),
			startedAt: new Date().toISOString(),
			lastVerifiedAt: new Date().toISOString(),
			lastFailureAt: null,
			lastFailureReason: null,
		}
		harnessWriteStateFile(wsDir, "test-project", initialState)

		const plugin = await importPlugin(wsDir)

		await dispatchCreated(plugin, "sess-stale-1")

		const state = harnessReadStateFile(wsDir, "test-project")
		if (!state) {
			fail(caseName, "No state file found after session.created")
		}

		if (state.pid === 99999) {
			fail(caseName, `Stale PID 99999 was not replaced, still ${state.pid}`)
		}

		if (state.status !== "running") {
			fail(caseName, `Expected status=running after recovery, got ${state.status}`)
		}

		await dispatchDeleted(plugin, "sess-stale-1")
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runMissingVeraFailsOpen() {
	const caseName = "missing-vera-fails-open"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	let restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project" })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		restoreSpawnSync()
		restoreSpawnSync = mockBunSpawnSync({ veraAvailable: false, projectId: "test-project" })

		let threw = false
		try {
			await dispatchCreated(plugin, "sess-missing-1")
		} catch {
			threw = true
		}

		if (threw) {
			fail(caseName, "session.created threw when vera binary is missing")
		}

		const state = harnessReadStateFile(wsDir, "test-project")

		if (!state) {
			fail(caseName, "No state file found")
		}

		if (state.status !== "missing-binary") {
			fail(caseName, `Expected status=missing-binary, got ${state.status}`)
		}

		try {
			await dispatchDeleted(plugin, "sess-missing-1")
		} catch {}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runUnknownEventNoop() {
	const caseName = "unknown-event-noop"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		await plugin.event({ event: { type: "session.status", properties: { session_id: "sess-unknown-1" } } })

		const state = harnessReadStateFile(wsDir, "test-project")

		if (state) {
			fail(caseName, "Watcher state was created for unknown event type 'session.status'")
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runSessionIdShapes() {
	const caseName = "session-id-shapes"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		{
			const ws = createTempWorkspace(tempHome)
			const plugin = await importPlugin(ws)
			await plugin.event({ event: { type: "session.created", properties: { info: { id: "sess-upstream" } } } })

			const state = harnessReadStateFile(ws, "test-project")
			if (!state || !state.sessionIds.includes("sess-upstream")) {
				fail(caseName, "upstream-info shape (info.id) did not resolve to 'sess-upstream'")
			}

			await plugin.event({ event: { type: "session.deleted", properties: { info: { id: "sess-upstream" } } } })
		}

		{
			const ws = createTempWorkspace(tempHome)
			const plugin = await importPlugin(ws)
			await plugin.event({ event: { type: "session.created", properties: { session_id: "sess-legacy" } } })

			const state = harnessReadStateFile(ws, "test-project")
			if (!state || !state.sessionIds.includes("sess-legacy")) {
				fail(caseName, "legacy-wrapper shape (session_id) did not resolve to 'sess-legacy'")
			}

			await plugin.event({ event: { type: "session.deleted", properties: { session_id: "sess-legacy" } } })
		}

		{
			const ws = createTempWorkspace(tempHome)
			const plugin = await importPlugin(ws)
			await plugin.event({ event: { type: "session.created", id: "sess-direct" } })

			const state = harnessReadStateFile(ws, "test-project")
			if (!state || !state.sessionIds.includes("sess-direct")) {
				fail(caseName, "direct shape (event.id) did not resolve to 'sess-direct'")
			}

			await plugin.event({ event: { type: "session.deleted", id: "sess-direct" } })
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runDefaultManualMode() {
	const caseName = "default-manual-mode"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome()
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: false })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const plugin = await importPlugin(wsDir)

		await dispatchCreated(plugin, "sess-manual-1")

		const state = harnessReadStateFile(wsDir, "test-project")
		if (!state) {
			fail(caseName, "No state file found after session.created")
		}
		if (state.status !== "stopped") {
			fail(caseName, `Expected status=stopped in default manual mode, got ${state.status}`)
		}
		if (state.pid !== null) {
			fail(caseName, `Expected pid=null in default manual mode, got ${state.pid}`)
		}
		if (state.automationMode !== "manual") {
			fail(caseName, `Expected automationMode=manual, got ${state.automationMode}`)
		}
		if (!state.sessionIds.includes("sess-manual-1")) {
			fail(caseName, "sess-manual-1 not in sessionIds")
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runUnsafePidStateRejected() {
	const caseName = "unsafe-pid-state-rejected"
	const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)
		const markerPath = join(tempHome, "pid-injection-marker")
		const key = harnessComputeWorkspaceKey(wsDir)
		const state = {
			workspaceKey: key,
			workspacePath: wsDir,
			projectId: "test-project",
			pid: `1; touch ${markerPath}`,
			status: "running",
			sessionIds: ["sess-unsafe-1"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: `${harnessGetStateFilePath(wsDir, "test-project").replace(/\.json$/, ".log")}`,
			lastIndexedAt: new Date().toISOString(),
			startedAt: new Date().toISOString(),
			lastVerifiedAt: new Date().toISOString(),
			lastFailureAt: null,
			lastFailureReason: null,
			automationMode: "autostart",
		}
		harnessWriteStateFile(wsDir, "test-project", state)

		const plugin = await importPlugin(wsDir)
		await dispatchCreated(plugin, "sess-unsafe-1")
		await dispatchDeleted(plugin, "sess-unsafe-1")

		if (existsSync(markerPath)) {
			fail(caseName, "malicious PID string was executed during session.created/session.deleted")
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
	}

	pass(caseName)
}

async function runToolUpdateOptInBehavior() {
	const caseName = "tool-update-opt-in-behavior"
	const disabledEnv = setupTempHome({ autostart: true })
	let restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", veraUpdateSuccess: true })
	let restoreSpawn = mockBunSpawn()

	try {
		spawnSyncCommands = []
		const wsDir = createTempWorkspace(disabledEnv.tempHome)
		const plugin = await importPlugin(wsDir)
		await dispatchCreated(plugin, "sess-tool-disabled")
		plugin["tool.execute.before"]({ tool: "task" }, {})

		if (spawnSyncCommands.some((cmd) => cmd.includes("vera update"))) {
			fail(caseName, "vera update ran while OMO_VERA_RUNTIME_TOOL_UPDATE was disabled")
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(disabledEnv.tempHome, disabledEnv.originalHome, disabledEnv.originalAutostart, disabledEnv.originalToolUpdate)
	}

	const enabledEnv = setupTempHome({ autostart: true, toolUpdate: true })
	restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", veraUpdateSuccess: true })
	restoreSpawn = mockBunSpawn()

	try {
		spawnSyncCommands = []
		const wsDir = createTempWorkspace(enabledEnv.tempHome)
		const plugin = await importPlugin(wsDir)
		await dispatchCreated(plugin, "sess-tool-enabled")

		const state = harnessReadStateFile(wsDir, "test-project")
		if (!state) {
			fail(caseName, "No state file found for enabled case")
		}
		state.lastIndexedAt = "2000-01-01T00:00:00.000Z"
		harnessWriteStateFile(wsDir, "test-project", state)

		plugin["tool.execute.before"]({ tool: "task" }, {})

		if (!spawnSyncCommands.some((cmd) => cmd.includes("vera update"))) {
			fail(caseName, "vera update did not run when OMO_VERA_RUNTIME_TOOL_UPDATE was enabled and index was stale")
		}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(enabledEnv.tempHome, enabledEnv.originalHome, enabledEnv.originalAutostart, enabledEnv.originalToolUpdate)
	}

	pass(caseName)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
	const args = process.argv.slice(2)
	const caseIdx = args.indexOf("--case")
	const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null

	{
		const { tempHome, originalHome, originalAutostart, originalToolUpdate } = setupTempHome({ autostart: true })
		const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project" })
		try {
			const guardPlugin = await importPlugin(createTempWorkspace(tempHome))
			if (typeof (guardPlugin as any)["session.created"] !== "undefined") {
				fail("guard-plugin-hooks", "plugin['session.created'] must be undefined (event dispatch only)")
			}
			if (typeof (guardPlugin as any)["session.deleted"] !== "undefined") {
				fail("guard-plugin-hooks", "plugin['session.deleted'] must be undefined (event dispatch only)")
			}
			pass("guard-plugin-hooks")
		} finally {
			restoreSpawnSync()
			cleanup(tempHome, originalHome, originalAutostart, originalToolUpdate)
		}
	}

	const testMap: Record<string, () => Promise<void>> = {
		"default-manual-mode": runDefaultManualMode,
		"event-session-created-bootstrap": runEventSessionCreatedBootstrap,
		"event-session-deleted-cleanup": runEventSessionDeletedCleanup,
		"session-deleted-escalates-to-sigkill": runSessionDeletedEscalatesToSigkill,
		"same-workspace-dedupe": runSameWorkspaceDedupe,
		"cross-workspace-isolation": runCrossWorkspaceIsolation,
		"stale-pid-recovery": runStalePidRecovery,
		"missing-vera-fails-open": runMissingVeraFailsOpen,
		"unknown-event-noop": runUnknownEventNoop,
		"session-id-shapes": runSessionIdShapes,
		"unsafe-pid-state-rejected": runUnsafePidStateRejected,
		"tool-update-opt-in-behavior": runToolUpdateOptInBehavior,
	}

	if (testCase) {
		const fn = testMap[testCase]
		if (!fn) {
			console.error(`Unknown test case: ${testCase}`)
			console.error("Valid cases:", Object.keys(testMap).join(", "))
			process.exit(1)
		}
		await fn()
	} else {
		for (const fn of Object.values(testMap)) {
			await fn()
		}
	}

	// Explicit exit to stop lingering health check timers
	process.exit(0)
}

main().catch((err) => {
	console.error(`UNEXPECTED ERROR: ${err?.message ?? err}`)
	console.error(err?.stack ?? "")
	process.exit(1)
})
