# Voice Bridge (Vox)

Vox is a voice agent for the OpenCode/OMO stack: phone push-to-talk → Gemini Live → discussion of escalations and next steps with the user, grounded in real artifacts, with confirmed mutations routed through a dispatcher-enforced pipeline. It is a **sibling service** to the Project Supervisor — it consumes the supervisor's ledger read-side and never writes to it.

The project lives in its own repository at `~/AI_projects/voice-bridge/` (Bun + strict TypeScript). This document is the ez-omo-config-side summary; the project README is the operational source of truth.

## Design summary

- **Topology**: phone browser (push-to-talk, foreground, wake-lock) → WSS → `voice-bridge` (Bun, `127.0.0.1:18220`) → Gemini Live API + `opencode serve :3021` + supervisor ledger file.
- **Model chain**: `gemini-3.8-live-extended-thinking` (primary) → base `gemini-3.8-live` → text-only tier. The ET model does not support `scheduling`, so interrupts are bridge-injected `realtime_input`; the base fallback model supports per-response `scheduling: "INTERRUPT"`.
- **Facts-in-bridge**: an append-only DiscussionLog plus pinned facts that survive compression and are re-injected on every reconnect — the model is never trusted for facts.
- **Authority model**: every state-changing op goes through `propose_mutation` — human-legible disambiguator, explicit yes / explicit no / timeout auto-cancel, hash-chained ledger entry written **before** execution.
- **Push policy**: escalation (`TICK_DECIDED` + `action=ESCALATE` + `confidence ≥ 0.7`), stale permissions (>5 min), and errors on sessions in the current discussion. Everything else is pull-only. Escalations are rare in practice, so Vox is pull-mode-first.
- **Grounding**: Vox calls `read_file_snippet` on the actual artifact before agreeing or disagreeing with a supervisor verdict.

Canonical design and the full adversarial review (Oracle proposal → Mephistopheles critique → revision → synthesis, plus two ground-truth audit amendments): [`.sisyphus/debates/voice-agent/final-design.md`](../.sisyphus/debates/voice-agent/final-design.md).

## Configuration and port

| Item | Value |
|---|---|
| Port | `18220` (registered range `18220–18229` in `~/.sisyphus/ports.json`) |
| Bind | `127.0.0.1` only; the phone reaches it via Tailscale |
| Bridge env | `~/.config/opencode/voice-bridge.env` (mode 600, machine-local, never committed) |
| Server auth | `~/.config/opencode/serve.env` (`OPENCODE_SERVER_*` pass-through) |
| State | `~/.local/state/voice-bridge/` (`discussions/`, `mutations.jsonl`) |
| Supervisor roots | `configs/opencode-supervisor/supervisor.json` (`roots[].path`) |

## Ops runbook

```bash
./deploy/install.sh                                  # install + enable the unit
systemctl --user status voice-bridge.service         # active
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18220/   # 200
bash scripts/loopback-e2e.sh                         # full text-loopback e2e (fixture-scoped)
```

Full runbook, text-loopback debug mode, and dogfood notes: `~/AI_projects/voice-bridge/README.md`.

## Evidence state

- `repo_implemented` — yes
- `tests_passed` — `bun test` 115 pass / 19 files; `bunx tsc --noEmit` exit 0
- `live_file_installed` — `voice-bridge.service` installed and enabled
- `runtime_loaded` — service active on `127.0.0.1:18220`; text-loopback e2e exercises the real Gemini Live relay
- `real_project_behavior_proven` — `bash scripts/loopback-e2e.sh` PASS (8/8 stages)
- **Not verified live**: real-voice dogfood (audio UX quality) — post-plan, user-owned

## Deferred items (with triggers)

| Deferred | Trigger |
|---|---|
| Ephemeral-token browser direct-connect | Proxy latency intolerable in daily use |
| `proactive_audio` self-triggering | After a stable dogfood baseline |
| Native mobile app | Browser push-to-talk proves insufficient |
| Versioned supervisor read-side schema | Second consumer or first schema break |
| Parsing the `[Supervisor]` console session | Only if the ledger file proves insufficient |
