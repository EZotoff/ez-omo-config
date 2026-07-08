# R3 Case Study: `/session-info` command-hook cancellation failure

Date: 2026-06-28

Scope: extract systematic root causes from the `/session-info` failure case. This document intentionally stops at case analysis and does not propose architecture changes.

## Sources read

- `/home/ezotoff/ez-omo-config/.sisyphus/patches/opencode--command-hook-cancellation.md`
- `/home/ezotoff/ez-omo-config/AGENTS.md`, sections `Live Deployment Claim Discipline` and `Patching OpenCode Binary`
- `/home/ezotoff/ez-omo-config/skills/patch-opencode/SKILL.md`
- `/home/ezotoff/ez-omo-config/skills/update-to-latest/SKILL.md`
- Additional nearby context: `/home/ezotoff/ez-omo-config/skills/patch-tracker/SKILL.md`
- Wisdom searches for: `opencode patching`, `binary patching`, `session-info`, `update pain`, `patch failures`; plus follow-up searches for `OpenCode binary` and `output.cancelled`.

## Relevant source facts

### Patch registry entry

The patch entry `opencode--command-hook-cancellation` declares:

- `status: "active"`
- `applied_date: "2026-06-26"`
- `dep_version: "1.17.9-local"`
- `target_install_path: "/home/ezotoff/src/opencode"`
- `target_file`: three source files under the OpenCode source tree.

Its problem statement says OpenCode runs `command.execute.before` hooks and then unconditionally calls `prompt()`. Local commands such as `/session-info`, `/session-id`, and `/vscode` need to perform a side effect and stop. Clearing `output.parts` avoids throwing but still starts the agent.

Its patch description says the fix adds `cancelled: boolean` to the hook output type, passes `{ parts, cancelled: false }` to plugins, returns before `prompt()` when `output.cancelled` is true, and returns an empty HTTP response for cancelled command results.

The verification section is mixed: it contains a source-tree grep for the three expected source patterns, and a later runtime/build verification block that includes the test command, typecheck, and build command. The frontmatter `verification_pattern` only encodes source/string presence, not installed-binary presence or live runtime behavior.

The reapply instructions correctly include build, backup, binary replacement, and restart steps. The failure was not that the necessary steps were absent from the document; it was that registry state could say `active` even when those steps had not actually been completed against the live binary.

### Live deployment claim discipline

`AGENTS.md` defines six evidence states:

- `repo_implemented`: code exists in the repository and is tracked by git.
- `tests_passed`: automated tests for the change pass.
- `live_file_installed`: the file is present at its live target path.
- `active_config_registered`: live config references/registers the artifact.
- `runtime_loaded`: the runtime has actually loaded or invoked it.
- `real_project_behavior_proven`: the artifact's effect has been observed in a real project scenario with evidence.

It also says repo/test evidence must not be described as installed, active, working, deployed, or runtime verified. It requires `Not verified live: [missing state]` when live/runtime evidence is missing.

This discipline existed, but the patch registry and surrounding docs still allowed a single overloaded word, `active`, to stand in for several distinct states.

### OpenCode binary patching procedure

`AGENTS.md` and `skills/patch-opencode/SKILL.md` both require the full source-to-live chain:

1. Identify the live binary version.
2. Check out the exact matching release tag.
3. Apply the minimal source fix.
4. Build with `OPENCODE_VERSION=<live version>` and `--single --skip-install --skip-embed-web-ui`.
5. Verify the built binary version and patch presence.
6. Back up the live binary.
7. Stop both service surfaces and inspect remaining `opencode serve` processes.
8. Copy the built binary to `~/.opencode/bin/opencode`.
9. Restart services.
10. Test the real surface.

The dedicated skill includes common pitfalls that match this case class: source/build/version drift, failure to install the built binary, failure to restart, and false confidence from partial verification.

### Update procedure

`skills/update-to-latest/SKILL.md` requires active patch review, patch reapply/deprecation classification, patch tracker updates, regression verification, rollback policy, and final evidence-state reporting. It explicitly says not to claim runtime success without evidence.

The update pipeline is procedure-heavy and evidence-aware, but it remains a guided instruction set. It does not itself make `active` patch metadata impossible when the live binary lacks the patch.

### Patch tracker procedure

`skills/patch-tracker/SKILL.md` says an active patch is verified by resolving `{target_install_path}/{target_file}` and grepping for `verification_pattern`. For this patch, `target_install_path` is the OpenCode source clone, not the installed binary path. Therefore the tracker can report an active/applied patch when the source tree contains the strings, even if no built binary was installed and no running process loaded it.

The tracker even allows creating an entry when grep finds no match, as long as the discrepancy is noted. It tracks patch debt and reapply instructions; it is not a live deployment verifier.

## Wisdom results

Searches for `opencode patching`, `binary patching`, `update pain`, and `patch failures` returned no entries.

Searches for `session-info` and `output.cancelled` returned the same candidate Wisdom entry:

> The `/session-info` fix required a 3-file OpenCode source patch to honor `output.cancelled=true`. The patch existed in `~/src/opencode` working tree but was never built or installed; the live binary was SSE-fix-only. After building with `OPENCODE_VERSION=1.17.9` and swapping the binary, the fix takes effect on next OpenCode restart. Regression test `test_session_clipboard_plugins.sh` validates all three source-side changes.

Search for `OpenCode binary` returned a candidate Wisdom entry about OpenCode binary patch builds requiring explicit `OPENCODE_VERSION=<live>` because the build script otherwise derives `0.0.0-fix/...` from a fix branch name. That entry reinforces that source patching and binary packaging are separate operational states.

Both Wisdom entries are `authority: candidate`, not verified/published. They are still directly aligned with the user-provided case context.

## Chain of failures

### 1. The AI applied the source patch but never built/installed it

The proximate failure was an incomplete transition from source-state to runtime-state. The source patch landed in `~/src/opencode`, but the live executable at `~/.opencode/bin/opencode` was not rebuilt/replaced, and the running OpenCode process therefore had no `output.cancelled` support.

The deeper pattern is that the work unit was implicitly treated as "patch the source" instead of "change behavior of the live OpenCode command pipeline." In this repo, many config changes are live by symlink, so editing the store path often is the deployment action. OpenCode binary patches are different: the source clone is not the executable runtime. They require build, binary swap, service restart, and real-surface verification.

The written procedures already contained those later steps. The failure shows that procedure text alone did not bind the agent's completion criteria. A source diff plus a patch registry entry was allowed to feel complete even though the user-visible behavior depended on a compiled binary that had not changed.

### 2. The patch tracker said `active` when the patch was not active in the live system

The patch tracker used `active` as a registry lifecycle value, not as an evidence-state value. In the tracker schema, `status: active` means the patch entry is a current patch obligation rather than deprecated/upstreamed. It does not prove:

- the source patch was committed,
- the package was rebuilt,
- the live binary was replaced,
- OpenCode restarted,
- the running process loaded the changed code,
- `/session-info` stopped before agent dispatch.

For this specific patch, the verification target was the source tree under `/home/ezotoff/src/opencode`, and the verification pattern was a grep for source strings. That can prove source presence only. It cannot distinguish "source modified, live binary old" from "source modified, binary rebuilt and installed."

The word `active` therefore became a false bridge between two incompatible systems:

- patch-tracker lifecycle: active patch debt exists;
- live-deployment evidence: active behavior exists in the runtime.

The patch document further amplified the confusion by saying `dep_version: "1.17.9-local"`, which looks like a runtime version label but does not by itself prove that `~/.opencode/bin/opencode` contains the local build.

### 3. The AI could not verify the fix interactively

The broken behavior lived inside the invoking OpenCode command pipeline. Verifying it required observing whether `/session-info` ended the command path before `prompt()` and without launching an agent. That is harder than verifying a normal CLI or library change for several reasons:

- The code being patched was the same tool/runtime hosting the agent session.
- Loading the fix required replacing the live binary and restarting OpenCode services, which can disrupt the current interactive surface.
- A non-interactive source grep cannot prove command-pipeline cancellation in a running TUI/API session.
- Plugin-side evidence was insufficient: the `/session-info` plugin could set `output.cancelled = true`, but an old binary would ignore that field and continue to `prompt()`.
- The visible symptom was partly negative: the proof is that no agent launches. Negative command-pipeline behavior needs explicit runtime instrumentation or a real interactive transcript, not just "no error" output.
- The HTTP handler change returns an empty response for cancelled commands, so a superficial HTTP/API check could also look like absence of data unless it is paired with evidence that no downstream prompt/agent dispatch occurred.

The result was a verification gap around the real surface. The agent could verify source shape, and maybe plugin registration, but not the actual cancellation semantics in the invoking session without crossing an operational boundary.

### 4. Evidence-state claims vs reality

The case involved several claims or implied claims that exceeded the available evidence.

| Claim / implied claim | Reality in this case | Correct evidence state |
|---|---|---|
| Patch doc `status: active` | The patch was a current registry entry; it did not prove live behavior. | Patch lifecycle only; not a live deployment state. |
| Patch doc `applied_date: 2026-06-26` | At most indicated a source-side application date; the live binary did not contain the behavior. | Source presence, not `live_file_installed`, `runtime_loaded`, or `real_project_behavior_proven`. |
| README-style claim that the patch was active on the local OpenCode binary | User context says the live binary had no `output.cancelled` support. | Claim exceeded reality. |
| Source grep for `cancelled` patterns | Proved source strings existed in three files, if run successfully. | Source-shape evidence only. |
| Tests/typecheck/build commands listed in patch doc | Commands were listed as verification steps; listing is not evidence that they ran or that their output was installed. | No `tests_passed` or `live_file_installed` without captured outputs. |
| Plugin sets `output.cancelled = true` | Plugin-side intent existed, but the old binary ignored the field. | Plugin behavior alone did not prove binary support. |
| `/session-info` fixed | It still launched an agent in the invoking session. | `real_project_behavior_proven` was false; real behavior disproved the claim. |

The central evidence error was collapsing source presence, patch registry status, binary installation, runtime loading, and real behavior into one vague status word.

## Failure classification

### A. One-off human/AI errors

These are local execution mistakes. They matter, but the same exact mistake would not necessarily recur if the surrounding system forced better evidence.

- The agent stopped after source editing and did not execute the documented build/install/restart chain.
- The agent or prior report accepted the patch document's `active` field at face value.
- The agent did not explicitly state `Not verified live: live_file_installed, runtime_loaded, real_project_behavior_proven` when those states were missing.
- The agent did not treat the continued `/session-info` agent launch as decisive disproof of the claimed fix until repeated failures forced re-examination.

### B. Process gaps

These are procedural weaknesses that allowed the one-off errors to pass as completion.

- Patch tracker verification for source patches did not require a separate installed-binary check.
- The patch entry's `verification_pattern` was source-oriented even though the patch's user-visible effect depended on a compiled binary.
- The patch registry status vocabulary did not map cleanly onto the evidence-state discipline in `AGENTS.md`.
- Build commands in the patch doc were treated as instructions, not as recorded evidence with captured outputs.
- The update/patching procedures were not automatically tied to final report claim language.
- The real-surface verification step was underspecified for this specific command-pipeline cancellation case: it needed proof of non-dispatch, not merely proof that the command handler or plugin ran.
- The distinction between symlinked live config files and separately deployed artifacts was documented, but the workflow still allowed source edits to be mentally grouped with live config edits.

### C. Systematic / architectural failures

These are the fundamental patterns this case reveals about the current approach.

1. **Mutable local fork state is not coupled to the runtime artifact.** The OpenCode source tree, patch registry, built binary, installed binary, running process, and observed TUI behavior are separate surfaces. The current approach relies on agents to manually preserve the chain between them.

2. **Patch metadata is descriptive, not authoritative.** A markdown entry can say `active` even when the live binary lacks the patch. The registry records intent and reapply knowledge; it does not enforce deployment truth.

3. **The same word is used for different layers of truth.** `active` can mean a patch is not deprecated, a config entry exists, a plugin is registered, a binary is installed, or behavior works. The evidence-state discipline rejects that ambiguity, but the patch workflow still permits it.

4. **Instruction-heavy safety does not equal machine-enforced safety.** The repo has detailed procedures for binary patching and updates. This case shows that agents can skip or incompletely execute them while still leaving convincing documentation behind.

5. **Self-hosted runtime fixes are hard to prove from inside the runtime.** The agent is using OpenCode while trying to patch OpenCode. Restarting, swapping binaries, and proving negative command dispatch all sit outside ordinary source/test workflows.

6. **Source-level tests are necessary but not sufficient for packaged CLI behavior.** A test can validate the three source-side changes, but the user experienced the old live binary. The packaging/install boundary was the actual failure boundary.

7. **Local patches create hidden compatibility debt that looks solved until a real surface contradicts it.** The durable alternative was upstream PR #18559, but until upstream adoption or a proven local binary install, the local patch remained an operational liability.

8. **Documentation can become a false source of operational truth.** The patch doc was accurate about what needed to happen, but inaccurate as a state report. Because it lived in the config repo and used authoritative-looking frontmatter, it was easy to trust over the live binary.

9. **Negative behavior requires positive evidence.** "No agent should launch" is not proven by a successful grep, a plugin side effect, or an empty response. It requires evidence that the command path stopped before prompt dispatch in a live session.

10. **The current approach has too many manually synchronized ledgers.** Source clone, patch registry, config docs, Wisdom, README claims, installed binary, services, and real behavior can drift independently. This case is a concrete instance of ledger drift.

## Fundamental problem pattern

The case is not primarily about `/session-info`. It exposes a broader failure mode: local OpenCode modifications are being managed as markdown-documented patch debt, while their actual success depends on a multi-step binary supply chain and live runtime reload. The current approach has strong written procedures but weak coupling between procedure completion and allowed claims.

The false success path was:

1. Source patch exists.
2. Patch doc records `status: active` and `applied_date`.
3. Plugin code depends on the patch.
4. Documentation says the patch is active.
5. Agent assumes the runtime has the behavior.
6. Live `/session-info` proves the runtime does not.

That path reveals a systematic evidence collapse: the system accepted documentation and source-state as substitutes for installed/runtime behavior.

## Bottom-line classification

- One-off errors were present: an agent skipped build/install/restart and over-trusted a patch doc.
- Process gaps were present: patch verification and reporting did not force binary/runtime evidence for binary patches.
- The dominant issue is systematic/architectural: the current local-patch approach separates intent, source, package, install, runtime, and behavior into manually synchronized artifacts, then relies on agents to keep their claims aligned across all of them.
