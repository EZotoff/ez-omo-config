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
| **omo-pulse** | `~/AI_projects/ez-omo-dash/` | Visual supervisor surface: attention queue, recent projects, session cards, remote UI (`?remote=1`), desktop deep-links | dev `:4300/:4301`, prod `:4300` |
| **ez-omo-config** | `~/ez-omo-config/` | Contract home (this doc), config store, design artifacts, docs sync | — |
| **OC Beacon fork** | separate repo (not started) | Future native front-end implementing the same contract; Phase-2+, after walking validation | — |

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
2. **Android (walking test)**: same web app in Chrome; responsive + push-to-talk are the gaps
   to close. Record fallback events per the proposal's §Prototype Validation.
3. **Peripheral decision**: only after (2); the contract's interaction concepts
   (PROJECT/SESSION/VIEW/SELECTION/VOICE/ACTION/SHOW/ATTENTION) stay stable across devices.

## Pending cross-repo work ledger

| Item | Repo | Status |
|---|---|---|
| Escalation `confidence ≥ 0.7` filter in ledger-tailer | voice-bridge | **done** — `ESCALATION_CONFIDENCE_THRESHOLD = 0.7` gate in [`src/pipeline/interrupts.ts:23`](file:///home/ezotoff/AI_projects/voice-bridge/src/pipeline/interrupts.ts) (TICK_DECIDED + ESCALATE + confidence ≥ 0.7, per final-design.md Amendment 2 §A) |
| `prompt_supervisor` write-path guardrail | this repo (design doc) | **REQUIRED, not done** — current implementation ([`src/pipeline/tools/prompt-supervisor.ts:20-46`](file:///home/ezotoff/AI_projects/voice-bridge/src/pipeline/tools/prompt-supervisor.ts)) is UNGATED: it writes into a supervisor console session directly via `promptAsync` (creates the `[Supervisor]` console session if absent). Future gate: replies become correlated queue events routed by the reply-router (Seam 4), not free-form console writes |
| Voice widget + context feed in remote UI | omo-pulse | not started |
| Show-view renderer (Seam 2 frames) | omo-pulse | not started |
| Real-voice dogfood → MANIFEST evidence upgrade | this repo | blocked on (row above) |

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

### Vox as a consumer (never the queue owner)

- `surface()` maps an item to a Seam 2 `show` frame + `contextTag`; `collectReply()` converts speech/choices/confirmations into **correlated reply events** (`ReplyEvent`, `reply_<id>`) — never direct writes into worker sessions.
- **Vox defer-as-request**: Vox may defer while speaking, mid-dialog, or when the operator is away. Deferral releases the lease, sets `notBefore`, and records `CHANNEL_DEFERRED` — it is a **scheduling request, never a retire**; the item stays queued and keeps aging.
- Code-affecting spoken answers still pass Vox's existing `propose_mutation` confirmation gate.

### Dispositions

- **SKIP** = next (snooze, `notBefore`); **HOLD** = freeze dwell on this channel; **DND** = global pause, aging continues, APPROVAL items never auto-resolve.
- Ambiguous replies correlate to nothing: record `QUEUE_REPLY_AMBIGUOUS`, request `Q<n>:` or a numbered choice — no guessing, no mutation.

Cross-repo impact: none for the console MVP (all inside the supervisor service); the omo-pulse attention view and the Vox queue-consumer transport are the future cross-repo pieces and land in this doc first when defined.
