import { expect, test } from "bun:test"
import { machineWriterPatterns, matchesMachineTemplate, patternFixtures } from "../src/patterns"

test.each(Object.entries(patternFixtures))("extracted %s fixture matches the registry", (_writer, fixture) => {
  expect(machineWriterPatterns.some((entry) => entry.regex.test(fixture))).toBe(true)
})

test("system-reminder injections match the machine registry", () => {
  expect(matchesMachineTemplate("<system-reminder>\n[BACKGROUND TASK COMPLETED]\n</system-reminder>")).toBe(true)
  expect(matchesMachineTemplate("<!-- OMO_INTERNAL_NOREPLY -->")).toBe(true)
  expect(matchesMachineTemplate("Yes, let's add them.")).toBe(false)
})
