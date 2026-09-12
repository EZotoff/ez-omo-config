import { existsSync } from "node:fs"
import { readFile, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { mkdir, rename } from "node:fs/promises"
import type { OpencodeClient } from "./client"
import type { Ledger } from "./ledger"

const MAX_OPEN_TICKETS_PER_ROOT = 5

export type OpenTicket = {
  readonly id: string
  readonly n: number
  readonly root: string
  readonly sessionID: string
  readonly question: string
  readonly createdAt: string
}

export type ConsoleState = {
  readonly consoles: Readonly<Record<string, string>>
  readonly counters: Readonly<Record<string, number>>
  readonly openTickets: readonly OpenTicket[]
}

const EMPTY: ConsoleState = { consoles: {}, counters: {}, openTickets: [] }

export function canOpenTicket(state: ConsoleState, root: string, sessionID: string): { ok: boolean; reason?: string } {
  const open = state.openTickets.filter((t) => t.root === root)
  if (open.some((t) => t.sessionID === sessionID)) return { ok: false, reason: "session already has an open ticket" }
  if (open.length >= MAX_OPEN_TICKETS_PER_ROOT) return { ok: false, reason: `root at open-ticket cap (${MAX_OPEN_TICKETS_PER_ROOT})` }
  return { ok: true }
}

async function persist(path: string, state: ConsoleState): Promise<void> {
  const tmp = `${path}.tmp`
  await mkdir(dirname(path), { recursive: true })
  await writeFile(tmp, JSON.stringify(state, null, 2))
  await rename(tmp, path)
}

export class ConsoleManager {
  private state: ConsoleState = EMPTY
  constructor(
    private readonly client: OpencodeClient,
    private readonly statePath: string,
    private readonly ledger: () => Ledger,
    private readonly setLedger: (l: Ledger) => void,
  ) {}

  async load(): Promise<void> {
    if (!existsSync(this.statePath)) return
    this.state = JSON.parse(await readFile(this.statePath, "utf8")) as ConsoleState
  }

  sessionID(root: string): string | undefined {
    return this.state.consoles[root]
  }

  allSessionIDs(): ReadonlySet<string> {
    return new Set(Object.values(this.state.consoles))
  }

  /** Find-or-create the per-root console; on first creation send an intro turn. */
  async ensure(root: string, title: string): Promise<string | undefined> {
    const existing = this.state.consoles[root]
    if (existing !== undefined) return existing
    try {
      const session = await this.client.createSession(root, title)
      this.state = { ...this.state, consoles: { ...this.state.consoles, [root]: session.id } }
      await persist(this.statePath, this.state)
      this.setLedger(await this.ledger().append("CONSOLE_INITIALIZED", { root, sessionID: session.id }))
      await this.client.promptAsync(
        session.id,
        root,
        "[Supervisor] console initialized. Escalations for this project appear here as numbered tickets (Q1, Q2, ...). Everything else the supervisor does stays read-only. Your replies are recorded in the audit ledger; automated ticket resolution arrives in a later phase.",
      )
      return session.id
    } catch {
      return undefined
    }
  }

  /** P1a write path: ESCALATE-only. Never writes into worker sessions. */
  async openTicket(root: string, sessionID: string, sessionTitle: string | undefined, question: string, rationale: string): Promise<OpenTicket | { skipped: string }> {
    const guard = canOpenTicket(this.state, root, sessionID)
    if (!guard.ok) return { skipped: guard.reason ?? "dedupe" }
    const n = (this.state.counters[root] ?? 0) + 1
    const consoleID = await this.ensure(root, `[Supervisor] ${root.split("/").at(-1) ?? root}`)
    if (consoleID === undefined) return { skipped: "console unavailable" }
    const text =
      `Q${n} [session ${sessionID.slice(0, 14)}${sessionTitle === undefined ? "" : ` — ${sessionTitle}`}]\n\n${question}\n\nWhy: ${rationale.slice(0, 400)}\n\nReply in this session, e.g. \"Q${n}: <your answer>\".`
    await this.client.promptAsync(consoleID, root, text)
    const ticket: OpenTicket = { id: `Q${n}`, n, root, sessionID, question, createdAt: new Date().toISOString() }
    this.state = {
      ...this.state,
      counters: { ...this.state.counters, [root]: n },
      openTickets: [...this.state.openTickets, ticket],
    }
    await persist(this.statePath, this.state)
    this.setLedger(await this.ledger().append("ESCALATION_CREATED", { root, ticket, consoleSessionID: consoleID }))
    await this.client.toast(`Q${n}: ${question.slice(0, 120)}`, `[Supervisor] ${root.split("/").at(-1) ?? root}`)
    return ticket
  }
}
