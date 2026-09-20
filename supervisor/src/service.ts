// allow: SIZE_OK — orchestrator (processIdle + poll loop + wiring); pre-existing growth, split deferred.
import { homedir } from "node:os"
import { join, resolve } from "node:path"
import { ZaiAdapter } from "./adapter"
import { assembleContext, type SiblingView } from "./assembler"
import { classifyAutonomousOrigin, type AutonomousOriginConfig } from "./origins"
import { OpencodeClient, type ServerEvent } from "./client"
import { loadApiKey, loadConfig, loadProviderBaseURL, rootAutonomousOrigin } from "./config"
import { Ledger } from "./ledger"
import { changedTurnsSinceWatermark, reconcileRoot, type ScanManifest } from "./reconcile"
import { pollRootOnce, ActivityGate } from "./poller"
import { writeStatus, type SupervisorStatus } from "./status"
import { initialState, transition, type SessionEvent, type SessionState } from "./statemachine"
import { runTickWithCollect } from "./tick"
import { pickTarget } from "./targets"
import { ConsoleChannel } from "./console"
import { Blackboard, parseTickDecided } from "./blackboard"
import { isAbortError, turnHealth } from "./health"
import { AttentionQueue, itemState, type RevalidationSources } from "./queue"
import { CollectBudget, CollectExecutor, type CollectEvent } from "./collect"
import { ProtectionRegistry } from "./protect"
import type { Action, AttentionQueueItem, Decision, OriginRegistry, Session, Turn } from "./types"

const emptyRegistry: OriginRegistry = { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }

type RootRuntime = {
  readonly root: string
  readonly mode: "shadow" | "observe" | "full"
  manifest: ScanManifest
  queueDepth: number
  scheduler?: SessionScheduler
  readonly states: Map<string, SessionState>
  readonly origin: AutonomousOriginConfig
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

  private readonly deferred = new Set<string>()

  enqueue(sessionID: string): Promise<void> {
    const previous = this.inFlight.get(sessionID) ?? Promise.resolve()
    const next = previous.then(() => {
      if (this.isThrottled(sessionID)) {
        // Defer, never drop: the poller emits idle only on the completed-flip,
        // so a dropped event leaves the turn permanently unsupervised (caught
        // live 2026-09-20: second turn inside the 300s window vanished).
        if (!this.deferred.has(sessionID)) {
          this.deferred.add(sessionID)
          const elapsed = this.nowFn() - (this.lastTickAt.get(sessionID) ?? 0)
          const wait = Math.max(this.minIntervalMs - elapsed, 1_000)
          setTimeout(() => {
            this.deferred.delete(sessionID)
            void this.enqueue(sessionID)
          }, wait)
        }
        return
      }
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
  return { lastReconcile: null, queueDepths: {}, ticksByAction: {}, unknownOriginRate: 0, machineMarkedRate: 0, modes: {}, errorsSinceStart: 0, errorsLastHour: 0, collect: { attempts: 0, performed: 0, changed: 0, discarded: 0, budgetExhausted: 0, tokens: 0, rate: 0, changedRate: 0 } }
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
  const errorHour = { windowStart: Date.now(), count: 0, toasted: false }
  async function recordErrorTelemetry(payload: Record<string, unknown>): Promise<void> {
    status.errorsSinceStart = (status.errorsSinceStart ?? 0) + 1
    if (Date.now() - errorHour.windowStart > 3_600_000) {
      errorHour.windowStart = Date.now()
      errorHour.count = 0
      errorHour.toasted = false
    }
    errorHour.count += 1
    status.errorsLastHour = errorHour.count
    if (errorHour.count >= 20 && !errorHour.toasted) {
      errorHour.toasted = true
      await client.toast(`Supervisor logged ${errorHour.count} errors in the last hour (check journald + ledger)`, "Supervisor error storm")
    }
  }

  const collectBudget = new CollectBudget()
  const runtimes = new Map<string, RootRuntime>()
  const protection = await ProtectionRegistry.open(join(stateDirectory, "protected.json"))
  const protectedSession = (sessionID: string): boolean => protection.isProtected(sessionID)
  const queue = await AttentionQueue.open({
    path: join(stateDirectory, "queue.json"),
    append: async (type, payload) => { ledger = await ledger.append(type, payload) },
    protectedSession,
  })
  const blackboard = await Blackboard.open({
    path: join(stateDirectory, "blackboard.json"),
    append: async (type, payload) => { ledger = await ledger.append(type, payload) },
  })
  const activityGate = new ActivityGate()
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
      blackboardFactActive: (premise) => blackboard.factActive(premise.factID, premise.factVersion, new Date().toISOString()),
      canonicalItemFor: (key) => queue.items.find((entry) => entry.decisionKey === key && itemState(entry) !== "resolved")?.id,
      answeredElsewhere: (item) => {
        const answer = blackboard.answerFor(item.decisionKey, new Date().toISOString())
        return answer === undefined ? undefined : { source: "blackboard", entryID: answer.entryID, version: answer.version }
      },
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
    const rootConfig = config.roots.find((r) => r.path === root)
    const runtime = previous ?? {
      root,
      mode: (rootConfig?.mode ?? "shadow") as "shadow" | "observe" | "full",
      origin: rootConfig === undefined ? { pathGlobs: [], titlePrefixes: [] } : rootAutonomousOrigin(rootConfig),
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
    try {
      await writeStatus(statusPath, status)
    } catch (error) {
      ledger = await ledger.append("ERROR", { root, error: `writeStatus failed: ${error instanceof Error ? error.message : String(error)}` })
      await recordErrorTelemetry({})
    }
    return runtime
  }

  const recordDecision = async (decision: Decision, turn: Turn, root: string): Promise<void> => {
    ledger = await ledger.append("TICK_DECIDED", { decision, sessionID: turn.sessionID, messageID: turn.userMessageID })
    const action: Action = decision.action
    status.ticksByAction[action] = (status.ticksByAction[action] ?? 0) + 1
    if (status.collect !== undefined) {
      const ticks = Object.values(status.ticksByAction).reduce((sum, count) => sum + count, 0)
      status.collect.rate = ticks === 0 ? 0 : status.collect.performed / ticks
      status.collect.changedRate = status.collect.performed === 0 ? 0 : status.collect.changed / status.collect.performed
    }
    await blackboard.writeDecision({
      root,
      tickID: `tick_${ledger.records.at(-1)?.seq ?? 0}`,
      sessionID: turn.sessionID,
      action,
      rationale: decision.rationale,
      now: new Date().toISOString(),
    })
    await writeStatus(statusPath, status)
  }

  const recordCollect = (event: CollectEvent): void => {
    const telemetry = status.collect ?? { attempts: 0, performed: 0, changed: 0, discarded: 0, budgetExhausted: 0, tokens: 0, rate: 0, changedRate: 0 }
    telemetry.attempts += 1
    if (event.outcome === "gathered") telemetry.performed += 1
    if (event.outcome === "discarded") telemetry.discarded += 1
    if (event.outcome === "budget-blocked") telemetry.budgetExhausted += 1
    if (event.changed) telemetry.changed += 1
    telemetry.tokens += event.tokens
    status.collect = telemetry
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
      const target = scan === undefined ? undefined : pickTarget(scan.turns, scan.messages, { sessionProtected: protectedSession(sessionID) })
      if (target === undefined) {
        if (scan !== undefined && scan.turns.length > 0) {
          ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: "target is not the session's last message (native continuation or newer turn intervened)" })
        }
      }
      if (target !== undefined) {
        // CONTINUE quiescence gate (T6): never kick-start a session that moved during grace.
        if (!activityGate.isQuiescent(sessionID, Date.now(), config.grace_period_s * 1000)) {
          ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: "activity gate: session moved during grace — not quiescent, tick suppressed" })
          return
        }
        ledger = await ledger.append("WORKER_TURN_COMPLETED", { sessionID, messageID: target.assistantMessageID })
        const recentDecisions: { readonly action: string; readonly rationale: string; readonly decidedAtMs: number }[] = []
        for (const record of [...ledger.records].reverse()) {
          const decided = parseTickDecided(record)
          if (decided === undefined || decided.sessionID !== sessionID) continue
          recentDecisions.push({ action: decided.action, rationale: decided.rationale, decidedAtMs: Date.parse(decided.decidedAt) })
          if (recentDecisions.length === 3) break
        }
        const isAutonomous = (session: Session, kickoffText?: string): boolean =>
          classifyAutonomousOrigin(
            { directory: session.directory, ...(session.title === undefined ? {} : { title: session.title }), ...(kickoffText === undefined ? {} : { kickoffText }) },
            runtime.origin,
          )
        const autonomousTarget = scan === undefined ? false : isAutonomous(scan.session, scan.turns[0]?.userText)
        const siblings: SiblingView[] = runtime.manifest.sessions
          .filter((entry) => entry.session.id !== sessionID)
          .map((entry) => {
            const previousWatermark = previousManifest.sessions.find((previous) => previous.session.id === entry.session.id)?.watermark
            return {
              sessionID: entry.session.id,
              ...(entry.session.title === undefined ? {} : { title: entry.session.title }),
              ...(entry.session.timeUpdatedMs === undefined ? {} : { lastActivityMs: entry.session.timeUpdatedMs }),
              turns: changedTurnsSinceWatermark(previousWatermark, entry),
              autonomous: isAutonomous(entry.session, entry.turns[0]?.userText),
            }
          })
        const context = assembleContext({
          target,
          targetHistory: scan?.turns ?? [],
          siblings,
          targetHistoryCapPairs: config.target_history_cap_pairs,
          siblingTurnWindow: config.sibling_turn_window,
          tokenBudget: config.token_budget,
          tierBudgets: {
            targetHistory: config.tier_budgets.target_history,
            hot: config.tier_budgets.hot,
            warm: config.tier_budgets.warm,
            cool: config.tier_budgets.cool,
            cold: config.tier_budgets.cold,
          },
          targetAutonomous: autonomousTarget,
          selfMemory: {
            decisions: recentDecisions,
            openItems: queue.items
              .filter((item) => item.target.root === runtime.root && itemState(item) !== "resolved")
              .slice(0, 5)
              .map((item) => ({ id: item.id, question: item.question, createdAtMs: Date.parse(item.priority.createdAt) })),
            nowMs: Date.now(),
          },
        })
        const health = scan === undefined ? "healthy" : turnHealth(target, scan.messages)
        const executor = new CollectExecutor({
          client,
          root: runtime.root,
          ledgerRecords: () => ledger.records,
          openItems: () => queue.items,
          nowMs: Date.now,
        })
        let suppressedReason: string | undefined = undefined
        const decision = await tickGate.run(() => runTickWithCollect({
          adapter,
          context,
          target,
          confidenceFloor: config.confidence_floor,
          root: runtime.root,
          executor,
          budget: collectBudget,
          isIdle: async () => {
            const messages = await client.listMessages(sessionID, runtime.root)
            const last = messages.at(-1)
            return last !== undefined && last.id === target.assistantMessageID && last.time.completed !== undefined
          },
          healthAmbiguous: health !== "healthy" && health !== "aborted",
          hasSiblings: runtime.manifest.sessions.some((entry) => entry.session.id !== sessionID),
          nowMs: Date.now,
          onCollect: recordCollect,
          autonomous: autonomousTarget,
          onSuppressed: (reason) => { suppressedReason = reason },
        }))
        await recordDecision(decision, target, runtime.root)
        if (suppressedReason !== undefined) {
          ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: suppressedReason })
        }
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
          if (proposed.kind === "enqueued") {
            await blackboard.openQuestion({
              root: runtime.root,
              decisionKey: proposed.item.decisionKey,
              queueItemID: proposed.item.id,
              question: decision.rationale,
              now: new Date().toISOString(),
            })
          }
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
      await recordErrorTelemetry({ root: runtime.root })
    })
  }

  const applyEvent = async (runtime: RootRuntime, sessionID: string, event: SessionEvent): Promise<boolean> => {
    const previous = runtime.states.get(sessionID) ?? initialState
    const result = transition(previous, event)
    runtime.states.set(sessionID, result.state)
    if (result.illegal) {
      ledger = await ledger.append("ERROR", { root: runtime.root, sessionID, reason: "illegal FSM transition", event: event.type })
      await recordErrorTelemetry({ root: runtime.root })
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
          activityGate.observe(signals, Date.now())
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
            await recordErrorTelemetry({ root: root.path })
          }
        }
      }
    })()
  }

  await new Promise<void>((resolveDone) => signal.addEventListener("abort", () => resolveDone(), { once: true }))
}
