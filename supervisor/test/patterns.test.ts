import { expect, test } from "bun:test"
import { machineWriterPatterns, patternFixtures } from "../src/patterns"

test.each(Object.entries(patternFixtures))("extracted %s fixture matches the registry", (_writer, fixture) => {
  expect(machineWriterPatterns.some((entry) => entry.regex.test(fixture))).toBe(true)
})
