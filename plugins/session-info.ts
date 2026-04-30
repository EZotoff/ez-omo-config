/**
 * Session Info to Clipboard Plugin
 *
 * Intercepts /session-info command and copies
 * "Project <path>:<branch>; Session <title>; ID <session-id>"
 * to the clipboard — no LLM round-trip.
 */

import { homedir } from "node:os"
import type { Plugin } from "@opencode-ai/plugin"

const SessionInfoPlugin: Plugin = async ({ client, worktree, directory }) => {
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
				const sessionResult = await client.session.get({ path: { id: input.sessionID } })
				title = sessionResult.data?.title ?? ""
			} catch {}

			const home = homedir()
			let displayPath = dir
			if (displayPath.startsWith(home)) {
				displayPath = `~${displayPath.slice(home.length)}`
			}
			if (branch) {
				displayPath = `${displayPath}:${branch}`
			}

			const result = `Project ${displayPath}; Session ${title}; ID ${input.sessionID}`

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

			console.error("[session-info] Copied session info to clipboard.")

			// Abort the pipeline so the command never reaches the LLM
			throw new Error("__session_info_handled__")
		},
	}
}

export default SessionInfoPlugin
