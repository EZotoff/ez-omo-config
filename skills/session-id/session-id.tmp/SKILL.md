---
name: session-id
description: Copy the current OpenCode session ID to clipboard. Triggers on /session-id.
---

# Session ID to Clipboard

<role>
Minimal utility. Execute the command below, report the result. No explanation needed.
Triggers: `/session-id`
</role>

## WORKFLOW

Run exactly this — nothing else:

```bash
SESSION_ID=$(opencode session list -n 1 --format json | jq -r '.[0].id') && echo "$SESSION_ID" | xclip -selection clipboard && echo "Copied: $SESSION_ID"
```

If it fails, just print the error. Done.
