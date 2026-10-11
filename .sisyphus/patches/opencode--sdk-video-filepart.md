---
patch_id: "opencode--sdk-video-filepart"
dependency: "opencode"
target_file: "node_modules/@ai-sdk/openai-compatible/dist/index.js, node_modules/@ai-sdk/openai-compatible/dist/index.mjs, node_modules/@ai-sdk/openai-compatible/src/chat/convert-to-openai-compatible-chat-messages.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode-video-filepart"
status: "active"
applied_date: "2026-10-11"
dep_version: "1.18.31-p5"
runtime_effective: true
upstream_issue: "none"
verification_pattern: "video file parts with URLs"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: ["server-api"]
---

# @ai-sdk/openai-compatible: serialize video file parts as video_url

## Problem
The vendored `@ai-sdk/openai-compatible@2.0.41` file-part converter handles
image/audio/pdf/text media types and throws
`UnsupportedFunctionalityError('file part media type video/mp4')` for anything
else. OpenCode's own pipeline passes `video/*` file parts through once the model
declares `video` in `modalities.input`, so a video attachment (e.g. `look_at` on
an .mp4 for motion/transition QA) reached the converter and died with "No
response from multimodal-looker agent" at the agent layer. Even the newest SDK
(2.0.56) has no video branch, so a dependency bump cannot fix it.

## Patch Description
Extends the repo's existing bun `patchedDependencies` patch for this package
(which already carried an error-preservation fix) with a `video/` branch
mirroring the image branch: emit
`{ type: "video_url", video_url: { url: "data:<mime>;base64,<payload>" } }`.
Both dist variants are patched — CJS uses the `import_provider_utils` namespace,
ESM uses the direct `convertToBase64` binding (a CJS-shaped insert into the .mjs
throws `import_provider_utils is not defined` at runtime) — plus the TS source.

## Verification
Pattern (necessary, NOT sufficient):
`grep -c 'video file parts with URLs' ~/.opencode/bin/opencode` → 1

## Runtime Verification
1. Video-capable model configured (zai-coding-plan/glm-5.3-flash declares
   `video` in `modalities.input`); a small .mp4 exists.
2. `opencode run` with a prompt calling
   `look_at(file_path=<clip.mp4>, goal='describe the transition/animation')`.
3. Expected: timestamped motion analysis (LOOKER-RESULT). Regression signal:
   `LOOKER-FAIL: Error: No response from multimodal-looker agent` (child-session
   error "file part media type video/mp4 ... not supported", or
   "import_provider_utils is not defined" for a botched .mjs patch).
4. If regression → runtime_effective: false + ## Current Runtime Status; do NOT bump dep_version.
Smoke: `~/.local/share/opencode/smoke-results/a9c5cdfd864c19687cc1c45348e09cc4a78aac5d5c32ebdc4539722882bf17f6.json` (smoke_id
`sdk-video-filepart`, PASS 2026-10-11 — look_at returned a timestamped
cross-fade analysis of the traveller chargen clip on this binary).

## Reapply Instructions
1. Worktree `/home/ezotoff/src/opencode-video-filepart` (branch
   `fix/sdk-video-filepart`, forked from the lockfile canonical aggregate
   branch; commits pushed to the `fork` remote).
2. `bun install`; `bun patch @ai-sdk/openai-compatible@2.0.41`; edit the editable
   copy's dist/index.js + dist/index.mjs + src/chat/convert-to-openai-compatible-chat-messages.ts
   (match each file's own import style!); `bun patch --commit`; `bun install`.
3. Build via `scripts/build-and-install-opencode.sh build` + `install … --force`
   (idle-gate caveat: wisdom 20261011-194128-grbm).

## Durable Alternative
Not-yet-pursued: upstream a `video/` branch to `@ai-sdk/openai-compatible`
(provider-agnostic; video_url is the OpenAI-compatible shape Z.AI already accepts).
