# Patch drift gate audit — 2026-09-22

## Finding

`tests/test_patch_versions.sh` did run through `tests/run_all.sh` auto-discovery, but the v1.18.31 cutover did not contain any verdict that the gate defines as unresolved `VERSION-DRIFT`.

The verifier intentionally changes a version mismatch to `ACKNOWLEDGED-DRIFT` whenever an entry has `runtime_effective: false`. The gate then reads only the aggregate `version_drift` and `acknowledged_drift` counts and explicitly exempts the latter. At cutover, the entries left on older versions (`opencode--bash-lifecycle-group-cleanup`, `opencode--sse-directory-filter-removal`, and `opencode--tui-pinned-session-race`) all had `runtime_effective: false`; the other active OpenCode entries were reconciled to `dep_version: 1.18.31`. The observed pass therefore followed the gate's documented contract rather than bypassing it.

The separate installed-verifier defect made operational output misleading but did not explain this gate result: `test_patch_versions.sh` invokes the repository script directly, so repository discovery was already correct in that path.

## Minimal-fix recommendation

Do not remove the acknowledged-drift exemption: it is the documented escape hatch for known-ineffective patches and changing it would alter patch semantics. If the policy should require stronger evidence, add a dedicated schema rule requiring a non-empty `runtime_effective_note` (or a `## Current Runtime Status` section) whenever `runtime_effective: false`, then update existing entries in one deliberate migration. That is not implemented here because current entries use mixed justification formats and silently redefining their validity would be unsafe.

The small safe repair implemented in this change is orthogonal: canonicalize the installed verifier's symlinked script path so it uses this repository's registry and lockfile, always hash an existing binary even when provenance metadata is missing, and prevent unavailable provenance from reporting GREEN.
