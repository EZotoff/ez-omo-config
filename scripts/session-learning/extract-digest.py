#!/usr/bin/env python3
"""session-learning: read-only session digest extractor + nightly sweep orchestrator.

Subcommands:
  select   Eligible finalized sessions (stale, top-level, unprocessed at the
           current watermark) with fork dedup. Prints JSON lines.
  digest   Bounded digest of one session. Prints JSON (or writes --out FILE).
  rank     Rank analyst candidates under per-session and global caps.
  sweep    Full nightly orchestration (select -> digest -> analyst -> rank ->
           wisdom writes -> ledger -> summary log). Requires the analyst
           prompt file next to this script.

The OpenCode DB is opened in SQLite read-only mode. The only writes this tool
performs are to its own state dir (~/.sisyphus/session-learning/) and, via
wisdom-closeout.sh in sweep mode, to the wisdom store.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")
DEFAULT_STATE_DIR = os.path.expanduser("~/.sisyphus/session-learning")
DEFAULT_WORKDIR = os.path.expanduser(
    "~/.local/share/opencode/session-learning/analyst-workdir"
)
DEFAULT_LOG = os.path.expanduser("~/.local/share/opencode/session-learning.log")
DEFAULT_MODEL = "zai-coding-plan/glm-5.3-flash"
WISDOM_SYSTEM_STORE = os.path.expanduser("~/.sisyphus/wisdom/system.jsonl")
WISDOM_CLOSEOUT = os.path.expanduser("~/.sisyphus/scripts/wisdom-closeout.sh")
ANALYST_TITLE_PREFIX = "[session-learning]"

EXCLUDE_DIR_PREFIXES = [
    DEFAULT_WORKDIR,
    os.path.expanduser("~/.local/share/opencode/session-learning"),
    "/tmp/",
]

# Mirrors configs/opencode/skill-nudger/signals.mjs FAILURE_RE
FAILURE_RE = re.compile(
    r"(exit(?:ed)?(?: with)?(?: code)?\s*[1-9]\d*)|\berror\b|\bfailed\b"
    r"|\btimeout\b|\bexception\b|\bcommand not found\b"
    r"|\bno such file or directory\b|\bpermission denied\b|\btraceback\b",
    re.I,
)
MUTATING_RE = re.compile(
    r"(^|&&|;|\|)\s*(rm|mv|cp|git\s+commit|git\s+push|npm\s+install|"
    r"bun\s+(?:add|install|run)|cargo\s+(?:build|install)|systemctl|"
    r"docker\s+(?:run|compose)|systemd-run|tee\s|>\s*/(?:etc|home))\b",
)
LONG_JOB_RE = re.compile(r"\b(?:systemd-run|durable-run|setsid|nohup)\b")
UNIT_NAME_RE = re.compile(r"(?:systemd-run[^|;>]*--unit[= ]([A-Za-z0-9_.@-]+)|durable-run\s+([A-Za-z0-9_.@-]+))")
WISDOM_CALL_RE = re.compile(r"wisdom-(?:write|closeout|sync|nominate)\.sh")
GIT_COMMIT_RE = re.compile(r"\bgit\s+commit\b")

CONFIDENCE_SCORE = {"high": 3, "medium": 2, "low": 1}


def connect_ro(db_path: str) -> sqlite3.Connection:
    if not os.path.exists(db_path):
        raise SystemExit(f"DB not found: {db_path}")
    return sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)


def to_ms(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def truncate(text: str, limit: int) -> str:
    text = (text or "").strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def load_ledger(path: str) -> dict:
    rows = {}
    p = Path(path)
    if not p.exists():
        return rows
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("session_id"):
            rows[row["session_id"]] = row
    return rows


def append_ledger(path: str, row: dict) -> None:
    row["analyzed_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(path, "a") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def part_text(data: dict) -> str:
    if data.get("type") != "text":
        return ""
    return data.get("text") or ""


def collect_session_parts(conn, session_id: str):
    """Return {message_id: [(order, part_data)]} for one session, time-ordered."""
    cur = conn.execute(
        "SELECT message_id, data FROM part WHERE session_id=? ORDER BY time_created, id",
        (session_id,),
    )
    grouped: dict[str, list] = {}
    for message_id, raw in cur:
        try:
            grouped.setdefault(message_id, []).append(json.loads(raw))
        except json.JSONDecodeError:
            continue
    return grouped


# ---------------------------------------------------------------- select


def qualifying_from_cursor(conn, cur, ledger, exclude, pool=None):
    """Shared qualification loop for the top-level and subagent pools."""
    qualifying = []
    for sid, directory, title, created, updated, agent, model, msgs in cur:
        directory = directory or ""
        title = title or ""
        if any(directory.startswith(p) for p in exclude):
            continue
        if title.startswith(ANALYST_TITLE_PREFIX):
            continue
        row = ledger.get(sid)
        if row:
            status = row.get("status")
            attempts = row.get("attempts", 1)
            if status in ("analyzed", "covered", "no_candidates", "proposal_only"):
                last = to_ms(row.get("last_time_updated"))
                updated_ms_early = to_ms(updated)
                if last is not None and updated_ms_early is not None and last >= updated_ms_early:
                    continue
            elif status in ("analyst_failed", "parse_failed") and attempts >= 5:
                continue
        msgs = int(msgs or 0)
        created_ms, updated_ms = to_ms(created), to_ms(updated)
        duration_min = (
            (updated_ms - created_ms) / 60000
            if created_ms and updated_ms and updated_ms > created_ms
            else 0
        )
        if msgs < 15:
            continue
        reason = None
        if msgs >= 40:
            reason = "messages>=40"
        elif duration_min >= 60 and msgs >= 20:
            reason = "duration>=60m_and_messages>=20"
        elif 15 <= msgs < 40:
            signals = session_signal_score(conn, sid)
            if signals["errors"] >= 5:
                reason = "error_signals>=5"
            elif signals["tool_calls"] >= 15 and signals["mutations"] >= 2:
                reason = "tool_calls>=15_and_mutations>=2"
        if not reason:
            continue
        entry = {
            "session_id": sid,
            "directory": directory,
            "title": truncate(title, 120),
            "msgs": msgs,
            "time_created": created_ms,
            "time_updated": updated_ms,
            "agent": agent,
            "model": model,
            "reason": reason,
        }
        if pool:
            entry["pool"] = pool
        qualifying.append(entry)
    return qualifying



def cmd_select(args) -> None:
    conn = connect_ro(args.db)
    cutoff_ms = int((time.time() - args.stale_hours * 3600) * 1000)
    ledger = load_ledger(args.ledger)
    exclude = [os.path.expanduser(p) for p in EXCLUDE_DIR_PREFIXES]
    if args.workdir and args.workdir not in exclude:
        exclude.append(args.workdir)

    cur = conn.execute(
        """
        SELECT s.id, s.directory, s.title, s.time_created, s.time_updated,
               s.agent, s.model,
               (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) AS msgs
        FROM session s
        WHERE s.parent_id IS NULL
          AND s.time_archived IS NULL
          AND s.time_updated < ?
        """,
        (cutoff_ms,),
    )

    qualifying = qualifying_from_cursor(conn, cur, ledger, exclude)

    # Fork dedup: same directory, created within the same hour -> keep the
    # largest (earliest on tie); mark the rest covered_by the canonical one.
    groups: dict[tuple, list] = {}
    for s in qualifying:
        hour_bucket = (s["time_created"] or 0) // 3_600_000
        groups.setdefault((s["directory"], hour_bucket), []).append(s)
    selected = []
    for members in groups.values():
        members.sort(key=lambda s: (-s["msgs"], s["time_created"] or 0))
        canonical = members[0]
        canonical["covered_by"] = None
        selected.append(canonical)
        for fork in members[1:]:
            fork["covered_by"] = canonical["session_id"]
            fork["reason"] += " +fork"
            selected.append(fork)

    # Analysis budget: canonical sessions ranked by size, biggest first.
    canonical_rows = [s for s in selected if not s["covered_by"]]
    canonical_rows.sort(key=lambda s: (-s["msgs"], s["time_updated"] or 0))
    keep = {s["session_id"] for s in canonical_rows[: args.limit]}
    out = [s for s in selected if not s["covered_by"] and s["session_id"] in keep]
    out += [s for s in selected if s["covered_by"]]

    # Subagent pool (2026-09-24): the original selector used WHERE parent_id IS NULL,
    # which structurally excluded every subagent session (oracle/Momus/debate children —
    # the sessions that carry plan-review and architecture learnings). Subagent sessions
    # are swept in their OWN capped pool so they never compete with the top-level budget:
    # allowlisted agents only, same staleness/ledger/msg gates, ranked by size.
    if getattr(args, "subagent_cap", 0) > 0:
        agents = [a.strip() for a in getattr(args, "subagent_agents", "").split(",") if a.strip()]
        if agents:
            marks = ",".join("?" for _ in agents)
            sub_cur = conn.execute(
                f"""
                SELECT s.id, s.directory, s.title, s.time_created, s.time_updated,
                       s.agent, s.model,
                       (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) AS msgs
                FROM session s
                WHERE s.parent_id IS NOT NULL
                  AND s.time_archived IS NULL
                  AND s.time_updated < ?
                  AND s.agent IN ({marks})
                """,
                (cutoff_ms, *agents),
            )
            sub_q = qualifying_from_cursor(conn, sub_cur, ledger, exclude, pool="subagent")
            sub_q.sort(key=lambda s: (-(s["msgs"]), s["time_updated"] or 0))
            out.extend(sub_q[: args.subagent_cap])

    for s in out:
        print(json.dumps(s, ensure_ascii=False))


def session_signal_score(conn, session_id: str) -> dict:
    tool_calls = errors = mutations = 0
    cur = conn.execute(
        "SELECT data FROM part WHERE session_id=? AND (data LIKE '%\"type\":\"tool\"%' OR data LIKE '%\"type\": \"tool\"%')",
        (session_id,),
    )
    for (raw,) in cur:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        tool_calls += 1
        state = data.get("state") or {}
        command = ((state.get("input") or {}).get("command")) or ""
        if data.get("tool") in ("bash", "terminal") and MUTATING_RE.search(command):
            mutations += 1
        output = (state.get("metadata") or {}).get("output") or state.get("output") or ""
        if FAILURE_RE.search(output or ""):
            errors += 1
    return {"tool_calls": tool_calls, "errors": errors, "mutations": mutations}


# ---------------------------------------------------------------- digest


def build_digest(conn, session_id: str) -> dict:
    row = conn.execute(
        "SELECT directory, title, agent, model, time_created, time_updated,"
        " (SELECT COUNT(*) FROM message WHERE session_id = s.id) FROM session s"
        " WHERE s.id=?",
        (session_id,),
    ).fetchone()
    if row is None:
        raise SystemExit(f"session not found: {session_id}")
    directory, title, agent, model, created, updated, message_count = row

    parts = collect_session_parts(conn, session_id)
    user_messages, assistant_finals = [], []
    tool_call_count = error_tool_calls = mutations = 0
    bash_commands, tool_errors, wisdom_calls, git_commits, launched_units = (
        [],
        [],
        [],
        [],
        [],
    )

    cur = conn.execute(
        "SELECT id, data, time_created FROM message WHERE session_id=?"
        " ORDER BY time_created, id",
        (session_id,),
    )
    messages = []
    for mid, raw, mtime in cur:
        try:
            info = json.loads(raw)
        except json.JSONDecodeError:
            continue
        messages.append((mid, info.get("role"), mtime))

    for mid, role, mtime in messages:
        mparts = parts.get(mid, [])
        if role == "user":
            text = " ".join(
                t for t in (part_text(p) for p in mparts) if t
            ).strip()
            if text:
                user_messages.append(
                    {"ts": mtime, "text": truncate(text, 600)}
                )
        elif role == "assistant":
            finals = [part_text(p) for p in mparts if part_text(p)]
            if finals:
                assistant_finals.append(
                    {"ts": mtime, "text": truncate(finals[-1], 700)}
                )
        for p in mparts:
            if p.get("type") != "tool":
                continue
            tool_call_count += 1
            state = p.get("state") or {}
            command = ((state.get("input") or {}).get("command")) or ""
            output = (
                (state.get("metadata") or {}).get("output")
                or state.get("output")
                or ""
            )
            if p.get("tool") in ("bash", "terminal") and command:
                if MUTATING_RE.search(command):
                    mutations += 1
                if WISDOM_CALL_RE.search(command):
                    wisdom_calls.append(truncate(command, 300))
                if GIT_COMMIT_RE.search(command):
                    git_commits.append(truncate(command, 300))
                for m in UNIT_NAME_RE.finditer(command):
                    unit = m.group(1) or m.group(2)
                    if unit and unit not in launched_units:
                        launched_units.append(unit)
                if len(bash_commands) < 300:
                    bash_commands.append(truncate(command, 200))
            if output and FAILURE_RE.search(output):
                error_tool_calls += 1
                if len(tool_errors) < 40:
                    tool_errors.append(
                        {
                            "tool": p.get("tool"),
                            "command": truncate(command, 160),
                            "output": truncate(output, 300),
                        }
                    )

    digest = {
        "schema": 1,
        "session_id": session_id,
        "directory": directory,
        "title": truncate(title or "", 120),
        "agent": agent,
        "model": model,
        "time_created": to_ms(created),
        "time_updated": to_ms(updated),
        "message_count": int(message_count or 0),
        "user_message_count": len(user_messages),
        "assistant_message_count": len(assistant_finals),
        "tool_call_count": tool_call_count,
        "error_tool_calls": error_tool_calls,
        "mutations": mutations,
        "launched_units": launched_units,
        "wisdom_calls": wisdom_calls[:20],
        "git_commits": git_commits[:20],
        "tool_errors": tool_errors,
        "user_messages": user_messages,
        "assistant_finals": assistant_finals,
    }
    return bound_digest_size(digest)


def bound_digest_size(digest: dict, max_bytes: int = 80_000) -> dict:
    def size(d):
        return len(json.dumps(d, ensure_ascii=False))

    while size(digest) > max_bytes:
        for key in ("assistant_finals", "user_messages", "tool_errors"):
            if len(digest[key]) > 10:
                digest[key] = digest[key][len(digest[key]) // 2 :]
                break
        else:
            break
    return digest


def cmd_digest(args) -> None:
    conn = connect_ro(args.db)
    digest = build_digest(conn, args.session)
    text = json.dumps(digest, ensure_ascii=False, indent=1)
    if args.out:
        Path(args.out).write_text(text)
    else:
        print(text)


# ---------------------------------------------------------------- rank


def cmd_rank(args) -> None:
    selected, dropped = [], []
    per_session: dict[str, int] = {}
    with open(args.candidates) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            sid = entry.get("session_id", "?")
            for cand in entry.get("candidates") or []:
                route = cand.get("route")
                if route not in ("wisdom", "proposal"):
                    dropped.append({"session_id": sid, "reason": f"route={route}"})
                    continue
                relationship = cand.get("relationship", "new")
                if relationship == "duplicate":
                    dropped.append(
                        {"session_id": sid, "reason": "duplicate", "claim": truncate(cand.get("claim", ""), 80)}
                    )
                    continue
                claim = (cand.get("claim") or "").strip()
                if not claim:
                    dropped.append({"session_id": sid, "reason": "empty_claim"})
                    continue
                confidence = cand.get("confidence", "low")
                score = CONFIDENCE_SCORE.get(confidence, 1) * 2 + (
                    1 if (cand.get("evidence") or "").strip() else 0
                )
                selected.append(
                    {
                        "session_id": sid,
                        "score": score,
                        "candidate": cand,
                    }
                )

    selected.sort(
        key=lambda s: (-s["score"], s["session_id"], s["candidate"].get("claim", ""))
    )
    final = []
    for item in selected:
        sid = item["session_id"]
        if per_session.get(sid, 0) >= args.per_session_cap:
            dropped.append({"session_id": sid, "reason": "per_session_cap"})
            continue
        if len(final) >= args.global_cap:
            dropped.append({"session_id": sid, "reason": "global_cap"})
            continue
        per_session[sid] = per_session.get(sid, 0) + 1
        final.append(item)

    print(
        json.dumps(
            {
                "selected": final,
                "dropped": dropped,
                "counts": {
                    "selected": len(final),
                    "dropped": len(dropped),
                    "sessions_with_candidates": len(per_session),
                },
            },
            ensure_ascii=False,
            indent=1,
        )
    )


# ---------------------------------------------------------------- sweep


def prior_captures(session_id: str) -> list:
    """Wisdom entries already written from this session (feedforward dedup)."""
    store = Path(WISDOM_SYSTEM_STORE)
    if not store.exists():
        return []
    out = []
    for line in store.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if rec.get("origin_session") != session_id:
            continue
        if (rec.get("status") or "active") in ("superseded", "retracted"):
            continue
        out.append(
            {
                "id": rec.get("id"),
                "type": rec.get("type"),
                "body": truncate(rec.get("body") or rec.get("content") or "", 200),
            }
        )
    return out


def extract_json_object(text: str):
    start = text.find("{")
    if start == -1:
        return None
    decoder = json.JSONDecoder()
    idx = start
    while idx != -1:
        try:
            obj, _ = decoder.raw_decode(text[idx:])
            return obj
        except json.JSONDecodeError:
            idx = text.find("{", idx + 1)
    return None


def load_prompt() -> str:
    prompt_path = Path(__file__).resolve().parent / "analyst-prompt.md"
    return prompt_path.read_text()


def run_analyst(args, session_id: str, digest_path: str, prior: list) -> dict:
    digest_text = Path(digest_path).read_text()
    message = (
        f"{load_prompt()}\n\nSESSION_ID: {session_id}\n\n"
        f"ALREADY CAPTURED from this session (do NOT re-emit; emit only explicit"
        f" contradictions):\n{json.dumps(prior, ensure_ascii=False)}\n\n"
        f"DIGEST:\n{digest_text}"
    )
    cmd = [
        "timeout",
        str(args.analyst_timeout),
        "opencode",
        "run",
        "--dir",
        args.workdir,
        "--model",
        args.model,
        "--title",
        f"{ANALYST_TITLE_PREFIX} analyze {session_id}",
        message,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"analyst exit {proc.returncode}: {truncate(proc.stderr or proc.stdout, 300)}"
        )
    obj = extract_json_object(proc.stdout)
    if obj is None:
        raise RuntimeError("analyst produced no parseable JSON object")
    return obj


def valid_candidate(cand) -> bool:
    if not isinstance(cand, dict):
        return False
    if cand.get("route") not in ("wisdom", "proposal", "none"):
        return False
    if cand.get("type") not in ("gotcha", "pattern", "fact", "decision", "warning", None):
        return False
    if cand.get("confidence") not in ("high", "medium", "low", None):
        return False
    if cand.get("relationship") not in ("new", "duplicate", "complements", "contradicts", None):
        return False
    return True


def cmd_sweep(args) -> None:
    state = Path(args.state_dir)
    digest_dir = state / "digests"
    workdir = Path(args.workdir)
    for d in (state, digest_dir, workdir):
        d.mkdir(parents=True, exist_ok=True)
    ledger_path = str(state / "ledger.jsonl")

    # 1. Select
    selected = []
    select_args = argparse.Namespace(
        db=args.db,
        ledger=ledger_path,
        stale_hours=args.stale_hours,
        limit=args.limit,
        workdir=str(workdir),
        subagent_cap=args.subagent_cap,
        subagent_agents=args.subagent_agents,
    )
    import io
    from contextlib import redirect_stdout

    buf = io.StringIO()
    with redirect_stdout(buf):
        cmd_select(select_args)
    for line in buf.getvalue().splitlines():
        if line.strip():
            selected.append(json.loads(line))

    canonical = [s for s in selected if not s.get("covered_by")]
    forks = [s for s in selected if s.get("covered_by")]
    for fork in forks:
        append_ledger(
            ledger_path,
            {
                "session_id": fork["session_id"],
                "last_time_updated": fork["time_updated"],
                "digest_sha256": None,
                "status": "covered",
                "covered_by": fork["covered_by"],
                "candidate_ids": [],
                "attempts": 1,
            },
        )

    written = proposals = analyst_failures = none_count = 0
    obligation_units: list = []
    all_candidates_path = state / "run-candidates.jsonl"
    all_candidates_path.write_text("")

    # 2. Digest + analyst per session
    for s in canonical:
        sid = s["session_id"]
        digest_path = str(digest_dir / f"{sid}.json")
        try:
            conn = connect_ro(args.db)
            digest = build_digest(conn, sid)
        except Exception as exc:  # noqa: BLE001 — record and continue
            append_ledger(
                ledger_path,
                {
                    "session_id": sid,
                    "last_time_updated": s["time_updated"],
                    "digest_sha256": None,
                    "status": "analyst_failed",
                    "error": truncate(str(exc), 200),
                    "candidate_ids": [],
                    "attempts": ledger_attempts(ledger_path, sid) + 1,
                },
            )
            analyst_failures += 1
            continue
        Path(digest_path).write_text(json.dumps(digest, ensure_ascii=False))
        digest_sha = hashlib.sha256(
            json.dumps(digest, ensure_ascii=False).encode()
        ).hexdigest()

        for unit in digest.get("launched_units", []):
            if unit not in obligation_units:
                obligation_units.append(unit)

        if args.dry_run:
            append_ledger(
                ledger_path,
                {
                    "session_id": sid,
                    "last_time_updated": s["time_updated"],
                    "digest_sha256": digest_sha,
                    "status": "dry_run",
                    "candidate_ids": [],
                    "attempts": 1,
                },
            )
            continue

        try:
            result = run_analyst(args, sid, digest_path, prior_captures(sid))
        except Exception as exc:  # noqa: BLE001
            append_ledger(
                ledger_path,
                {
                    "session_id": sid,
                    "last_time_updated": s["time_updated"],
                    "digest_sha256": digest_sha,
                    "status": "analyst_failed",
                    "error": truncate(str(exc), 200),
                    "candidate_ids": [],
                    "attempts": ledger_attempts(ledger_path, sid) + 1,
                },
            )
            analyst_failures += 1
            continue

        raw_candidates = result.get("candidates") or []
        candidates = [c for c in raw_candidates if valid_candidate(c)]
        with open(all_candidates_path, "a") as fh:
            fh.write(
                json.dumps({"session_id": sid, "candidates": candidates}, ensure_ascii=False)
                + "\n"
            )
        obligations = result.get("obligations") or []
        status = "no_candidates" if not candidates else "analyzed"
        if not candidates:
            none_count += 1
        append_ledger(
            ledger_path,
            {
                "session_id": sid,
                "last_time_updated": s["time_updated"],
                "digest_sha256": digest_sha,
                "status": status,
                "obligations": obligations if isinstance(obligations, list) else [],
                "candidate_ids": [],
                "attempts": 1,
            },
        )

    # 3. Rank + write
    if all_candidates_path.exists() and all_candidates_path.stat().st_size > 0:
        rank_args = argparse.Namespace(
            candidates=str(all_candidates_path),
            global_cap=args.global_cap,
            per_session_cap=args.per_session_cap,
        )
        import io as _io
        from contextlib import redirect_stdout as _rso

        rbuf = _io.StringIO()
        with _rso(rbuf):
            cmd_rank(rank_args)
        ranking = json.loads(rbuf.getvalue())
    else:
        ranking = {"selected": [], "dropped": [], "counts": {"selected": 0}}

    session_rows = {s["session_id"]: s for s in canonical}
    for item in ranking["selected"]:
        sid = item["session_id"]
        cand = item["candidate"]
        tags = ["session-learning", cand.get("type") or "fact"]
        if cand.get("route") == "proposal":
            tags.append(f"proposal:{cand.get('proposal_kind', 'policy')}")
        cmd = [
            WISDOM_CLOSEOUT,
            "--no-supersede",
            "--scope",
            "system",
            "--type",
            cand.get("type") or "fact",
            "--tags",
            ",".join(tags),
            "--session-id",
            sid,
            "--source",
            "closeout:sweep",
            "--content",
            cand["claim"],
        ]
        if args.dry_run:
            written += 1
            continue
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            new_id = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else ""
            if cand.get("route") == "proposal":
                proposals += 1
            else:
                written += 1
            ledger_bump_candidates(ledger_path, sid, new_id)
        else:
            analyst_failures += 1  # reuse failure counter for write failures
            append_ledger(
                ledger_path,
                {
                    "session_id": sid,
                    "last_time_updated": session_rows.get(sid, {}).get("time_updated"),
                    "digest_sha256": None,
                    "status": "write_failed",
                    "error": truncate(proc.stderr, 200),
                    "candidate_ids": [],
                    "attempts": 1,
                },
            )

    # 4. Obligation check (deterministic)
    active_obligations = []
    for unit in obligation_units:
        probe = subprocess.run(
            ["systemctl", "--user", "is-active", unit], capture_output=True, text=True
        )
        if probe.returncode == 0 and probe.stdout.strip() == "active":
            active_obligations.append(unit)

    counts = ranking["counts"]
    summary = (
        f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} "
        f"sweep analyzed={len(canonical)} forks_covered={len(forks)} "
        f"written={written} proposals={proposals} none={none_count} "
        f"failures={analyst_failures} selected={counts.get('selected', 0)} "
        f"dropped={counts.get('dropped', 0)} "
        f"active_obligations={','.join(active_obligations) or '-'}"
    )
    with open(args.log, "a") as fh:
        fh.write(summary + "\n")
    print(summary)


def ledger_attempts(ledger_path: str, session_id: str) -> int:
    return load_ledger(ledger_path).get(session_id, {}).get("attempts", 0)


def ledger_bump_candidates(ledger_path: str, session_id: str, new_id: str) -> None:
    """Append candidate id to the session's latest ledger row (rewrite file)."""
    rows_out = []
    p = Path(ledger_path)
    for line in p.read_text().splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("session_id") == session_id:
            ids = row.get("candidate_ids") or []
            if new_id:
                ids.append(new_id)
            row["candidate_ids"] = ids
        rows_out.append(json.dumps(row, ensure_ascii=False))
    p.write_text("\n".join(rows_out) + ("\n" if rows_out else ""))


# ---------------------------------------------------------------- cli


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("--db", default=DEFAULT_DB)
        p.add_argument(
            "--ledger", default=os.path.join(DEFAULT_STATE_DIR, "ledger.jsonl")
        )

    p_select = sub.add_parser("select")
    common(p_select)
    p_select.add_argument("--stale-hours", type=float, default=6)
    p_select.add_argument("--limit", type=int, default=8)
    p_select.add_argument("--workdir", default=DEFAULT_WORKDIR)
    p_select.add_argument("--subagent-cap", type=int, default=0)
    p_select.add_argument("--subagent-agents", default="oracle,Momus,general")
    p_select.set_defaults(func=cmd_select)
    p_select.set_defaults(func=cmd_select)

    p_digest = sub.add_parser("digest")
    common(p_digest)
    p_digest.add_argument("--session", required=True)
    p_digest.add_argument("--out", default=None)
    p_digest.set_defaults(func=cmd_digest)

    p_rank = sub.add_parser("rank")
    p_rank.add_argument("--candidates", required=True)
    p_rank.add_argument("--global-cap", type=int, default=6)
    p_rank.add_argument("--per-session-cap", type=int, default=3)
    p_rank.set_defaults(func=cmd_rank)

    p_sweep = sub.add_parser("sweep")
    common(p_sweep)
    p_sweep.add_argument("--state-dir", default=DEFAULT_STATE_DIR)
    p_sweep.add_argument("--workdir", default=DEFAULT_WORKDIR)
    p_sweep.add_argument("--log", default=DEFAULT_LOG)
    p_sweep.add_argument("--model", default=DEFAULT_MODEL)
    p_sweep.add_argument("--stale-hours", type=float, default=6)
    p_sweep.add_argument("--limit", type=int, default=8)
    p_sweep.add_argument("--global-cap", type=int, default=6)
    p_sweep.add_argument("--per-session-cap", type=int, default=3)
    p_sweep.add_argument("--analyst-timeout", type=int, default=900)
    p_sweep.add_argument("--subagent-cap", type=int, default=3)
    p_sweep.add_argument("--subagent-agents", default="oracle,Momus,general")
    p_sweep.add_argument("--dry-run", action="store_true")
    p_sweep.set_defaults(func=cmd_sweep)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
