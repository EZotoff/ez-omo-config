# marketplace/agensi — Agensi.io Skill Marketplace Pilot

Listing package for two skills prepared for the Agensi.io marketplace
(2026-10-16). Only `LISTINGS.md` (listing copy, pricing, upload steps, pilot
kill criteria) is tracked in this public repo.

**The skill sources and upload zips are deliberately NOT in this public
repo** — the paid listing depends on exclusivity, and Agensi rejects
repackaged public skills. They live in the machine-local, untracked
directory `~/.local/share/opencode/agensi-bundles/`:

- `debate/SKILL.md` + `debate-skill.zip` — agent-agnostic rewrite of
  `~/.config/opencode/skills/debate/` (OMO dispatch mechanics replaced
  with portable consultant-dispatch rules; judge-category table → role
  personas)
- `typographic-writing/` + `typographic-writing.zip` — de-personalized
  copy of `~/.config/opencode/skills/typographic-writing/` including the
  standalone `checks/check-prose.mjs` linter

The live skills in `~/.config/opencode/skills/` remain canonical; the
bundle copies are edited derivatives, do not sync mechanically in either
direction.

If the machine-local bundles are lost, they can be reconstructed from the
live skills plus the deltas recorded above — no other remote copy exists.

Not MANIFEST-tracked: these are export products, not installed config
artifacts (no install targets, no live symlinks).
