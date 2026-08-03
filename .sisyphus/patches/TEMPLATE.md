---
patch_id: ""          # unique slug: {dep}--{short-description}
dependency: ""        # package/tool name (e.g., "oh-my-openagent")
target_file: ""       # path to patched file relative to dep root (e.g., "src/hooks/sisyphus-junior-notepad/constants.ts")
target_install_path: "" # absolute path where dep is installed. For opencode binary patches, use the live binary path (e.g., "/home/ezotoff/.opencode/bin/opencode") — the verifier resolves opencode/opencode-dcp dependencies to this path automatically.
source_repo: ""       # OPTIONAL. For binary patches built from a local source checkout (e.g., "/home/ezotoff/src/opencode"). Documents where to reapply; not used by the verifier.
status: "active"      # active | upstreamed | deprecated
applied_date: ""      # ISO 8601 date
dep_version: ""       # LAST VERSION WHERE RUNTIME EFFECTIVENESS WAS VERIFIED. Do NOT bump just because the patch string is present in a newer binary — that is a pattern-presence claim, not an effectiveness claim.
runtime_effective: true # REQUIRED for monkey-patches / ref-callback patches (overrides an internal method, attaches a ref, patches a renderable). Set true ONLY after observing the patched behaviour on the real surface. Set false when the patch string is present but the feature regressed.
upstream_issue: ""    # URL to upstream issue/PR tracking the fix, or "none"
verification_pattern: "" # grep-compatible regex. CAVEAT: Bun minification preserves JS property keys and string literals, so a property-key pattern reports a false-positive APPLIED even when the code is unreachable. Prefer a pattern that disappears if the code path is dead; otherwise require a ## Runtime Verification section.
surfaces: []           # REQUIRED for rendering patches: list of cli-run | tui-interactive | server-api. Add this field when target_file is in a rendering directory (cli/cmd/run/, tui/src/routes/, etc.) or the patch overrides a renderable method.
---

# {Title}

## Problem
What was broken and why a patch was needed.

## Patch Description
What was changed, with before/after summary (no large diffs).

## Verification
How to check if this patch is still applied. Include the exact grep command.
Label this section "Pattern (necessary, NOT sufficient)" for binary patches — pattern-grep confirms the string is embedded but CANNOT confirm runtime effectiveness.

## Runtime Verification
REQUIRED for rendering patches and any patch with `runtime_effective` flag OR a minification-survivor `verification_pattern` (JS property key, string literal).
Concrete surface-exercise steps: what prompt to send, what to observe, what constitutes the regression signal. Example:
  1. Start the surface (e.g., `opencode` for tui-interactive, `opencode run` for cli-run).
  2. Trigger the patched behaviour (e.g., send a prompt that causes a `[label](file:///abs/path)` markdown link to render).
  3. Expected vs regression signal described in plain language.
  4. If regression signal observed → set runtime_effective: false and add a ## Current Runtime Status section; do NOT bump dep_version.

## Reapply Instructions
Step-by-step instructions to reapply this patch if lost after an update.
For monkey-patches / ref-callback patches, the FIRST step MUST be: "Identify the ACTIVE rendering hook point in the TARGET version — do NOT blindly re-edit the old hook, which may no longer be invoked on the active render path."

## Durable Alternative
What would make this patch unnecessary (plugin, hook, config, upstream fix).
Status: {pursued | not-yet-pursued | blocked-by-upstream | not-applicable}
