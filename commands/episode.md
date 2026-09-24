---
description: Write an episode checkpoint receipt for the current session's episode
---

Record a checkpoint for the current episode by invoking the receipt script directly — this command documents the invocation; it does NOT pretend to observe the transcript.

Run from the episode's project root:

```bash
scripts/episode-receipt.sh append --checkpoint \
  --intent "<what this session is doing for the episode>" \
  --claims "<what was done, as verifiable claims>" \
  --evidence-refs "<paths + quoted message excerpts with message IDs, comma-separated>" \
  --resume-pointer "<where the next session should pick up>"
```

Rules:

- Every argument must be explicit — the script does not infer intent, claims, or evidence from the session.
- Evidence refs MUST include quoted message excerpts with their message IDs (bounded `session_evidence`); never paste full transcripts.
- If no manifest exists yet for the episode, `--checkpoint` auto-creates a minimal one at `.omo/episodes/<slug>/manifest.yaml` — the manifest is the single source of truth; no sidecar receipts.
- Never fabricate a checkpoint: if you cannot name concrete evidence, say so and stop.

Then check episode hygiene and flag (never fix silently):

- **Stale active episodes**: manifests with `status: active` but no recent activity — report them.
- **Missing checkpoints**: work done in this session with no receipt recorded — name the gap and checkpoint it now.

Reply with: the receipt sequence number (or the script's error), and any hygiene flags raised.
