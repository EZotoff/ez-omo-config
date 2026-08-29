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

test("ASTRA automation kickoffs and shepherd nudges are machine", () => {
  expect(matchesMachineTemplate("AUTOMATED SHEPHERD CHECK \u2014 the night has stalled: results.tsv is at 41 rows")).toBe(true)
  expect(matchesMachineTemplate("ASTRA Night 2026-08-28, hypothesis H1 (main experiment): deep momentum scan")).toBe(true)
  expect(matchesMachineTemplate("HYPOTHESIS H1 (tonight's highest-priority experiment): investigate")).toBe(true)
  expect(matchesMachineTemplate("Continue Project ~/AI_projects/kraken:main; Session Overnight")).toBe(true)
  expect(matchesMachineTemplate("Let's assess another piece of tech for this project: https://")).toBe(false)
  expect(matchesMachineTemplate("I am looking at the latest opencode session in this dir")).toBe(false)
})
