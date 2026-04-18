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

			// Abort the pipeline so the command never reaches the LLM
			throw new Error("__vscode_handled__")
		},
	}
}

export default VscodePlugin
