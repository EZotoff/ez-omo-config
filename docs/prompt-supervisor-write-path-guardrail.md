# prompt_supervisor write-path guardrail — design note (2026-09-25)

Status: **DESIGN ONLY — bridge implements later in its own session** (contract-first per the
[portable-supervisor contract](portable-supervisor-contract.md#session-run-discipline)).
Contract anchor: Seam 4, *Write-path rule — replies are queue events, never console writes*
(Amendment 2026-09-25). Pending-work ledger row: `prompt_supervisor write-path guardrail` —
**contract defined, implementation pending**.

## Problem

Current voice-bridge implementation
([`src/pipeline/tools/prompt-supervisor.ts`](file:///home/ezotoff/AI_projects/voice-bridge/src/pipeline/tools/prompt-supervisor.ts))
is **UNGATED against the queue**: with a `Q<n>:`-prefixed `text` argument it already resolves
the alias (via `consoles.json`) and validates the item is open — but it then delivers the
answer by `promptAsync` into the `[Supervisor]` console session directly. Free-form text
(without `Q<n>:`) is written to the console with no correlation attempt at all. That makes the
bridge a second write path into a supervisor-owned surface: it can create the console session,
inject text the router then picks up out-of-band, and race or bypass the reply-router's
correlation → revalidation → route pipeline. It works today only because the router happens to
observe console turns; the contract now forbids that path for consumers.

## Target state

`prompt_supervisor` (renamed or re-scoped: it becomes a **reply source**, not a console
writer) submits the operator's reply as a correlated queue event and never performs a session
write. Concretely:

1. **Submission transport.** The bridge submits via the same ingress defined for OC Beacon
   (contract Amendment 2026-09-25): a per-root reply-inbox session observed by the supervisor.
   Alternative considered: a direct in-process call into the supervisor service — rejected for
   now because the bridge and supervisor are separate processes with no shared transport, and
   the inbox-session transport needs no new daemon/port/credential. If a supervisor HTTP write
   API ever exists, this tool can switch transports without a shape change (the envelope is
   the same).

2. **Envelope.** The tool emits the contract's envelope JSON:
   `{ v: 1, clientMessageID: uuidv7(), kind: "text"|"choice"|"speech", text?, index?,
   contextTag?, explicitItemID? }`. The bridge already resolves `Q<n>` aliases
   (`consoles.json`) and validates open-ness — that logic is reused to fill
   `explicitItemID` when the operator used an alias; otherwise the field is omitted and the
   supervisor's standard correlation rules apply.

3. **No-correlation text is not a write.** Text that resolves to no open item returns a tool
   error to Vox (`"not an open item — use Q<n>: or answer the surfaced question"`), exactly
   like the current alias-validation error path, and writes nothing anywhere. The supervisor
   records `QUEUE_REPLY_AMBIGUOUS` for anything that does reach it uncorrelated — the bridge
   never retries into a session.

4. **Dispositions.** SKIP / HOLD / DND utterances map to the same plain-text disposition
   keywords through the ingress; the router applies them (`applyDisposition`), the bridge does
   not touch queue state.

5. **Code-affecting propagation stays double-gated.** A reply that routes to
   `prompt_session`/`answer_question` propagation is executed by the supervisor's gated
   path; where Vox is the surfacing channel, its existing `propose_mutation` confirmation gate
   still applies before the reply is ever submitted (queue spec §8, Vox channel rules). The
   mutation gate moves from *write time* (today: gate the console write) to *submission time*
   (gate the reply submission) — nothing is written if the operator does not confirm.

6. **Idempotency.** `clientMessageID` is generated once per confirmed reply; on retransmit the
   same ID is reused, and the supervisor's dedup (plus the router's idempotent transitions)
   makes at-least-once delivery safe.

## Migration path

1. Supervisor lands `BeaconChannel`-equivalent inbox observation (shared with the OC Beacon
   ingress — one mechanism, many consumer channels) — supervisor session.
2. Bridge re-points `prompt_supervisor` at the inbox transport, adds envelope emission and the
   no-write error path, drops `proposeSupervisor`/`promptAsync`/console-session creation from
   the tool — bridge session.
3. Regression: no tool path in the bridge may call `promptAsync` on a `[Supervisor]`-prefixed
   session; console session creation is supervisor-only. Add a paired regression test on the
   bridge side (`tests/regressions/` here only if a repo-local contract check applies).

## Non-goals

- No change to the queue item schema, correlation rules, or routing outcomes (all defined in
  the attention-queue spec §5).
- No Vox speech-channel work (separate ledger row: "OC Beacon walking-rung prep / spoken
  replies via Vox").
- No omo-pulse work.
