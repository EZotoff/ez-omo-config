// allow: SIZE_OK — orchestrator (processIdle + poll loop + wiring); pre-existing growth, split deferred.
import { homedir } from "node:os"
import { join, resolve } from "node:path"
import { ZaiAdapter } from "./adapter"
import { assembleContext, type SiblingView } from "./assembler"
import { classifyAutonomousOrigin, type AutonomousOriginConfig } from "./origins"
import { OpencodeClient, type ServerEvent } from "./client"
import { loadApiKey, loadConfig, loadProviderBaseURL, rootAutonomousOrigin } from "./config"
import { Ledger } from "./ledger"
import { changedTurnsSinceWatermark, reconcileRoot, SessionBackoff, type ScanManifest } from "./reconcile"
import { pollRootOnce, ActivityGate, type WatchState } from "./poller"
import { clipFragment, truncateAtSentence } from "./text"
import { awaitingOperatorAnswer, createGuardedPrompt, pendingQuestionPart, pendingQuestionStartedAtMs, pendingQuestionText } from "./awaiting-input"
import { boundedDrain, STOP_DRAIN_GRACE_MS } from "./stop-drain"
import { writeStatus, type SupervisorStatus } from "./status"
import { initialState, transition, type SessionEvent, type SessionState } from "./statemachine"
import { runTickWithCollect } from "./tick"
import { pickTarget } from "./targets"
import { continueCapKey, continueWriteText, gateApproveWrite, approveWriteText, gateContinueWrite, gateSteerWrite, gateReformulateWrite, reformulateWriteText, steerWriteText } from "./continue-writes"
import { ConsoleChannel } from "./console"
import { errorSignature, InvestigationMemory, maybeDispatchErrorInvestigation } from "./investigation"
import { BeaconChannel, BEACON_CHANNEL_ID } from "./beacon"
import { Blackboard, parseTickDecided } from "./blackboard"
import { isAbortError, turnHealth } from "./health"
import { ContinuationBridge, readJournalEntries } from "./journalbridge"
import { AttentionQueue, itemState, openItemsByRoot, type RevalidationSources } from "./queue"
import { CollectBudget, CollectExecutor, type CollectEvent } from "./collect"
import { ProtectionRegistry } from "./protect"
import { OperatorViewPublisher, isProbeTarget } from "./operator-view"
import type { Action, AttentionQueueItem, Decision, OriginRegistry, Session, Turn } from "./types"

const emptyRegistry: OriginRegistry = { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }

type RootRuntime = {
  readonly root: string
  readonly mode: "shadow" | "observe" | "full"
  manifest: ScanManifest
  scheduler?: SessionScheduler
  readonly states: Map<string, SessionState>
  readonly origin: AutonomousOriginConfig
  continueWrites: { dateKey: string; count: number }
  steerWrites: { dateKey: string; count: number }
  reformulateWrites: { dateKey: string; count: number }
  approveWrites: { dateKey: string; count: number }
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
    const lastTick = this.lastTickAt.get(sessionID)
    return lastTick !== undefined && this.nowFn() - lastTick < this.minIntervalMs
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

export const tickDecidedPayload = (decision: Decision, turn: Turn, root: string) => ({
  decision,
  root,
  sessionID: turn.sessionID,
  messageID: turn.userMessageID,
})

function eventSessionID(event: ServerEvent): string | undefined {
  const properties = event.properties
  if (properties === undefined) return undefined
  const sessionID = properties["sessionID"] ?? properties["sessionId"]
  return typeof sessionID === "string" ? sessionID : undefined
}

function emptyStatus(): SupervisorStatus {
  return { lastReconcile: null, queueDepths: {}, ticksByAction: {}, unknownOriginRate: 0, machineMarkedRate: 0, modes: {}, errorsSinceStart: 0, errorsLastHour: 0, errorInvestigations: 0, collect: { attempts: 0, performed: 0, changed: 0, discarded: 0, budgetExhausted: 0, tokens: 0, rate: 0, changedRate: 0 } }
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
  // approveWrites counters are rebuilt from the durable ledger at boot — an
  // in-memory counter silently zeroed on restart and contradicted the review
  // surface (2026-10-04 evaluation: status showed {} with 2 would-grants logged).
  {
    // Epoch-scoped (Option 2, 2026-10-05): count only events at/after
    // approve_writes.epoch_started_at on any root; before it is epoch-1 history.
    const epochStartedAt = config.roots.find((r) => r.approve_writes?.epoch_started_at !== undefined)?.approve_writes?.epoch_started_at
    const epochMs = epochStartedAt === undefined ? 0 : Date.parse(epochStartedAt)
    const rebuilt = { wouldGrant: 0, granted: 0, skipped: 0 }
    for (const record of ledger.records) {
      if (Date.parse(record.timestamp) < epochMs) continue
      const payload = record.payload as { readonly reason?: string; readonly mode?: string }
      if (record.type === "TICK_SKIPPED" && (payload.reason ?? "").startsWith("approve write: WOULD-GRANT")) rebuilt.wouldGrant += 1
      else if (record.type === "TICK_SKIPPED" && (payload.reason ?? "").startsWith("approve write:")) rebuilt.skipped += 1
      else if (record.type === "INTERVENTION_SENT" && payload.mode === "approve") rebuilt.granted += 1
    }
    if (epochStartedAt !== undefined || rebuilt.wouldGrant + rebuilt.granted + rebuilt.skipped > 0) status.approveWrites = rebuilt
  }

  const errorHour = { windowStart: Date.now(), count: 0, toasted: false, investigated: false }
  const investigationMemory = new InvestigationMemory(config.error_investigation.dedup_window_h)
  async function recordErrorTelemetry(payload: Record<string, unknown>): Promise<void> {
    status.errorsSinceStart = (status.errorsSinceStart ?? 0) + 1
    if (Date.now() - errorHour.windowStart > 3_600_000) {
      errorHour.windowStart = Date.now()
      errorHour.count = 0
      errorHour.toasted = false
      errorHour.investigated = false
    }
    errorHour.count += 1
    status.errorsLastHour = errorHour.count
    status.errorsLastHourPeak = Math.max(status.errorsLastHourPeak ?? 0, errorHour.count)
    if (errorHour.count >= 10 && !errorHour.toasted) {
      errorHour.toasted = true
      await client.toast(`Supervisor logged ${errorHour.count} errors in the last hour (check journald + ledger)`, "Supervisor error storm")
    }
    // Dedup signature: the most recent ledger ERROR (payload error or reason).
    const latestErrorPayload = ledger.records.findLast((record) => record.type === "ERROR")?.payload as { readonly error?: unknown; readonly reason?: unknown } | undefined
    const latestErrorText = typeof latestErrorPayload?.error === "string" ? latestErrorPayload.error : typeof latestErrorPayload?.reason === "string" ? latestErrorPayload.reason : undefined
    const outcome = await maybeDispatchErrorInvestigation({
      client,
      append: async (type, record) => { ledger = await ledger.append(type, record) },
      config: config.error_investigation,
      errorHour,
      root: typeof payload["root"] === "string" ? payload["root"] : repoRoot,
      count: errorHour.count,
      peak: status.errorsLastHourPeak ?? errorHour.count,
      signature: latestErrorText === undefined ? undefined : errorSignature(latestErrorText),
      dedupWindowH: config.error_investigation.dedup_window_h,
      memory: investigationMemory,
    })
    if (outcome.dispatched) {
      status.errorInvestigations = (status.errorInvestigations ?? 0) + 1
      await client.toast(`Created session ${outcome.sessionID} to investigate the error peak (${errorHour.count} in the last hour)`, "Supervisor error investigation")
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
  // Atomic operator-view.json read model (orca-transition Task 2): published
  // after ledger append + queue derivation, plus a ≤15 s idle heartbeat.
  const operatorView = new OperatorViewPublisher({
    path: join(stateDirectory, "operator-view.json"),
    items: () => queue.items,
    ledgerSeq: () => ledger.records.at(-1)?.seq ?? 0,
    onHeartbeatError: (error) => {
      void ledger.append("ERROR", { reason: "operator-view heartbeat publish failed", error: error instanceof Error ? error.message : String(error) }).then((next) => { ledger = next }).catch(() => undefined)
    },
  })
  const publishOperatorView = async (): Promise<void> => {
    try {
      await operatorView.publish()
    } catch (error) {
      ledger = await ledger.append("ERROR", { reason: "operator-view publish failed", error: error instanceof Error ? error.message : String(error) })
      await recordErrorTelemetry({})
    }
  }
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
    deliverPropagation: async (input) => {
      const rootConfig = config.roots.find((r) => r.path === input.root)
      if (rootConfig?.continue_writes?.enabled !== true) return false
      await client.promptAsync(input.sessionID, input.root, `[supervisor] (operator answer) ${truncateAtSentence(input.answer, 4000)}`)
      ledger = await ledger.append("QUEUE_PROPAGATION_DELIVERED", { root: input.root, sessionID: input.sessionID, answer: truncateAtSentence(input.answer, 2000) })
      return true
    },
  })
  // Write-time guard (2026-10-05 incident class): EVERY supervisor-authored
  // intervention write routes through this — it re-fetches the target's
  // messages and refuses delivery while a question-tool dialog is pending.
  // The only permitted raw client.promptAsync in this file is the human
  // operator-answer propagation above; tests/test_supervisor_awaiting_input.sh
  // enforces that invariant structurally.
  const guardedPrompt = createGuardedPrompt({
    listMessages: (sessionID, root) => client.listMessages(sessionID, root),
    promptAsync: (sessionID, root, text) => client.promptAsync(sessionID, root, text),
  })
  await investigationMemory.load(join(stateDirectory, "investigations.json"))
  await consoles.load()
  const recovered = await consoles.recoverAnswered()
  if (recovered > 0) {
  }

  // OC Beacon answer capture (Seam 4, Amendment 2026-09-25): polls per-root
  // reply-inbox sessions and routes replies through the shared reply-router.
  const beacon = new BeaconChannel({
    client,
    queue,
    statePath: join(stateDirectory, "beacon.json"),
    aliases: () => consoles.aliasTable(),
    route: (reply, now) => consoles.handleReply(reply, now, { channelID: "beacon", promptChoice: false }),
  })
  await beacon.load()

  // Continuation journal→ledger bridge (task 10): escalate-only, no session writes.
  const bridge = new ContinuationBridge({
    statePath: join(stateDirectory, "journal-bridge.json"),
    read: readJournalEntries,
    append: async (type, payload) => { ledger = await ledger.append(type, payload) },
  })
  const pollBridge = async (): Promise<void> => {
    try {
      await bridge.poll()
    } catch (error) {
      ledger = await ledger.append("ERROR", { reason: "journal bridge poll failed", error: error instanceof Error ? error.message : String(error) })
    }
  }

  const rootBackoff = new Map<string, { failures: number; nextAttemptAt: number }>()
  const sessionBackoff = new SessionBackoff()
  const SWEEP_INTERVAL_MS = 5 * 60_000
  const RESURFACE_MS = 6 * 60 * 60_000
  const sweepState = new Map<string, { lastSweepMs: number; lastSurfaceMs: number }>()
  const reconcile = async (root: string): Promise<RootRuntime | undefined> => {
    const backoff = rootBackoff.get(root)
    if (backoff !== undefined && Date.now() < backoff.nextAttemptAt) {
      status.rootHealth = { ...status.rootHealth, [root]: { state: "failing", consecutiveFailures: backoff.failures, lastErrorAt: new Date(backoff.nextAttemptAt).toISOString() } }
      return runtimes.get(root)
    }
    let manifest
    try {
      manifest = await reconcileRoot(client, root, emptyRegistry, {
        initialWindowDays: config.initial_window_days,
        fetchConcurrency: config.fetch_concurrency,
        sessionBackoff,
        signal,
        previous: runtimes.get(root)?.manifest,
      }, new Set([...consoles.allSessionIDs(), ...beacon.allSessionIDs()]))
      rootBackoff.delete(root)
      if (manifest.fetchErrors.length > 0) {
        ledger = await ledger.append("ERROR", { root, error: `reconcile degraded: ${manifest.fetchErrors.length} session fetch(es) failed`, fetchErrors: manifest.fetchErrors.slice(0, 10) })
        // Undercount fix (2026-10-08): reconcile-degraded fetch failures were the
        // dominant storm signal but bypassed hourly telemetry — the error-peak gauge
        // ran ~2x low mid-incident (Oct 6: 108 ledger vs 58 counted).
        for (let i = 0; i < manifest.fetchErrors.length; i += 1) await recordErrorTelemetry({ root })
      }
      for (const sessionID of manifest.backoffEntered ?? []) {
        ledger = await ledger.append("ERROR", { root, reason: "session fetch backoff entered", sessionID })
      }
      for (const sessionID of manifest.backoffRecovered ?? []) {
        ledger = await ledger.append("ERROR", { root, reason: "session fetch backoff recovered", sessionID })
      }
    } catch (error) {
      if (signal.aborted) return runtimes.get(root)
      const b = rootBackoff.get(root) ?? { failures: 0, nextAttemptAt: 0 }
      const failures = b.failures + 1
      const delay = Math.min(2 ** Math.min(failures, 5) * 60_000, 1_800_000)
      rootBackoff.set(root, { failures, nextAttemptAt: Date.now() + delay })
      status.rootHealth = { ...status.rootHealth, [root]: { state: "failing", consecutiveFailures: failures, lastErrorAt: new Date().toISOString() } }
      try { await writeStatusSynced() } catch {}
      ledger = await ledger.append("ERROR", { root, error: `root reconcile failed (root degraded, service continues): ${error instanceof Error ? error.message : String(error)}` })
      await recordErrorTelemetry({ root })
      return runtimes.get(root)
    }
    const previous = runtimes.get(root)
    const rootConfig = config.roots.find((r) => r.path === root)
    const runtime = previous ?? {
      root,
      mode: (rootConfig?.mode ?? "shadow") as "shadow" | "observe" | "full",
      origin: rootConfig === undefined ? { pathGlobs: [], titlePrefixes: [] } : rootAutonomousOrigin(rootConfig),
      manifest,
      states: new Map<string, SessionState>(),
      continueWrites: { dateKey: continueCapKey(new Date()), count: 0 },
      steerWrites: { dateKey: continueCapKey(new Date()), count: 0 },
      reformulateWrites: { dateKey: continueCapKey(new Date()), count: 0 },
      approveWrites: { dateKey: continueCapKey(new Date()), count: 0 },
    }
    runtime.manifest = manifest
    runtimes.set(root, runtime)
    status.rootHealth = { ...status.rootHealth, [root]: { state: "ok", consecutiveFailures: 0 } }
    status.lastReconcile = manifest.completedAt
    await writeStatusSynced()
    const turns = [...runtimes.values()].flatMap((entry) => entry.manifest.sessions.flatMap((scan) => scan.turns))
    status.unknownOriginRate = turns.length === 0 ? 0 : turns.filter((turn) => turn.origin === "unknown").length / turns.length
    status.machineMarkedRate = turns.length === 0 ? 0 : turns.filter((turn) => turn.origin === "machine-synthetic" || turn.origin === "machine-template").length / turns.length
    try {
      await writeStatusSynced()
    } catch (error) {
      ledger = await ledger.append("ERROR", { root, error: `writeStatus failed: ${error instanceof Error ? error.message : String(error)}` })
      await recordErrorTelemetry({})
    }
    return runtime
  }

  const recordDecision = async (decision: Decision, turn: Turn, root: string): Promise<void> => {
    ledger = await ledger.append("TICK_DECIDED", tickDecidedPayload(decision, turn, root))
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
    await writeStatusSynced()
    await publishOperatorView()
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
      const refreshed = await reconcile(runtime.root)
      if (refreshed !== undefined) runtime.manifest = refreshed.manifest
      const rootConfig = config.roots.find((r) => r.path === runtime.root)
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
        // Awaiting-operator guard (2026-10-05 incident, ses_ef4ef9abaffe): a
        // session whose last assistant message trails a RUNNING question-tool
        // part is blocked on the operator's dialog answer. The projector drops
        // tool parts, so the text-less reply reads as undelivered and the tick
        // kick-starts the dialog. Suppress the WHOLE tick: no model call, no
        // decision, no write — the only owed surface is the operator counter
        // (status.awaitingOperator, computed in writeStatusSynced).
        const awaitingInputAtDecision = scan !== undefined && awaitingOperatorAnswer(scan.messages)
        if (awaitingInputAtDecision) {
          const pending = scan === undefined ? undefined : pendingQuestionPart(scan.messages)
          const sinceMs = pending === undefined ? undefined : pendingQuestionStartedAtMs(pending)
          ledger = await ledger.append("TICK_SKIPPED", {
            root: runtime.root,
            sessionID,
            reason: `awaiting-operator-input: question-tool dialog pending${sinceMs === undefined ? "" : ` since ${new Date(sinceMs).toISOString()}`}: ${pending === undefined ? "" : pendingQuestionText(pending, 140)}`,
          })
          runtime.states.set(sessionID, transition(graceResult.state, { type: "decision_recorded", at: Date.now() }).state)
          runtime.scheduler?.markTicked(sessionID)
          return
        }
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
        assertDispatchHandlesEveryAction(decision.action)
        // Funnel invariant (2026-10-02 postmortem): every non-terminal action must
        // end this tick with an effect or an explicit skip — an unhandled dispatch
        // is a schema ghost and gets a ledger ERROR instead of silence.
        let actionOutcome: "effect" | "skip" | "unhandled" = "unhandled"
        if (suppressedReason !== undefined) {
          ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: suppressedReason })
          actionOutcome = "skip"
        }
        if (decision.action === "ESCALATE" && (runtime.mode === "observe" || runtime.mode === "full")) {
          const evidence = decision.citations.map((c) => `${c.session}/${c.messageID}: ${clipFragment(c.quote, 800)}`).join("; ")
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
            actionOutcome = "skip"
          } else {
            actionOutcome = "effect"
            const surfaced = await consoles.surfaceNext(runtime.root, new Date().toISOString())
            if (surfaced.kind === "resolved") {
              ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `escalation ${surfaced.disposition}: ${surfaced.reason}` })
            }
          }
        }
if (
decision.action === "CONTINUE" &&
runtime.mode === "observe" &&
rootConfig?.continue_writes?.enabled === true
        ) {
          // Evidence gate (2026-09 audit): never kick-start a probe/throwaway
          // session — a bare "OK" on a compliance probe is DELIVERED work
          // (live false positive 2026-09-22, kick K1).
          if (scan !== undefined && isProbeTarget({ root: runtime.root, ...(scan.session.title === undefined ? {} : { sessionTitle: scan.session.title }) })) {
            ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: "continue write: probe/throwaway session — acknowledgment is delivery" })
            actionOutcome = "skip"
          } else {
          const today = continueCapKey(new Date())
          if (runtime.continueWrites.dateKey !== today) runtime.continueWrites = { dateKey: today, count: 0 }
          // APPROVE sub-path (2026-10-03 operator decision, Option C, rollout-
          // staged): a trivial in-scope "shall I?" gets counted (observe) or
          // granted (grant) under approve_writes; without the block, the
          // kick_start-only gate drops it as before.
          if (decision.mode === "approve" && rootConfig?.approve_writes?.enabled === true) {
            const approveCfg = rootConfig.approve_writes
            const today = continueCapKey(new Date())
            if (runtime.approveWrites.dateKey !== today) runtime.approveWrites = { dateKey: today, count: 0 }
            status.approveWrites ??= { wouldGrant: 0, granted: 0, skipped: 0 }
            if (approveCfg.mode === "observe") {
              status.approveWrites.wouldGrant += 1
              ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `approve write: WOULD-GRANT (observe): ${decision.rationale.slice(0, 160)}` })
              actionOutcome = "skip"
            } else {
              const approveGate = gateApproveWrite({
                config: { enabled: true, ...(approveCfg.daily_cap === undefined ? {} : { dailyCap: approveCfg.daily_cap }) },
                capUsedToday: runtime.approveWrites.count,
                lastMessageID: scan?.messages.at(-1)?.id,
                target: target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID },
                sessionProtected: protectedSession(sessionID),
                awaitingOperatorInput: awaitingInputAtDecision,
              })
              if (!approveGate.allowed) {
                status.approveWrites.skipped += 1
                ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `approve write: ${approveGate.reason}` })
                actionOutcome = "skip"
              } else {
                const sent = await guardedPrompt(sessionID, runtime.root, approveWriteText({ rationale: decision.rationale }))
                if (!sent.sent) {
                  status.approveWrites.skipped += 1
                  ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `approve write: ${sent.reason}` })
                  actionOutcome = "skip"
                } else {
                  runtime.approveWrites.count += 1
                  status.approveWrites.granted += 1
                  actionOutcome = "effect"
                  try {
                    await client.toast(`Supervisor approved: ${decision.rationale.slice(0, 160)} (${sessionID.slice(-8)})`, `[Supervisor] ${runtime.root.split("/").pop() ?? runtime.root}`)
                  } catch {}
                  ledger = await ledger.append("INTERVENTION_SENT", { root: runtime.root, sessionID, targetMessageID: target.userMessageID, mode: "approve", text: "[supervisor] (approve)", rationale: decision.rationale })
                }
              }
            }
          } else {
          const gate = gateContinueWrite({
            decision,
            config: {
              enabled: rootConfig.continue_writes.enabled,
              dailyCap: rootConfig.continue_writes.daily_cap,
              kickStartOnly: rootConfig.continue_writes.kick_start_only,
            },
            capUsedToday: runtime.continueWrites.count,
            lastMessageID: scan?.messages.at(-1)?.id,
            target: target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID },
            sessionProtected: protectedSession(sessionID),
            awaitingOperatorInput: awaitingInputAtDecision,
          })
          if (!gate.allowed) {
            ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `continue write: ${gate.reason}` })
            actionOutcome = "skip"
          } else {
            // Final premise re-check against live state immediately before the write.
            const fresh = await client.listMessages(sessionID, runtime.root)
            const liveGate = gateContinueWrite({
              decision,
              config: {
              enabled: rootConfig.continue_writes.enabled,
              dailyCap: rootConfig.continue_writes.daily_cap,
              kickStartOnly: rootConfig.continue_writes.kick_start_only,
            },
              capUsedToday: runtime.continueWrites.count,
              lastMessageID: fresh.at(-1)?.id,
              target: target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID },
              sessionProtected: protectedSession(sessionID),
              // Write-time awaiting check from the SAME fresh snapshot the
              // premise re-check uses; guardedPrompt below re-fetches again as
              // the final gate (two reads on a rare capped path is the price
              // of a race-free write).
              awaitingOperatorInput: awaitingOperatorAnswer(fresh),
            })
            if (!liveGate.allowed) {
              ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `continue write: ${liveGate.reason}` })
            actionOutcome = "skip"
            } else {
              const sent = await guardedPrompt(sessionID, runtime.root, continueWriteText(decision))
              if (!sent.sent) {
                ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `continue write: ${sent.reason}` })
                actionOutcome = "skip"
              } else {
                runtime.continueWrites.count += 1
                actionOutcome = "effect"
                ledger = await ledger.append("INTERVENTION_SENT", {
                  root: runtime.root,
                  sessionID,
                  targetMessageID: target.userMessageID,
                  mode: decision.mode ?? null,
                  text: "[supervisor] (continue)",
                  rationale: decision.rationale,
                })
              }
            }
          }
          }
          } // approve-writes else
        }
        // STEER write path (2026-10-02: gate/text existed with tests but were never
        // wired — the action was a schema ghost; 3 historical STEER decisions were
        // silently dropped).
        if (decision.action === "STEER" && runtime.mode === "observe" && rootConfig?.steer_writes?.enabled === true) {
          const today = continueCapKey(new Date())
          if (runtime.steerWrites.dateKey !== today) runtime.steerWrites = { dateKey: today, count: 0 }
          const gate = gateSteerWrite({
            decision,
            config: { enabled: rootConfig.steer_writes.enabled, dailyCap: rootConfig.steer_writes.daily_cap },
            capUsedToday: runtime.steerWrites.count,
            lastMessageID: scan?.messages.at(-1)?.id,
            target: { ...(target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID }), sessionID },
            sessionProtected: protectedSession(sessionID),
            awaitingOperatorInput: awaitingInputAtDecision,
          })
          if (!gate.allowed) {
            ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `steer write: ${gate.reason}` })
            actionOutcome = "skip"
          } else {
            const sent = await guardedPrompt(sessionID, runtime.root, steerWriteText(decision))
            if (!sent.sent) {
              ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `steer write: ${sent.reason}` })
              actionOutcome = "skip"
            } else {
              runtime.steerWrites.count += 1
              actionOutcome = "effect"
              ledger = await ledger.append("INTERVENTION_SENT", { root: runtime.root, sessionID, targetMessageID: target.userMessageID, mode: "steer", text: "[supervisor] (steer)", rationale: decision.rationale })
            }
          }
        }
        // REFORMULATE write path (2026-10-02: same ghost — never wired; the
        // operator-facing "ask for a fresh explain" capability).
        if (decision.action === "REFORMULATE" && runtime.mode === "observe" && rootConfig?.reformulate_writes?.enabled === true) {
          const today = continueCapKey(new Date())
          if (runtime.reformulateWrites.dateKey !== today) runtime.reformulateWrites = { dateKey: today, count: 0 }
          const gate = gateReformulateWrite({
            config: { enabled: rootConfig.reformulate_writes.enabled, dailyCap: rootConfig.reformulate_writes.daily_cap },
            capUsedToday: runtime.reformulateWrites.count,
            lastMessageID: scan?.messages.at(-1)?.id,
            target: target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID },
            sessionProtected: protectedSession(sessionID),
            awaitingOperatorInput: awaitingInputAtDecision,
          })
          if (!gate.allowed) {
            ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `reformulate write: ${gate.reason}` })
            actionOutcome = "skip"
          } else {
            const sent = await guardedPrompt(sessionID, runtime.root, reformulateWriteText({ rationale: decision.rationale }))
            if (!sent.sent) {
              ledger = await ledger.append("TICK_SKIPPED", { root: runtime.root, sessionID, reason: `reformulate write: ${sent.reason}` })
              actionOutcome = "skip"
            } else {
              runtime.reformulateWrites.count += 1
              actionOutcome = "effect"
              ledger = await ledger.append("INTERVENTION_SENT", { root: runtime.root, sessionID, targetMessageID: target.userMessageID, mode: "reformulate", text: "[supervisor] (reformulate)", rationale: decision.rationale })
            }
          }
        }
        if (decision.action !== "ACCEPT" && decision.action !== "ABSTAIN" && actionOutcome === "unhandled") {
          ledger = await ledger.append("ERROR", { root: runtime.root, sessionID, reason: "action funnel violation", action: decision.action })
          await recordErrorTelemetry({ root: runtime.root })
        }
        const funnel = status.actionFunnel ?? {}
        const entry = funnel[decision.action] ?? { decided: 0, effect: 0, skipped: 0 }
        status.actionFunnel = {
          ...funnel,
          [decision.action]: {
            decided: entry.decided + 1,
            effect: entry.effect + (actionOutcome === "effect" ? 1 : 0),
            skipped: entry.skipped + (actionOutcome === "skip" ? 1 : 0),
          },
        }
        runtime.states.set(sessionID, transition(graceResult.state, { type: "decision_recorded", at: Date.now() }).state)
        runtime.scheduler?.markTicked(sessionID)
      }
    } finally {
      await writeStatusSynced()
    }
  }

  /** queueDepths must mirror the attention queue (open = non-resolved items per
   *  root), never a hand-incremented counter — the counter drifted from the
   *  operator-view read model (0 vs 4 open cards, 2026-09-30 audit). */
  const writeStatusSynced = async (): Promise<void> => {
    for (const runtime of runtimes.values()) {
      status.queueDepths[runtime.root] = openItemsByRoot(queue.items)[runtime.root] ?? 0
    }
    // Safety valve for the awaiting-operator-input suppression: the operator-
    // facing count of sessions blocked on their question-tool dialog. Suppression
    // is never the wrong call for a blocked session (its next action is
    // structurally impossible until the dialog is answered), but reminder duty
    // belongs HERE — on the operator surface, not as a write into the session.
    let awaitingCount = 0
    let oldestQuestionStartMs: number | undefined
    for (const runtime of runtimes.values()) {
      for (const scan of runtime.manifest.sessions) {
        const pending = pendingQuestionPart(scan.messages)
        if (pending === undefined) continue
        awaitingCount += 1
        const start = pendingQuestionStartedAtMs(pending)
        if (start !== undefined && (oldestQuestionStartMs === undefined || start < oldestQuestionStartMs)) oldestQuestionStartMs = start
      }
    }
    status.awaitingOperator = { count: awaitingCount, ...(oldestQuestionStartMs === undefined ? {} : { oldestQuestionStartMs }) }
    await writeStatus(statusPath, status)
  }

  const enqueueIdle = async (runtime: RootRuntime, sessionID: string): Promise<void> => {
    runtime.scheduler ??= new SessionScheduler(
      config.min_intervention_interval_s * 1000,
      Date.now,
      (sid) => processIdle(runtime, sid),
    )
    await writeStatusSynced()
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
    // 2026-10-02 bonsai-stall fix: a fresh completion on an already-idle session
    // re-arms the tick. The old rule (only non-GRACE → GRACE enqueues) meant each
    // session ticked at most once per busy cycle — every later turn that completed
    // between polls was ignored until the operator poked it manually.
    return result.state.kind === "GRACE" && (previous.kind !== "GRACE" || event.type === "idle") && !result.illegal
  }

  const periodicReconcile = setInterval(() => {
    void pollBridge()
    for (const root of config.roots) {
      if (root.mode === "off") continue
      void reconcile(root.path)
    }
    void publishOperatorView()
  }, 600_000)
  signal.addEventListener("abort", () => clearInterval(periodicReconcile), { once: true })
  operatorView.startHeartbeat()
  signal.addEventListener("abort", () => operatorView.stop(), { once: true })

  // Polling ingress (SSE is unusable on live 1.18.5 for project events — see poller.ts).
  const POLL_INTERVAL_MS = 20_000
  const activeRoots = config.roots.filter((root) => root.mode !== "off")
  // Bounded stop-drain tracking (2026-10-07 shutdown hang): each poll loop
  // decrements activeLoops when it exits; when all loops have finished their
  // in-flight iteration after abort, the drain is complete and the process may
  // exit immediately (see boundedDrain at the end of runService).
  let activeLoops = 0
  let resolveDrainDone!: () => void
  const drainDone = new Promise<"drained">((resolve) => { resolveDrainDone = () => resolve("drained") })
  // Boot reconcile (RESTORED 2026-10-08): a8eeb40's stop-drain refactor dropped
  // the startup Promise.all — runtimes stayed empty, the poll-loop guard below
  // skipped every root, and the supervisor went blind after every restart (no
  // polling, no ticks; only the 600s sweeps kept lastReconcile moving).
  if (!signal.aborted) await Promise.all(activeRoots.map((root) => reconcile(root.path)))
  for (const root of activeRoots) {
    const runtime0 = runtimes.get(root.path)
    if (runtime0 === undefined) continue
    status.modes = { ...status.modes, [root.path]: runtime0.mode }
    await writeStatusSynced()
    if (root.mode === "observe" || root.mode === "full") {
      void consoles.ensure(root.path, `[Supervisor] ${root.path.split("/").at(-1) ?? root.path}`)
    }
    const watchStates = new Map<string, WatchState>()
    void (async () => {
      activeLoops += 1
      try {
      while (!signal.aborted) {
        await Bun.sleep(POLL_INTERVAL_MS)
        const runtime = runtimes.get(root.path)
        if (runtime === undefined) continue
        try {
          const childIDs = new Set([...runtime.manifest.childSessionIDs, ...consoles.allSessionIDs(), ...beacon.allSessionIDs()])
          const signals = await pollRootOnce(client, root.path, childIDs, watchStates, Date.now(), config.stall_minutes * 60_000)
          activityGate.observe(signals, Date.now())
          for (const sig of signals) {
            if (sig.kind === "busy") {
              await applyEvent(runtime, sig.sessionID, { type: "busy", at: Date.now() })
            } else if (sig.kind === "idle" || sig.kind === "stalled") {
              // A STALL is a synthetic idle: the worker stopped producing without
              // ever completing — the same operator-attention point, detected by
              // absence instead of by completion (wedged-stream class, D295-adjacent).
              if (await applyEvent(runtime, sig.sessionID, { type: "idle", at: Date.now() })) {
                await enqueueIdle(runtime, sig.sessionID)
              }
            }
          }
          const replies = await consoles.pollReplies(root.path, new Date().toISOString())
          for (const reply of replies) {
            await consoles.handleReply(reply, new Date().toISOString())
          }
          // Retry answered-but-undelivered propagations every tick (stuck-pending
          // fix): revalidate, then deliver the stored reply text or resolve.
          await consoles.retryPendingPropagations(new Date().toISOString())
          // Open-item lifecycle sweep (2026-10-01 audit): unanswered items aged
          // for days with nothing to trigger revalidation. Sweep revalidates on
          // a 5-min cadence (resolving dead items frees the open-item cap);
          // still-valid items are re-surfaced on a 6h dwell, not every sweep.
          const sweepClock = sweepState.get(root.path) ?? { lastSweepMs: 0, lastSurfaceMs: Date.now() }
          if (Date.now() - sweepClock.lastSweepMs >= SWEEP_INTERVAL_MS) {
            sweepClock.lastSweepMs = Date.now()
            const resolvedCount = await consoles.sweepOpenItems(root.path, new Date().toISOString())
            if (resolvedCount > 0) {
              ledger = await ledger.append("QUEUE_SWEPT", { root: root.path, resolved: resolvedCount })
            }
            const stillOpen = queue.items.some((item) => item.target.root === root.path && itemState(item) !== "resolved")
            if (stillOpen && Date.now() - sweepClock.lastSurfaceMs >= RESURFACE_MS) {
              sweepClock.lastSurfaceMs = Date.now()
              await consoles.surfaceNext(root.path, new Date().toISOString())
            }
            sweepState.set(root.path, sweepClock)
          }
          // OC Beacon reply-inbox ingestion (Seam 4, Amendment 2026-09-25) — same
          // tick cadence as the console channel; routing shares the reply-router.
          const beaconReplies = await beacon.poll(root.path, new Date().toISOString())
          for (const reply of beaconReplies) {
            await beacon.handleReply(reply, new Date().toISOString())
          }
        } catch (error) {
          if (error instanceof Error) {
            ledger = await ledger.append("ERROR", { root: root.path, error: error.message })
            await recordErrorTelemetry({ root: root.path })
          }
        }
      }
      } finally {
        activeLoops -= 1
        if (activeLoops === 0 && signal.aborted) resolveDrainDone()
      }
    })()
  }

  await new Promise<void>((resolveDone) => signal.addEventListener("abort", () => resolveDone(), { once: true }))
  // Bounded drain (see stop-drain.ts): wait for the per-root loops to finish
  // their in-flight iteration; force-exit at the deadline if a wedged client
  // call would hold the process forever. Attempt 1's unref'd timer starved
  // (it never counts toward the IO-poll timeout); a referenced Bun.sleep does
  // fire — and process.exit drops any remaining wedged fetch.
  const drainOutcome = await boundedDrain(drainDone, STOP_DRAIN_GRACE_MS)
  if (drainOutcome === "deadline") {
    try {
      ledger = await ledger.append("ERROR", { reason: `stop drain exceeded ${STOP_DRAIN_GRACE_MS}ms — force exit (wedged in-flight client call holds the event loop; pending fetches dropped, ledger writes are fs-complete)` })
    } catch (error) {
      // no-excuse-ok: catch — shutdown boundary; stderr before exit
      console.error("stop-drain ledger append failed:", error instanceof Error ? error.message : String(error))
    }
  }
  process.exit(0)
}

/** Compile-time exhaustiveness for the tick dispatch (2026-10-02 postmortem:
 *  STEER/REFORMULATE existed in the action schema for 10+ days with zero call
 *  sites — "schema ghosts" that green tests could not see). Adding a member to
 *  ACTIONS without updating the dispatch handling fails tsc at the never-default
 *  below. Structural bijection is additionally enforced at gate time by
 *  tests/test_supervisor_dispatch.sh. */
function assertDispatchHandlesEveryAction(action: Action): void {
  switch (action) {
    case "ACCEPT":
    case "ABSTAIN":
    case "CONTINUE":
    case "ESCALATE":
    case "STEER":
    case "REFORMULATE":
      return
    default: {
      const unhandled: never = action
      throw new Error(`tick action has no dispatch handling: ${String(unhandled)}`)
    }
  }
}
