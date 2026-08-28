import { homedir } from "node:os"
import { join, resolve } from "node:path"
import { ZaiAdapter } from "./adapter"
import { assembleContext, type AssembledContext } from "./assembler"
import { OpencodeClient } from "./client"
import { loadApiKey, loadConfig, loadProviderBaseURL } from "./config"
import { runTick } from "./tick"
import { deriveChildSessionIDs, topLevelSessions } from "./topology"
import { projectTurns } from "./projector"
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

type CompactTurn = { turn: Turn; userCreatedMs: number }

function compactTurns(messages: readonly Message[], sessionID: string): CompactTurn[] {
  return projectTurns(messages, { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() })
    .map((turn) => ({
      turn,
      userCreatedMs: messages.find((m) => m.id === turn.userMessageID)?.time.created ?? 0,
    }))
    .filter((t) => t.turn.sessionID === sessionID)
}

async function main(): Promise<void> {
  const args = new Map(process.argv.slice(2).map((v, i, all) => (v.startsWith("--") ? [v.slice(2), all[i + 1] ?? ""] : [String(i), v])))
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

  const perSession = new Map<string, CompactTurn[]>()
  for (let i = 0; i < top.length; i += 1) perSession.set(top[i]!.id, compactTurns(all[i] ?? [], top[i]!.id))
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
      const REDIRECT_RE = /^(what|why|how|who|when|where|which|can|could|would|is|are|do|does|did|no\b|don't|dont|stop|wait|actually|instead|not\b|before|first)\b/i
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

await main()
