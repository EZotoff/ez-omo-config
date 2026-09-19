import { homedir } from "node:os"
import { join, resolve } from "node:path"
import { ZaiAdapter } from "./adapter"
import { assembleContext } from "./assembler"
import { OpencodeClient, type ServerEvent } from "./client"
import { loadApiKey, loadConfig, loadProviderBaseURL } from "./config"
import { Ledger } from "./ledger"
import { changedTurnsSinceWatermark, reconcileRoot, type ScanManifest } from "./reconcile"
import { pollRootOnce } from "./poller"
import { writeStatus, type SupervisorStatus } from "./status"
import { initialState, transition, type SessionEvent, type SessionState } from "./statemachine"
import { runTick } from "./tick"
import { pickTarget } from "./targets"
import { ConsoleChannel } from "./console"
import { isAbortError } from "./health"
import { AttentionQueue, itemState, type RevalidationSources } from "./queue"
import type { Action, AttentionQueueItem, Decision, OriginRegistry, Turn } from "./types"

const emptyRegistry: OriginRegistry = { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }

type RootRuntime = {
  readonly root: string
  readonly mode: "shadow" | "observe" | "full"
  manifest: ScanManifest
  queueDepth: number
  scheduler?: SessionScheduler
  readonly states: Map<string, SessionState>
}

class ConcurrencyGate {
  private active = 0
  private readonly waiters: Array<() => void> = []
  constructor(private readonly limit: number) {}

  async run<T>(operation: () => Promise<T>): Promise<T> {
    if (this.active >= this.limit) await new Promise<void>((resolveWaiter) => this.waiters.push(resolveWaiter))
    this.active += 1
    try {
      return await operation()
    } finally {
      this.active -= 1
      this.waiters.shift()?.()
    }
  }
}

/**
 * Per-session intervention intervals and per-session work chains.
 *
 * Interval throttle is per SESSION (sessionID → lastTickAt), not per root: one
 * busy session must not mute the rest of the project. Work for the same
 * session is serialized (grace periods never overlap for one session);
 * different sessions dispatch concurrently — the global cap stays with
 * ConcurrencyGate around runTick, not here.
 */
export class SessionScheduler {
  private readonly lastTickAt = new Map<string, number>()
  private readonly inFlight = new Map<string, Promise<void>>()
  constructor(
    private readonly minIntervalMs: number,
    private readonly nowFn: () => number,
    private readonly run: (sessionID: string) => Promise<void>,
  ) {}

  isThrottled(sessionID: string): boolean {
    return this.nowFn() - (this.lastTickAt.get(sessionID) ?? 0) < this.minIntervalMs
  }

  markTicked(sessionID: string): void {
    this.lastTickAt.set(sessionID, this.nowFn())
  }

  enqueue(sessionID: string): Promise<void> {
    const previous = this.inFlight.get(sessionID) ?? Promise.resolve()
    const next = previous.then(() => {
      if (this.isThrottled(sessionID)) return
      return this.run(sessionID)
    })
    // Chain state must never reject (a failed run would poison every later
    // tick for the session); rejections are surfaced to the caller via `next`.
    this.inFlight.set(sessionID, next.catch(() => undefined))
    return next
  }
}

function eventSessionID(event: ServerEvent): string | undefined {
  const properties = event.properties
  if (properties === undefined) return undefined
  const sessionID = properties["sessionID"] ?? properties["sessionId"]
  return typeof sessionID === "string" ? sessionID : undefined
}

function emptyStatus(): SupervisorStatus {
  return { lastReconcile: null, queueDepths: {}, ticksByAction: {}, unknownOriginRate: 0, machineMarkedRate: 0, modes: {} }
}

export async function runService(signal: AbortSignal): Promise<void> {
  const repoRoot = resolve(import.meta.dir, "../..")
  const config = await loadConfig(join(repoRoot, "configs", "opencode-supervisor", "supervisor.json"))
  const stateDirectory = join(homedir(), ".local", "state", "opencode-supervisor")
  const statusPath = join(stateDirectory, "status.json")
  const ledgerPath = join(stateDirectory, "ledger.jsonl")
  const client = new OpencodeClient(config.server_url, {
    username: config.server_username,
    password: process.env[config.server_password_env] ?? "",
  })
  const baseURL = await loadProviderBaseURL(join(repoRoot, "configs", "opencode", "opencode.json"), config.model.provider)
  const apiKey = await loadApiKey(join(homedir(), ".local", "share", "opencode", "auth.json"), config.model.provider)
  const adapter = new ZaiAdapter(baseURL, config.model.id, apiKey)
  const tickGate = new ConcurrencyGate(config.max_tick_concurrency)
  let ledger = await Ledger.open(ledgerPath)
  const status = emptyStatus()
  const runtimes = new Map<string, RootRuntime>()
  const queue = await AttentionQueue.open({
    path: join(stateDirectory, "queue.json"),
    append: async (type, payload) => { ledger = await ledger.append(type, payload) },
  })
  const buildSources = async (item: AttentionQueueItem): Promise<RevalidationSources> => {
    const root = item.target.root
    const sessions = await client.listSessions(root)
    const exists = sessions.some((session) => session.id === item.target.sessionID)
    const messages = exists ? await client.listMessages(item.target.sessionID, root) : []
    const last = messages.at(-1)
    const idle = last !== undefined && last.role === "assistant" && last.time.completed !== undefined
    const aborted = last !== undefined && last.role === "assistant" && (last.finish === "aborted" || isAbortError(last.error))
    return {
      targetExists: () => exists,
      targetIdle: () => idle,
      latestMessageID: () => last?.id,
      targetTurnAborted: () => aborted,
      ticketOpen: () => queue.items.some((entry) => entry.id === item.id && itemState(entry) !== "resolved"),
      blackboardFactActive: () => true,
      canonicalItemFor: (key) => queue.items.find((entry) => entry.decisionKey === key && itemState(entry) !== "resolved")?.id,
      answeredElsewhere: () => undefined,
      approvalRequired: () => false,
      modePermits: () => true,
      citationsAdmissible: () => true,
    }
  }
  const consoles = new ConsoleChannel({
    client,
    queue,
    statePath: join(stateDirectory, "consoles.json"),
    ledger: () => ledger,
    setLedger: (next) => { ledger = next },
    probe: buildSources,
  })
  await consoles.load()

  const reconcile = async (root: string): Promise<RootRuntime> => {
    const manifest = await reconcileRoot(client, root, emptyRegistry, {
      initialWindowDays: config.initial_window_days,
      fetchConcurrency: config.fetch_concurrency,
    }, consoles.allSessionIDs())
    const previous = runtimes.get(root)
    const runtime = previous ?? {
      root,
      mode: (config.roots.find((r) => r.path === root)?.mode ?? "shadow") as "shadow" | "observe" | "full",
      manifest,
      queueDepth: 0,
      states: new Map<string, SessionState>(),
    }
    runtime.manifest = manifest
    runtimes.set(root, runtime)
    status.lastReconcile = manifest.completedAt
    status.queueDepths[root] = runtime.queueDepth
    const turns = [...runtimes.values()].flatMap((entry) => entry.manifest.sessions.flatMap((scan) => scan.turns))
    status.unknownOriginRate = turns.length === 0 ? 0 : turns.filter((turn) => turn.origin === "unknown").length / turns.length
    status.machineMarkedRate = turns.length === 0 ? 0 : turns.filter((turn) => turn.origin === "machine-synthetic" || turn.origin === "machine-template").length / turns.length
    await writeStatus(statusPath, status)
    return runtime
  }

  const recordDecision = async (decision: Decision, turn: Turn): Promise<void> => {
    ledger = await ledger.append("TICK_DECIDED", { decision, sessionID: turn.sessionID, messageID: turn.userMessageID })
    const action: Action = decision.action
    status.ticksByAction[action] = (status.ticksByAction[action] ?? 0) + 1
    await writeStatus(statusPath, status)
  }

  const processIdle = async (runtime: RootRuntime, sessionID: string): Promise<void> => {
    try {
      // Interval throttle lives in SessionScheduler (per session, checked at dispatch).
      await Bun.sleep(config.grace_period_s * 1000)
      if (signal.aborted) return
      const graceResult = transition(runtime.states.get(sessionID) ?? initialState, { type: "grace_elapsed", at: Date.now() })
      runtime.states.set(sessionID, graceResult.state)
      if (graceResult.illegal || graceResult.state.kind !== "TICK") return
      const previousManifest = runtime.manifest
      runtime.manifest = (await reconcile(runtime.root)).manifest
      const scan = runtime.manifest.sessions.find((entry) => entry.session.id === sessionID)
      // Operator-attention-point guard: tick only if the target reply is the
      // session's LAST message. If anything arrived after it (a ralph push, a
      // nudge, a user message), that idle moment was already handled — stand down.
      const target = scan === undefined ? undefined : pickTarget(scan.turns, scan.messages)
      if (target === undefined) {
        if (scan !== undefined && scan.turns.length > 0) {
          ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: "target is not the session's last message (native continuation or newer turn intervened)" })
        }
      }
      if (target !== undefined) {
        ledger = await ledger.append("WORKER_TURN_COMPLETED", { sessionID, messageID: target.assistantMessageID })
        if (target.origin === "unknown") ledger = await ledger.append("CLASSIFIED_UNKNOWN", { sessionID, messageID: target.userMessageID })
        const context = assembleContext({
          target,
          targetHistory: scan?.turns ?? [],
          siblingChanges: Object.fromEntries(runtime.manifest.sessions
            .filter((entry) => entry.session.id !== sessionID)
            .map((entry) => {
              const previousWatermark = previousManifest.sessions.find((previous) => previous.session.id === entry.session.id)?.watermark
              return [entry.session.id, changedTurnsSinceWatermark(previousWatermark, entry)]
            })),
          targetHistoryCapPairs: config.target_history_cap_pairs,
          siblingTurnWindow: config.sibling_turn_window,
          tokenBudget: config.token_budget,
        })
        const decision = await tickGate.run(() => runTick({ adapter, context, target, confidenceFloor: config.confidence_floor }))
        await recordDecision(decision, target)
        if (decision.action === "ESCALATE" && (runtime.mode === "observe" || runtime.mode === "full")) {
          const evidence = decision.citations.map((c) => `${c.session}/${c.messageID}: ${c.quote.slice(0, 80)}`).join("; ")
          const proposed = await consoles.proposeEscalation({
            root: runtime.root,
            sessionID,
            question: decision.rationale,
            rationale: evidence || "no citations supplied",
            citations: decision.citations,
            confidence: decision.confidence,
            target: {
              root: runtime.root,
              sessionID,
              userMessageID: target.userMessageID,
              ...(target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID }),
              ...(scan?.session.title === undefined ? {} : { sessionTitle: scan.session.title }),
            },
          })
          if (proposed.kind === "deduped" || proposed.kind === "capped") {
            const reason = proposed.kind === "deduped" ? "escalation deduped by decision key" : proposed.reason
            ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason })
          } else {
            const surfaced = await consoles.surfaceNext(runtime.root, new Date().toISOString())
            if (surfaced.kind === "resolved") {
              ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `escalation ${surfaced.disposition}: ${surfaced.reason}` })
            }
          }
        }
        runtime.states.set(sessionID, transition(graceResult.state, { type: "decision_recorded", at: Date.now() }).state)
        runtime.scheduler?.markTicked(sessionID)
      }
    } finally {
      runtime.queueDepth = Math.max(0, runtime.queueDepth - 1)
      status.queueDepths[runtime.root] = runtime.queueDepth
      await writeStatus(statusPath, status)
    }
  }

  const enqueueIdle = async (runtime: RootRuntime, sessionID: string): Promise<void> => {
    runtime.scheduler ??= new SessionScheduler(
      config.min_intervention_interval_s * 1000,
      Date.now,
      (sid) => processIdle(runtime, sid),
    )
    runtime.queueDepth += 1
    status.queueDepths[runtime.root] = runtime.queueDepth
    await writeStatus(statusPath, status)
    void runtime.scheduler.enqueue(sessionID).catch(async (error) => {
      if (!(error instanceof Error)) throw error
      ledger = await ledger.append("ERROR", { root: runtime.root, sessionID, error: error.message })
    })
  }

  const applyEvent = async (runtime: RootRuntime, sessionID: string, event: SessionEvent): Promise<boolean> => {
    const previous = runtime.states.get(sessionID) ?? initialState
    const result = transition(previous, event)
    runtime.states.set(sessionID, result.state)
    if (result.illegal) {
      ledger = await ledger.append("ERROR", { root: runtime.root, sessionID, reason: "illegal FSM transition", event: event.type })
    }
    return previous.kind !== "GRACE" && result.state.kind === "GRACE" && !result.illegal
  }

  const periodicReconcile = setInterval(() => {
    for (const root of config.roots) {
      if (root.mode === "off") continue
      void reconcile(root.path)
    }
  }, 600_000)
  signal.addEventListener("abort", () => clearInterval(periodicReconcile), { once: true })

  // Polling ingress (SSE is unusable on live 1.18.5 for project events — see poller.ts).
  const POLL_INTERVAL_MS = 20_000
  for (const root of config.roots) {
    if (root.mode === "off") continue
    const runtime0 = await reconcile(root.path)
    status.modes = { ...status.modes, [root.path]: runtime0.mode }
    await writeStatus(statusPath, status)
    if (root.mode === "observe" || root.mode === "full") {
      void consoles.ensure(root.path, `[Supervisor] ${root.path.split("/").at(-1) ?? root.path}`)
    }
    const watchStates = new Map<string, { messageCount: number; completed: boolean }>()
    void (async () => {
      while (!signal.aborted) {
        await Bun.sleep(POLL_INTERVAL_MS)
        const runtime = runtimes.get(root.path)
        if (runtime === undefined) continue
        try {
          const childIDs = new Set([...runtime.manifest.childSessionIDs, ...consoles.allSessionIDs()])
          const signals = await pollRootOnce(client, root.path, childIDs, watchStates, Date.now())
          for (const sig of signals) {
            if (sig.kind === "busy") {
              await applyEvent(runtime, sig.sessionID, { type: "busy", at: Date.now() })
            } else if (sig.kind === "idle") {
              if (await applyEvent(runtime, sig.sessionID, { type: "idle", at: Date.now() })) {
                await enqueueIdle(runtime, sig.sessionID)
              }
            }
          }
          const replies = await consoles.pollReplies(root.path, new Date().toISOString())
          for (const reply of replies) {
            await consoles.handleReply(reply, new Date().toISOString())
          }
        } catch (error) {
          if (error instanceof Error) {
            ledger = await ledger.append("ERROR", { root: root.path, error: error.message })
          }
        }
      }
    })()
  }

  await new Promise<void>((resolveDone) => signal.addEventListener("abort", () => resolveDone(), { once: true }))
}
