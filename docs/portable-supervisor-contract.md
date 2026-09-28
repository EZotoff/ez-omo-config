# Portable Supervisor — Cross-Project Integration Contract

> Single source of truth for how the three prototype components fit together. Every repo
> implements against this document; changes here are a contract change and land FIRST
> (see [Session-run discipline](#session-run-discipline)).
>
> Component docs: [voice-bridge](voice-bridge.md) · proposal: [portable-supervisor-proposal.md](portable-supervisor-proposal.md)
> · voice design: [`.sisyphus/debates/voice-agent/final-design.md`](../.sisyphus/debates/voice-agent/final-design.md)

## Components and repos

| Component | Repo | Role | Runs |
|---|---|---|---|
| **voice-bridge ("Vox")** | `~/AI_projects/voice-bridge/` | Voice brain: Gemini Live session, tools, interrupts, mutation pipeline, fallback chain | `voice-bridge.service`, `127.0.0.1:18220` |
| **omo-pulse** | `~/AI_projects/ez-omo-dash/` | Visual supervisor surface: attention queue, recent projects, session cards, remote UI (`?view=remote`, FIFO), desktop deep-links | dev `:4300/:4301`, prod `:4300` |
| **ez-omo-config** | `~/ez-omo-config/` | Contract home (this doc), config store, design artifacts, docs sync | — |
| **OC Beacon** | `~/src/oc-beacon/` | Native ambient attention surface (SHIPPED 2026-09-21: attention cards, AR-glance headlines, escalation/root-health/error-peak push notifications, directory-grouped strands); reads supervisor state through the already-configured OpenCode server | Android app |

Layering: **omo-pulse is the eyes and hands, voice-bridge is the ears and voice, this repo
owns the seam.** The interaction model: *navigate visually to establish context, then use
voice to reason or act on that context.*

## Seam 1 — Current-view context feed (omo-pulse → voice-bridge)

Sent on every navigation change while a voice session is active, over the voice WSS
(`ws://127.0.0.1:18220/voice?client=dash`):

```jsonc
{
  "type": "view-context",
  "project": { "id": "veran", "name": "Veran" },
  "session": { "id": "ses_…14", "title": "retrieval architecture", "state": "waiting|running|error" },
  "view": "home|project|session|comparison|attention",
  "selection": { "kind": "card|option|row", "id": "…", "label": "Qdrant" },  // when something is selected
  "recent": [ { "projectId": "…", "sessionId": "…" } ]                        // max 5, most recent first
}
```

Bridge behavior: store as **current context**; inject into Vox via `sendRealtimeInput({text})`
only on change (dedup) and only compactly (one line). Vox may reference it deictically
("why is *it* waiting?") and must treat it as a hint — tool calls remain the ground truth.
`propose_mutation` disambiguators may be resolved against current context (the readback
still names the target in human-legible form).

## Seam 2 — Show channel (voice-bridge → client)

Vox tool `show(view, title, payload)` → bridge emits a control frame; client renders
semantically (no phone-layout assumptions — glasses/watch may render the same frames later):

```jsonc
{ "type": "show", "view": "card|list|table|choice|progress|comparison|diff",
  "title": "DB OPTIONS", "contextTag": "ctx-17",
  "payload": { /* rows | options | items per view */ } }
```

Selection feedback (client → bridge): `{ "type": "selection", "contextTag": "ctx-17", "index": 1 }`
→ bridge logs it, pins it as a discussion fact, and includes it in the next context injection.
`contextTag` pairs a selection with the show frame it belongs to; stale tags are dropped.

## Seam 3 — Voice WSS client classes

One bridge, two client classes, **one active voice client at a time** (last connect wins;
the previous is closed with `{type:"handoff"}`):

| Client | Connects via | Audio | Control frames |
|---|---|---|---|
| bundled page (`web/index.html`) | `/voice` | full duplex (dev harness / standalone phone use) | send + receive |
| omo-pulse widget | `/voice?client=dash` | full duplex | send + receive + `view-context` + `selection` |

Auth is server-side only; the per-boot page token pattern stays. Dash and the bundled page
never talk to Gemini directly.

## Semantic action vocabulary (prototype §9 → bridge tools)

| User intention | Bridge implementation | Confirm gate |
|---|---|---|
| interrupt | `propose_mutation(abort_session)` | yes |
| continue | `prompt_session(sid, "continue")` | yes (code-affecting) |
| approve / proceed | confirm pending `propose_mutation` / `answer_question` | inherent |
| defer | `log_discussion_fact` + DiscussionLog note | no |
| send instruction | `prompt_session(sid, text)` | yes (code-affecting) |
| request more detail | read tools (`session_digest`, `read_file_snippet`) | no |
| show options / comparison | `show(view, …)` via Seam 2 | no |
| switch project / session | omo-pulse-local navigation + Seam 1 update | n/a |

The vocabulary stays deliberately small; extend here first, then implement per repo.

## Session-run discipline

Work happens in **per-repo sessions, contract-first** (one session per repo — AGENTS.md,
codegraph, and tests are repo-scoped):

| Work type | Session repo | Notes |
|---|---|---|
| Contract/vocabulary change | `ez-omo-config` (this doc) | lands FIRST, versioned here |
| Bridge-side implementation | `voice-bridge` | its tests + deploy discipline |
| Dash-side implementation | `omo-pulse` (`ez-omo-dash`) | **central dev session** — where the prototype iteration loop lives |
| Ops/config/docs | `ez-omo-config` | doc-sync rules apply |

## Validation ladder

1. **Desktop**: omo-pulse + voice widget on the workstation; deep-links as the full-view fallback.
2. **Android (walking test)**: **primary vehicle is OC Beacon native** (amended 2026-09-21 —
   shipped ahead of schedule: attention cards, AR-glance headlines, escalation/root-health/
   error-peak push notifications, directory-grouped strands). Remaining gap for the walking
   rung: **answer capture** (tap/spoken reply routed as a queue reply event, Seam 4) and
   spoken replies via Vox. Web-in-Chrome (`?view=remote`) remains the fallback/comparison path;
   its responsive + push-to-talk gaps are unchanged. Record fallback events per the
   proposal's §Prototype Validation.
3. **Peripheral decision**: only after (2); the contract's interaction concepts
   (PROJECT/SESSION/VIEW/SELECTION/VOICE/ACTION/SHOW/ATTENTION) stay stable across devices.

## Pending cross-repo work ledger

| Item | Repo | Status |
|---|---|---|
| Escalation `confidence ≥ 0.7` filter in ledger-tailer | voice-bridge | **done** — `ESCALATION_CONFIDENCE_THRESHOLD = 0.7` gate in [`src/pipeline/interrupts.ts:23`](file:///home/ezotoff/AI_projects/voice-bridge/src/pipeline/interrupts.ts) (TICK_DECIDED + ESCALATE + confidence ≥ 0.7, per final-design.md Amendment 2 §A) |
| `prompt_supervisor` write-path guardrail | this repo (design doc) | **contract defined, implementation pending** — design note: [docs/prompt-supervisor-write-path-guardrail.md](prompt-supervisor-write-path-guardrail.md); contract rule in Seam 4 (Amendment 2026-09-25): replies become correlated queue events routed by the reply-router (Seam 4 — the router is LIVE in the supervisor service), never free-form console writes. Current implementation ([`src/pipeline/tools/prompt-supervisor.ts:20-46`](file:///home/ezotoff/AI_projects/voice-bridge/src/pipeline/tools/prompt-supervisor.ts)) remains UNGATED (direct `promptAsync` into the `[Supervisor]` console session) until the bridge lands the gate in its own session |
| Voice widget + context feed in remote UI | omo-pulse | not started |
| Show-view renderer (Seam 2 frames) | omo-pulse | not started |
| Real-voice dogfood → MANIFEST evidence upgrade | this repo | blocked on (voice widget row) |
| Attention projection consumption (Seam 4 read → attention view) | omo-pulse | not started (schema defined above) |
| Ledger-tailer → `QUEUE_*` projection upgrade (escalations from the queue, not raw TICK_DECIDED) | voice-bridge | not started |
| OC Beacon answer capture (native tap/spoken reply → Seam 4 reply event) | oc-beacon + ez-omo-config | **implementation done, runtime observation pending** — send path SHIPPED in oc-beacon (`0ab9780c`); supervisor-side `BeaconChannel` implemented in ez-omo-config (`supervisor/src/beacon.ts`, 2026-09-26): inbox discovery + watermark + envelope/plain-text + `clientMessageID` dedup + correlation (explicitItemID → contextTag → alias → §5) routed through the shared reply-router with `channelID: "beacon"`; repo_implemented + tests_passed, not yet observed on a live beacon reply |
| OC Beacon walking-rung prep (spoken replies via Vox, small-screen polish) | oc-beacon + voice-bridge | not started |

## Seam 4 — Attention queue (Supervisor-owned)

The supervisor service owns a durable `AttentionQueue` (spec: `~/.local/state/opencode-supervisor/grading/attention-queue-contract.md`, incl. Addendum A; responsibility split per `vox-supervisor-context-split.md`). **Queue schema version: 1** (`schemaVersion: 1`, queue-item ID `att_<id>`, tick ID `tick_<id>`, alias `Q<n>` per root). Channels only present and collect; ticks propose but never surface directly.

### Ownership and lifecycle

- Supervisor decides **what** objectively needs attention; Vox decides **how and when** to discuss it (context-split ruling).
- Items enter via `propose` (deterministic `decisionKey` upsert, cross-tick dedupe), pass **premise revalidation at surfacing**, and again **after each reply** before any propagation to a worker session.
- Resolutions: `propagated` (confirm-gated), `retired-by-evidence`, `superseded`, `expired`. Lifecycle is append-only ledger events (`QUEUE_*`).

### Channel classes (Addendum A)

| Class | Channels | Surfacing |
|---|---|---|
| **DEMANDING** | voice readout (Vox) | exclusive **global presentation lease** — at most one item surfaced anywhere at a time; serial operator attention |
| **AMBIENT/VISUAL** | omo-pulse attention cards, glasses TLDR | non-exclusive **dwell carousel**; may coexist with a demanding surface. Pacing config: `min_dwell_s`, `max_queue_depth`, `batch_after_idle_s` (tuned from live telemetry, not fixed now) |

Cross-channel rule: if an item is currently visible on an ambient channel, the demanding channel receives that fact in its surfacing context and goes **deictic** ("the card you see") instead of re-reading.

### OC Beacon read transport

OC Beacon is an **AMBIENT/VISUAL, read-only** consumer. It uses the app's existing authenticated OpenCode connection and the OpenCode file-read API to read the workstation's `~/.local/state/opencode-supervisor/status.json`, `queue.json`, and `ledger.jsonl`. The home directory comes from the OpenCode path endpoint; no supervisor listener, daemon, port, or credential is added to the app.

For native decision cards, every new `TICK_DECIDED` ledger payload includes `root` alongside `decision`, `sessionID`, and `messageID`. Existing ledger rows may omit `root`; consumers display an unknown-project fallback for those historical rows. The surface does not acquire presentation leases or write queue lifecycle events.

#### OC Beacon answer capture — reply ingress (Amendment 2026-09-25)

Defines how a native-app answer (tap on a choice card, or a typed reply) becomes a
correlated `ReplyEvent` (`reply_<id>`) the live reply-router consumes. Design constraint:
OC Beacon keeps its read-transport posture — **no new supervisor listener, daemon, port, or
credential in the app**. The ingress therefore reuses the app's existing authenticated
OpenCode connection, in the write direction, via the same session API the supervisor's
console channel already polls.

**Transport: per-root reply-inbox session.** OC Beacon sends each answer as one top-level
`user` message (promptAsync) into a dedicated inbox session per target root, titled
`[Beacon replies] <basename(root)>` (created on first reply if absent; the title prefix MUST
NOT be `[Supervisor]`, which the supervisor excludes as its own chatter). The supervisor
extends its existing `pollReplies` watermark pattern to observe inbox-session user turns —
the same mechanism it uses for console replies — through a `BeaconChannel` (channel class
AMBIENT/VISUAL per Addendum A; presents nothing, collects replies only). Inbox sessions are
excluded from ordinary supervision, exactly like `[Supervisor]` console sessions.

**Message shape.** One reply per message, either:

1. *Envelope* (preferred; single JSON object as the whole message text):

```jsonc
{ "v": 1,
  "clientMessageID": "<uuidv7>",          // client-generated, used for dedup
  "kind": "text|choice|speech",           // ReplyInput kinds per the queue spec §5
  "text": "use Qdrant",                    // text / transcript; for choice: omit, use index
  "index": 1,                              // choice only, 0-based into the card's options
  "contextTag": "pres_…",                 // optional, from the surfaced presentation
  "explicitItemID": "att_…" }              // optional, when the card names the item
```

2. *Plain-text fallback* (no envelope): `Q<n>:`-prefixed answer, bare answer, or disposition
   keyword (SKIP / HOLD / DND) — parsed by the same normalizer as console replies.

**Correlation with the queue item.** Resolution order matches the queue spec §5:
`explicitItemID` wins; then `contextTag` if it maps to the currently surfaced presentation;
then the `Q<n>` alias (resolved through the supervisor's per-root alias table in `consoles.json`);
then the standard rules (a bare answer correlates to the single globally surfaced item;
otherwise `ambiguous` — never guessed, `QUEUE_REPLY_AMBIGUOUS` recorded, the app is asked to
re-present with `Q<n>:` or a numbered choice). Ledger events are unchanged
(`QUEUE_REPLY_RECEIVED` / `QUEUE_REPLY_AMBIGUOUS` with `channelID: "beacon"`).

**Auth.** Inherited from the app's existing OpenCode server connection — the same credential
used for the file-read transport. The supervisor accepts replies only from its designated
inbox sessions (matched by the title convention above) and ignores any other session content.
Spoken replies are out of scope for this ingress (they ride the Vox channel); the envelope's
`speech` kind exists so a future transcribe-then-send path needs no schema change.

**Idempotency and dedup.** Delivery is at-least-once: the client may retransmit after a
timeout using the SAME `clientMessageID`. The supervisor records processed `clientMessageID`s
and drops duplicates; the watermark on the inbox session prevents replay of already-observed
messages; and the reply-router's transitions are idempotent by construction (transition key
`(itemID, itemVersion, fromState, eventID)`; a duplicate reply-event key returns the prior
route result per the queue spec §7/§10). Late replies to terminal items are recorded, never
re-routed.

Implementation status (updated 2026-09-26): the OC Beacon send path is SHIPPED (oc-beacon
commit `0ab9780c` — per-root reply-inbox sessions over the app's existing OpenCode
connection). The supervisor-side `BeaconChannel` is implemented in ez-omo-config
(`supervisor/src/beacon.ts` + `supervisor/test/beacon-channel.test.ts`): inbox discovery by
title convention, watermark polling, v1-envelope parsing with `clientMessageID` dedup,
correlation order as specified, routing through the shared reply-router with
`channelID: "beacon"`. Runtime observation on a live beacon reply is still pending
(status: repo_implemented + tests_passed). The contract shape above remains binding.

### Vox as a consumer (never the queue owner)

- `surface()` maps an item to a Seam 2 `show` frame + `contextTag`; `collectReply()` converts speech/choices/confirmations into **correlated reply events** (`ReplyEvent`, `reply_<id>`) — never direct writes into worker sessions.
- **Vox defer-as-request**: Vox may defer while speaking, mid-dialog, or when the operator is away. Deferral releases the lease, sets `notBefore`, and records `CHANNEL_DEFERRED` — it is a **scheduling request, never a retire**; the item stays queued and keeps aging.
- Code-affecting spoken answers still pass Vox's existing `propose_mutation` confirmation gate.

#### Write-path rule — replies are queue events, never console writes (Amendment 2026-09-25)

Any consumer that speaks on the operator's behalf — Vox (`prompt_supervisor` tool today),
OC Beacon, omo-pulse — MUST deliver an operator reply as a **correlated queue reply event**
(`ReplyEvent`, routed by the reply-router) and MUST NOT write free-form text into a
`[Supervisor]` console session or a worker session. Consumers are reply *sources*, not write
paths: they submit a reply through the channel ingress defined for their class (Vox:
`collectReply()` per the queue spec §8; OC Beacon: the reply-inbox transport above) and the
supervisor alone decides correlation, revalidation, and propagation. Text that correlates to
nothing is `QUEUE_REPLY_AMBIGUOUS` — recorded, never written anywhere, never guessed.
Direct `promptAsync` into console/worker sessions is reserved to the supervisor service
(single writer) and to the supervisor's own gated propagation path. Design note for the
voice-bridge gate: [docs/prompt-supervisor-write-path-guardrail.md](prompt-supervisor-write-path-guardrail.md).

### Dispositions

- **SKIP** = next (snooze, `notBefore`); **HOLD** = freeze dwell on this channel; **DND** = global pause, aging continues, APPROVAL items never auto-resolve.
- Ambiguous replies correlate to nothing: record `QUEUE_REPLY_AMBIGUOUS`, request `Q<n>:` or a numbered choice — no guessing, no mutation.

#### Attention projection (consumption contract)

The stable surface every consumer reads (OC Beacon today; omo-pulse attention view and Vox
tomorrow) is the supervisor's state directory, in this priority order:

1. **`queue.json`** — open attention items, each an `AttentionQueueItem` (`schemaVersion: 1`)
   with the exact schema of the working spec (§2 of
   `.local-state/attention-queue-contract.md`, mirrored in
   `supervisor/src/queue.ts`): id, decisionKey, actionClass, escalationKind, question,
   rationale, citations, target {root, sessionID, sessionTitle}, priority inputs, premises,
   lifecycle (append-only; current state = last event).
2. **`status.json`** — operational telemetry: `modes` per root, `rootHealth` per root
   (ok/failing + consecutive failures), `errorsSinceStart`/`errorsLastHour`/`errorsLastHourPeak`,
   `collect` telemetry, `queueDepths`.
3. **`ledger.jsonl`** — append-only event stream (`QUEUE_ITEM_PROPOSED/REVALIDATED/SURFACED/
   RESOLVED`, `QUEUE_REPLY_RECEIVED/AMBIGUOUS`, `QUEUE_PROPAGATION_DELIVERED/PROPOSED`,
   `INTERVENTION_SENT`, `TICK_DECIDED`, `TICK_SKIPPED`) for consumers that want history
   rather than snapshot.

Versioning: `schemaVersion` on items; v1 changes are ADDITIVE ONLY (consumers tolerate
unknown fields); a breaking change ships as `schemaVersion: 2` with a dual-write window.
Consumers must never write these files (single writer: the supervisor service).

**Live-card retraction (2026-09-23):** the three-file priority order above is RETAINED for
diagnostics and history only. For **live operator-facing cards** it is RETRACTED — the binding
source is the [`operator-view.json` read model](#operator-read-model-operatorviewjson--binding-for-live-operator-facing-cards)
below; consumers MUST NOT independently join these files into live card state.

**Supervisor ingress note** (internal, no seam change): the supervisor's own observation
ingress is HTTP polling because project-scoped instance SSE is broken (see patch
`opencode--sse-directory-filter-removal`). The server-level `/global/event` route — being
adopted by omo-pulse's SSE-realtime plan — is unfiltered and is the candidate event-driven
ingress for a future supervisor version, with client-side filtering.

Cross-repo impact: none for the console MVP (all inside the supervisor service); the omo-pulse attention view and the Vox queue-consumer transport are the future cross-repo pieces and land in this doc first when defined — the schema above is that definition.

### Operator read model (`operator-view.json`) — binding for live operator-facing cards

Amendment 2026-09-23 (design source of truth: `.omo/notes/orca-transition/40-oracle-design.md` §5; that
design body wins on any conflict). **The three-file independent read above is RETRACTED for live
operator-facing cards**: consumers MUST NOT join `status.json`, `queue.json`, or a ledger tail into
live card state. The single live-card source is one versioned atomic read model published by the
supervisor. This section is binding BEFORE any consumer exists; supervisor implementation (plan
orca-transition Task 2) and Orca/omo-pulse consumers (Tasks 3, 12) implement to this text exactly.

**File**: `operator-view.json` in the supervisor state directory, alongside the files above.

#### Publication (supervisor obligations)

- **(a) Content.** The file MUST contain `generation`, `lastSeq`, `producedAt`, and a bounded set of
  active queue cards with decision/premise summaries, computed from **ONE coherent ledger prefix** —
  the publish operation captures a single state/seq snapshot taken after ledger append AND queue
  derivation. The supervisor MUST NEVER publish a `lastSeq` beyond the data incorporated in the
  cards.
- **(b) Atomicity and monotonicity.** Publication MUST be single-image atomic: write a temp file in
  the same directory, then rename over `operator-view.json`. `(generation, lastSeq)` MUST be
  strictly monotonically increasing across publications (lexicographic: `generation` first, then
  `lastSeq`).
- **(d) Heartbeat.** The supervisor MUST republish `operator-view.json` at most every **15 seconds**
  even when no ledger change occurred, so `producedAt` staleness measures supervisor liveness
  rather than a quiet queue.
- **(e) Ledger tail is diagnostic-only.** `ledger.jsonl` entries at `seq <= lastSeq` MAY be used for
  diagnostic history, but MUST NEVER be joined to an independently newer `status.json`/
  `queue.json` for live cards. The old independent-join plan is **RETRACTED**.
- **(f) Probe/throwaway filter.** Sessions classified as autonomous probe/throwaway traffic (the
  omo-focus "PROBE-OK" class) MUST be excluded at the read model — from Needs You cards, rail
  attention marking, and jump targets. The supervisor's test suite MUST include a probe-noise test
  case: a probe burst must not surface or displace any card.

#### Reader obligations (c)

- Readers MUST validate the schema before use, poll at most every **5 seconds**, and after receipt
  recheck freshness with a **monotonic timer** (never an extended wall-clock read).
- Stale = `producedAt` older than **30 seconds** at receipt, or more than **5 seconds** in the
  future. Readers MUST freeze (grey existing cards, disable their jump actions, label
  "**Supervisor state stale**") within **5 seconds** after the 30-second budget expires.
- The same freeze/grey + disabled-jump + stale-label treatment MUST apply on: a `(generation, lastSeq)`
  gap/regression, invalid schema, older `generation`, or supervisor not running.
- Readers MUST NEVER render a partly joined queue and MUST NEVER convert a stale card to Idle.
- Readers MUST reread on rename (atomic replace invalidates any cached image) and refresh
  periodically.
- A wall-clock jump beyond **±5 seconds** (backward or forward) MUST force a fresh read rather than
  extending validity of the current image.

Amendment 2026-09-25 (additive, `schemaVersion` stays 1): operator-view cards additionally carry optional
`escalationKind` (`"DECISION"|"INFORMATION"|"APPROVAL"`, absent = non-escalation), `actionClass` (the queue
Action vocabulary: ACCEPT|ABSTAIN|CONTINUE|STEER|REFORMULATE|ESCALATE), and `root` (absolute project root
path, enabling consumers' correlated reply targeting) as additive card fields. Consumers MUST tolerate their
absence (pre-amendment publisher images remain valid). The APPROVAL/DECISION push-filter decision and the
Beacon reply funnel reference these fields; `escalationKind` is the filter key — absence or an unknown value
fails toward exclusion (fail-safe silence).

#### Required test cases

29/31-second ages; +6-second future `producedAt`; restart with an old snapshot on disk; missing
updates; clock jumps under a fake clock; a 10-minute quiet period (no escalations → cards remain
live, never grey — gates the panel); and the probe-noise burst case above.


### Worker-prompt lifecycle and Orca authority boundary (Amendment 2026-09-28)

Source: factory buy-vs-make tournament rounds 1–2 (2026-09-27/28),
`.sisyphus/debates/factory-buy-vs-make-20260927/` in the factory repo; ADOPTED verdicts both rounds.

1. **Reply-router scope.** The supervisor reply-router is the OPERATOR ingress: it correlates
   operator replies (Vox, Beacon, console) to attention-queue events. It does not own
   worker-session prompts. The Factory owns the worker-prompt lifecycle:
   prompt persisted → wake durably scheduled → response correlated → premise revalidated,
   including defer and crash cases. A defer retries the wake only while the prompt remains current.
   No second prompt owner is introduced.

2. **Orca orchestration authority boundary.** Orca's orchestration subsystem (Runs, Dispatches,
   coordinator inboxes, gates) is agent-local convenience. Factory work MUST enter only through
   the Factory-owned queue and PostgreSQL admission. A conformance test MUST attempt to originate
   Factory work through Orca orchestration and confirm it cannot bypass queue entry, admission,
   or escalation. If the boundary cannot be enforced and tested, orchestration is disabled in
   Factory contexts (not fork-wide).

3. **Attention vocabulary unchanged.** `DEMANDING`/`AMBIENT`, `escalationKind`, `priority`, and
   the stale-freeze rules remain the only authority/notification dimensions. The gascity-style
   actionable/watch/unavailable taxonomy was considered and rejected (no demonstrated decision
   benefit; drift risk across five surfaces). Unavailable-host presentation derives from the
   existing stale-freeze behavior — readers already must not render stale state as healthy.
