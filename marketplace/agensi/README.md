# marketplace/agensi — Export Bundles for the Agensi.io Skill Marketplace

Upload-ready SKILL.md packages derived from repo skills, de-personalized for
public sale. The live skills in `~/.config/opencode/skills/` remain the
canonical internal versions — these copies are **derivatives**, edited for
portability; do not sync mechanically in either direction.

| Artifact | Source | Deltas vs source |
|---|---|---|
| `debate/SKILL.md` | `~/.config/opencode/skills/debate/SKILL.md` | Replaced OMO dispatch (`task(category=...)`, `background_output`) with agent-agnostic consultant dispatch; `.sisyphus/debates/` → `./debates/`; judge-category table → role personas; removed reader-report chaining and legacy-migration notes. |
| `typographic-writing/SKILL.md` + `checks/` | `~/.config/opencode/skills/typographic-writing/` | Removed cross-references to other stack skills (reader-report, fresh-explain, web-typography, dynamic-typography); generalized "Layer contract" into "Composition". |
| `*-skill.zip` / `*.zip` | the dirs here | Submission artifacts for Agensi review. |
| `LISTINGS.md` | — | Listing copy, tags, pricing, upload steps, pilot kill criteria. |

Not MANIFEST-tracked: these are export products, not installed config
artifacts (no install targets, no live symlinks).
