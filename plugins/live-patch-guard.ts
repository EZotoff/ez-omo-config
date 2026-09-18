import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"

// =============================================================================
// live-patch-guard.ts
//
// Intercepts commands that could overwrite tracked-patched artifacts:
//   1. cp/mv/install targeting ~/.opencode/bin/opencode (binary swap)
//   2. bun/npm/pnpm install or opencode upgrade (potential plugin version drift)
//   3. rm/mv targeting MANIFEST-tracked runtime installs in $HOME
//      (~/oh-my-openagent-v4.19.2) or live plugin dir (~/.opencode/plugin)
//
// Behavior:
//   - Binary swaps and OMO install/upgrade commands are blocked by default.
//   - The structured patch-opencode / update-to-latest workflows may bypass
//     after their own backup, patch review, and verification phases.
//   - Bypass: set OPENCODE_PATCH_GUARD=off env var. The patch-opencode and
//     update-to-latest skills should set this when intentionally running.
//
// Motivation: the 2026-07-13 OMO silent bump (4.12.1 → 4.17.1 via @latest),
// the 2026-07-22 binary rebuild incident, and the 2026-09-18 deletion of
// ~/oh-my-openagent-v4.19.2 by a disk-cleanup session (silently unloaded the
// OMO plugin and destroyed unpushed fork commits) — no guard watched these
// operations. See:
//   - .sisyphus/patches/opencode--turn-summary-timestamp.md (Regression History)
//   - AGENTS.md "Patching OpenCode Binary" → NEVER #4 and #5
// =============================================================================

const GUARD_BYPASS_ENV = "OPENCODE_PATCH_GUARD"
const VERIFY_SCRIPT = `${process.env.HOME ?? ""}/.sisyphus/scripts/verify-live-patches.sh`

// Commands that swap the live binary
const BINARY_SWAP_PATTERNS: ReadonlyArray<{ pattern: RegExp; description: string }> = [
	{ pattern: /\bcp\b.*\.opencode\/bin\/opencode(\s|$)/, description: "cp to ~/.opencode/bin/opencode" },
	{ pattern: /\bmv\b.*\.opencode\/bin\/opencode(\s|$)/, description: "mv to ~/.opencode/bin/opencode" },
	{ pattern: /\binstall\b.*\.opencode\/bin\/opencode(\s|$)/, description: "install to ~/.opencode/bin/opencode" },
	{ pattern: /\bdd\b.*of=.*\.opencode\/bin\/opencode(\s|$)/, description: "dd writing to ~/.opencode/bin/opencode" },
]

// Commands that delete/move tracked runtime installs in $HOME
const RUNTIME_DELETE_PATTERNS: ReadonlyArray<{ pattern: RegExp; description: string }> = [
	{ pattern: /\brm\b[^\n|;&]*oh-my-openagent-v[0-9]/, description: "rm touching the OMO fork runtime dir (~/oh-my-openagent-v*)" },
	{ pattern: /\bmv\b[^\n|;&]*oh-my-openagent-v[0-9]/, description: "mv touching the OMO fork runtime dir (~/oh-my-openagent-v*)" },
	{ pattern: /\brm\b[^\n|;&]*\.opencode\/plugin/, description: "rm touching the live plugin install dir" },
	{ pattern: /\bmv\b[^\n|;&]*\.opencode\/plugin/, description: "mv touching the live plugin install dir" },
]

// Commands that may advance plugin versions
const PLUGIN_INSTALL_PATTERNS: ReadonlyArray<{ pattern: RegExp; description: string }> = [
	{ pattern: /\bopencode\s+upgrade\b/, description: "opencode upgrade (may advance plugin versions)" },
	{ pattern: /\bbun\s+install\b.*oh-my-openagent/, description: "bun install touching oh-my-openagent" },
	{ pattern: /\bnpm\s+install\b.*oh-my-openagent/, description: "npm install touching oh-my-openagent" },
	{ pattern: /\bpnpm\s+install\b.*oh-my-openagent/, description: "pnpm install touching oh-my-openagent" },
	{ pattern: /\bbun\s+install\b.*oh-my-opencode/, description: "bun install touching oh-my-opencode" },
	{ pattern: /\bbun\s+install\b.*opencode-ai\b/, description: "bun install touching opencode-ai" },
]

interface DetectionResult {
	readonly kind: "binary-swap" | "plugin-install" | "runtime-delete" | "none"
	readonly description: string
}

function detectDanger(command: string): DetectionResult {
	// Accept either a server-process bypass or a command-local prefix. The latter
	// is what the audited skills use so the bypass never leaks to later commands.
	if (process.env[GUARD_BYPASS_ENV] === "off" || /\bOPENCODE_PATCH_GUARD=off\b/.test(command)) {
		return { kind: "none", description: "" }
	}

	// Layer 1: binary swap
	for (const { pattern, description } of BINARY_SWAP_PATTERNS) {
		if (pattern.test(command)) {
			return { kind: "binary-swap", description }
		}
	}

	// Layer 2: plugin install/upgrade
	for (const { pattern, description } of PLUGIN_INSTALL_PATTERNS) {
		if (pattern.test(command)) {
			return { kind: "plugin-install", description }
		}
	}

	// Layer 3: runtime dir deletion (2026-09-18 incident)
	for (const { pattern, description } of RUNTIME_DELETE_PATTERNS) {
		if (pattern.test(command)) {
			return { kind: "runtime-delete", description }
		}
	}

	return { kind: "none", description: "" }
}

async function runVerifyScript(
	candidatePath: string,
	directory: string,
	onLog: (message: string) => void,
): Promise<{ passed: boolean; output: string }> {
	try {
		const args = ["bash", VERIFY_SCRIPT]
		if (candidatePath) args.push(candidatePath)
		const proc = Bun.spawn(args, {
			cwd: directory,
			stdout: "pipe",
			stderr: "pipe",
		})
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(proc.stdout).text(),
			new Response(proc.stderr).text(),
			proc.exited,
		])
		onLog(`verify-live-patches.sh exit=${exitCode}`)
		return {
			passed: exitCode === 0,
			output: stdout + (stderr ? `\nSTDERR:\n${stderr}` : ""),
		}
	} catch (error) {
		return {
			passed: false,
			output: `Failed to run ${VERIFY_SCRIPT}: ${error instanceof Error ? error.message : String(error)}`,
		}
	}
}

export const LivePatchGuardPlugin: Plugin = async (ctx) => {
	const { directory, client } = ctx

	const log = {
		debug: (msg: string) =>
			client.app.log({ body: { service: "live-patch-guard", level: "debug", message: msg } }).catch(() => {}),
		info: (msg: string) =>
			client.app.log({ body: { service: "live-patch-guard", level: "info", message: msg } }).catch(() => {}),
		warn: (msg: string) =>
			client.app.log({ body: { service: "live-patch-guard", level: "warn", message: msg } }).catch(() => {}),
		error: (msg: string) =>
			client.app.log({ body: { service: "live-patch-guard", level: "error", message: msg } }).catch(() => {}),
	}

	log.info("Live-patch-guard plugin initialized — watching binary swaps and plugin installs")

	const configuredPlugins = await Bun.file(`${process.env.HOME ?? ""}/.config/opencode/opencode.json`)
		.json()
		.catch(() => undefined)
	if (
		configuredPlugins &&
		typeof configuredPlugins === "object" &&
		"plugin" in configuredPlugins &&
		Array.isArray(configuredPlugins.plugin) &&
		configuredPlugins.plugin.some(
			(entry: unknown) => typeof entry === "string" && /oh-my-(openagent|opencode)@latest/.test(entry),
		)
	) {
		void client.tui.showToast({
			body: {
				title: "Tracked OMO patches at risk",
				message: "oh-my-openagent uses @latest. Pin it or use the canonical file:// fork before restarting.",
				variant: "error",
				duration: 15000,
			},
		})
	}

	return {
		tool: {
			live_patch_check: tool({
				description:
					"Run scripts/verify-live-patches.sh to check that every tracked patch in .sisyphus/patches/ is applied to the live binary and plugin installs. Returns APPLIED/STALE/MISSING-TARGET/VERSION-DRIFT per patch.",
				args: {},
				async execute(_args, _toolCtx) {
					const result = await runVerifyScript("", directory, log.info)
					return result.output
				},
			}),
		},

		"tool.execute.before": async (input, output) => {
			const toolName = input.tool
			let command: string | undefined

			if (toolName === "bash" || toolName === "terminal") {
				command = output.args.command as string | undefined
			} else if (toolName === "interactive_bash" || toolName === "tmux") {
				command = output.args.tmux_command as string | undefined
			}

			if (!command || typeof command !== "string") return

			const detection = detectDanger(command)
			if (detection.kind === "none") return

			// BINARY SWAP: only the structured patch workflows may bypass.
			if (detection.kind === "binary-swap") {
				log.error(`BLOCKING binary swap — tracked patches at risk`)
				throw new Error(
					`[LIVE-PATCH-GUARD] BLOCKED: ${detection.description}\n\n` +
						`Command: ${command}\n\n` +
						`Invoke the patch-opencode or update-to-latest skill. Those workflows create a backup, ` +
						`review every active registry entry, run verify-live-patches.sh, and may then set ` +
						`OPENCODE_PATCH_GUARD=off for the audited swap. Do not bypass this guard ad hoc.`,
				)
			}

			// RUNTIME DIR DELETE/MOVE: these dirs are live infrastructure
			// (AGENTS.md "Protected runtime directories") — report, don't delete.
			if (detection.kind === "runtime-delete") {
				log.error(`BLOCKING runtime dir delete/move: ${detection.description}`)
				throw new Error(
					`[LIVE-PATCH-GUARD] BLOCKED: ${detection.description}\n\n` +
						`Command: ${command}\n\n` +
						`This directory is a MANIFEST-tracked live runtime install (see AGENTS.md ` +
						`"Protected runtime directories"). Report it to the operator as a review ` +
						`candidate instead of deleting it.`,
				)
			}

			// OMO PLUGIN INSTALL/UPGRADE: only update-to-latest may bypass.
			if (detection.kind === "plugin-install") {
				log.error(`BLOCKING plugin install/upgrade: ${detection.description}`)
				throw new Error(
					`[LIVE-PATCH-GUARD] BLOCKED: ${detection.description}\n\n` +
						`Command: ${command}\n\n` +
						`OMO has tracked local patches. Version advances must use the update-to-latest skill's ` +
						`13-phase backup, patch-review, reapply, and regression pipeline. That workflow may set ` +
						`OPENCODE_PATCH_GUARD=off only for the audited command.`,
				)
			}
		},
	}
}

export default LivePatchGuardPlugin
