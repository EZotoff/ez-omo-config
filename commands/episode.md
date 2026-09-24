---
description: Write an episode checkpoint receipt for the current session's episode
---

Record a checkpoint for the current episode by invoking the receipt script directly — this command documents the invocation; it does NOT pretend to observe the transcript.

Run from the episode's project root:

```bash
scripts/episode-receipt.sh append .omo/episodes/<slug> --checkpoint \
  --intent "<what this session is doing for the episode>" \
  --claims '["<what was done, as verifiable claims>"]' \
  --evidence-refs "<paths + quoted message excerpts with message IDs, comma-separated>" \
  --resume-pointer "<where the next session should pick up>"
```

Rules:

- Every argument must be explicit — the script does not infer intent, claims, or evidence from the session.
- Evidence refs MUST include quoted message excerpts with their message IDs (bounded `session_evidence`); never paste full transcripts. A session-evidence ref has the exact form `msg:<message-id>|<quoted excerpt>` (comma-separated with file refs; excerpts must not contain commas) — the receipt stores `{path: "msg:<message-id>", sha256: <sha256 of excerpt UTF-8 bytes>, excerpt}`, and `verify` recomputes the digest over the stored excerpt (mismatch → digest-mismatch failure).
- If no manifest exists yet for the episode, `--checkpoint` auto-creates a minimal one at `.omo/episodes/<slug>/manifest.yaml` — the manifest is the single source of truth; no sidecar receipts.
- Never fabricate a checkpoint: if you cannot name concrete evidence, say so and stop.

Then check episode hygiene with `scripts/episode-receipt.sh lint .omo/episodes/<slug>` (flags, never fixes):

- **Stale active episodes**: manifests with `status: active` but no activity (last verify or newest receipt) in >7 days — report them.
- **Missing checkpoints**: `status: active` with no `kind:"checkpoint"` receipt — name the gap and checkpoint it now.

Reply with: the receipt sequence number (or the script's error), and any hygiene flags raised.
