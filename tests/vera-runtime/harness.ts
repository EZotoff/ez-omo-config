#!/usr/bin/env bun
/**
 * Vera Runtime Plugin Behavioral Test Harness
 *
 * Tests the plugin in isolated temp directories without touching ~/.local/share/opencode/
 */

import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

const TESTS_FAILED = []
const TESTS_PASSED = []

function pass(name: string) {
	console.log(`PASS: ${name}`)
	TESTS_PASSED.push(name)
}

function fail(name: string, reason: string) {
	console.log(`FAIL: ${name} — ${reason}`)
	TESTS_FAILED.push({ name, reason })
}

function makeTempHome(): string {
	return fs.mkdtempSync(path.join(os.tmpdir(), "vera-harness-"))
}

function makeGitRepo(dir: string): void {
	fs.mkdirSync(dir, { recursive: true })
	// Minimal git repo for computeProjectId
	fs.mkdirSync(path.join(dir, ".git"), { recursive: true })
	fs.writeFileSync(path.join(dir, ".git", "HEAD"), "ref: refs/heads/main\n")
}

// Mock Bun.spawnSync to simulate vera presence/absence
function mockVeraAvailable(available: boolean) {
	const original = (Bun as any).spawnSync
	;(Bun as any).spawnSync = (...args: any[]) => {
		const cmd = args[0]
		if (Array.isArray(cmd) && cmd[0] === "bash" && cmd[2] === "command -v vera") {
			return {
				success: available,
				stdout: { toString: () => available ? "/usr/bin/vera\n" : "" },
				stderr: { toString: () => "" },
			}
		}
		// For git rev-parse
		if (Array.isArray(cmd) && cmd[0] === "bash" && cmd[2]?.includes("git rev-parse")) {
			return {
				success: true,
				stdout: { toString: () => "test-repo" },
				stderr: { toString: () => "" },
			}
		}
		// For realpath
		if (Array.isArray(cmd) && cmd[0] === "realpath") {
			return {
				success: true,
				stdout: { toString: () => cmd[1] },
				stderr: { toString: () => "" },
			}
		}
		// For vera index
		if (Array.isArray(cmd) && cmd[0] === "vera" && cmd[1] === "index") {
			return {
				success: true,
				stdout: { toString: () => "indexed\n" },
				stderr: { toString: () => "" },
			}
		}
		// For vera watch - simulate spawning
		if (Array.isArray(cmd) && cmd[0] === "vera" && cmd[1] === "watch") {
			return {
				success: true,
				stdout: { toString: () => "" },
				stderr: { toString: () => "" },
			}
		}
		// For kill -0 (PID check) - simulate dead PID
		if (Array.isArray(cmd) && cmd[0] === "bash" && cmd[2]?.includes("kill -0")) {
			return {
				success: false,
				stdout: { toString: () => "" },
				stderr: { toString: () => "No such process" },
			}
		}
		return original.apply(Bun, args)
	}
}

function mockVeraSpawn() {
	const original = (Bun as any).spawn
	let fakePid = 10000
	;(Bun as any).spawn = (...args: any[]) => {
		const cmd = args[0]
		if (Array.isArray(cmd) && cmd[0] === "vera" && cmd[1] === "watch") {
			fakePid += 1
			return {
				pid: fakePid,
				kill: () => {},
			}
		}
		return original.apply(Bun, args)
	}
}

function unmockBun() {
	// Bun.spawnSync and Bun.spawn are read-only in some environments,
	// so we just keep the mocks for the test session
}

async function runTest(name: string, fn: () => Promise<void>) {
	try {
		await fn()
	} catch (err) {
		fail(name, err instanceof Error ? err.message : String(err))
	}
}

// ============================================================
// TEST 1: same-workspace-dedupe
// ============================================================
await runTest("same-workspace-dedupe", async () => {
	const tmpHome = makeTempHome()
	const originalHome = process.env.HOME
	process.env.HOME = tmpHome

	try {
		mockVeraAvailable(true)
		mockVeraSpawn()

		const workspaceDir = path.join(tmpHome, "workspace1")
		makeGitRepo(workspaceDir)

		// Import plugin with cache busting
		const pluginPath = path.join(process.cwd(), "plugins/vera-runtime.ts")
		const { default: VeraRuntimePlugin } = await import(`${pluginPath}?t=${Date.now()}`)
		const plugin = await VeraRuntimePlugin({ directory: workspaceDir })

		if (!plugin["session.created"]) {
			throw new Error("session.created handler not found")
		}

		// First session
		await plugin["session.created"]({ properties: { session_id: "sess-1" } }, {})

		// Second session on same workspace
		await plugin["session.created"]({ properties: { session_id: "sess-2" } }, {})

		// Read state
		const { readWatcherState } = await import(`${pluginPath}?t=${Date.now() + 1}`)
		const state = readWatcherState(workspaceDir)

		if (!state) {
			throw new Error("No state file created")
		}
		if (state.sessionIds.length !== 2) {
			throw new Error(`Expected 2 sessionIds, got ${state.sessionIds.length}`)
		}
		if (!state.sessionIds.includes("sess-1") || !state.sessionIds.includes("sess-2")) {
			throw new Error(`Expected both sess-1 and sess-2 in sessionIds`)
		}

		// Cleanup
		if (plugin["session.deleted"]) {
			await plugin["session.deleted"]({ properties: { session_id: "sess-1" } }, {})
			await plugin["session.deleted"]({ properties: { session_id: "sess-2" } }, {})
		}

		pass("same-workspace-dedupe")
	} finally {
		process.env.HOME = originalHome
		fs.rmSync(tmpHome, { recursive: true, force: true })
	}
})

// ============================================================
// TEST 2: cross-workspace-isolation
// ============================================================
await runTest("cross-workspace-isolation", async () => {
	const tmpHome = makeTempHome()
	const originalHome = process.env.HOME
	process.env.HOME = tmpHome

	try {
		mockVeraAvailable(true)
		mockVeraSpawn()

		const workspaceA = path.join(tmpHome, "workspaceA")
		const workspaceB = path.join(tmpHome, "workspaceB")
		makeGitRepo(workspaceA)
		makeGitRepo(workspaceB)

		const pluginPath = path.join(process.cwd(), "plugins/vera-runtime.ts")
		const { default: VeraRuntimePlugin } = await import(`${pluginPath}?t=${Date.now()}`)

		const pluginA = await VeraRuntimePlugin({ directory: workspaceA })
		const pluginB = await VeraRuntimePlugin({ directory: workspaceB })

		await pluginA["session.created"]({ properties: { session_id: "sess-a" } }, {})
		await pluginB["session.created"]({ properties: { session_id: "sess-b" } }, {})

		const { readWatcherState } = await import(`${pluginPath}?t=${Date.now() + 1}`)
		const stateA = readWatcherState(workspaceA)
		const stateB = readWatcherState(workspaceB)

		if (!stateA || !stateB) {
			throw new Error("Missing state files for workspaces")
		}
		if (stateA.workspaceKey === stateB.workspaceKey) {
			throw new Error("Workspace keys should be different")
		}

		// Cleanup
		if (pluginA["session.deleted"]) {
			await pluginA["session.deleted"]({ properties: { session_id: "sess-a" } }, {})
		}
		if (pluginB["session.deleted"]) {
			await pluginB["session.deleted"]({ properties: { session_id: "sess-b" } }, {})
		}

		pass("cross-workspace-isolation")
	} finally {
		process.env.HOME = originalHome
		fs.rmSync(tmpHome, { recursive: true, force: true })
	}
})

// ============================================================
// TEST 3: stale-pid-recovery
// ============================================================
await runTest("stale-pid-recovery", async () => {
	const tmpHome = makeTempHome()
	const originalHome = process.env.HOME
	process.env.HOME = tmpHome

	try {
		mockVeraAvailable(true)
		mockVeraSpawn()

		const workspaceDir = path.join(tmpHome, "workspace-stale")
		makeGitRepo(workspaceDir)

		const pluginPath = path.join(process.cwd(), "plugins/vera-runtime.ts")
		const { default: VeraRuntimePlugin, writeWatcherState, computeWorkspaceKey } = await import(`${pluginPath}?t=${Date.now()}`)

		// Pre-write a state with a dead PID
		const workspaceKey = computeWorkspaceKey(workspaceDir)
		const state = {
			workspaceKey,
			workspacePath: workspaceDir,
			projectId: "test-repo",
			pid: null as number | null,
			status: "stopped" as const,
			sessionIds: [] as string[],
			indexPath: `${workspaceDir}/.vera`,
			watchLogPath: `${workspaceDir}/.vera/watch.log`,
			lastIndexedAt: null as string | null,
			startedAt: null as string | null,
			lastVerifiedAt: null as string | null,
			lastFailureAt: null as string | null,
			lastFailureReason: null as string | null,
		}
		state.status = "running"
		state.pid = 99999
		state.sessionIds = ["sess-old"]
		state.lastIndexedAt = new Date().toISOString()
		writeWatcherState(workspaceDir, state)

		const plugin = await VeraRuntimePlugin({ directory: workspaceDir })
		await plugin["session.created"]({ properties: { session_id: "sess-new" } }, {})

		const { readWatcherState } = await import(`${pluginPath}?t=${Date.now() + 1}`)
		const newState = readWatcherState(workspaceDir)

		if (!newState) {
			throw new Error("No state after recovery")
		}
		if (newState.pid === 99999) {
			throw new Error("Stale PID was not replaced")
		}
		if (newState.status !== "running") {
			throw new Error(`Expected status running, got ${newState.status}`)
		}

		// Cleanup
		if (plugin["session.deleted"]) {
			await plugin["session.deleted"]({ properties: { session_id: "sess-new" } }, {})
		}

		pass("stale-pid-recovery")
	} finally {
		process.env.HOME = originalHome
		fs.rmSync(tmpHome, { recursive: true, force: true })
	}
})

// ============================================================
// TEST 4: missing-vera-fails-open
// ============================================================
await runTest("missing-vera-fails-open", async () => {
	const tmpHome = makeTempHome()
	const originalHome = process.env.HOME
	process.env.HOME = tmpHome

	try {
		mockVeraAvailable(false)

		const workspaceDir = path.join(tmpHome, "workspace-missing")
		makeGitRepo(workspaceDir)

		const pluginPath = path.join(process.cwd(), "plugins/vera-runtime.ts")
		const { default: VeraRuntimePlugin } = await import(`${pluginPath}?t=${Date.now()}`)

		// When vera is not available, plugin returns empty handlers
		const plugin = await VeraRuntimePlugin({ directory: workspaceDir })

		// Should return empty object (fail-open)
		if (Object.keys(plugin).length !== 0) {
			throw new Error(`Expected empty plugin when vera missing, got handlers: ${Object.keys(plugin).join(", ")}`)
		}

		pass("missing-vera-fails-open")
	} finally {
		process.env.HOME = originalHome
		fs.rmSync(tmpHome, { recursive: true, force: true })
	}
})

// ============================================================
// SUMMARY
// ============================================================
console.log(``)
console.log(`Vera runtime harness: ${TESTS_PASSED.length} passed, ${TESTS_FAILED.length} failed`)

if (TESTS_FAILED.length > 0) {
	process.exit(1)
}

process.exit(0)
