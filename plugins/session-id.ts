/**
 * Session ID to Clipboard Plugin
 *
 * Intercepts /session-id command and copies the invoking session ID
 * to the clipboard — no LLM round-trip.
 */

import type { Plugin } from "@opencode-ai/plugin"

const SessionIdPlugin: Plugin = async () => {
	return {
		"command.execute.before": async (input, output) => {
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
			} else {
				console.error("[session-id] Copied invoking session ID to clipboard.")
			}

			// Suppress the command from reaching the LLM by clearing parts in place.
			// We cannot throw to abort (OpenCode 1.17.5+ surfaces plugin hook errors as TUI
			// toasts via session.error SSE — upstream issue #32253).
			output.parts.length = 0
			output.parts.push({ type: "text", text: "" })
			output.cancelled = true
		},
	}
}

export default SessionIdPlugin
