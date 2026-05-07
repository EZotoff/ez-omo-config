# Non-Wisdom Observability

This page links to per-system observability documentation for the four non-Wisdom systems in the OMO ecosystem. For Wisdom observability, see [docs/wisdom.md](wisdom.md).

## Systems

### Aspect Dynamics

- **Repo docs**: [configs/opencode/aspect-dynamics/README.md](../configs/opencode/aspect-dynamics/README.md) (if present), [configs/opencode/README.md](../configs/opencode/README.md)
- **Implementation**: `configs/opencode/aspect-dynamics.mjs`, `configs/opencode/aspect-dynamics/logging.mjs`
- **Tests**: `tests/test_aspect_dynamics_runtime.sh`
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — Aspect Dynamics

### Control Plane

- **External repo**: `/home/ezotoff/AI_projects/omo-control-plane`
- **Repo docs**: `docs/observability.md` (in the Control Plane repo)
- **Implementation**: `src/server/api.ts`
- **Tests**: `bun test` (156 tests)
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — Control Plane

### Decision Extractor

- **External repo**: `/home/ezotoff/omo-hub/projects/decision-extractor`
- **Implementation**: `src/cli.ts`, `src/schema/run-summary.ts`
- **Tests**: `bun test` (239 tests)
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — Decision Extractor

### DCP Bounded-Memory

- **Repo docs**: [README.md](../README.md) (DCP Observability section), [docs/configs.md](configs.md)
- **Patch docs**: `.sisyphus/patches/opencode-dcp--bounded-range-archive-mode.md`
- **Implementation**: `configs/opencode/dcp.jsonc`
- **Tests**: `tests/test_dcp_bounded_range.sh`, `tests/test_dcp_startup_warning.sh`
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — DCP bounded-memory

## Consolidated Runbook

The end-to-end observability runbook with commands, artifact paths, health checks, failure scenarios, retention policies, and test commands for all four systems is located at:

`.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md`

## Test Evidence

Latest proof command outputs: `.sisyphus/evidence/task-11-final-commands.txt`

## Exclusion Rationale

Wisdom has its own dedicated observability system documented in [docs/wisdom.md](wisdom.md).
