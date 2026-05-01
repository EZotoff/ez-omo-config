import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { Readable } from "node:stream";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PLUGIN_PATH = join(__dirname, "..", "..", "plugins", "auto-checkpoint.ts");

function fail(message) {
	console.error(`FAIL: ${message}`);
	process.exit(1);
}

function pass(message) {
	console.log(`PASS: ${message}`);
}

function createBunSpawnShim() {
	return function bunSpawn(argv, opts = {}) {
		const child = spawn(argv[0], argv.slice(1), {
			cwd: opts.cwd,
			stdio: ["ignore", "pipe", "pipe"],
			env: opts.env,
		});

		return {
			stdout: Readable.toWeb(child.stdout),
			stderr: Readable.toWeb(child.stderr),
			exited: new Promise((resolve, reject) => {
				child.once("error", reject);
				child.once("close", (code) => resolve(code ?? 0));
			}),
		};
	};
}

function createBunSpawnSyncShim() {
	return function bunSpawnSync(argv, opts = {}) {
		const result = spawnSync(argv[0], argv.slice(1), {
			cwd: opts.cwd,
			encoding: null,
			env: opts.env,
		});

		return {
			exitCode: result.status ?? 0,
			stdout: result.stdout ?? Buffer.from(""),
			stderr: result.stderr ?? Buffer.from(""),
		};
	};
}

function installBunShim() {
	if (!globalThis.Bun) {
		globalThis.Bun = {};
	}

	if (typeof globalThis.Bun.spawn !== "function") {
		globalThis.Bun.spawn = createBunSpawnShim();
	}
	if (typeof globalThis.Bun.spawnSync !== "function") {
		globalThis.Bun.spawnSync = createBunSpawnSyncShim();
	}
}

function makeFakeCtx(opts = {}) {
	const sessionParents = new Map(opts.parents ?? []);
	const appLogs = [];
	const helperCreates = [];
	const helperPrompts = [];
	const helperDeletes = [];
	const helperMessageCalls = [];
	const helperSessionIDs = [...(opts.helperSessionIDs ?? [])];
	const helperMessageBatches = new Map();

	if (opts.helperMessageBatchesBySessionID) {
		for (const [sessionID, batches] of Object.entries(opts.helperMessageBatchesBySessionID)) {
			helperMessageBatches.set(
				sessionID,
				Array.isArray(batches) ? batches.map((entry) => ({
					data: Array.isArray(entry?.data) ? entry.data : [],
				})) : [],
			);
		}
	}

	let sessionGetCallCount = 0;
	let spawnSyncCallCount = 0;
	let helperCounter = 0;

	function nextHelperSessionID() {
		if (helperSessionIDs.length > 0) {
			return helperSessionIDs.shift();
		}
		helperCounter += 1;
		return `helper-${helperCounter}`;
	}

	return {
		directory: opts.directory ?? process.cwd(),
		client: {
			app: {
				async log({ body }) {
					appLogs.push(body);
					return { data: { ok: true } };
				},
			},
			session: {
				async get({ path }) {
					sessionGetCallCount++;
					return {
						data: {
							id: path.id,
							parentID: sessionParents.get(path.id) ?? null,
						},
					};
				},
				async create({ body }) {
					const id = nextHelperSessionID();
					helperCreates.push({ id, body });
					if (!helperMessageBatches.has(id)) {
						const defaultBatches = Array.isArray(opts.defaultHelperMessageBatches)
							? opts.defaultHelperMessageBatches.map((entry) => ({ data: Array.isArray(entry?.data) ? entry.data : [] }))
							: [];
						helperMessageBatches.set(id, defaultBatches);
					}
					return { data: { id } };
				},
				async promptAsync({ path, body }) {
					helperPrompts.push({ path, body });
					return { data: { ok: true } };
				},
				async messages({ path }) {
					helperMessageCalls.push({ id: path.id });
					const batches = helperMessageBatches.get(path.id) ?? [];
					if (batches.length === 0) {
						return { data: [] };
					}
					const nextBatch = batches.shift();
					helperMessageBatches.set(path.id, batches);
					return { data: nextBatch?.data ?? [] };
				},
				async delete({ path }) {
					helperDeletes.push({ id: path.id });
					return { data: { ok: true } };
				},
			},
		},
		__test: {
			incrementSpawnSyncCallCount() {
				spawnSyncCallCount++;
			},
			getSpawnSyncCallCount() {
				return spawnSyncCallCount;
			},
			getSessionGetCallCount() {
				return sessionGetCallCount;
			},
			getAppLogs() {
				return appLogs;
			},
			getHelperCreates() {
				return helperCreates;
			},
			getHelperPrompts() {
				return helperPrompts;
			},
			getHelperDeletes() {
				return helperDeletes;
			},
			getHelperMessageCalls() {
				return helperMessageCalls;
			},
		},
	};
}

function runCommand(cwd, argv) {
	const result = spawnSync(argv[0], argv.slice(1), {
		cwd,
		encoding: "utf8",
	});

	if (result.status !== 0) {
		const stderr = (result.stderr ?? "").trim();
		const stdout = (result.stdout ?? "").trim();
		fail(
			`command failed (${argv.join(" ")})\nstdout: ${stdout || "<empty>"}\nstderr: ${stderr || "<empty>"}`,
		);
	}

	return (result.stdout ?? "").trim();
}

function createTempGitRepo() {
	const repoDir = mkdtempSync(join(tmpdir(), "auto-checkpoint-repo-"));
	runCommand(repoDir, ["git", "init"]);
	runCommand(repoDir, ["git", "config", "user.email", "harness@example.com"]);
	runCommand(repoDir, ["git", "config", "user.name", "Harness Test"]);

	const seedPath = join(repoDir, "tracked.txt");
	writeFileSync(seedPath, "seed\n", "utf8");
	runCommand(repoDir, ["git", "add", "tracked.txt"]);
	runCommand(repoDir, ["git", "commit", "-m", "seed"]);

	return repoDir;
}

function appendFile(repoDir, relativePath, content) {
	const fullPath = join(repoDir, relativePath);
	const parentDir = dirname(fullPath);
	if (!existsSync(parentDir)) {
		mkdirSync(parentDir, { recursive: true });
	}
	const previous = existsSync(fullPath) ? readFileSync(fullPath, "utf8") : "";
	writeFileSync(fullPath, `${previous}${content}`, "utf8");
}

async function runToolCycle(hooks, sessionID, applyChanges) {
	if (typeof hooks["tool.execute.before"] !== "function") {
		fail("plugin did not expose tool.execute.before hook");
	}
	if (typeof hooks["tool.execute.after"] !== "function") {
		fail("plugin did not expose tool.execute.after hook");
	}

	await hooks["tool.execute.before"]({ sessionID, tool: "bash" }, { args: {} });
	await applyChanges();
	await hooks["tool.execute.after"]({ sessionID, tool: "bash" }, { metadata: {} });
}

async function loadPluginBundle() {
	installBunShim();
	const pluginUrl = pathToFileURL(PLUGIN_PATH).href;
	const mod = await import(pluginUrl);
	const plugin = mod.default ?? mod.AutoCheckpointPlugin;
	if (typeof plugin !== "function") {
		fail(`auto-checkpoint plugin export is not a function (got ${typeof plugin})`);
	}
	return { plugin, mod };
}

function writeTextFile(repoDir, relativePath, content) {
	const fullPath = join(repoDir, relativePath);
	const parentDir = dirname(fullPath);
	if (!existsSync(parentDir)) {
		mkdirSync(parentDir, { recursive: true });
	}
	writeFileSync(fullPath, content, "utf8");
}

function writeBinaryFile(repoDir, relativePath, bytes) {
	const fullPath = join(repoDir, relativePath);
	const parentDir = dirname(fullPath);
	if (!existsSync(parentDir)) {
		mkdirSync(parentDir, { recursive: true });
	}
	writeFileSync(fullPath, Buffer.from(bytes));
}

function makeLargeDiffContent(size = 200_000) {
	const line = "0123456789abcdef".repeat(8);
	const chunks = [];
	while (chunks.join("").length < size) {
		chunks.push(`${line}\n`);
	}
	return chunks.join("");
}

function withImmediateTimers(fn) {
	const originalSetTimeout = globalThis.setTimeout;
	const originalClearTimeout = globalThis.clearTimeout;

	globalThis.setTimeout = ((callback, _ms, ...args) => {
		callback(...args);
		return 1;
	});
	globalThis.clearTimeout = (() => {});

	try {
		return fn();
	} finally {
		globalThis.setTimeout = originalSetTimeout;
		globalThis.clearTimeout = originalClearTimeout;
	}
}

async function withTempHome(fn) {
	const previousHome = process.env.HOME;
	const tempHome = mkdtempSync(join(tmpdir(), "auto-checkpoint-harness-"));
	process.env.HOME = tempHome;

	try {
		return await fn(tempHome);
	} finally {
		process.env.HOME = previousHome;
	}
}

function readPluginLog(homeDir) {
	const logPath = join(homeDir, ".opencode", "plugin", "auto-checkpoint.log");
	if (!existsSync(logPath)) {
		return "";
	}
	return readFileSync(logPath, "utf8");
}

async function waitForLogContains(homeDir, needle, timeoutMs = 2_000) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		const logs = readPluginLog(homeDir);
		if (logs.includes(needle)) {
			return logs;
		}
		await new Promise((resolve) => setTimeout(resolve, 25));
	}
	return readPluginLog(homeDir);
}

async function runHelperSessionsIgnored() {
	await withTempHome(async (homeDir) => {
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			parents: [["helper-1", "root-1"]],
		});

		const hooks = await plugin(ctx);
		if (!hooks || typeof hooks.event !== "function") {
			fail("plugin did not expose event hook");
		}

		const initialGetCalls = ctx.__test.getSessionGetCallCount();

		await hooks.event({
			event: {
				type: "session.created",
				properties: {
					sessionID: "helper-1",
					title: "[auto-checkpoint helper] semantic proposal",
					parentSessionId: "root-1",
					directory: process.cwd(),
				},
			},
		});

		if (typeof hooks["tool.execute.after"] !== "function") {
			fail("plugin did not expose tool.execute.after hook");
		}

		await hooks["tool.execute.after"](
			{ sessionID: "helper-1", tool: "bash" },
			{ metadata: {} },
		);

		await hooks.event({
			event: {
				type: "session.idle",
				properties: {
					sessionID: "helper-1",
					title: "[auto-checkpoint helper] semantic proposal",
					directory: process.cwd(),
				},
			},
		});

		const finalGetCalls = ctx.__test.getSessionGetCallCount();
		if (finalGetCalls !== initialGetCalls) {
			fail("helper session should be ignored before root-session lookup");
		}

		const logs = await waitForLogContains(homeDir, "session.created — helper-1 (helper ignored)");
		if (!logs.includes("session.created — helper-1 (helper ignored)")) {
			fail("expected helper ignored log entry");
		}

		pass("helper-sessions-ignored");
	});
}

async function runChildActivityRollsUpToRoot() {
	await withTempHome(async (homeDir) => {
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			parents: [
				["root-1", null],
				["child-1", "root-1"],
			],
		});

		const hooks = await plugin(ctx);

		await hooks.event({
			event: {
				type: "session.created",
				properties: {
					sessionID: "root-1",
					title: "root",
					directory: process.cwd(),
				},
			},
		});

		await hooks.event({
			event: {
				type: "session.created",
				properties: {
					sessionID: "child-1",
					title: "child",
					parentSessionId: "root-1",
					directory: process.cwd(),
				},
			},
		});

		await hooks["tool.execute.after"](
			{ sessionID: "child-1", tool: "bash" },
			{ metadata: {} },
		);

		await withImmediateTimers(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: {
						sessionID: "child-1",
						title: "child",
						directory: process.cwd(),
					},
				},
			});
		});

		const logs = await waitForLogContains(homeDir, "tool activity rolled up — session=child-1, root=root-1");
		if (!logs.includes("tool activity rolled up — session=child-1, root=root-1")) {
			fail("expected child tool activity to roll up to root session");
		}

		pass("child-activity-rolls-up-to-root");
	});
}

async function createRootSession(hooks, sessionID, directory) {
	await hooks.event({
		event: {
			type: "session.created",
			properties: {
				sessionID,
				title: sessionID,
				directory,
			},
		},
	});
}

async function runSessionCreatedStartupSafe() {
	await withTempHome(async () => {
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: process.cwd(),
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);

		const originalSpawnSync = globalThis.Bun.spawnSync;
		globalThis.Bun.spawnSync = (...args) => {
			ctx.__test.incrementSpawnSyncCallCount();
			return originalSpawnSync(...args);
		};

		try {
			const beforeSessionGets = ctx.__test.getSessionGetCallCount();
			const beforeSpawnSync = ctx.__test.getSpawnSyncCallCount();
			await hooks.event({
				event: {
					type: "session.created",
					properties: {
						sessionID: "root-1",
						title: "root",
						directory: process.cwd(),
					},
				},
			});

			if (ctx.__test.getSessionGetCallCount() !== beforeSessionGets) {
				fail("session.created should not query OpenCode session API");
			}
			if (ctx.__test.getSpawnSyncCallCount() !== beforeSpawnSync) {
				fail("session.created should not run synchronous child processes before returning");
			}
		} finally {
			globalThis.Bun.spawnSync = originalSpawnSync;
		}

		pass("session-created-startup-safe");
	});
}

async function runPredirtyPathSkipped() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();
		appendFile(repoDir, "tracked.txt", "pre-dirty\n");

		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);

		await createRootSession(hooks, "root-1", repoDir);
		await waitForLogContains(homeDir, "baseline snapshot captured — root=root-1");
		runCommand(repoDir, ["git", "checkout", "--", "tracked.txt"]);

		await runToolCycle(hooks, "root-1", async () => {
			appendFile(repoDir, "tracked.txt", "tool-touch\n");
		});

		const logs = await waitForLogContains(homeDir, "reason=baseline-dirty");
		if (!logs.includes("path attribution conflict — path=tracked.txt")) {
			fail("expected baseline-dirty path conflict for tracked.txt");
		}
		if (!logs.includes("reason=baseline-dirty")) {
			fail("expected baseline-dirty conflict reason");
		}
		if (logs.includes("path attributed — path=tracked.txt, root=root-1")) {
			fail("baseline-dirty path should not be attributed");
		}

		pass("predirty-path-skipped");
	});
}

async function runConflictingRootOwnershipSkips() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [
				["root-1", null],
				["root-2", null],
			],
		});
		const hooks = await plugin(ctx);

		await createRootSession(hooks, "root-1", repoDir);
		await createRootSession(hooks, "root-2", repoDir);
		await waitForLogContains(homeDir, "baseline snapshot captured — root=root-2");

		await runToolCycle(hooks, "root-1", async () => {
			appendFile(repoDir, "tracked.txt", "root-1-change\n");
		});
		runCommand(repoDir, ["git", "checkout", "--", "tracked.txt"]);

		await runToolCycle(hooks, "root-2", async () => {
			appendFile(repoDir, "tracked.txt", "root-2-change\n");
		});

		const logs = await waitForLogContains(homeDir, "reason=owned-by-another-root");
		if (!logs.includes("path attributed — path=tracked.txt, root=root-1")) {
			fail("expected root-1 initial attribution");
		}
		if (!logs.includes("path attribution conflict — path=tracked.txt")) {
			fail("expected shared path conflict for tracked.txt");
		}
		if (!logs.includes("roots=root-1,root-2")) {
			fail("expected conflicting roots root-1 and root-2");
		}
		if (logs.includes("path attributed — path=tracked.txt, root=root-2")) {
			fail("root-2 should not claim path already owned by root-1");
		}

		pass("conflicting-root-ownership-skips");
	});
}

async function runRootOwnedFileRemainsEligible() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);

		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			appendFile(repoDir, "tracked.txt", "first-touch\n");
		});
		runCommand(repoDir, ["git", "checkout", "--", "tracked.txt"]);

		await runToolCycle(hooks, "root-1", async () => {
			appendFile(repoDir, "tracked.txt", "second-touch\n");
		});

		const logs = await waitForLogContains(homeDir, "path remains root-owned — path=tracked.txt, root=root-1");
		if (!logs.includes("path attributed — path=tracked.txt, root=root-1")) {
			fail("expected initial root ownership attribution");
		}
		if (!logs.includes("path remains root-owned — path=tracked.txt, root=root-1")) {
			fail("expected root-owned file to remain eligible");
		}
		if (logs.includes("reason=owned-by-another-root") || logs.includes("reason=baseline-dirty")) {
			fail("root-owned file should not be marked conflicted for same root");
		}

		pass("root-owned-file-remains-eligible");
	});
}

async function runRenameDeleteUntrackedCollected() {
	await withTempHome(async () => {
		const repoDir = createTempGitRepo();

		writeTextFile(repoDir, "delete-me.txt", "delete-me\n");
		runCommand(repoDir, ["git", "add", "delete-me.txt"]);
		runCommand(repoDir, ["git", "commit", "-m", "add delete-me"]);

		const { plugin, mod } = await loadPluginBundle();
		if (typeof mod.getCandidatePaths !== "function") {
			fail("plugin did not export getCandidatePaths helper");
		}

		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		const renamedPath = "renamed [space] #file.txt";
		const untrackedPath = "new folder/untracked [special] @.txt";

		await runToolCycle(hooks, "root-1", async () => {
			runCommand(repoDir, ["git", "mv", "tracked.txt", renamedPath]);
			runCommand(repoDir, ["git", "rm", "delete-me.txt"]);
			appendFile(repoDir, untrackedPath, "new content\n");
		});

		const result = await mod.getCandidatePaths("root-1");
		if (!result?.ok) {
			fail(`getCandidatePaths failed: ${result?.error ?? "unknown error"}`);
		}

		const expectedPaths = ["tracked.txt", renamedPath, "delete-me.txt", untrackedPath].sort();
		const gotPaths = [...result.value.paths].sort();
		if (JSON.stringify(gotPaths) !== JSON.stringify(expectedPaths)) {
			fail(`unexpected candidate paths\nexpected: ${JSON.stringify(expectedPaths)}\nactual: ${JSON.stringify(gotPaths)}`);
		}

		const renamePair = result.value.renamePairs.find(
			(pair) => pair.oldPath === "tracked.txt" && pair.newPath === renamedPath,
		);
		if (!renamePair) {
			fail("expected rename pair tracked.txt -> renamed [space] #file.txt");
		}

		if (gotPaths.some((p) => p.startsWith("/"))) {
			fail("candidate paths must be repo-relative, found absolute path");
		}

		pass("rename-delete-untracked-collected");
	});
}

async function runBinaryCandidateSkips() {
	await withTempHome(async () => {
		const repoDir = createTempGitRepo();
		writeBinaryFile(repoDir, "binary.bin", [0x00, 0x01, 0x02, 0xff, 0x10, 0x20]);
		runCommand(repoDir, ["git", "add", "binary.bin"]);
		runCommand(repoDir, ["git", "commit", "-m", "add binary"]);

		const { plugin, mod } = await loadPluginBundle();
		if (typeof mod.getCandidateDiffPayload !== "function") {
			fail("plugin did not export getCandidateDiffPayload helper");
		}

		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeBinaryFile(repoDir, "binary.bin", [0x00, 0xff, 0xaa, 0xbb, 0xcc, 0xdd, 0xee]);
		});

		const result = await mod.getCandidateDiffPayload("root-1");
		if (!result?.ok) {
			fail(`getCandidateDiffPayload failed: ${result?.error ?? "unknown error"}`);
		}

		if (!result.value.skipped || result.value.skipReason !== "binary-candidate") {
			fail(
				`expected binary-candidate skip, got skipped=${String(result.value.skipped)} reason=${result.value.skipReason}`,
			);
		}

		if (!result.value.paths.includes("binary.bin")) {
			fail("expected binary.bin in candidate paths");
		}

		pass("binary-candidate-skips");
	});
}

async function runDiffBudgetOverflowSkips() {
	await withTempHome(async () => {
		const repoDir = createTempGitRepo();
		writeTextFile(repoDir, "large-diff.txt", "seed\n");
		runCommand(repoDir, ["git", "add", "large-diff.txt"]);
		runCommand(repoDir, ["git", "commit", "-m", "add large-diff"]);

		const { plugin, mod } = await loadPluginBundle();
		if (typeof mod.getCandidateDiffPayload !== "function") {
			fail("plugin did not export getCandidateDiffPayload helper");
		}

		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeTextFile(repoDir, "large-diff.txt", makeLargeDiffContent());
		});

		const result = await mod.getCandidateDiffPayload("root-1");
		if (!result?.ok) {
			fail(`getCandidateDiffPayload failed: ${result?.error ?? "unknown error"}`);
		}

		if (!result.value.skipped || result.value.skipReason !== "diff-budget-overflow") {
			fail(
				`expected diff-budget-overflow skip, got skipped=${String(result.value.skipped)} reason=${result.value.skipReason}`,
			);
		}

		if (result.value.diffBytes <= 120_000) {
			fail(`expected diffBytes > 120000, got ${result.value.diffBytes}`);
		}

		if (!result.value.paths.includes("large-diff.txt")) {
			fail("expected large-diff.txt in candidate paths");
		}

		pass("diff-budget-overflow-skips");
	});
}

function makeSemanticPayload(candidatePaths) {
	return {
		repoRoot: "/repo",
		paths: candidatePaths,
		renamePairs: [],
		skipped: false,
		diffText: "diff --git a/tracked.txt b/tracked.txt\n+semantic-change\n",
		diffBytes: 64,
	};
}

function makeAssistantTextMessage(text) {
	return {
		info: { role: "assistant" },
		parts: [{ type: "text", text }],
	};
}

async function runStructuredHelperResponseAccepted() {
	const { mod } = await loadPluginBundle();
	if (typeof mod.resolveSemanticProposal !== "function") {
		fail("plugin did not export resolveSemanticProposal helper");
	}

	const candidatePaths = ["tracked.txt", "src/main.ts"];
	const ctx = makeFakeCtx({
		helperSessionIDs: ["helper-123"],
		defaultHelperMessageBatches: [
			{ data: [] },
			{
				data: [
					makeAssistantTextMessage(
						'{"confidence":"high","files":["tracked.txt"],"summary":"semantic tracked update"}',
					),
				],
			},
		],
	});

	const rootState = {
		cwd: process.cwd(),
		conflictPaths: new Set(),
	};

	const result = await mod.resolveSemanticProposal({
		client: ctx.client,
		rootState,
		rootSessionId: "root-abcdef12",
		rootTitle: "Root Session",
		payload: makeSemanticPayload(candidatePaths),
	});

	if (!result?.ok) {
		fail(`expected semantic proposal accepted, got error=${result?.error ?? "unknown"}`);
	}

	if (result.value.summary !== "semantic tracked update") {
		fail(`unexpected semantic summary: ${result.value.summary}`);
	}

	const creates = ctx.__test.getHelperCreates();
	if (creates.length !== 1) {
		fail(`expected exactly one helper session create, got ${creates.length}`);
	}
	if (!String(creates[0].body?.title ?? "").startsWith("[auto-checkpoint helper]")) {
		fail(`expected helper session title prefix, got: ${creates[0].body?.title}`);
	}

	const prompts = ctx.__test.getHelperPrompts();
	if (prompts.length !== 1) {
		fail(`expected exactly one helper prompt, got ${prompts.length}`);
	}
	const promptText = String(prompts[0].body?.parts?.[0]?.text ?? "");
	if (!promptText.includes("rootSessionTitle=") || !promptText.includes("rootShortId=") || !promptText.includes("responseSchema=")) {
		fail("helper prompt missing required strict JSON fields");
	}

	const deletes = ctx.__test.getHelperDeletes();
	if (deletes.length !== 1 || deletes[0].id !== "helper-123") {
		fail(`expected helper session deleted once, got ${JSON.stringify(deletes)}`);
	}

	if (ctx.__test.getHelperMessageCalls().length < 1) {
		fail("expected helper polling via session.messages");
	}

	pass("structured-helper-response-accepted");
}

async function runMissingRootSessionMetadataFallbacks() {
	const { mod } = await loadPluginBundle();
	if (typeof mod.resolveSemanticProposal !== "function") {
		fail("plugin did not export resolveSemanticProposal helper");
	}

	const ctx = makeFakeCtx({
		helperSessionIDs: ["helper-missing-metadata"],
		defaultHelperMessageBatches: [
			{
				data: [
					makeAssistantTextMessage(
						'{"confidence":"high","files":["tracked.txt"],"summary":"metadata fallback update"}',
					),
				],
			},
		],
	});

	const result = await mod.resolveSemanticProposal({
		client: ctx.client,
		rootState: { cwd: process.cwd(), conflictPaths: new Set() },
		rootSessionId: undefined,
		rootTitle: undefined,
		payload: makeSemanticPayload(["tracked.txt"]),
	});

	if (!result?.ok) {
		fail(`expected semantic proposal accepted with missing metadata, got error=${result?.error ?? "unknown"}`);
	}

	const creates = ctx.__test.getHelperCreates();
	if (creates.length !== 1) {
		fail(`expected exactly one helper session create, got ${creates.length}`);
	}
	const helperTitle = String(creates[0].body?.title ?? "");
	if (!helperTitle.includes("unknown") || !helperTitle.includes("checkpoint")) {
		fail(`expected helper title to use unknown/checkpoint fallbacks, got: ${helperTitle}`);
	}

	const prompts = ctx.__test.getHelperPrompts();
	if (prompts.length !== 1) {
		fail(`expected exactly one helper prompt, got ${prompts.length}`);
	}
	const promptText = String(prompts[0].body?.parts?.[0]?.text ?? "");
	if (!promptText.includes('rootSessionTitle=undefined') || !promptText.includes('rootShortId="unknown"')) {
		fail("helper prompt missing undefined title and unknown short-id fallback markers");
	}

	const deletes = ctx.__test.getHelperDeletes();
	if (deletes.length !== 1 || deletes[0].id !== "helper-missing-metadata") {
		fail(`expected helper session deleted once, got ${JSON.stringify(deletes)}`);
	}

	pass("missing-root-session-metadata-fallbacks");
}

async function runMalformedLlmResponseSkips() {
	const { mod } = await loadPluginBundle();
	if (typeof mod.resolveSemanticProposal !== "function") {
		fail("plugin did not export resolveSemanticProposal helper");
	}

	const ctx = makeFakeCtx({
		helperSessionIDs: ["helper-124"],
		defaultHelperMessageBatches: [
			{
				data: [makeAssistantTextMessage("{not-json")],
			},
		],
	});

	const result = await mod.resolveSemanticProposal({
		client: ctx.client,
		rootState: { cwd: process.cwd(), conflictPaths: new Set() },
		rootSessionId: "root-abcdef12",
		rootTitle: "Root Session",
		payload: makeSemanticPayload(["tracked.txt"]),
	});

	if (result?.ok || result?.error !== "invalid-json") {
		fail(`expected invalid-json semantic rejection, got ${JSON.stringify(result)}`);
	}

	const deletes = ctx.__test.getHelperDeletes();
	if (deletes.length !== 1 || deletes[0].id !== "helper-124") {
		fail(`expected helper delete after malformed response, got ${JSON.stringify(deletes)}`);
	}

	pass("malformed-llm-response-skips");
}

async function withImmediateTimersAndTimeAdvance(fn) {
	const originalSetTimeout = globalThis.setTimeout;
	const originalClearTimeout = globalThis.clearTimeout;
	const originalDateNow = Date.now;

	let fakeTime = originalDateNow();

	globalThis.setTimeout = ((callback, _ms, ...args) => {
		fakeTime += 60_000;
		callback(...args);
		return 1;
	});
	globalThis.clearTimeout = (() => {});
	Date.now = () => fakeTime;

	try {
		await fn();
	} finally {
		globalThis.setTimeout = originalSetTimeout;
		globalThis.clearTimeout = originalClearTimeout;
		Date.now = originalDateNow;
	}
}

async function runLlmOutOfScopeFileSkips() {
	const { mod } = await loadPluginBundle();
	if (typeof mod.resolveSemanticProposal !== "function") {
		fail("plugin did not export resolveSemanticProposal helper");
	}

	const ctx = makeFakeCtx({
		helperSessionIDs: ["helper-125"],
		defaultHelperMessageBatches: [
			{
				data: [
					makeAssistantTextMessage(
						'{"confidence":"high","files":["outside.txt"],"summary":"unsafe scope"}',
					),
				],
			},
		],
	});

	const result = await mod.resolveSemanticProposal({
		client: ctx.client,
		rootState: { cwd: process.cwd(), conflictPaths: new Set() },
		rootSessionId: "root-abcdef12",
		rootTitle: "Root Session",
		payload: makeSemanticPayload(["tracked.txt"]),
	});

	if (result?.ok || result?.error !== "file-out-of-scope") {
		fail(`expected file-out-of-scope semantic rejection, got ${JSON.stringify(result)}`);
	}

	const deletes = ctx.__test.getHelperDeletes();
	if (deletes.length !== 1 || deletes[0].id !== "helper-125") {
		fail(`expected helper delete after out-of-scope response, got ${JSON.stringify(deletes)}`);
	}

	pass("llm-out-of-scope-file-skips");
}

async function runStagedForeignIndexPreserved() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();

		writeTextFile(repoDir, "foreign.txt", "foreign content\n");
		runCommand(repoDir, ["git", "add", "foreign.txt"]);

		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
			defaultHelperMessageBatches: [
				{ data: [] },
				{
					data: [
						makeAssistantTextMessage(
							'{"confidence":"high","files":["checkpoint.txt"],"summary":"checkpoint commit"}',
						),
					],
				},
			],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeTextFile(repoDir, "checkpoint.txt", "new checkpoint content\n");
		});

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: {
						sessionID: "root-1",
						title: "root-1",
						directory: repoDir,
					},
				},
			});
		});

		const logs = await waitForLogContains(homeDir, "COMMITTED", 5_000);
		if (!logs.includes("COMMITTED")) {
			console.error("DEBUG LOGS:\n", logs);
			if (logs.includes("SKIP (semantic payload skipped)")) {
				fail("semantic payload was skipped");
			}
			if (logs.includes("SKIP (semantic candidate collection failed)")) {
				fail("semantic candidate collection failed");
			}
			if (logs.includes("SKIP (semantic proposal rejected)")) {
				fail("semantic proposal was rejected");
			}
			if (logs.includes("SKIP (tree clean)")) {
				fail("tree was unexpectedly clean");
			}
			if (logs.includes("SKIP (not idle long enough)")) {
				fail("not idle long enough guard hit");
			}
			if (logs.includes("SKIP (not quiet long enough)")) {
				fail("not quiet long enough guard hit");
			}
			fail("expected checkpoint commit");
		}

		const realIndexFiles = runCommand(repoDir, ["git", "ls-files"]);
		if (!realIndexFiles.split("\n").includes("foreign.txt")) {
			fail(`real index should still contain foreign.txt, got: ${realIndexFiles}`);
		}
		if (realIndexFiles.split("\n").includes("checkpoint.txt")) {
			fail(`real index should not contain checkpoint.txt, got: ${realIndexFiles}`);
		}

		const logOutput = runCommand(repoDir, ["git", "log", "-1", "--pretty=format:%s"]);
		if (!logOutput.includes("checkpoint commit")) {
			fail(`commit message should reference checkpoint commit, got: ${logOutput}`);
		}

		const committedFiles = runCommand(repoDir, [
			"git",
			"diff-tree",
			"--no-commit-id",
			"--name-only",
			"-r",
			"HEAD",
		]);
		if (committedFiles !== "checkpoint.txt") {
			fail(`commit should only contain checkpoint.txt, got: ${committedFiles}`);
		}

		pass("staged-foreign-index-preserved");
	});
}

async function runExactValidatedSubsetCommitted() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();

		writeTextFile(repoDir, "alpha.txt", "alpha\n");
		writeTextFile(repoDir, "beta.txt", "beta\n");
		writeTextFile(repoDir, "gamma.txt", "gamma\n");
		runCommand(repoDir, ["git", "add", "."]);
		runCommand(repoDir, ["git", "commit", "-m", "add files"]);

		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
			defaultHelperMessageBatches: [
				{ data: [] },
				{
					data: [
						makeAssistantTextMessage(
							'{"confidence":"high","files":["alpha.txt","gamma.txt"],"summary":"subset commit"}',
						),
					],
				},
			],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeTextFile(repoDir, "alpha.txt", "alpha-mod\n");
			writeTextFile(repoDir, "beta.txt", "beta-mod\n");
			writeTextFile(repoDir, "gamma.txt", "gamma-mod\n");
		});

		const realIndexBefore = runCommand(repoDir, ["git", "ls-files"]);

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: {
						sessionID: "root-1",
						title: "root-1",
						directory: repoDir,
					},
				},
			});
		});

		const logs = await waitForLogContains(homeDir, "COMMITTED", 5_000);
		if (!logs.includes("COMMITTED")) {
			console.error("DEBUG LOGS:\n", logs);
			fail("expected checkpoint commit");
		}

		const realIndexAfter = runCommand(repoDir, ["git", "ls-files"]);
		if (realIndexAfter !== realIndexBefore) {
			fail(`real index should remain untouched. before: ${realIndexBefore}, after: ${realIndexAfter}`);
		}

		const committedFiles = runCommand(repoDir, [
			"git",
			"diff-tree",
			"--no-commit-id",
			"--name-only",
			"-r",
			"HEAD",
		]);
		const expectedFiles = ["alpha.txt", "gamma.txt"].sort().join("\n");
		const actualFiles = committedFiles.split("\n").sort().join("\n");
		if (actualFiles !== expectedFiles) {
			fail(`commit should only contain alpha.txt and gamma.txt, got: ${committedFiles}`);
		}

		pass("exact-validated-subset-committed");
	});
}

async function runDeleteAndRenameCommitViaTempIndex() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();

		writeTextFile(repoDir, "delete-me.txt", "delete-me\n");
		writeTextFile(repoDir, "rename-me.txt", "rename-me\n");
		writeTextFile(repoDir, "modify-me.txt", "modify-me\n");
		runCommand(repoDir, ["git", "add", "."]);
		runCommand(repoDir, ["git", "commit", "-m", "add files"]);

		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
			defaultHelperMessageBatches: [
				{ data: [] },
				{
					data: [
						makeAssistantTextMessage(
							'{"confidence":"high","files":["delete-me.txt","modify-me.txt","renamed [space] file.txt"],"summary":"delete rename modify commit"}',
						),
					],
				},
			],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			runCommand(repoDir, ["git", "rm", "delete-me.txt"]);
			runCommand(repoDir, [
				"git",
				"mv",
				"rename-me.txt",
				"renamed [space] file.txt",
			]);
			appendFile(repoDir, "modify-me.txt", "modified\n");
		});

		const realIndexBefore = runCommand(repoDir, ["git", "ls-files"]);

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: {
						sessionID: "root-1",
						title: "root-1",
						directory: repoDir,
					},
				},
			});
		});

		const logs = await waitForLogContains(homeDir, "COMMITTED", 5_000);
		if (!logs.includes("COMMITTED")) {
			fail("expected checkpoint commit");
		}

		const realIndexAfter = runCommand(repoDir, ["git", "ls-files"]);
		if (realIndexAfter !== realIndexBefore) {
			fail(`real index should remain untouched. before: ${realIndexBefore}, after: ${realIndexAfter}`);
		}

		const committedFiles = runCommand(repoDir, [
			"git",
			"diff-tree",
			"--no-commit-id",
			"--name-only",
			"-r",
			"HEAD",
		]);
		const expected = ["delete-me.txt", "modify-me.txt", "renamed [space] file.txt"]
			.sort()
			.join("\n");
		const actual = committedFiles.split("\n").sort().join("\n");
		if (actual !== expected) {
			fail(`unexpected committed files. expected:\n${expected}\nactual:\n${actual}`);
		}

		pass("delete-and-rename-commit-via-temp-index");
	});
}

async function runDisjointRootCommits() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [
				["root-1", null],
				["root-2", null],
			],
			helperSessionIDs: ["helper-root1", "helper-root2"],
			helperMessageBatchesBySessionID: {
				"helper-root1": [
					{ data: [] },
					{
						data: [
							makeAssistantTextMessage(
								'{"confidence":"high","files":["file-a.txt"],"summary":"root1 commit"}',
							),
						],
					},
				],
				"helper-root2": [
					{ data: [] },
					{
						data: [
							makeAssistantTextMessage(
								'{"confidence":"high","files":["file-b.txt"],"summary":"root2 commit"}',
							),
						],
					},
				],
			},
		});
		const hooks = await plugin(ctx);

		await createRootSession(hooks, "root-1", repoDir);
		await createRootSession(hooks, "root-2", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeTextFile(repoDir, "file-a.txt", "root-1 content\n");
		});

		await runToolCycle(hooks, "root-2", async () => {
			writeTextFile(repoDir, "file-b.txt", "root-2 content\n");
		});

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: { sessionID: "root-1", title: "root-1", directory: repoDir },
				},
			});
		});

		let logs = await waitForLogContains(homeDir, "COMMITTED", 5_000);
		if (!logs.includes("COMMITTED")) {
			console.error("DEBUG LOGS:\n", logs);
			fail("expected root-1 checkpoint commit");
		}

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: { sessionID: "root-2", title: "root-2", directory: repoDir },
				},
			});
		});

		logs = await waitForLogContains(homeDir, "root2 commit", 5_000);
		if (!logs.includes("root2 commit")) {
			console.error("DEBUG LOGS:\n", logs);
			fail("expected root-2 checkpoint commit");
		}

		const logOutput = runCommand(repoDir, ["git", "log", "--oneline"]);
		const commits = logOutput.split("\n").filter((l) => l.trim());
		if (commits.length < 3) {
			fail(`expected at least 3 commits (seed + 2 checkpoints), got:\n${logOutput}`);
		}

		const headFiles = runCommand(repoDir, [
			"git",
			"diff-tree",
			"--no-commit-id",
			"--name-only",
			"-r",
			"HEAD",
		]);
		if (headFiles !== "file-b.txt") {
			fail(`HEAD commit should contain file-b.txt, got: ${headFiles}`);
		}

		const parentFiles = runCommand(repoDir, [
			"git",
			"diff-tree",
			"--no-commit-id",
			"--name-only",
			"-r",
			"HEAD~1",
		]);
		if (parentFiles !== "file-a.txt") {
			fail(`HEAD~1 commit should contain file-a.txt, got: ${parentFiles}`);
		}

		pass("disjoint-root-commits");
	});
}

async function runSkipDoesNotAdvanceHead() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();
		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [
				["root-1", null],
				["root-2", null],
			],
		});
		const hooks = await plugin(ctx);

		await createRootSession(hooks, "root-1", repoDir);
		await createRootSession(hooks, "root-2", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeTextFile(repoDir, "file-a.txt", "root-1 content\n");
		});

		const headBefore = runCommand(repoDir, ["git", "rev-parse", "HEAD"]);

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: { sessionID: "root-2", title: "root-2", directory: repoDir },
				},
			});
		});

		const logs = await waitForLogContains(homeDir, "no-candidates", 5_000);
		if (!logs.includes("no-candidates")) {
			console.error("DEBUG LOGS:\n", logs);
			fail("expected no-candidates skip reason");
		}

		const headAfter = runCommand(repoDir, ["git", "rev-parse", "HEAD"]);
		if (headAfter !== headBefore) {
			fail(`HEAD should not advance on skip. before=${headBefore}, after=${headAfter}`);
		}

		pass("skip-does-not-advance-head");
	});
}

async function runGitOperationInProgressSkips() {
	await withTempHome(async (homeDir) => {
		const repoDir = createTempGitRepo();

		writeTextFile(repoDir, "shared.txt", "base content\n");
		runCommand(repoDir, ["git", "add", "shared.txt"]);
		runCommand(repoDir, ["git", "commit", "-m", "add shared"]);
		runCommand(repoDir, ["git", "checkout", "-b", "feature"]);
		writeTextFile(repoDir, "shared.txt", "feature content\n");
		runCommand(repoDir, ["git", "add", "shared.txt"]);
		runCommand(repoDir, ["git", "commit", "-m", "feature change"]);

		runCommand(repoDir, ["git", "checkout", "master"]);
		writeTextFile(repoDir, "shared.txt", "master content\n");
		runCommand(repoDir, ["git", "add", "shared.txt"]);
		runCommand(repoDir, ["git", "commit", "-m", "master change"]);

		const mergeResult = spawnSync("git", ["merge", "feature"], { cwd: repoDir, encoding: "utf8" });
		if (!existsSync(join(repoDir, ".git", "MERGE_HEAD"))) {
			console.error("merge stdout:", mergeResult.stdout);
			console.error("merge stderr:", mergeResult.stderr);
			fail("expected MERGE_HEAD to exist after merge attempt");
		}

		const { plugin } = await loadPluginBundle();
		const ctx = makeFakeCtx({
			directory: repoDir,
			parents: [["root-1", null]],
		});
		const hooks = await plugin(ctx);
		await createRootSession(hooks, "root-1", repoDir);

		await runToolCycle(hooks, "root-1", async () => {
			writeTextFile(repoDir, "checkpoint.txt", "checkpoint content\n");
		});

		await withImmediateTimersAndTimeAdvance(async () => {
			await hooks.event({
				event: {
					type: "session.idle",
					properties: { sessionID: "root-1", title: "root-1", directory: repoDir },
				},
			});
		});

		const logs = await waitForLogContains(homeDir, "git operation in progress", 5_000);
		if (!logs.includes("git operation in progress")) {
			console.error("DEBUG LOGS:\n", logs);
			fail("expected git-operation-in-progress skip reason");
		}

		pass("git-operation-in-progress-skips");
	});
}

async function main() {
	const args = process.argv.slice(2);

	let testCase = null;
	const caseIdx = args.indexOf("--case");
	if (caseIdx >= 0) {
		testCase = args[caseIdx + 1];
	} else if (args.length > 0 && !args[0].startsWith("-")) {
		testCase = args[0];
	}

	if (!testCase) {
		console.error("Usage: node tests/auto-checkpoint/harness.mjs --case <case-name>");
	console.error(
		"Cases: helper-sessions-ignored, session-created-startup-safe, child-activity-rolls-up-to-root, predirty-path-skipped, conflicting-root-ownership-skips, root-owned-file-remains-eligible, rename-delete-untracked-collected, binary-candidate-skips, diff-budget-overflow-skips, structured-helper-response-accepted, missing-root-session-metadata-fallbacks, malformed-llm-response-skips, llm-out-of-scope-file-skips, staged-foreign-index-preserved, exact-validated-subset-committed, delete-and-rename-commit-via-temp-index, disjoint-root-commits, skip-does-not-advance-head, git-operation-in-progress-skips",
	);
		process.exit(1);
	}

		switch (testCase) {
	case "helper-sessions-ignored":
		await runHelperSessionsIgnored();
		break;
	case "session-created-startup-safe":
		await runSessionCreatedStartupSafe();
		break;
			case "child-activity-rolls-up-to-root":
				await runChildActivityRollsUpToRoot();
				break;
			case "predirty-path-skipped":
				await runPredirtyPathSkipped();
				break;
			case "conflicting-root-ownership-skips":
				await runConflictingRootOwnershipSkips();
				break;
			case "root-owned-file-remains-eligible":
				await runRootOwnedFileRemainsEligible();
				break;
			case "rename-delete-untracked-collected":
				await runRenameDeleteUntrackedCollected();
				break;
			case "binary-candidate-skips":
				await runBinaryCandidateSkips();
				break;
			case "diff-budget-overflow-skips":
				await runDiffBudgetOverflowSkips();
				break;
			case "structured-helper-response-accepted":
				await runStructuredHelperResponseAccepted();
				break;
			case "missing-root-session-metadata-fallbacks":
				await runMissingRootSessionMetadataFallbacks();
				break;
			case "malformed-llm-response-skips":
				await runMalformedLlmResponseSkips();
				break;
			case "llm-out-of-scope-file-skips":
				await runLlmOutOfScopeFileSkips();
				break;
			case "staged-foreign-index-preserved":
				await runStagedForeignIndexPreserved();
				break;
			case "exact-validated-subset-committed":
				await runExactValidatedSubsetCommitted();
				break;
			case "delete-and-rename-commit-via-temp-index":
				await runDeleteAndRenameCommitViaTempIndex();
				break;
			case "disjoint-root-commits":
				await runDisjointRootCommits();
				break;
			case "skip-does-not-advance-head":
				await runSkipDoesNotAdvanceHead();
				break;
			case "git-operation-in-progress-skips":
				await runGitOperationInProgressSkips();
				break;
			default:
				console.error(`Unknown scenario: ${testCase}`);
				process.exit(1);
		}
}

await main();
