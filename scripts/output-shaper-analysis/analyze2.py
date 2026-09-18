#!/usr/bin/env python3
# Output-shaper effectiveness analyzer v2 (2026-09, reconstructed from session
# history after /tmp wipe — output evidence in results2.txt).
# Fixes over v1 (per meta-review):
#   F1 treatment arms: treated vs placebo (NOTE: superseded 2026-09-15 by the
#      discovery that snake_case reasoning_effort was silently dropped by the
#      AI SDK openai-compatible Zod layer — see model-gating.mjs header. The
#      Jul-Aug "treated" arm was untreated at the wire for all openai-compatible
#      providers; only openai (camelCase reasoningEffort) was truly treated.
#      v3 must split arms by CASING: openai=actually-treated Jul-Aug, all
#      snake_case providers=accidental-placebo.)
#   F2 absolute tokens as estimand (no ratio claims); zeros included
#   F3 session-clustered bootstrap CIs (B=1000); real n = sessions
#   F4 proper median/p75; ordering tie-audit
#   F5 full session history loaded (state back-filled before window)
#   F6 per-(model,period) reasoning-reporting guard
#   F7 event study around deployment (7d before/after)
#   F8 variant mix reported
# v3 TODO: join Clamped/Pass lines (now carry sid= agent=) for true treatment receipt.
from __future__ import annotations
import sqlite3, os, json, sys, time, random
from datetime import datetime, timezone
from collections import defaultdict
import statistics as st

try:
    import numpy as np
    MED = np.median
except ImportError:
    MED = st.median

DB = os.path.expanduser("~/.local/share/opencode/opencode.db")
def ms(s): return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)
T_WIN  = ms("2026-07-01T00:00:00Z")
T_PRE  = ms("2026-08-06T22:33:51Z")   # terseness live
T_POST = ms("2026-08-07T06:24:25Z")   # clamps live (but see F1: wire-no-op for snake_case providers)
B = 1000
_R = random.Random(20260829)

TREATED = {"glm-5.2", "glm-5.3", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
           "kimi-for-coding", "k3",
           "gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.1-pro-preview"}
PLACEBO = {"deepseek-v4-flash", "deepseek-v4-pro", "minimax-m3", "kimi-k2.6"}
ARMS = {m: "treated" for m in TREATED} | {m: "placebo" for m in PLACEBO}

db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
db.execute("PRAGMA cache_size=-262144")

t0 = time.time()
raw = defaultdict(list)
for mid, sid, tc, data in db.execute("SELECT id, session_id, time_created, data FROM message"):
    try: d = json.loads(data)
    except Exception: continue
    role = d.get("role")
    if role not in ("assistant", "user"): continue
    raw[sid].append(dict(id=mid, tc=tc, role=role, model=d.get("modelID"),
                         tokens=d.get("tokens"), variant=d.get("variant")))

allids = [m["id"] for lst in raw.values() for m in lst]
has_ctool, has_tool = {}, {}
for i in range(0, len(allids), 400):
    batch = allids[i:i+400]
    ph = ",".join("?" * len(batch))
    for pid, pt, ps in db.execute(
        f"SELECT message_id, json_extract(data,'$.type'), json_extract(data,'$.state.status') "
        f"FROM part WHERE message_id IN ({ph})", batch):
        if pt == "tool":
            has_tool[pid] = True
            if ps == "completed": has_ctool[pid] = True
print(f"loaded {sum(len(v) for v in raw.values())} msgs, parts scan {time.time()-t0:.0f}s", file=sys.stderr)

ties = 0
cohort = []
for sid, lst in raw.items():
    lst.sort(key=lambda m: (m["tc"], m["id"]))
    ties += sum(1 for a, b in zip(lst, lst[1:]) if a["tc"] == b["tc"])
    prev_ctool, user_text = False, False
    for m in lst:
        if m["role"] == "assistant":
            m["resume"] = prev_ctool and not user_text
            prev_ctool = has_ctool.get(m["id"], False)
            if prev_ctool: user_text = False
            if m["tc"] >= T_WIN and m["tokens"] is not None:
                m["sid"] = sid
                cohort.append(m)
        else:
            if not has_tool.get(m["id"], False):
                user_text, prev_ctool = True, False
print(f"cohort={len(cohort)}  same-ms adjacent ties={ties}", file=sys.stderr)

def period(tc): return "pre" if tc < T_PRE else ("gap" if tc < T_POST else "post")

rep = {}
for m in cohort:
    if m["model"] is None: continue
    t = m["tokens"]
    if (t.get("output") or 0) > 0:
        key = (m["model"], period(m["tc"]))
        a, b = rep.get(key, (0, 0))
        rep[key] = (a + (1 if (t.get("reasoning") or 0) > 0 else 0), b + 1)
def rr_ok(model, p):
    a, b = rep.get((model, p), (0, 0))
    return b >= 30 and a / b >= 0.02

cells = defaultdict(lambda: ([], []))
vcount = defaultdict(lambda: defaultdict(int))
for m in cohort:
    if m["model"] is None or period(m["tc"]) == "gap" or m["model"] not in ARMS: continue
    key = (m["model"], period(m["tc"]), m["resume"])
    cr, co = cells[key]
    if rr_ok(m["model"], period(m["tc"])):
        cr.append((m["sid"], m["tokens"].get("reasoning") or 0))
    co.append((m["sid"], m["tokens"].get("output") or 0))
    vcount[m["model"]][(period(m["tc"]), m["variant"], m["resume"])] += 1

def cluster_median(sm):
    sids = list(sm)
    if not sids: return None
    pick = [_R.choice(sids) for _ in sids]
    pooled = [v for s in pick for v in sm[s]]
    return float(MED(pooled)) if pooled else None

def sess_map(pairs):
    d = defaultdict(list)
    for sid, v in pairs: d[sid].append(v)
    return d

def boot_ci(pairs):
    if len(pairs) < 20: return (None, None)
    sm = sess_map(pairs)
    reps = [v for _ in range(B) if (v := cluster_median(sm)) is not None]
    if len(reps) < B // 2: return (None, None)
    reps.sort()
    return (reps[int(0.025 * len(reps))], reps[int(0.975 * len(reps))])

def did_ci(pr, pn, qr, qn):
    maps = [sess_map(x) for x in (pr, pn, qr, qn)]
    union = list(set().union(*[set(m) for m in maps]))
    if len(union) < 10: return (None, None)
    reps = []
    for _ in range(B):
        pick = [_R.choice(union) for _ in union]
        def m_of(sm):
            vals = [v for s in pick for v in sm.get(s, [])]
            return float(MED(vals)) if vals else None
        a, b, c, d = (m_of(x) for x in maps)
        if None not in (a, b, c, d): reps.append((c - d) - (a - b))
    if len(reps) < B // 2: return (None, None)
    reps.sort()
    return (reps[int(0.025 * len(reps))], reps[int(0.975 * len(reps))])

MODELS = [m for m in ["glm-5.2", "glm-5.3", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
                      "kimi-for-coding", "k3", "gemini-3.6-flash", "gemini-3.7-flash",
                      "gemini-3.1-pro-preview", "deepseek-v4-flash", "deepseek-v4-pro", "minimax-m3"]
          if any(k[0] == m for k in cells)]
print(f"\n{'model':20s}{'arm':8s}{'per':4s}{'turn':6s}{'nmsg':>6s}{'nses':>5s}  {'reasoning_med [95%CI]':>24s}  {'output_med [95%CI]':>24s}")
for mdl in MODELS:
    for p in ("pre", "post"):
        for r in (True, False):
            rea, out = cells.get((mdl, p, r), ([], []))
            if not rea and not out: continue
            nsess = len({s for s, _ in (out or rea)})
            fmt = lambda pairs, med, ci: (f"{med:>8.0f} [{ci[0]:.0f},{ci[1]:.0f}]"
                                          if med is not None and ci[0] is not None else
                                          (f"{med:>8.0f} [n/r]" if pairs else f"{'-':>8s}       "))
            rmed = st.median([v for _, v in rea]) if rea else None
            omed = st.median([v for _, v in out]) if out else None
            print(f"{mdl:20s}{ARMS[mdl]:8s}{p:4s}{'res' if r else 'new':6s}{len(out or rea):6d}{nsess:5d}"
                  f"  {fmt(rea, rmed, boot_ci(rea)):>24s}  {fmt(out, omed, boot_ci(out)):>24s}")
    for idx, field in ((0, "rea"), (1, "out")):
        pr, pn = cells.get((mdl, "pre", True), ([], []))[idx], cells.get((mdl, "pre", False), ([], []))[idx]
        qr, qn = cells.get((mdl, "post", True), ([], []))[idx], cells.get((mdl, "post", False), ([], []))[idx]
        if min(len(pr), len(pn), len(qr), len(qn)) >= 100:
            pt = lambda x: st.median([v for _, v in x])
            lo, hi = did_ci(pr, pn, qr, qn)
            if lo is not None:
                print(f"{mdl:20s}>>> DiD {field}: point={((pt(qr)-pt(qn))-(pt(pr)-pt(pn))):+.0f}  95%CI [{lo:+.0f},{hi:+.0f}]  (neg = clamp-direction)")

print("\n=== event study: 7d before vs after clamp start (Aug 7), reasoning medians ===")
for mdl in MODELS:
    if ARMS.get(mdl) != "treated" and ARMS.get(mdl) != "placebo": continue
    daily = defaultdict(lambda: ([], []))
    for m in cohort:
        if m["model"] != mdl or period(m["tc"]) == "gap" or not rr_ok(mdl, period(m["tc"])): continue
        day = datetime.fromtimestamp(m["tc"] / 1000, tz=timezone.utc).strftime("%m-%d")
        daily[day][0 if m["resume"] else 1].append(m["tokens"].get("reasoning") or 0)
    days = sorted(daily)
    pre7, post7 = [d for d in days if d < "08-07"][-7:], [d for d in days if d >= "08-07"][:7]
    def w(ds, r):
        v = [x for d in ds for x in daily[d][r]]
        return (float(MED(v)), len(v)) if v else (None, 0)
    prm, prn, pom, pon = w(pre7, 0), w(pre7, 1), w(post7, 0), w(post7, 1)
    if None in (prm[0], prn[0], pom[0], pon[0]):
        print(f"{mdl:20s}{ARMS[mdl]:8s} insufficient paired 7d data (pre days={len(pre7)}, post days={len(post7)})")
    else:
        print(f"{mdl:20s}{ARMS[mdl]:8s} 7d-pre: res {prm[0]:>5.0f}({prm[1]:<5}) new {prn[0]:>5.0f}({prn[1]:<5})"
              f" | 7d-post: res {pom[0]:>5.0f}({pom[1]:<5}) new {pon[0]:>5.0f}({pon[1]:<5})"
              f" | Dres={pom[0]-prm[0]:+.0f} Dnew={pon[0]-prn[0]:+.0f}")

print("\n=== variant mix (period|variant|resume -> counts, top) ===")
for mdl in MODELS:
    tops = dict(sorted(vcount[mdl].items(), key=lambda kv: -kv[1])[:6])
    print(f"{mdl:20s} {tops}")
