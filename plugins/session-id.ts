/**
 * Session ID to Clipboard Plugin
 *
 * Intercepts /session-id command and copies the invoking session ID
 * to the clipboard — no LLM round-trip.
 */

import type { Plugin } from "@opencode-ai/plugin"

const SessionIdPlugin: Plugin = async ({ client }) => {
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

			const toast = (message: string, variant: "success" | "error") =>
				client.tui.showToast({ body: { title: "Session ID", message, variant } }).catch(() => {
					// toast is best-effort — never break the command hook
				})

			if (!clipResult.success) {
				toast(`Failed to copy to clipboard (exit ${clipResult.exitCode}). Is xclip installed?`, "error")
			} else {
				toast("Copied invoking session ID to clipboard.", "success")
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
