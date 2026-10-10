import { execFile } from "node:child_process"
import { assertNever, type WakeHandle } from "./types"

export type WakeProbe = (command: string, args: readonly string[], timeoutMs: number) => Promise<boolean>
const probe: WakeProbe = (command, args, timeoutMs) => new Promise((resolve) => {
  execFile(command, [...args], { timeout: timeoutMs }, (error) => resolve(error === null))
})

export async function verifyWakeHandle(handle: WakeHandle, run: WakeProbe = probe): Promise<boolean> {
  switch (handle.kind) {
    case "systemd-unit":
    case "timer": return run("systemctl", ["--user", "is-active", "--", handle.ref], 2_000)
    case "process": return /^\d+$/.test(handle.ref)
      ? run("kill", ["-0", "--", handle.ref], 2_000)
      : run("pgrep", ["-f", "--", handle.ref], 2_000)
    case "none": return true
    default: return assertNever(handle.kind)
  }
}
