import { expect, test } from "bun:test"
import { readFile } from "node:fs/promises"
import { supervisorConfigSchema } from "../src/config"

const example: unknown = JSON.parse(await readFile(new URL("../../configs/opencode-supervisor/supervisor.json", import.meta.url), "utf8"))
const config = supervisorConfigSchema.parse(example)

test("bundled example documents default-off D3 flags and bounded retries", () => {
  expect(example).toMatchObject({
    targeting: { adjudicate_machine_origin: false },
    pending_attention: { enabled: false, max_attempts: 4, backoff_s: [120, 300, 900, 1800] },
    wake_verification: { enabled: false },
  })
})

test("omitted or partial D3 sections remain default-off", () => {
  const { targeting: _targeting, pending_attention: _pending, wake_verification: _wake, ...legacy } = config
  for (const input of [legacy, { ...legacy, targeting: {}, pending_attention: {}, wake_verification: {} }]) {
    expect(supervisorConfigSchema.parse(input)).toMatchObject({
      targeting: { adjudicate_machine_origin: false },
      pending_attention: { enabled: false, max_attempts: 4, backoff_s: [120, 300, 900, 1800] },
      wake_verification: { enabled: false },
    })
  }
})

test("flag-on config is accepted and nested unknown keys fail closed", () => {
  expect(supervisorConfigSchema.parse({ ...config, targeting: { adjudicate_machine_origin: true }, pending_attention: { enabled: true }, wake_verification: { enabled: true } })).toMatchObject({ targeting: { adjudicate_machine_origin: true }, pending_attention: { enabled: true }, wake_verification: { enabled: true } })
  for (const field of ["targeting", "pending_attention", "wake_verification"] as const) {
    expect(supervisorConfigSchema.safeParse({ ...config, [field]: { ...config[field], unknown: true } }).success).toBe(false)
  }
})

test("retry settings cannot remove the hard cap or create an empty backoff", () => {
  for (const pending_attention of [{ enabled: true, max_attempts: 5 }, { enabled: true, max_attempts: 0 }, { enabled: true, backoff_s: [] }, { enabled: true, backoff_s: [0] }, { enabled: true, backoff_s: [1, 2, 3, 4, 5] }]) {
    expect(supervisorConfigSchema.safeParse({ ...config, pending_attention }).success).toBe(false)
  }
})
