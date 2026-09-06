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
		"command.execute.before": async (input, output) => {
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

			const toast = (message: string, variant: "success" | "error") =>
				client.tui.showToast({ body: { title: "Session Info", message, variant } }).catch(() => {
					// toast is best-effort — never break the command hook
				})

			if (!clipResult.success) {
				toast(`Failed to copy to clipboard (exit ${clipResult.exitCode}). Is xclip installed?`, "error")
			} else {
				toast("Copied session info to clipboard.", "success")
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

export default SessionInfoPlugin
