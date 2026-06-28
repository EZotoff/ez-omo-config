/**
 * VS Code Launcher Plugin
 *
 * Intercepts /vscode command and opens VS Code directly in the
 * current worktree/project directory — no LLM round-trip.
 */

import { spawn } from "node:child_process"
import type { Plugin } from "@opencode-ai/plugin"

const VscodePlugin: Plugin = async ({ worktree, directory }) => {
	const dir = worktree || directory

	return {
		"command.execute.before": async (input, output) => {
			if (input.command !== "vscode") return

			spawn("code", [dir], {
				detached: true,
				stdio: "ignore",
			}).unref()

			// Suppress the command from reaching the LLM by clearing parts in place.
			// We cannot throw to abort (OpenCode 1.17.5+ surfaces plugin hook errors as TUI
			// toasts via session.error SSE — upstream issue #32253).
			output.parts.length = 0
			output.parts.push({ type: "text", text: "" })
			output.cancelled = true
		},
	}
}

export default VscodePlugin
