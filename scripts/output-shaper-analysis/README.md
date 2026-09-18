# Output-shaper effectiveness analysis (2026-09)

Evidence trail for the output-shaper effectiveness review. Reconstructed here
after `/tmp` was wiped twice mid-session (durable-workspace policy).

## Files
- `analyze2.py` — storage analyzer v2 (session-clustered bootstrap CIs, absolute
  tokens, event study, placebo arms). Run: `python3 analyze2.py` (read-only
  against `~/.local/share/opencode/opencode.db`).
- `results2.txt` — v2 output, 2026-09 run.
- `probe_wire.py` — live wire probe (zai); reads keys from auth.json, never prints them.
- `go_matrix.sh` — live wire probe (opencode-go; curl needed — urllib TLS
  fingerprint is Cloudflare-banned with error 1010).

## Key findings
1. **Silent no-op casing bug (root cause, found 2026-09-15)**: during Jul–Aug
   the plugin wrote snake_case `reasoning_effort` into chat.params options; the
   AI SDK openai-compatible Zod layer silently drops it — the clamp NEVER
   reached the wire for zai/kimi/deepseek/opencode-go. Only `openai`
   (camelCase `reasoningEffort`) was truly treated. This explains the storage
   nulls: glm-5.2 resume reasoning flat (100→138) while sol/terra (actually
   treated) dropped (sol 86→31 absolute; terra output DiD −140 [−216,−39]).
   Fixed in `configs/opencode/output-shaper/model-gating.mjs` (camelCase +
   per-model allowlists).
2. **Gateway-level values are honored** (live probe, 2026-09): zai glm-5.3
   body `reasoning_effort:"low"` → reasoning 197→0 (19 with
   `thinking:{enabled}` present, the live wire shape); opencode-go
   deepseek-v4-pro/flash accept `low` with modest monotone cuts (−21%/−37%).
   The models-snapshot registry `values` lists are picker metadata, not
   gateway capability.
3. **v2 analyzer conclusions** (see results2.txt): pre/post storage comparison
   cannot identify clamp effects (placebo arm moved like treated; ratio
   artifacts; reporting drift). Treatment receipt must come from the plugin log.

## v3 (next)
The plugin now logs `sid=` and `agent=` on Clamped/Pass/Terseness lines
(2026-09-18). After ~2 weeks of accumulation, extend analyze2.py to join
clamp events to messages by (sid, timestamp) for true treatment-receipt
measurement. Split Jul–Aug historical arms by CASING (openai=actually treated,
snake_case providers=accidental placebo), not by the v2 ARMS sets.
