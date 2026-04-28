/**
 * Session Info to Clipboard Plugin
 *
 * Intercepts /session-info command and copies "Project <path>:<branch>; Session <title>"
 * to the clipboard — no LLM round-trip.
 */

import { homedir } from "node:os"
import type { Plugin } from "@opencode-ai/plugin"

const SessionInfoPlugin: Plugin = async ({ worktree, directory }) => {
	const dir = worktree || directory

	return {
		"command.execute.before": async (input, _output) => {
			if (input.command !== "session-info") return

			let branch = ""
			try {
				const gitResult = Bun.spawnSync(
					["git", "rev-parse", "--abbrev-ref", "HEAD"],
					{ cwd: dir, stdout: "pipe", stderr: "pipe" },
				)
				if (gitResult.success && gitResult.stdout) {
					branch = new TextDecoder().decode(gitResult.stdout as Uint8Array).trim()
				}
			} catch {}

			let title = ""
			try {
				const sessionResult = Bun.spawnSync(
					["opencode", "session", "list", "-n", "1", "--format", "json"],
					{ stdout: "pipe", stderr: "pipe" },
				)
				if (sessionResult.success && sessionResult.stdout) {
					const raw = new TextDecoder().decode(sessionResult.stdout as Uint8Array)
					const sessions = JSON.parse(raw)
					if (Array.isArray(sessions) && sessions.length > 0) {
						title = sessions[0].title ?? ""
					}
				}
			} catch {}

			const home = homedir()
			let displayPath = dir
			if (displayPath.startsWith(home)) {
				displayPath = "~" + displayPath.slice(home.length)
			}
			if (branch) {
				displayPath = `${displayPath}:${branch}`
			}

			const result = `Project ${displayPath}; Session ${title}`

			const safeResult = result.replace(/'/g, "'\\''")
			const clipResult = Bun.spawnSync(
				["bash", "-c", `printf '%s' '${safeResult}' | xclip -selection clipboard`],
			)

			if (!clipResult.success) {
				console.error(
					`[session-info] Failed to copy to clipboard (exit ${clipResult.exitCode}). Is xclip installed?`,
				)
				throw new Error("__session_info_handled__")
			}

			console.error(`[session-info] Copied: ${result}`)

			// Abort the pipeline so the command never reaches the LLM
			throw new Error("__session_info_handled__")
		},
	}
}

export default SessionInfoPlugin
