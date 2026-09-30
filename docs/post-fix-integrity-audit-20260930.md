# Post-fix integrity audit — 2026-09-30 (~09:10 CEST)

Auditor: Sisyphus orchestrator session (ez-omo-dash), independent re-verification of the
`oa` outage fix delivered by session `ses_f12aa8eebffeJfv2sHk4MUY5fw`
("Troubleshooting broken `oa` sessions (fork #1)", morning report 2026-09-30 08:43 CEST).

All commands run directly by the auditor against the live system (binary `2f18430e…`,
installed 2026-09-30 08:38 CEST). No sub-agents, no mutations.

## 1. Audit results (run 2026-09-30 ~09:05–09:10 CEST)

| Check | Result | Detail |
|---|---|---|
| `verify-live-patches.sh` | **rc=1, AMBER** | binary `2f18430e` provenance-verified (11) + runtime-verified (2); **3 runtime smokes PENDING** on the new binary (`sdk-sse-socket-leak`, `sse-queue-bounded`, `stream-stall-watchdog`); 1 WEAK-MARKER (`opencode--sse-directory-filter-removal`: pattern matched but not in `config/patch-lockfile.json` required set); 3 stale OMO-layer patches; 0 missing-target, 0 version-drift |
| `check-provenance.sh` | **rc=1, HARD FAIL** | `omo-dist: no receipt for sha256 ceb98201a29a93546215bab81dacd98b2d644ed4f137de61e3e0f85d7a7965f1 in ~/.local/share/opencode/builds` — identical to the failure at 14:11Z on 09-29; **still unfixed** |
| `check-live-config-drift.sh` | rc=0 | clean |
| `check-remote-presence.sh` | rc=0 | clean |

**Contradiction with the fix session's morning report**, which claimed "All regression
suites, schema, version-drift, and live-patch verifier pass." The verifier exits 1 right
now. What does hold: binary identity, patch provenance for the new SSE patches, config
drift clean, and the empirical gate numbers were reproduced by an independent probe at
09:05 (loopback ≤1.93 MiB/s watcher samples, RSS ~1.6–1.8 GB, 0 restarts since 08:38,
hermes-workspace NRestarts=0). The core memory/SSE fix looks real; the verification
paperwork around it is not green.

## 2. Alert-suppression chain (safety net was quietly broken pre-outage)

Timeline on 2026-09-29 (CEST journal times):

- ~09:40 — integrity pipeline starts failing (per triage: "failure unchanged and
  escalated 270 min ago" as of 16:11).
- 14:10:58 — `opencode-patch-integrity-check.service` exits 1
  (`smoke FAIL: question-stream-stall-guard` on the then-live binary + the omo-dist
  receipt failure) → `OnFailure=` starts `opencode-integrity-triage.service`.
- 14:11:42 — triage exits 1; logs "failure unchanged and escalated 270 min ago —
  **suppressed duplicate operator notification**".
- 14:13:28 — unexplained restart of `opencode-interactive.service` (see §4).
- 14:21:19 — keeper restart of `:3030` (by design).

Effect: the integrity check fails every 30 min, triage fails after it, and operator
notifications are suppressed as duplicates once a fingerprint has been escalated.
Current state confirms this persists: `~/.local/state/opencode/integrity-triage.json`
(`last_escalation` = 2026-09-29 22:10 CEST, `agent_runs: 0`) and a stale
`patch-integrity.alert` marker from 22:10 Sep 29.

## 3. `@opencode-ai/plugin@1.18.31-p2` unpublished → background installs failing

Since the first `-p2` binary (2026-09-29 23:00 CEST), `opencode.service` logs
`background dependency install failed … No matching version found for
@opencode-ai/plugin@1.18.31-p2` (29 occurrences by 09:55 CEST Sep 30) across project
dirs (ez-omo-dash, accounting, bench worktrees). npm has no `-pN` prerelease for this
package (registry tops at plain releases). WARN-level; OMO still loads via the global
`file://` plugin path, so no observed functional breakage — but it is periodic noise
and fails every project-local plugin install. Options: strip the prerelease suffix when
resolving the SDK package (binary patch + registry entry), or satisfy the pin from a
locally packed tarball.

## 4. Restart-initiator forensics (09-29 outage)

- **14:21:19 — SOLVED: the keeper.** `opencode-daemon-keeper.sh` logged
  ":3030 unreachable but unit active — restarting opencode-interactive.service" at
  14:21:19 (unit runs each minute via timer). Working as designed.
- **14:13:28 — unprovable with available logs.** Ruled out with evidence: any agent
  session (0 matches in the session DB for systemctl/pkill/service-restart commands in
  the window; the bench campaign's systemctl activity was sandboxed gate tests under
  `/tmp/opencode/t3verify`), the keeper (ran 14:13:04–06, no action, wrong timing),
  operator shell history (no manual restarts since Sep 13–14), cron,
  `restart-with-continuation.log` (untouched since Sep 28), and triage (failed 14:11:42
  with no restart action logged). The stop arrived via D-Bus with no journald
  attribution; auditd is inactive. Most plausible: a command from a process that died
  with the server (the 5 unsnapshotted busy sessions' final parts were never persisted).
  **Recommendation:** enable auditd (or log D-Bus caller credentials in the keeper/hooks)
  so restart initiators are attributable next time.

## 5. Recommended actions

1. Generate the missing omo-dist receipt (sha `ceb98201…`) or rebuild the dist with a
   receipt — this closes the standing hard failure that keeps the 30-min integrity unit
   red and triage suppressed.
2. Run the 3 pending runtime smokes on `2f18430e` to close AMBER.
3. Resolve the `sse-directory-filter-removal` weak marker (add to the lockfile required
   set or drop the marker).
4. Clear the stale `patch-integrity.alert` marker / re-arm escalation once green, so
   future failures can actually notify the operator.
5. Decide the `@opencode-ai/plugin` prerelease-pin policy (§3).
6. Enable auditd or equivalent D-Bus-caller logging (§4).

## 6. Provenance of this audit

- Session DB queries (readonly) against `~/.local/share/opencode/opencode.db`
  (`session`/`message`/`part`), windows around 2026-09-29 13:30–15:00Z.
- `journalctl --user` for `opencode-interactive.service`, keeper, checkpoint timer,
  integrity-check/triage units, 2026-09-29 13:50–14:25 CEST.
- Live runs of the four audit scripts (2026-09-30 ~09:05 CEST), outputs quoted above.
- Independent live probes: binary sha, watcher state file, ps/journal since 08:38,
  hermes unit state, npm registry query.
