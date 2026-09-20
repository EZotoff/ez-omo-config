---
patch_id: "opencode--plugin-engine-prerelease"
dependency: "opencode"
target_file: "packages/opencode/src/plugin/shared.ts"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-20"
dep_version: "1.18.31"
verification_pattern: "satisfies\([a-zA-Z_$][a-zA-Z0-9_$]*,[a-zA-Z_$][a-zA-Z0-9_$]*,\{includePrerelease:!0\}\)"
verification_strength: "discriminative"
required_evidence: "provenance"
runtime_effective: true
surfaces: "server-api"
---

# Plugin engine ranges must match prerelease-suffixed host builds

## Problem
`checkPluginCompatibility` in `packages/opencode/src/plugin/shared.ts` validates each plugin's `engines.opencode` range with `semver.satisfies(opencodeVersion, range)`. The locally patched live binary reports `1.18.31-p1` (the `-p<N>` patch-provenance suffix). Per semver, `-p1` marks the version as a *prerelease* of 1.18.31, and `semver.satisfies` excludes prereleases from range matching unless `includePrerelease: true` is passed. Result: every plugin declaring a plain `>=x.y.z` range was skipped at load with the toast `Plugin <name> skipped: Plugin requires opencode >=… but running 1.18.31-p1`, even though 1.18.31 plainly satisfies the range. First observed with `opencode-kimi-full` (`>=1.4.6`).

## Patch Description
One-line change: pass `{ includePrerelease: true }` to the `semver.satisfies` call in `checkPluginCompatibility`. The provenance suffix is not release maturity; a patched host build at `1.18.31-p<N>` satisfies any range the base `1.18.31` satisfies. Build metadata (`+`) would also work but conflicts with the established `-p<N>` provenance convention consumed by `scripts/parse-opencode-version.sh`, the build compat gate, and the patch lockfile.

## Verification
Source:
```bash
grep -n "includePrerelease" /home/ezotoff/src/opencode/packages/opencode/src/plugin/shared.ts
```
Binary (minification preserves property keys and object-literal argument shape; `includePrerelease` alone is NOT discriminative — the semver package uses it internally, so the pattern pins the 3-arg `satisfies` call):
```bash
grep -cE 'satisfies\([a-zA-Z_$][a-zA-Z0-9_$]*,[a-zA-Z_$][a-zA-Z0-9_$]*,\{includePrerelease:!0\}\)' ~/.opencode/bin/opencode
```

Runtime verification (the real surface): after install + service restart, a TUI boot must NOT emit the `Plugin opencode-kimi-full skipped` toast, and `journalctl --user -u opencode.service` must not record the skip for any plugin that was previously skipped. Baseline pre-fix: toast observed in TUI on 2026-09-20.

## Reapply Instructions
1. In `packages/opencode/src/plugin/shared.ts`, `checkPluginCompatibility`: change `semver.satisfies(opencodeVersion, range)` to `semver.satisfies(opencodeVersion, range, { includePrerelease: true })`.
2. Commit on `update/v1.18.31`, update `config/patch-lockfile.json` (generation + implementation_commits), push the branch to the fork, then build + install via `scripts/build-and-install-opencode.sh build` / `install`.

### Observed 2026-09-20 (v1.18.31-p2 install)
- Pattern matches live binary (exactly 1 hit; minified 3-arg satisfies shape), provenance-verified via receipt e01c2070c550 (generation opencode-1.18.31-patches.2, source_head 3b734b960d pushed to fork).
- A/B syscall trace (strace openat, scratch-dir `opencode run`): p1 backup binary resolves the npm plugin entry (`src/index.ts`) but never imports the module graph (compatibility-stage skip); p2 binary imports the full graph (`src/auth-refresh.ts`, `src/auth-store.ts`, `src/constants.ts`, `src/headers.ts`, `src/oauth.ts` present in p2 trace only). Plugin load confirmed on the real surface. Note: skip events are publish-only (no log, dropped from /event at boot) and file plugins bypass the gate entirely (loader.ts:123), so toast watching and file-plugin probes are NOT valid observations for this gate.

## Durable Alternative
Upstreamable: `anomalyco/opencode` `checkPluginCompatibility` should pass `includePrerelease: true` (or strip the prerelease label from the host version) so nightly/patched/fork builds satisfy plugin engine ranges. Not yet filed.
