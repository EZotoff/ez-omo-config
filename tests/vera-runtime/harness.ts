import { mkdtempSync, rmSync, readdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const PLUGIN_PATH = join(import.meta.dir, "..", "..", "plugins", "vera-runtime.ts")

let _originalHome: string | undefined
let _tempHome: string | null = null
let _pluginModule: any = null

function setupTempHome(): string {
	if (_tempHome) return _tempHome
	_originalHome = process.env.HOME
	_tempHome = mkdtempSync(join(tmpdir(), "vera-runtime-test-"))
	process.env.HOME = _tempHome
	return _tempHome
}

async function loadPluginModule() {
	if (!_pluginModule) {
		_pluginModule = await import(`${PLUGIN_PATH}?${Date.now()}`)
	}
	return _pluginModule
}

function cleanup() {
	if (_tempHome) {
		try {
			rmSync(_tempHome, { recursive: true, force: true })
		} catch {}
		_tempHome = null
	}
	if (_originalHome !== undefined) {
		process.env.HOME = _originalHome
	}
}

function fail(caseName: string, reason: string): never {
	console.error(`FAIL: ${caseName}: ${reason}`)
	process.exit(1)
}

function pass(caseName: string) {
	console.log(`PASS: ${caseName}`)
}

function createTempWorkspace(): string {
	const home = setupTempHome()
	const wsDir = mkdtempSync(join(home, "workspace-"))
	return wsDir
}

function makeMockState(partial: Partial<any> = {}): any {
	return {
		workspaceKey: partial.workspaceKey ?? "",
		workspacePath: partial.workspacePath ?? "",
		projectId: partial.projectId ?? "",
		pid: partial.pid ?? null,
		status: partial.status ?? "stopped",
		sessionIds: partial.sessionIds ?? [],
		indexPath: partial.indexPath ?? "",
		watchLogPath: partial.watchLogPath ?? "",
		lastIndexedAt: partial.lastIndexedAt ?? null,
		startedAt: partial.startedAt ?? null,
		lastVerifiedAt: partial.lastVerifiedAt ?? null,
		lastFailureAt: partial.lastFailureAt ?? null,
		lastFailureReason: partial.lastFailureReason ?? null,
	}
}

async function runSameWorkspaceDedupe() {
	const caseName = "same-workspace-dedupe"
	const wsDir = createTempWorkspace()

	try {
		const mod = await loadPluginModule()
		const { computeWorkspaceKey, getStateFilePath, readWatcherState, writeWatcherState } = mod

		const key1 = computeWorkspaceKey(wsDir)
		const key2 = computeWorkspaceKey(wsDir)
		if (key1 !== key2) {
			fail(caseName, `workspaceKey not deterministic: ${key1} !== ${key2}`)
		}

		const stateFile = getStateFilePath(wsDir)
		if (!stateFile.endsWith(`${key1}.json`)) {
			fail(caseName, `state file path incorrect: ${stateFile}`)
		}

		const state1 = makeMockState({
			workspaceKey: key1,
			workspacePath: wsDir,
			projectId: "ez-omo-config",
			status: "running",
			pid: 12345,
			sessionIds: ["session-1"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: stateFile.replace(/\.json$/, ".log"),
		})

		writeWatcherState(wsDir, state1)

		const read1 = readWatcherState(wsDir)
		if (!read1) {
			fail(caseName, "readWatcherState returned null after first write")
		}
		if (read1.pid !== 12345) {
			fail(caseName, `expected pid=12345, got ${read1.pid}`)
		}
		if (read1.status !== "running") {
			fail(caseName, `expected status=running, got ${read1.status}`)
		}

		const state2 = makeMockState({
			workspaceKey: key1,
			workspacePath: wsDir,
			projectId: "ez-omo-config",
			status: "stopped",
			pid: null,
			sessionIds: ["session-1", "session-2"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: stateFile.replace(/\.json$/, ".log"),
		})

		writeWatcherState(wsDir, state2)

		const read2 = readWatcherState(wsDir)
		if (!read2) {
			fail(caseName, "readWatcherState returned null after second write")
		}
		if (read2.status !== "stopped") {
			fail(caseName, `expected status=stopped after overwrite, got ${read2.status}`)
		}
		if (read2.sessionIds.length !== 2) {
			fail(caseName, `expected 2 sessionIds after overwrite, got ${read2.sessionIds.length}`)
		}

		const watchersDir = join(stateFile, "..")
		const files = readdirSync(watchersDir)
		const jsonFiles = files.filter((f: string) => f.endsWith(".json"))
		if (jsonFiles.length !== 1) {
			fail(caseName, `expected exactly 1 state file, found ${jsonFiles.length}`)
		}
	} finally {
		try { rmSync(wsDir, { recursive: true, force: true }) } catch {}
	}

	pass(caseName)
}

async function runCrossWorkspaceIsolation() {
	const caseName = "cross-workspace-isolation"
	const wsA = createTempWorkspace()
	const wsB = createTempWorkspace()

	try {
		const mod = await loadPluginModule()
		const { computeWorkspaceKey, getStateFilePath, readWatcherState, writeWatcherState } = mod

		const keyA = computeWorkspaceKey(wsA)
		const keyB = computeWorkspaceKey(wsB)

		if (keyA === keyB) {
			fail(caseName, `different workspaces produced identical keys: ${keyA}`)
		}

		const statePathA = getStateFilePath(wsA)
		const statePathB = getStateFilePath(wsB)

		if (statePathA === statePathB) {
			fail(caseName, "different workspaces mapped to same state file path")
		}

		const stateA = makeMockState({
			workspaceKey: keyA,
			workspacePath: wsA,
			projectId: "ez-omo-config",
			status: "running",
			pid: 11111,
			sessionIds: ["sess-a-1"],
			indexPath: `${wsA}/.vera`,
			watchLogPath: statePathA.replace(/\.json$/, ".log"),
		})

		const stateB = makeMockState({
			workspaceKey: keyB,
			workspacePath: wsB,
			projectId: "ez-omo-config",
			status: "indexed",
			pid: 22222,
			sessionIds: ["sess-b-1"],
			indexPath: `${wsB}/.vera`,
			watchLogPath: statePathB.replace(/\.json$/, ".log"),
		})

		writeWatcherState(wsA, stateA)
		writeWatcherState(wsB, stateB)

		const readA = readWatcherState(wsA)
		const readB = readWatcherState(wsB)

		if (!readA) {
			fail(caseName, "readWatcherState returned null for workspace A")
		}
		if (!readB) {
			fail(caseName, "readWatcherState returned null for workspace B")
		}

		if (readA.pid !== 11111) {
			fail(caseName, `workspace A: expected pid=11111, got ${readA.pid}`)
		}
		if (readA.status !== "running") {
			fail(caseName, `workspace A: expected status=running, got ${readA.status}`)
		}

		if (readB.pid !== 22222) {
			fail(caseName, `workspace B: expected pid=22222, got ${readB.pid}`)
		}
		if (readB.status !== "indexed") {
			fail(caseName, `workspace B: expected status=indexed, got ${readB.status}`)
		}
	} finally {
		try { rmSync(wsA, { recursive: true, force: true }) } catch {}
		try { rmSync(wsB, { recursive: true, force: true }) } catch {}
	}

	pass(caseName)
}

async function runStalePidRecovery() {
	const caseName = "stale-pid-recovery"
	const wsDir = createTempWorkspace()

	try {
		const mod = await loadPluginModule()
		const { computeWorkspaceKey, getStateFilePath, readWatcherState, writeWatcherState } = mod

		const key = computeWorkspaceKey(wsDir)
		const statePath = getStateFilePath(wsDir)

		const staleState = makeMockState({
			workspaceKey: key,
			workspacePath: wsDir,
			projectId: "ez-omo-config",
			status: "running",
			pid: 99999,
			sessionIds: ["sess-stale-1"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: statePath.replace(/\.json$/, ".log"),
		})

		writeWatcherState(wsDir, staleState)

		const readStale = readWatcherState(wsDir)
		if (!readStale) {
			fail(caseName, "readWatcherState returned null for stale state")
		}
		if (readStale.pid !== 99999) {
			fail(caseName, `expected stale pid=99999, got ${readStale.pid}`)
		}
		if (readStale.status !== "running") {
			fail(caseName, `expected status=running for stale state, got ${readStale.status}`)
		}

		const recoveredState = makeMockState({
			workspaceKey: key,
			workspacePath: wsDir,
			projectId: "ez-omo-config",
			status: "stopped",
			pid: null,
			sessionIds: ["sess-stale-1"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: statePath.replace(/\.json$/, ".log"),
		})

		writeWatcherState(wsDir, recoveredState)

		const readRecovered = readWatcherState(wsDir)
		if (!readRecovered) {
			fail(caseName, "readWatcherState returned null after recovery write")
		}
		if (readRecovered.pid !== null) {
			fail(caseName, `expected recovered pid=null, got ${readRecovered.pid}`)
		}
		if (readRecovered.status !== "stopped") {
			fail(caseName, `expected recovered status=stopped, got ${readRecovered.status}`)
		}
	} finally {
		try { rmSync(wsDir, { recursive: true, force: true }) } catch {}
	}

	pass(caseName)
}

async function runMissingVeraFailsOpen() {
	const caseName = "missing-vera-fails-open"
	const wsDir = createTempWorkspace()

	try {
		const mod = await loadPluginModule()
		const { computeWorkspaceKey, getStateFilePath, readWatcherState, writeWatcherState } = mod

		const key = computeWorkspaceKey(wsDir)
		const statePath = getStateFilePath(wsDir)

		const state = makeMockState({
			workspaceKey: key,
			workspacePath: wsDir,
			projectId: "ez-omo-config",
			status: "missing-binary",
			pid: null,
			sessionIds: [],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: statePath.replace(/\.json$/, ".log"),
		})

		writeWatcherState(wsDir, state)

		const readBack = readWatcherState(wsDir)
		if (!readBack) {
			fail(caseName, "readWatcherState returned null")
		}
		if (readBack.status !== "missing-binary") {
			fail(caseName, `expected status=missing-binary, got ${readBack.status}`)
		}

		const originalPath = process.env.PATH
		process.env.PATH = "/usr/bin:/bin"

		let pluginResult: any
		try {
			const pluginFn = mod.default
			pluginResult = await pluginFn({ directory: wsDir })
		} finally {
			process.env.PATH = originalPath
		}

		if (pluginResult === null || typeof pluginResult !== "object") {
			fail(caseName, `expected plugin to return an object, got ${typeof pluginResult}`)
		}
		if (Object.keys(pluginResult).length !== 0) {
			fail(caseName, `expected plugin to return empty object when vera unavailable, got keys: ${Object.keys(pluginResult).join(", ")}`)
		}
	} finally {
		try { rmSync(wsDir, { recursive: true, force: true }) } catch {}
	}

	pass(caseName)
}

async function main() {
	const args = process.argv.slice(2)
	const caseIdx = args.indexOf("--case")
	const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null

	const allCases = [
		"same-workspace-dedupe",
		"cross-workspace-isolation",
		"stale-pid-recovery",
		"missing-vera-fails-open",
	]

	if (!testCase) {
		console.error("Usage: bun tests/vera-runtime/harness.ts --case <case-name>")
		console.error("Cases:", allCases.join(", "))
		process.exit(1)
	}

	try {
		switch (testCase) {
			case "same-workspace-dedupe":
				await runSameWorkspaceDedupe()
				break
			case "cross-workspace-isolation":
				await runCrossWorkspaceIsolation()
				break
			case "stale-pid-recovery":
				await runStalePidRecovery()
				break
			case "missing-vera-fails-open":
				await runMissingVeraFailsOpen()
				break
			default:
				console.error(`Unknown test case: ${testCase}`)
				console.error("Valid cases:", allCases.join(", "))
				process.exit(1)
		}
	} catch (err: any) {
		console.error(`UNEXPECTED ERROR in ${testCase}: ${err?.message ?? err}`)
		console.error(err?.stack ?? "")
		process.exit(1)
	} finally {
		cleanup()
	}
}

main().catch((err) => {
	console.error(`UNEXPECTED ERROR: ${err?.message ?? err}`)
	console.error(err?.stack ?? "")
	process.exit(1)
})
