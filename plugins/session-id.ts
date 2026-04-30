/**
 * Session ID to Clipboard Plugin
 *
 * Intercepts /session-id command and copies the invoking session ID
 * to the clipboard — no LLM round-trip.
 */

import type { Plugin } from "@opencode-ai/plugin"

const SessionIdPlugin: Plugin = async () => {
	return {
		"command.execute.before": async (input, _output) => {
			if (input.command !== "session-id") return

			const result = input.sessionID
			const safeResult = result.replace(/'/g, "'\\''")
			const clipResult = Bun.spawnSync([
				"bash",
				"-c",
				`printf '%s' '${safeResult}' | xclip -selection clipboard`,
			])

			if (!clipResult.success) {
				console.error(
					`[session-id] Failed to copy to clipboard (exit ${clipResult.exitCode}). Is xclip installed?`,
				)
				throw new Error("__session_id_handled__")
			}

			console.error(`[session-id] Copied: ${result}`)

			throw new Error("__session_id_handled__")
		},
	}
}

export default SessionIdPlugin
