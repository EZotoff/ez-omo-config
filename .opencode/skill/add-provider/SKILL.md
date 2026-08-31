---
name: add-provider
description: "MUST USE when adding or changing models/providers in this repo's OpenCode config: new provider blocks, new model entries, enabled_providers edits, fallback chains, small_model / agent.title.model / OMO agent model assignments, or provider auth wiring. Encodes the checklist that prevents the six recurring setup failure classes (missing limit fields, enabled-list omission, upstream limit poisoning, wrong model ids/limits, stale-process activation gaps, reference drift)."
---

# Add / Change Provider or Model

Provider/model edits in this repo have failed **nine times in six weeks** (Aug 14–30, 2026), each time in one of six predictable ways. This skill is the checklist that makes those failures impossible to ship. Background and full incident corpus: [references/rca-2026-08-30.md](references/rca-2026-08-30.md).

## The six failure classes (know them before editing)

| Class | What happened | Anchor |
|---|---|---|
| Missing required fields | model block without `limit.output` → config rejected at load | `2711fbd` |
| Enabled-list omission | provider block added but never added to `enabled_providers` → invisible | `78687c9`→`7663dd2` |
| Upstream limit poisoning | config omitted `limit.input`; models.dev phantom value survived the per-field `??` merge → compaction at 352K/1M | `1776a57` |
| Wrong id / wrong limits | K2.7-era id labeled K3; declared ctx ≠ served ctx; plan-tier ctx < marketing ctx | `8cf88e4`, `4c588d0`, `c53d062` |
| Activation gap | config correct on disk, but TUI panes older than the change kept serving stale config → silent title death for 3 days | Aug 30 title incident |
| Reference drift | model ids referenced in OMO agents / small_model / title that don't resolve, or docs tables lagging config | audit 2026-08-30 |

## Coupled surfaces — one change touches up to six places

- [ ] `provider.<id>` block (or `models` entry) in `configs/opencode/opencode.json`
- [ ] `enabled_providers` array (same edit, always)
- [ ] `~/.local/share/opencode/auth.json` key entry (if provider needs a key and it's not inline `options.apiKey`)
- [ ] OMO agent/category assignments + fallback chains in `configs/oh-my-openagent/oh-my-openagent.json` (if the model gets used there)
- [ ] `small_model` / `agent.title.model` (only via the promotion rule below)
- [ ] Docs: README provider table, `docs/configs.md` counts, MANIFEST.md if artifact inventory changed

**Always edit the store path** (`configs/opencode/opencode.json`). The live `~/.config/opencode/opencode.json` is a symlink — same file, but edits belong in the repo.

## Workflow

### 1. Probe sources — never write ids/limits from memory

- Live catalog: `curl -s <baseURL>/v1/models` (with the provider's auth header) — record exact model ids and advertised context (`n_ctx` where given).
- Official model page for context/input/output limits. Note: limits can be **plan-tier- or deployment-dependent** (Kimi K3 serves 256K on lower tiers despite "1M" marketing; llama.cpp servers serve `n_ctx`, not the model's nominal window). What the *endpoint+plan* actually serves is the only truth.
- Probe the reasoning field once: `curl -s <baseURL>/v1/chat/completions` with a trivial prompt — does the response contain `reasoning`, `reasoning_content`, or `reasoning_details`? That decides `interleaved.field`.

### 2. Write the block — every limit explicit

Model entry template (custom providers):

```json
"<model-id>": {
  "name": "<Display Name>",
  "reasoning": true,
  "attachment": false,
  "interleaved": { "field": "reasoning_content" },
  "limit": { "context": 1000000, "input": 922000, "output": 131072 }
}
```

- **All three `limit` fields, always** (`context`, `input`, `output`). Omitting any one leaves it to the upstream registry merge — that is exactly how the phantom `input=372000` poisoned GPT-5.6 (`1776a57`).
- `interleaved.field` allowed values: `"reasoning" | "reasoning_content" | "reasoning_details"` (opencode `provider.ts` schema). Only set it if the endpoint emits the field (step 1 probe).
- Provider block needs `npm: "@ai-sdk/openai-compatible"` + `options.baseURL` + (`options.apiKey` inline or an `auth.json` entry under the provider id).
- **Built-in providers** (`google`, `openai`, `opencode-go`, `anthropic`) need NO block — just `enabled_providers` + key.
- **Declared exception**: a model whose limits are discovered at runtime (`kimi-for-coding-oauth/kimi-for-coding`) may omit limits — record it in the exceptions list in [references/rca-2026-08-30.md](references/rca-2026-08-30.md) §4 with justification, so audits don't flag it.

### 3. Enable + auth

Add the provider id to `enabled_providers`. If auth is needed, add `~/.local/share/opencode/auth.json` entry `{"<provider-id>": {"type": "api", "key": "..."}}` — never commit that file.

### 4. Structural gate (before commit)

```bash
python3 -c "import json; json.load(open('configs/opencode/opencode.json'))"   # parses
```

Reference-integrity audit (offline; checks every `provider/model` string in both configs resolves, and flags missing explicit limits):

```bash
python3 - <<'EOF'
import json, re
cfg = json.load(open('configs/opencode/opencode.json'))
omo = json.load(open('configs/oh-my-openagent/oh-my-openagent.json'))
provs, enabled = cfg.get('provider', {}), set(cfg.get('enabled_providers', []))
BUILTINS = {'google', 'openai', 'opencode-go', 'anthropic'}
EXC = {'kimi-for-coding-oauth/kimi-for-coding'}  # runtime limit discovery — declared exceptions
issues = []
for pid in provs:
    if pid not in BUILTINS and pid not in enabled: issues.append(f"block '{pid}' not enabled")
for pid in enabled:
    if pid not in provs and pid not in BUILTINS: issues.append(f"enabled '{pid}' has no block")
for pid, p in provs.items():
    for mid, m in (p.get('models') or {}).items():
        lim = m.get('limit', {})
        if f"{pid}/{mid}" in EXC: continue
        for f in ('context', 'output'):
            if not lim.get(f): issues.append(f"{pid}/{mid}: limit.{f} missing")
defined = {f"{pid}/{mid}" for pid, p in provs.items() for mid in (p.get('models') or {})}
known = '|'.join(map(re.escape, list(BUILTINS) + list(provs)))
refs = set(re.findall(r'"((?:' + known + r')/[a-zA-Z0-9._:\-]+)"', json.dumps(cfg) + json.dumps(omo)))
for r in sorted(refs):
    pid = r.split('/', 1)[0]
    if pid not in BUILTINS and r not in defined: issues.append(f"dangling ref: {r}")
    m = provs.get(pid, {}).get('models', {}).get(r.split('/', 1)[1], {})
    if r not in EXC and m and not m.get('limit', {}).get('input'):
        issues.append(f"{r}: limit.input not explicit (upstream-merge poisoning risk)")
print("RESULT:", "CLEAN" if not issues else f"{len(issues)} ISSUE(S)")
[print(" -", i) for i in issues]
EOF
```

Every finding is either fixed or added to the declared-exceptions list — never ignored.

### 5. Live verification (real surface)

```bash
# Config loads through the real binary (catches config-invalid / schema errors):
mkdir -p /tmp/opencode/provider-check && cd /tmp/opencode/provider-check && timeout 90 opencode run "Reply with exactly: LOAD-OK"

# The new model actually completes:
opencode run -m <provider>/<model> "Reply with exactly one word: SMOKE-OK"

# Model is registered/visible:
opencode models | grep -F "<provider>/<model>"
```

Cleanup the scratch dir afterwards.

### 6. Commit

`bash tests/run_all.sh` first (review-enforcer consumes it). Commit config + docs in one atomic commit (`feat(providers): ...`).

### 7. Activate — ALL processes, not just the daemon

```bash
systemctl --user restart opencode.service omo-tg.service
# Then find TUI panes older than the config change — they embed stale servers:
ps -eo pid,lstart,etimes,args | grep '[o]pencode serve'
git log -1 --format=%ci -- configs/opencode/opencode.json   # compare start times against this
```

Any opencode process whose start time predates the commit is serving the old config. `systemctl` restart does NOT cover TUI-embedded servers — cycle those panes (close/reopen; sessions persist in `opencode.db` and are resumable). This step is mandatory after every model/provider change: the Aug 30 title outage was exactly this gap.

### 8. Sync docs

README provider table, `docs/configs.md`, MANIFEST.md if the artifact inventory changed. A config change without its doc update is an incomplete change.

## Hard rules

1. **Probe, don't recall** — ids and limits come from the live endpoint + official docs, this session.
2. **All three limits explicit** — no field left to the upstream `??` merge.
3. **Provider block and `enabled_providers` in the same commit.**
4. **Promotion rule**: a brand-new model serves a non-critical agent first. It may not enter `small_model` or `agent.title.model` (single-point roles with no fallback chain) until it has a successful live smoke test AND at least one observed working session. (FLARE-4B was promoted straight to title/small_model and reverted within days: `9ca7895`→`a003cba`.)
5. **Reference integrity is a gate** — no dangling `provider/model` strings in either config, ever.
6. **Config change ≠ runtime change** — step 7 always; verification claims follow the repo's Live Deployment Claim Discipline (script presence is not runtime proof).
