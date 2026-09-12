/**
 * Clipboard helper for display-less server processes.
 *
 * OpenCode plugins run inside `opencode serve`, which under systemd user units
 * does NOT inherit the desktop session's DISPLAY/XAUTHORITY (2026-09-12
 * regression: /session-id and /session-info failed with xclip exit 1,
 * "Can't open display: (null)", despite xclip being installed).
 *
 * copyToClipboard discovers a usable X11 display when the environment lacks
 * one (scanning /tmp/.X11-unix sockets) and injects it into the spawned
 * xclip process env only.
 *
 * @module kdco-primitives/clipboard
 */

import { existsSync, readdirSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

/** Outcome of a clipboard copy attempt, with diagnostics for toast reporting. */
export interface ClipboardResult {
	success: boolean
	exitCode: number | null
	stderr: string
}

/**
 * Resolve an X11 display string for clipboard access.
 *
 * Order:
 * 1. The inherited DISPLAY, when present.
 * 2. Sockets found in /tmp/.X11-unix (X0, X1, ... → ":0", ":1", ...).
 *    Multiple sockets produce a comma-separated list; Xlib tries each in
 *    order, so the first reachable display wins.
 *
 * @returns A DISPLAY value, or null when none can be discovered.
 */
export function discoverX11Display(): string | null {
	if (process.env.DISPLAY) return process.env.DISPLAY
	try {
		const sockets = readdirSync("/tmp/.X11-unix")
			.filter((f) => /^X\d+$/.test(f))
			.map((f) => `:${f.slice(1)}`)
			.sort((a, b) => Number(a.slice(1)) - Number(b.slice(1)))
		return sockets.length > 0 ? sockets.join(",") : null
	} catch {
		return null
	}
}

/**
 * Build the env for a clipboard subprocess: the current env plus a
 * discovered DISPLAY, plus XAUTHORITY from common session locations when
 * unset (gdm's runtime cookie first, then ~/.Xauthority). Candidates that
 * do not exist are skipped so Xlib's default lookup still applies.
 */
export function buildDisplayEnv(): Record<string, string> {
	const env: Record<string, string> = {}
	for (const [key, value] of Object.entries(process.env)) {
		if (value !== undefined) env[key] = value
	}
	const display = discoverX11Display()
	if (display) env.DISPLAY = display
	if (env.XAUTHORITY === undefined) {
		const candidates = [
			process.env.XDG_RUNTIME_DIR ? join(process.env.XDG_RUNTIME_DIR, "gdm", "Xauthority") : null,
			join(homedir(), ".Xauthority"),
		]
		for (const candidate of candidates) {
			if (candidate && existsSync(candidate)) {
				env.XAUTHORITY = candidate
				break
			}
		}
	}
	return env
}

/**
 * Copy text to the X11 clipboard via xclip, working even when the calling
 * process has no DISPLAY (systemd-launched servers).
 *
 * Text is piped through bash with single-quote escaping (the pattern the
 * clipboard plugins have always used); only the env injection is new.
 *
 * @param text - Text to place on the clipboard selection.
 */
export function copyToClipboard(text: string): ClipboardResult {
	const env = buildDisplayEnv()
	if (!env.DISPLAY) {
		return {
			success: false,
			exitCode: null,
			stderr: "no X display available (DISPLAY unset, no /tmp/.X11-unix sockets)",
		}
	}
	const safeText = text.replace(/'/g, "'\\''")
	const result = Bun.spawnSync(["bash", "-c", `printf '%s' '${safeText}' | xclip -selection clipboard`], { env })
	return {
		success: result.success,
		exitCode: result.exitCode,
		stderr: result.stderr ? new TextDecoder().decode(result.stderr).trim() : "",
	}
}
