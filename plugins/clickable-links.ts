/**
 * Clickable Links Plugin
 *
 * Injects a system-prompt instruction on every session (root + subagent,
 * all agents, all models) telling the model to format file references as
 * markdown links so they are clickable in the OpenCode TUI.
 *
 * Why: the OpenCode TUI (via OpenTUI) only renders `[label](url)` markdown
 * links as clickable (OSC 8). Bare paths and backtick-wrapped paths are
 * styled but NOT clickable, despite what the built-in default.txt/codex.txt
 * system prompts claim. This plugin closes that gap with one universal hook.
 *
 * Hook: experimental.chat.system.transform — mutates output.system (string[])
 * before it is sent to the LLM. Fires once per LLM round-trip for every
 * session. Fail-open: a throw is caught by the plugin host, not by us.
 */

import type { Plugin } from "@opencode-ai/plugin"

const INSTRUCTION = `## Clickable File Links (TUI)

You are writing for a TUI where ONLY markdown links are clickable. Bare paths and backtick-wrapped paths are NOT clickable — do not use them for files the user may want to open.

When you mention a file the user may want to open — deliveries, status/progress reports, edits, diffs, error locations, config references — format it as:

[relative/path.ext:line](file:///absolute/path/to/file.ext)

- Target: a file:// URL with an ABSOLUTE path. Relative targets are not clickable.
- Label: the workspace-relative path, optionally with :line or :line:col.
- Apply this to every user-facing file reference. Inside fenced code blocks, bare paths are fine.
- Example: Edited [configs/opencode/opencode.json:15](file:///home/ezotoff/ez-omo-config/configs/opencode/opencode.json)`

const ClickableLinksPlugin: Plugin = async () => {
	return {
		"experimental.chat.system.transform": async (_input, output) => {
			if (Array.isArray(output.system)) {
				output.system.push(INSTRUCTION)
			}
		},
	}
}

export default ClickableLinksPlugin
