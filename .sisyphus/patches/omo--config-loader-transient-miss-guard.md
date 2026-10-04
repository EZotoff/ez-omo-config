---
patch_id: "omo--config-loader-transient-miss-guard"
dependency: "oh-my-openagent"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
source_repo: ""
status: "active"
applied_date: "2026-10-04"
dep_version: "4.19.2"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "omo-config-loader"
surfaces: ["server-api"]
note: "Live dist patch (Bun bundle, not minified — identifiers survive as-is). verification_pattern is a string literal present 3× — pattern match is necessary but NOT sufficient; see ## Runtime Verification. runtime_effective stays false until a transient-miss boot is OBSERVED to recover (the guard only executes when layer detection returns none); normal boots never exercise it. Root cause incident 2026-10-04 (see wisdom 20261004-215325-ic2c and .omo/plans/event-log-write-amplification.md 'Restart-gate rider')."
---

# OMO config-loader transient-miss guard (global config layer recovery)

## Problem

At some process boots, OMO's layered config discovery returned ZERO config layers although `~/.config/opencode/oh-my-openagent.json` existed and was readable — OMO log showed `Final merged config {}` with zero `Config loaded from` lines. Investigation (2026-10-04, bg_5cf04f8b) narrowed the mechanism to a **transient false `existsSync`** inside `detectPluginConfigFile` (Node's `existsSync` returns `false` on ANY error — ESTALE/EAGAIN/ENOMEM/EACCES — not just ENOENT), which is then **permanently negative-cached** in the module-global `pluginConfigFileDetectionCache` — no retry, no invalidation — freezing the bad state for the process lifetime.

Consequence (2026-10-04 incident, servers :3021/:3030 booted 09:26): agent registry built from OMO **builtin** model chains instead of `oh-my-openagent.json` overrides — `multimodal-looker → openai/gpt-5.6-sol` (not whitelisted → every look_at child session hung to the 120 s poll timeout → `Unexpected error analyzing …: {}`), Hephaestus dropped from the registry, Metis on parked `anthropic/claude-opus-5`, all other agents on wrong models. 476 empty merges logged 2026-10-03T23:48 → 2026-10-04T14Z; the vision-grounding bench campaign lost 42 look_at calls to it.

## Patch Description

In `getUserConfigLayers` (dist bundle region `packages/omo-opencode/src/plugin-config/layered-config-loader.ts`): when a config dir's detection yields `configPath: null`, perform ONE fresh direct `existsSync(<configDir>/oh-my-openagent.json)` bypassing the negative cache:

- **Probe true** (the transient-miss case): set `configPath` to the canonical path and log `[omo-config-loader] recovered config layer after transient detection miss {path, detectedFormat}` — the boot self-heals, overrides apply.
- **Probe false** (genuine absence): log `[omo-config-loader] config layer absent after direct probe (builtin defaults in effect) {configDir}` — the silent-bad-boot case becomes a greppable log line.
- **Probe throws**: log `[omo-config-loader] guard probe error` and leave `configPath` null (no behavior change vs upstream).

Only the null path changes; normal boots (detection succeeds) execute zero additional syscalls. Deliberate scope cut: no TUI toast — the loader has no `ctx.client` in scope and threading one through risks more than it buys; the recovery path needs no human action, the double-miss case is caught by the post-restart verification gate (plan rider), and the log lines are greppable by the integrity-check layer.

## Verification

Label: Pattern (necessary, NOT sufficient).

```bash
grep -c "omo-config-loader" ~/oh-my-openagent-v4.19.2/dist/index.js   # expect 3
```

Backup: `dist/index.js.pre-omo-config-loader-guard-1791146936` (same dir).

## Runtime Verification

1. Boot any surface loading the OMO plugin (e.g. `opencode run --dir <scratch> 'Reply with exactly: OK'`).
2. Normal boot: OMO log shows `Config loaded from /home/…/oh-my-openagent.json {agents…}` and NO `[omo-config-loader]` line — guard inactive, no regression. (Verified 2026-10-04T20:49:09Z, scratch boot OK.)
3. Effectiveness signal (flips `runtime_effective: true` when observed): an OMO log line `[omo-config-loader] recovered config layer after transient detection miss` followed by a NON-empty `Final merged config {agents…}` in the same boot.
4. Regression signal: `Final merged config {}` at boot with zero `Config loaded from` lines AND no `[omo-config-loader]` line → guard dead; set `runtime_effective: false`, reapply.

## Reapply Instructions

1. Locate `function getUserConfigLayers()` in the new dist bundle (it maps `getOpenCodeConfigDirs({binary:"opencode"})` over `detectPluginConfigFile`).
2. Change `const configPath = detected.format !== "none" ? resolveConfigPathAfterLegacyMigration(detected.path) : null;` to `let`, then insert the guard block (direct `existsSync(path.join(configDir, CONFIG_BASENAME))` with try/catch, recover-or-log) between it and `return { configDir, configPath };` — see backup file `dist/index.js.pre-omo-config-loader-guard-1791146936` for the exact pre-patch anchor and this entry's Patch Description for the post shape.
3. Validate with a scratch CLI boot BEFORE restarting any server (config loads, no plugin-load errors).
