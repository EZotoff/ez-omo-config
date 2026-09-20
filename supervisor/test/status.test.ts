import { describe, expect, test } from "bun:test"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { writeStatus } from "../src/status"

describe("writeStatus", () => {
  test("survives concurrent writers when 25 writes race on one path", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-status-"))
    const path = join(directory, "status.json")
    try {
      await Promise.all(
        Array.from({ length: 25 }, (_, index) =>
          writeStatus(path, {
            lastReconcile: null,
            queueDepths: { [`root-${index}`]: index },
            ticksByAction: {},
            unknownOriginRate: 0,
            machineMarkedRate: 0,
          }),
        ),
      )
      const parsed = JSON.parse(await readFile(path, "utf8"))
      expect(Object.keys(parsed.queueDepths)).toHaveLength(1)
      expect(await Array.fromAsync(new Bun.Glob("*.tmp-*").scan({ cwd: directory }))).toHaveLength(0)
    } finally {
      await rm(directory, { recursive: true, force: true })
    }
  })
})
