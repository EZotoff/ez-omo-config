---
patch_id: "opencode--plugin-engine-prerelease"
dependency: "opencode"
target_file: "packages/opencode/src/plugin/shared.ts"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-20"
dep_version: "1.18.31"
verification_pattern: "satisfies\\([a-zA-Z_$][a-zA-Z0-9_$]*,[a-zA-Z_$][a-zA-Z0-9_$]*,\\{includePrerelease:!0\\})"
verification_strength: "discriminative"
required_evidence: "provenance"
runtime_effective: false
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

## Durable Alternative
Upstreamable: `anomalyco/opencode` `checkPluginCompatibility` should pass `includePrerelease: true` (or strip the prerelease label from the host version) so nightly/patched/fork builds satisfy plugin engine ranges. Not yet filed.
