# Live wire probe — zai coding-plan (2026-09). Evidence: README.md finding 2.
# Reads keys from auth.json in-process; never prints them.
# NOTE: urllib works against api.z.ai; opencode.ai/zen Cloudflare-bans urllib's
# TLS signature (403 error 1010) — use go_matrix.sh (curl) for opencode-go.
import json, urllib.request, urllib.error, time

auth = json.load(open('/home/ezotoff/.local/share/opencode/auth.json'))
KEY = auth['zai-coding-plan']['key']
PROMPT = ("Solve step by step: A bat and a ball cost $1.10 together. "
          "The bat costs $1.00 more than the ball. How much is the ball? "
          "Then compute 17*23.")
MAXTOK = 3000

def call(extra):
    body = {"model": "glm-5.3", "max_tokens": MAXTOK,
            "messages": [{"role": "user", "content": PROMPT}]}
    body.update(extra)
    req = urllib.request.Request("https://api.z.ai/api/coding/paas/v4/chat/completions",
        data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            d = json.loads(r.read())
            u = d.get("usage", {})
            ctd = (u.get("completion_tokens_details") or {})
            return dict(status=r.status, secs=round(time.time()-t0, 1),
                completion=u.get("completion_tokens"), reasoning=ctd.get("reasoning_tokens"),
                prompt=u.get("prompt_tokens"), finish=d.get("choices", [{}])[0].get("finish_reason"))
    except urllib.error.HTTPError as e:
        return dict(status=e.code, error=e.read().decode()[:250])
    except Exception as e:
        return dict(status=-1, error=str(e)[:250])

THINK = {"thinking": {"type": "enabled", "clear_thinking": False}}
for label, extra in [
    ("absent", {}), ("low", {"reasoning_effort": "low"}), ("high", {"reasoning_effort": "high"}),
    ("low+thinking", {"reasoning_effort": "low", **THINK}),
    ("high+thinking", {"reasoning_effort": "high", **THINK}),
]:
    print(f"zai glm-5.3 effort={label:12s} -> {json.dumps(call(extra))}")

# Observed 2026-09: absent reasoning=197; low reasoning=0; high reasoning=200;
# low+thinking reasoning=19 (live wire shape -> ~10x cut, not zero);
# high+thinking reasoning=196. reasoning_effort honored at body level.
