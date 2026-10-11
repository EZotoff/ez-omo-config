// F3 end-to-end QA: one summary-bearing ESCALATE queue item flows through BOTH
// operator surfaces — buildOperatorView/toCard (operator-view.json card shape)
// and formatTicket (console ticket rendering) — with no unit-level mocking of
// the summary path.
import { describe, expect, test } from "bun:test"
import { buildOperatorView } from "../src/operator-view"
import { formatTicket } from "../src/console"
import { fixtureItem, T0 } from "./helpers"
import type { DecisionSummary } from "../src/types"

const summary: DecisionSummary = {
  headline: "Worker blocked on schema choice",
  ask: "Which migration strategy should the worker use for the ledger table?",
  options: ["expand-contract migration", "big-bang rewrite", "defer until review"],
  recommendation: "expand-contract migration",
}

const item = fixtureItem({
  id: "att_f3e2e01",
  summary,
  question: "Decide the migration strategy.",
  rationale: "Two viable strategies exist; the operator previously stated a preference for reversible changes.",
})

describe("F3 summary-to-structured-card end-to-end", () => {
  test("operator-view card carries headline/ask/options/recommendation verbatim", () => {
    const { view } = buildOperatorView({ items: [item], ledgerSeq: 5, generation: 1, nowMs: T0 + 60_000 })
    expect(view.cards).toHaveLength(1)
    const card = view.cards[0]!
    expect(card.id).toBe(item.id)
    expect(card.headline).toBe(summary.headline)
    expect(card.ask).toBe(summary.ask)
    const options = summary.options ?? []
    const recommendation = summary.recommendation ?? ""
    expect(card.options).toEqual(options)
    expect(card.recommendation).toBe(recommendation)
  })

  test("console ticket renders the structured ask, numbered options, and recommendation", () => {
    const options = summary.options ?? []
    const ticket = formatTicket("ezotoff", item)
    expect(ticket.startsWith("[Supervisor] ezotoff — ")).toBe(true)
    expect(ticket).toContain(summary.ask)
    expect(ticket).toContain(`1) ${options[0]}`)
    expect(ticket).toContain(`2) ${options[1]}`)
    expect(ticket).toContain(`3) ${options[2]}`)
    expect(ticket).toContain(`Rec: ${summary.recommendation}`)
  })

  test("summary-less item renders legacy shapes on both surfaces without summary keys", () => {
    const legacy = fixtureItem({ id: "att_f3e2e02" })
    const { view } = buildOperatorView({ items: [legacy], ledgerSeq: 5, generation: 1, nowMs: T0 + 60_000 })
    const card = view.cards[0]!
    expect("headline" in card).toBe(false)
    expect("ask" in card).toBe(false)
    expect("options" in card).toBe(false)
    expect("recommendation" in card).toBe(false)
    const ticket = formatTicket("ezotoff", legacy)
    expect(ticket).toContain(legacy.question)
    expect(ticket).not.toContain("Rec:")
  })
})
