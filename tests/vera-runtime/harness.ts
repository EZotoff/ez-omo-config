import { mkdtempSync, rmSync, readdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const PLUGIN_PATH = join(import.meta.dir, "..", "..", "plugins", "vera-runtime.ts")

let nextFakePid = 50000

function setupTempHome(): { tempHome: string; originalHome: string | undefined } {
	const originalHome = process.env.HOME
	const tempHome = mkdtempSync(join(tmpdir(), "vera-runtime-test-"))
	process.env.HOME = tempHome
	return { tempHome, originalHome }
}

function mockBunSpawnSync(overrides: {
	veraAvailable?: boolean
	pidAlive?: boolean
	veraIndexSuccess?: boolean
	veraUpdateSuccess?: boolean
	projectId?: string
} = {}): () => void {
	const original = Bun.spawnSync
	Bun.spawnSync = function (cmd: any, opts?: any) {
		const cmdArray = Array.isArray(cmd) ? cmd : [String(cmd)]
		const cmdStr = cmdArray.join(" ")

		if (cmdStr.includes("command -v vera")) {
			const available = overrides.veraAvailable ?? true
			const stdout = available ? Buffer.from("/usr/bin/vera") : Buffer.from("")
			return { success: available, exitCode: available ? 0 : 1, stdout, stderr: Buffer.from("") } as any
		}

		if (cmdStr.includes("git rev-parse")) {
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

function cleanup(tempHome: string, originalHome: string | undefined) {
	try {
		rmSync(tempHome, { recursive: true, force: true })
	} catch {}
	if (originalHome !== undefined) {
		process.env.HOME = originalHome
	}
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
	const mod = await import(`${PLUGIN_PATH}?${Date.now()}`)
	const pluginFn = mod.default
	return await pluginFn({ directory })
}

async function runSameWorkspaceDedupe() {
	const caseName = "same-workspace-dedupe"
	const { tempHome, originalHome } = setupTempHome()
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)

		const plugin = await importPlugin(wsDir)

		await plugin["session.created"](
			{
				event: { properties: { session_id: "sess-1" } },
			},
			{},
		)

		await plugin["session.created"](
			{
				event: { properties: { session_id: "sess-2" } },
			},
			{},
		)

		const mod = await import(`${PLUGIN_PATH}?${Date.now()}`)
		const state = mod.readWatcherState(wsDir)

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

		await plugin["session.deleted"](
			{
				event: { properties: { session_id: "sess-1" } },
			},
			{},
		)
		await plugin["session.deleted"](
			{
				event: { properties: { session_id: "sess-2" } },
			},
			{},
		)
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome)
	}

	pass(caseName)
}

async function runCrossWorkspaceIsolation() {
	const caseName = "cross-workspace-isolation"
	const { tempHome, originalHome } = setupTempHome()
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: true })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsA = createTempWorkspace(tempHome)
		const wsB = createTempWorkspace(tempHome)

		const pluginA = await importPlugin(wsA)
		const pluginB = await importPlugin(wsB)

		await pluginA["session.created"](
			{
				event: { properties: { session_id: "sess-a-1" } },
			},
			{},
		)

		await pluginB["session.created"](
			{
				event: { properties: { session_id: "sess-b-1" } },
			},
			{},
		)

		const mod = await import(`${PLUGIN_PATH}?${Date.now()}`)
		const stateA = mod.readWatcherState(wsA)
		const stateB = mod.readWatcherState(wsB)

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

		await pluginA["session.deleted"](
			{
				event: { properties: { session_id: "sess-a-1" } },
			},
			{},
		)
		await pluginB["session.deleted"](
			{
				event: { properties: { session_id: "sess-b-1" } },
			},
			{},
		)
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome)
	}

	pass(caseName)
}

async function runStalePidRecovery() {
	const caseName = "stale-pid-recovery"
	const { tempHome, originalHome } = setupTempHome()
	const restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project", pidAlive: false })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)

		const mod = await import(`${PLUGIN_PATH}?${Date.now()}`)
		const key = mod.computeWorkspaceKey(wsDir)
		const initialState = {
			workspaceKey: key,
			workspacePath: wsDir,
			projectId: "test-project",
			pid: 99999,
			status: "running",
			sessionIds: ["sess-stale-1"],
			indexPath: `${wsDir}/.vera`,
			watchLogPath: `${mod.getStateFilePath(wsDir).replace(/\.json$/, ".log")}`,
			lastIndexedAt: new Date().toISOString(),
			startedAt: new Date().toISOString(),
			lastVerifiedAt: new Date().toISOString(),
			lastFailureAt: null,
			lastFailureReason: null,
		}
		mod.writeWatcherState(wsDir, initialState)

		const plugin = await importPlugin(wsDir)

		await plugin["session.created"](
			{
				event: { properties: { session_id: "sess-stale-1" } },
			},
			{},
		)

		const state = mod.readWatcherState(wsDir)
		if (!state) {
			fail(caseName, "No state file found after session.created")
		}

		if (state.pid === 99999) {
			fail(caseName, `Stale PID 99999 was not replaced, still ${state.pid}`)
		}

		if (state.status !== "running") {
			fail(caseName, `Expected status=running after recovery, got ${state.status}`)
		}

		await plugin["session.deleted"](
			{
				event: { properties: { session_id: "sess-stale-1" } },
			},
			{},
		)
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome)
	}

	pass(caseName)
}

async function runMissingVeraFailsOpen() {
	const caseName = "missing-vera-fails-open"
	const { tempHome, originalHome } = setupTempHome()
	let restoreSpawnSync = mockBunSpawnSync({ veraAvailable: true, projectId: "test-project" })
	const restoreSpawn = mockBunSpawn()

	try {
		const wsDir = createTempWorkspace(tempHome)

		const plugin = await importPlugin(wsDir)

		restoreSpawnSync()
		restoreSpawnSync = mockBunSpawnSync({ veraAvailable: false, projectId: "test-project" })

		let threw = false
		try {
			await plugin["session.created"](
				{
					event: { properties: { session_id: "sess-missing-1" } },
				},
				{},
			)
		} catch (_err) {
			threw = true
		}

		if (threw) {
			fail(caseName, "session.created threw when vera binary is missing")
		}

		const mod = await import(`${PLUGIN_PATH}?${Date.now()}`)
		const state = mod.readWatcherState(wsDir)

		if (!state) {
			fail(caseName, "No state file found")
		}

		if (state.status !== "missing-binary") {
			fail(caseName, `Expected status=missing-binary, got ${state.status}`)
		}

		try {
			await plugin["session.deleted"](
				{
					event: { properties: { session_id: "sess-missing-1" } },
				},
				{},
			)
		} catch {}
	} finally {
		restoreSpawnSync()
		restoreSpawn()
		cleanup(tempHome, originalHome)
	}

	pass(caseName)
}

async function main() {
	const args = process.argv.slice(2)
	const caseIdx = args.indexOf("--case")
	const testCase = caseIdx >= 0 ? args[caseIdx + 1] : null

	const testMap: Record<string, () => Promise<void>> = {
		"same-workspace-dedupe": runSameWorkspaceDedupe,
		"cross-workspace-isolation": runCrossWorkspaceIsolation,
		"stale-pid-recovery": runStalePidRecovery,
		"missing-vera-fails-open": runMissingVeraFailsOpen,
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
}

main().catch((err) => {
	console.error(`UNEXPECTED ERROR: ${err?.message ?? err}`)
	console.error(err?.stack ?? "")
	process.exit(1)
})
