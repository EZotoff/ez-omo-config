# Root Cause Synthesis (Phase 2)

## From R1-R5 findings, the systematic root causes are:

### RC1: The Interactive Testing Gap (Fundamental)
The AI agent runs INSIDE the system it's patching. It can edit source, typecheck, build, and install — but it CANNOT restart OpenCode to verify the fix works at runtime (restart kills its own session). This means every binary patch is shipped untested. The session-info bug persisted through 3 "fixes" because each fix was declared complete without runtime verification.

**This is architectural, not procedural.** No amount of better documentation or process fixes this. The verifier cannot be the same process as the thing being verified.

### RC2: Source-Binary Disconnect
Patches exist in source working trees but never get built into binaries. The patch-tracker says "active" but there's no enforcement linking "source has patch" → "binary has patch" → "runtime honors patch." The chain has 3 links and any can break silently.

### RC3: Patch-Tracker is Documentation, Not Enforcement
14 patch docs exist. At least 1 (`opencode--commit-policy-unblock`) claims `active` but is missing from source. Others are partially applied. The patch-tracker skill defines a lifecycle but has no automation to verify or enforce it. An AI can mark a patch "active" without actually applying it — and nothing catches the lie.

### RC4: No Build/CI Infrastructure
No automated build pipeline. Every binary patch requires manual: checkout → edit → typecheck → build → backup → swap → restart. Each step is a failure point. No CI means no regression testing. The AI can't push to a branch and let CI validate.

### RC5: Nested Extension Boundaries
Three layers, each with source patches because the extension mechanism below isn't powerful enough:
- OpenCode: plugin SDK can't cancel commands → source patch needed
- OMO: hook system doesn't cover all cases → source patch needed  
- ez-omo-config: config/skill layer (this one works fine)

### RC6: AI-Agent-as-Maintainer Constraints
The human never works on this. The AI must:
1. Understand the patch (read code, understand Effect-TS, Bun build system)
2. Apply it correctly (edit, handle types)
3. Build it (know the build flags, version env vars)
4. Install it (backup, swap without killing self)
5. Verify it (impossible interactively)

Git operations (merge, rebase, cherry-pick) are MUCH more AI-friendly than patch-doc reapplication because git has structured conflict markers, history, and abort/retry semantics. Patch docs require the AI to re-derive context from prose instructions.

## Key Decision Question
Given these root causes, what is the optimal architecture for managing local modifications to OpenCode and OMO, specifically designed for AI-agent-as-maintainer operation?

## Options Identified from Research
A. Status quo: patch-tracker docs + manual build/install
B. Fork OpenCode: commits replace docs, CI tests, git merge for updates
C. Plugin-first: push everything possible to plugin/hooks, minimize source patches
D. Hybrid: fork only OpenCode (the binary), plugin everything else, automated upstream sync
E. Automated overlay: patch files + CI that builds/verifies, no fork
