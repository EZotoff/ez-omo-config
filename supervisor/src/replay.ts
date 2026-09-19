import { homedir } from "node:os"
import { join, resolve } from "node:path"
import { ZaiAdapter } from "./adapter"
import { assembleContext, type AssembledContext } from "./assembler"
import { OpencodeClient } from "./client"
import { loadApiKey, loadConfig, loadProviderBaseURL } from "./config"
import { runTick, runTickWithCollect } from "./tick"
import { CollectBudget, CollectExecutor, type CollectEvent } from "./collect"
import { Ledger } from "./ledger"
import { deriveChildSessionIDs, topLevelSessions } from "./topology"
import { contiguousAssistantRun, messageText, projectTurns } from "./projector"
import type { Message, Turn } from "./types"

/**
 * Retrospective benchmark: find historical turns where the human pushed with a
 * continue-class reply ("proceed", "continue", "go", "ok", ...) after a completed
 * assistant answer, then re-decide those turns with the live tick brain.
 * Ground truth = the human acted as the CONTINUE surrogate. A control set of
 * turns followed by substantive human messages checks false positives.
 */

const CONTINUE_RE = /\b(proceed|continue|go|ok|okay|go ahead|keep going|carry on|do it|yes|next)\b/i
const PUSH_MAX_CHARS = 120

function isContinuePush(text: string): boolean {
  const trimmed = text.trim()
  return trimmed.length > 0 && trimmed.length <= PUSH_MAX_CHARS && CONTINUE_RE.test(trimmed)
}

export type ExtractedExchange = {
  readonly sessionID: string
  readonly userMessageID: string
  readonly assistantMessageIDs: readonly string[]
  readonly workerText: string
}

/**
 * Corpus extraction contract: locate the target user message by ID, joining the
 * FULL contiguous assistant run after it. When the messageID lookup fails
 * (corpus ids drift from live message ids — D211 shape), fall back to an
 * exact-text quote match. Session ids pass through verbatim — never truncated.
 */
export function extractExchange(messages: readonly Message[], userMessageID: string, userText: string): ExtractedExchange | undefined {
  let userIndex = messages.findIndex((m) => m.id === userMessageID)
  if (userIndex === -1) {
    const needle = userText.trim()
    userIndex = messages.findIndex((m) => m.role === "user" && messageText(m) === needle)
  }
  if (userIndex === -1) return undefined
  const user = messages[userIndex]!
  const run = contiguousAssistantRun(messages, userIndex)
  return {
    sessionID: user.sessionID,
    userMessageID: user.id,
    assistantMessageIDs: run.map((m) => m.id),
    workerText: run.map(messageText).filter((text) => text !== "").join("\n"),
  }
}

type CompactTurn = { turn: Turn; userCreatedMs: number }

function compactTurns(messages: readonly Message[], sessionID: string): CompactTurn[] {
  return projectTurns(messages, { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() })
    .map((turn) => ({
      turn,
      userCreatedMs: messages.find((m) => m.id === turn.userMessageID)?.time.created ?? 0,
    }))
    .filter((t) => t.turn.sessionID === sessionID)
}

type CorpusItem = {
  readonly id: string
  readonly action: string
  readonly confidence: number
  readonly root: string
  readonly session: string
  readonly title?: string
  readonly user: string
  readonly worker: string
}

/**
 * Targeted corpus replay through the collect-vs-decide fork. Resolves each
 * corpus id's live session, rebuilds the tick context, and runs the two-tick
 * fork with the real primitives. Reports tick1 needs, gather outcome, and the
 * tick2 action — never fabricates a result on provider failure.
 */
async function runCorpusFork(ids: readonly string[]): Promise<void> {
  const repoRoot = resolve(import.meta.dir, "../..")
  const config = await loadConfig(join(repoRoot, "configs", "opencode-supervisor", "supervisor.json"))
  const client = new OpencodeClient(config.server_url, {
    username: config.server_username,
    password: process.env[config.server_password_env] ?? "",
  })
  const baseURL = await loadProviderBaseURL(join(repoRoot, "configs", "opencode", "opencode.json"), config.model.provider)
  const apiKey = await loadApiKey(join(homedir(), ".local/share/opencode/auth.json"), config.model.provider)
  const adapter = new ZaiAdapter(baseURL, config.model.id, apiKey)
  const stateDir = join(homedir(), ".local", "state", "opencode-supervisor")
  const { readFile, writeFile, mkdir } = await import("node:fs/promises")
  const ledger = await Ledger.open(join(stateDir, "ledger.jsonl"))
  const budget = new CollectBudget()

  const repaired = JSON.parse(await readFile(join(stateDir, "grading", "repaired-items.json"), "utf8")) as CorpusItem[]
  const batches: CorpusItem[] = []
  for (let index = 1; index <= 15; index += 1) {
    const name = `batch-${String(index).padStart(2, "0")}.json`
    try {
      const data = JSON.parse(await readFile(join(stateDir, "grading", name), "utf8")) as unknown
      const list = Array.isArray(data) ? data : ((data as { items?: unknown[]; cases?: unknown[] }).items ?? (data as { cases?: unknown[] }).cases ?? [])
      batches.push(...(list as CorpusItem[]))
    } catch {
      // batch file absent — skip
    }
  }
  const byId = new Map<string, CorpusItem>()
  // Repaired items win over batches: the batch copy of a repaired id carries a
  // placeholder user field (D211: "(message not found)") that breaks target lookup.
  for (const item of [...repaired, ...batches]) if (typeof item.id === "string" && !byId.has(item.id)) byId.set(item.id, item)

  const allSessions = await client.listAllSessions()
  const results: Record<string, unknown>[] = []
  for (const id of ids) {
    const item = byId.get(id)
    if (item === undefined) {
      console.error(`[${id}] not found in corpus`)
      continue
    }
    const session = allSessions.find((entry) => entry.id === item.session) ?? allSessions.find((entry) => entry.id.startsWith(item.session.slice(0, 12)))
    if (session === undefined) {
      console.error(`[${id}] session ${item.session} not found`)
      continue
    }
    const messages = await client.listMessages(session.id, session.directory)
    const turns = projectTurns(messages, { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() })
    const normalize = (value: string): string => value.replace(/\s+/g, " ").trim()
    const normalizedUser = normalize(item.user)
    const needle = normalizedUser === "" || normalizedUser.startsWith("(") ? "" : normalizedUser.slice(0, 40)
    const matchedIndex = needle === "" ? -1 : turns.findIndex((turn) => normalize(turn.userText).startsWith(needle))
    const targetIndex = matchedIndex === -1 ? turns.length - 1 : matchedIndex
    const target = turns[targetIndex]
    if (target === undefined) {
      console.error(`[${id}] no target turn in ${session.id}`)
      continue
    }
    const context = assembleContext({
      target,
      targetHistory: turns.slice(0, targetIndex + 1),
      siblingChanges: {},
      targetHistoryCapPairs: config.target_history_cap_pairs,
      siblingTurnWindow: config.sibling_turn_window,
      tokenBudget: config.token_budget,
    })
    const events: CollectEvent[] = []
    const executor = new CollectExecutor({
      client,
      root: session.directory,
      ledgerRecords: () => ledger.records,
      openItems: () => [],
      nowMs: Date.now,
    })
    const decision = await runTickWithCollect({
      adapter,
      context,
      target,
      confidenceFloor: config.confidence_floor,
      root: session.directory,
      executor,
      budget,
      isIdle: async () => true,
      healthAmbiguous: false,
      hasSiblings: false,
      nowMs: Date.now,
      onCollect: (event) => events.push(event),
    })
    const event = events[0]
    const record = {
      id,
      corpusAction: item.action,
      corpusConfidence: item.confidence,
      session: session.id,
      targetMessage: target.userMessageID,
      targetUser: target.userText.slice(0, 140),
      userText: target.userText.slice(0, 2000),
      workerText: target.assistantText.slice(0, 4000),
      tick1Needs: event?.needs.map((entry) => ({ scope: entry.scope, target: entry.target, question: entry.question })) ?? [],
      outcome: event?.outcome ?? "none",
      gatheredTokens: event?.tokens ?? 0,
      tick2Action: decision.action,
      evidenceEffect: decision.evidence_effect ?? null,
      changed: event?.changed ?? false,
      rationale: decision.rationale.slice(0, 200),
    }
    console.error(`[${id}] corpus=${item.action} → tick2=${decision.action} outcome=${record.outcome} changed=${record.changed}`)
    results.push(record)
  }
  const outPath = join(stateDir, `collect-fork-replay-${new Date().toISOString().replace(/[:.]/g, "-")}.json`)
  await mkdir(stateDir, { recursive: true })
  await writeFile(outPath, JSON.stringify({ ids, results }, null, 2))
  console.log(JSON.stringify({ outPath, results }, null, 2))
}

async function main(): Promise<void> {
  const args = new Map(process.argv.slice(2).map((v, i, all) => (v.startsWith("--") ? [v.slice(2), all[i + 1] ?? ""] : [String(i), v])))
  const idsArg = args.get("ids")
  if (idsArg !== undefined && idsArg !== "") {
    await runCorpusFork(idsArg.split(",").map((value) => value.trim()).filter((value) => value !== ""))
    return
  }
  const allProjects = args.has("all")
  const root = args.get("--root") ?? "/home/ezotoff/AI_projects/veran"
  const maxContinue = Number(args.get("--sample") ?? 30)
  const maxControl = Number(args.get("--control") ?? 15)
  const days = Number(args.get("--days") ?? 9999)

  const repoRoot = resolve(import.meta.dir, "../..")
  const config = await loadConfig(join(repoRoot, "configs", "opencode-supervisor", "supervisor.json"))
  const client = new OpencodeClient(config.server_url, {
    username: config.server_username,
    password: process.env[config.server_password_env] ?? "",
  })
  const baseURL = await loadProviderBaseURL(join(repoRoot, "configs", "opencode", "opencode.json"), config.model.provider)
  const apiKey = await loadApiKey(join(homedir(), ".local/share/opencode/auth.json"), config.model.provider)
  const adapter = new ZaiAdapter(baseURL, config.model.id, apiKey)

  const cutoff = Date.now() - days * 86_400_000
  type ScanSession = { id: string; directory: string; timeUpdatedMs?: number }
  const sessions: readonly ScanSession[] = allProjects
    ? (await client.listAllSessions()).filter((s) => (s.timeUpdatedMs ?? 0) >= cutoff)
    : (await client.listSessions(root)).filter((s) => (s.timeUpdatedMs ?? 0) >= cutoff)
  console.error(`scan: ${sessions.length} sessions updated within ${days}d across ${allProjects ? "all projects" : root}`)

  const all: Message[][] = []
  for (const session of sessions) {
    const messages: Message[] = [...(await client.listMessages(session.id, session.directory))]
    all.push(messages)
  }
  const childIDs = deriveChildSessionIDs(all.flat())
  const top = topLevelSessions(sessions, childIDs)
  const directories = new Set(top.map((session) => session.directory))
  console.error(`topology: ${top.length} top-level across ${directories.size} project dirs (${childIDs.size} children derived)`)

  const messagesBySession = new Map<string, Message[]>(sessions.map((session, index) => [session.id, all[index] ?? []]))
  const perSession = new Map<string, CompactTurn[]>()
  for (const session of top) perSession.set(session.id, compactTurns(messagesBySession.get(session.id) ?? [], session.id))
  const dirOf = new Map(top.map((session) => [session.id, session.directory]))

  type Case = { kind: "continue" | "control"; session: string; target: Turn; targetCreatedMs: number; history: Turn[] }
  const cases: Case[] = []
  const perSessionCap = 3
  const usedPerSession = new Map<string, number>()
  for (const [sessionID, turns] of perSession) {
    for (let i = 0; i + 1 < turns.length; i += 1) {
      const current = turns[i]!
      const nextUser = turns[i + 1]!.turn.userText
      // Negative control: the next human message clearly opens a NEW topic or
      // redirects (question/negation openers) — a context where CONTINUE would
      // be a genuine false positive. Substantive approvals-with-additions are
      // deliberately EXCLUDED (semantically they are go-aheads).
      // True rejection signal only: explicit redirect/negation after the worker
      // proposed something. Question-openers are excluded — a new question after an
      // incomplete reply is often a legitimate continue point, not a rejection.
      const REDIRECT_RE = /^(no\b|nope|don't|dont|stop|wait|hold on|actually|instead|rather|not\b|never|cancel)\b/i
      const kind: "continue" | "control" | null = isContinuePush(nextUser)
        ? current.turn.origin === "human" || current.turn.origin === "unknown" ? "continue" : null
        : nextUser.trim().length > 80 && REDIRECT_RE.test(nextUser.trim())
          ? "control"
          : null
      if (kind === null) continue
      if (current.turn.assistantMessageID === undefined || current.turn.assistantText.trim() === "") continue
      if ((usedPerSession.get(`${sessionID}:${kind}`) ?? 0) >= perSessionCap) continue
      usedPerSession.set(`${sessionID}:${kind}`, (usedPerSession.get(`${sessionID}:${kind}`) ?? 0) + 1)
      cases.push({ kind, session: sessionID, target: current.turn, targetCreatedMs: current.userCreatedMs, history: turns.slice(0, i + 1).map((t) => t.turn) })
    }
  }
  const continueCases = cases.filter((c) => c.kind === "continue").slice(0, maxContinue)
  const controlCases = cases.filter((c) => c.kind === "control").slice(0, maxControl)
  console.error(`cases: ${continueCases.length} continue-ground-truth, ${controlCases.length} control`)

  const siblings = [...perSession.entries()]
  const results: Record<string, unknown>[] = []
  let done = 0
  for (const c of [...continueCases, ...controlCases]) {
    const siblingChanges: Record<string, Turn[]> = {}
    const targetDir = dirOf.get(c.session)
    for (const [sessionID, turns] of siblings) {
      if (sessionID === c.session) continue
      if (dirOf.get(sessionID) !== targetDir) continue
      siblingChanges[sessionID] = turns.filter((t) => t.userCreatedMs > 0 && t.userCreatedMs <= c.targetCreatedMs).map((t) => t.turn)
    }
    const context: AssembledContext = assembleContext({
      target: c.target,
      targetHistory: c.history,
      siblingChanges,
      targetHistoryCapPairs: config.target_history_cap_pairs,
      siblingTurnWindow: config.sibling_turn_window,
      tokenBudget: config.token_budget,
    })
    const decision = await runTick({ adapter, context, target: c.target, confidenceFloor: config.confidence_floor })
    done += 1
    console.error(`[${done}/${continueCases.length + controlCases.length}] ${c.kind} → ${decision.action}`)
    results.push({
      kind: c.kind,
      session: c.session,
      targetMessage: c.target.userMessageID,
      push: c.kind === "continue" ? "continue-class" : "substantive",
      decision: decision.action,
      confidence: decision.confidence,
      rationale: decision.rationale.slice(0, 220),
      userText: c.target.userText.slice(0, 2000),
      workerText: c.target.assistantText.slice(0, 4000),
      targetExcerpt: c.target.assistantText.slice(0, 120),
    })
  }

  const summary = {
    continueTotal: continueCases.length,
    continueHits: results.filter((r) => r['kind'] === "continue" && r['decision'] === "CONTINUE").length,
    continueAccepts: results.filter((r) => r['kind'] === "continue" && r['decision'] === "ACCEPT").length,
    continueAbstains: results.filter((r) => r['kind'] === "continue" && r['decision'] === "ABSTAIN").length,
    continueOther: results.filter((r) => r['kind'] === "continue" && !["CONTINUE", "ACCEPT", "ABSTAIN"].includes(String(r['decision']))).length,
    controlContinueFalsePositives: results.filter((r) => r['kind'] === "control" && r['decision'] === "CONTINUE").length,
    controlTotal: controlCases.length,
  }
  const outPath = join(homedir(), ".local", "state", "opencode-supervisor", `benchmark-continue-${new Date().toISOString().replace(/[:.]/g, "-")}.json`)
  const { writeFile, mkdir } = await import("node:fs/promises")
  await mkdir(join(homedir(), ".local", "state", "opencode-supervisor"), { recursive: true })
  await writeFile(outPath, JSON.stringify({ summary, results }, null, 2))
  console.log(JSON.stringify({ summary, outPath }, null, 2))
}

if (import.meta.main) await main()
