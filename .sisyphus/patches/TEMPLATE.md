---
patch_id: ""          # unique slug: {dep}--{short-description}
dependency: ""        # package/tool name (e.g., "oh-my-openagent")
target_file: ""       # path to patched file relative to dep root (e.g., "src/hooks/sisyphus-junior-notepad/constants.ts")
target_install_path: "" # absolute path where dep is installed (e.g., "/home/ezotoff/oh-my-openagent")
status: "active"      # active | upstreamed | deprecated
applied_date: ""      # ISO 8601 date
dep_version: ""       # version or range when patch was applied (e.g., "0.5.2", ">=0.5.0")
upstream_issue: ""    # URL to upstream issue/PR tracking the fix, or "none"
verification_pattern: "" # grep-compatible regex to verify patch is applied
---

# {Title}

## Problem
What was broken and why a patch was needed.

## Patch Description
What was changed, with before/after summary (no large diffs).

## Verification
How to check if this patch is still applied. Include the exact grep command.

## Reapply Instructions
Step-by-step instructions to reapply this patch if lost after an update.

## Durable Alternative
What would make this patch unnecessary (plugin, hook, config, upstream fix).
Status: {pursued | not-yet-pursued | blocked-by-upstream | not-applicable}
