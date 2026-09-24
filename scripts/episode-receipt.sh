#!/usr/bin/env bash
#
# episode-receipt.sh — episode manifest receipt mechanism (schema v0.2)
#
# Plan: .omo/plans/workflow-standardization.md §Architecture 1-3 (W1.1).
#
# Manifest: .omo/episodes/<slug>/manifest.yaml — schema v0.2. Machine-managed
# manifests are written as canonical JSON (jq -S), which is a valid YAML
# subset; human-authored YAML manifests (schema v0.1 probe) are never rewritten
# by this script.
#
# Manifest schema v0.2 (JSON shape):
#   {
#     "schema": "0.2",
#     "episode": "<slug>", "project": "<path>", "intent": "<text>",
#     "started": "<ISO8601>", "status": "active|paused|closed|superseded",
#     "lane": "full|lite|in-session", "owner": "<agent-or-human>",
#     "current_phase": "<phase name>",
#     "phases": [ { "name": "...", "status": "pending|in_progress|done",
#                   "receipts": [ <receipt>... ], "sessions": [ "ses_..." ] } ],
#     "learnings":  [ { "seq", "phase", "kind", "claim", "evidence_refs", "scope" } ],
#     "follow_ups": [ { "id", "text", "mandatory" } ]
#   }
#
# Receipt schema (append-only, sequence-numbered, monotonic across the manifest):
#   {
#     "seq": <int>,                     # assigned by append, under flock
#     "ts": "<ISO8601>",                # append time
#     "phase": "<phase name>",          # must exist in phases[]
#     "kind": "receipt|checkpoint",
#     "claims": [ "<text>"... ],        # non-empty array of strings
#     "evidence": [ <evidence entry>... ],
#     "session": "<ses_...>|null",
#     "resume_pointer": "<text>|null",  # checkpoints only
#     "verified": null|true|false,      # null=pending, set by verify
#     "verified_reason": null|"<evidence-missing|digest-mismatch|...>"
#   }
# Evidence entries:
#   file evidence:      { "path": "<abs file path>", "sha256": "<hex>" }
#                       sha256 = hash of file bytes at append time
#   session evidence:   { "path": "msg:<message-id>", "sha256": "<hex>",
#                         "excerpt": "<quoted excerpt>" }
#                       sha256 = hash of the excerpt's UTF-8 bytes; verify
#                       recomputes it over the stored excerpt.
#
# Subcommands:
#   append  <episode_dir> [--phase P] --claims '<json array>' [--evidence-refs p1,p2]
#           [--session ses_x] [--checkpoint] [--intent T] [--resume-pointer '<text>']
#       Canonicalizes receipt JSON (jq -S), hashes evidence at append time,
#       validates against schema v0.2, appends under flock on
#       <episode_dir>/.lock, assigns monotonic seq. Atomic write (tmp + mv).
#       --evidence-refs is an exact alias of --evidence; each ref is EITHER an
#       existing file path (hashed from file bytes) OR a bounded session-evidence
#       ref of the exact form `msg:<message-id>|<quoted excerpt>` (comma-separated
#       list; excerpts must not contain commas). --resume-pointer sets the
#       receipt's resume_pointer (checkpoints).
#       --checkpoint: with no manifest, auto-creates a minimal v0.2 manifest
#       (lane in-session, single "session" phase) and puts the receipt in it —
#       single source of truth, no sidecar files. --intent required in that case.
#       With --checkpoint, --phase defaults to "session"; on an existing manifest
#       the (defaulted or given) phase must exist in phases[] as usual.
#   verify  <episode_dir>
#       Consumer-side check: manifest schema validity (incl. phase status values
#       and learnings[]/follow_ups[] entry structure), full receipt schema
#       validity per receipt, evidence existence + digest match (files: file
#       bytes; msg: refs: stored excerpt bytes), phase-transition legality
#       (receipt.phase must exist in phases[]; seq unique + monotonic).
#       Unresolvable evidence (missing file) → receipt KEPT, marked
#       "verified": false (degraded). Writes updated verified flags under flock.
#   advance <episode_dir> <to_phase>
#       Runs verify in-process (same flock acquisition — single lock per
#       command); moves the phase pointer ONLY after a passing verify (current
#       phase → done, to_phase → in_progress, current_phase updated). Refuses
#       otherwise. There is no manual-advance path.
#   lint   <episode_dir>
#       Read-only hygiene check; flags, never fabricates or fixes:
#         (a) stale active episode: status active AND last activity
#             (last_verify.ts or newest receipt ts, falling back to started)
#             older than 7 days;
#         (b) missing checkpoint: status active with no kind:"checkpoint" receipt.
#
# Exit codes:
#   0  success (verify: all receipts verified; lint: no findings)
#   1  usage error / invalid input / internal error; lint: findings raised
#   2  verify hard failure (schema invalid, digest mismatch / tampered evidence)
#   3  verify degraded (unresolvable evidence; receipts kept, verified:false)
#   4  advance refused (verify did not pass / illegal transition)
#
# Dependencies: bash >= 4.3, jq, sha256sum, flock. No network, no ports.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

die_usage() {
    echo "usage error: $*" >&2
    exit 1
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

manifest_path() {
    local dir="$1"
    printf '%s/manifest.yaml' "$dir"
}

require_manifest() {
    local dir="$1" mp
    mp="$(manifest_path "$dir")"
    [[ -f "$mp" ]] || die_usage "no manifest at $mp (use append --checkpoint to auto-create)"
    printf '%s' "$mp"
}

# Acquire the episode lock on fd 9. Caller must hold it for the whole
# read-compute-write cycle and close with release_lock.
acquire_lock() {
    local dir="$1"
    exec 9>"$dir/.lock"
    flock 9
}

release_lock() {
    exec 9>&- 2>/dev/null || true
}

sha256_of_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'  # macOS fallback
    fi
}

# Validate manifest against schema v0.2 (structural). Echo "ok" or error text; rc!=0 on failure.
manifest_schema_errors() {
    local mp="$1"
    jq -e '
        . as $m
        | ($m.schema == "0.2")
        and ($m.episode | type == "string" and length > 0)
        and ($m.project | type == "string")
        and ($m.intent | type == "string")
        and ($m.started | type == "string")
        and (["active","paused","closed","superseded"] | index($m.status))
        and (["full","lite","in-session"] | index($m.lane))
        and ($m.owner | type == "string")
        and ($m.phases | type == "array" and length > 0)
        and ($m.phases | all((.name | type == "string" and length > 0)
            and (.status as $st | (["pending","in_progress","done"] | index($st)))
            and (.receipts | type == "array")
            and (.sessions | type == "array")))
        and (($m.learnings // []) | type == "array"
             and all((.seq | type == "number")
                 and (.phase | type == "string")
                 and (.kind | type == "string")
                 and (.claim | type == "string" and length > 0)
                 and (.evidence_refs | type == "array")
                 and (.scope | type == "string")))
        and (($m.follow_ups // []) | type == "array"
             and all((.id | type == "string" and length > 0)
                 and (.text | type == "string" and length > 0)
                 and (.mandatory | type == "boolean")))
    ' "$mp" >/dev/null 2>&1 && { echo ok; return 0; }
    echo "manifest fails schema v0.2: $mp"
    return 1
}

# Validate a receipt object (jq input). rc!=0 + message on failure.
receipt_schema_errors() {
    local r="$1"
    printf '%s' "$r" | jq -e '
        . as $o
        | ($o.seq | type == "number")
        and ($o.ts | type == "string")
        and ($o.phase | type == "string" and length > 0)
        and (["receipt","checkpoint"] | index($o.kind))
        and ($o.claims | type == "array" and length > 0 and all(type == "string"))
        and ($o.evidence | type == "array"
             and all((.path | type == "string")
                 and (.sha256 | type == "string")
                 and ((.excerpt // null) | (. == null or type == "string"))))
        and (($o.session // null) | (. == null or type == "string"))
    ' >/dev/null 2>&1 && return 0
    echo "receipt fails schema: $r"
    return 1
}

next_seq() {
    echo '[.phases[].receipts[].seq] | (max // 0) + 1'
}

cmd_append() {
    local dir="" phase="" claims="" evidence="" session="" checkpoint=false intent="" resume=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase) phase="${2:?}"; shift 2 ;;
            --claims) claims="${2:?}"; shift 2 ;;
            --evidence|--evidence-refs) evidence="${2:?}"; shift 2 ;;
            --session) session="${2:?}"; shift 2 ;;
            --intent) intent="${2:?}"; shift 2 ;;
            --checkpoint) checkpoint=true; shift ;;
            --resume-pointer) resume="${2:?}"; shift 2 ;;
            *) [[ -z "$dir" ]] || die_usage "unexpected arg: $1"; dir="$1"; shift ;;
        esac
    done
    [[ -n "$dir" ]] || die_usage "append <episode_dir> [--phase P] --claims '<json array>' [...]"
    # --phase optional with --checkpoint: default 'session' (matches auto-created manifest)
    if [[ -z "$phase" ]]; then
        $checkpoint || die_usage "append: --phase required (or use --checkpoint for default 'session')"
        phase="session"
    fi
    [[ -n "$claims" ]] || die_usage "append: --claims required"
    mkdir -p "$dir"

    # Validate claims input early
    printf '%s' "$claims" | jq -e 'type == "array" and length > 0 and all(type == "string")' >/dev/null \
        || die_usage "--claims must be a non-empty JSON array of strings"

    # Lock BEFORE any manifest read or write (checkpoint auto-create included)
    acquire_lock "$dir"

    local mp; mp="$(manifest_path "$dir")"
    if [[ ! -f "$mp" ]]; then
        $checkpoint || die_usage "no manifest at $mp (append --checkpoint auto-creates one)"
        [[ -n "$intent" ]] || die_usage "--checkpoint auto-create requires --intent"
        local slug; slug="$(basename "$dir")"
        local mtmp="$mp.tmp"
        jq -S -n \
            --arg episode "$slug" \
            --arg project "$PWD" \
            --arg intent "$intent" \
            --arg started "$(now_iso)" \
            '{
                schema: "0.2", episode: $episode, project: $project, intent: $intent,
                started: $started, status: "active", lane: "in-session", owner: "agent",
                current_phase: "session",
                phases: [{name: "session", status: "in_progress", receipts: [], sessions: []}],
                learnings: [], follow_ups: []
            }' > "$mtmp" && mv "$mtmp" "$mp" || die_usage "failed to auto-create manifest at $mp"
    fi

    manifest_schema_errors "$mp" >/dev/null || die_usage "$(manifest_schema_errors "$mp")"

    # Hash evidence at append time: file path → file bytes; msg:<id>|<excerpt> → excerpt bytes
    local ev_json='[]'
    if [[ -n "$evidence" ]]; then
        local IFS=','
        for p in $evidence; do
            local abs digest mtmp
            if [[ "$p" == msg:* && "$p" == *"|"* ]]; then
                local mid="${p%%|*}" excerpt="${p#*|}"
                digest="$(printf '%s' "$excerpt" | sha256_of_stdin)"
                ev_json="$(printf '%s' "$ev_json" | jq -c --arg p "$mid" --arg d "$digest" --arg e "$excerpt" \
                    '. + [{path: $p, sha256: $d, excerpt: $e}]')" \
                    || die_usage "failed to encode msg evidence ref: $p"
            else
                [[ -f "$p" ]] || die_usage "evidence file not found: $p"
                abs="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
                digest="$(sha256_of_stdin < "$p")"
                ev_json="$(printf '%s' "$ev_json" | jq -c --arg p "$abs" --arg d "$digest" \
                    '. + [{path: $p, sha256: $d}]')" \
                    || die_usage "failed to encode evidence entry: $p"
            fi
        done
        unset IFS
    fi

    local kind="receipt"
    $checkpoint && kind="checkpoint"

    local seq
    seq="$(jq -r "$(next_seq)" "$mp")" || die_usage "failed to compute next seq in $mp"

    local receipt
    receipt="$(jq -S -c -n \
        --argjson seq "$seq" \
        --arg ts "$(now_iso)" \
        --arg phase "$phase" \
        --arg kind "$kind" \
        --argjson claims "$claims" \
        --argjson evidence "$ev_json" \
        --arg sess "${session:-}" \
        --arg res "${resume:-}" \
        '{
            seq: $seq, ts: $ts, phase: $phase, kind: $kind,
            claims: $claims, evidence: $evidence,
            session: (if ($sess | length) == 0 then null else $sess end),
            resume_pointer: (if ($res | length) == 0 then null else $res end), verified: null, verified_reason: null
        }')" || die_usage "failed to build receipt JSON"
    receipt_schema_errors "$receipt" >/dev/null || die_usage "$(receipt_schema_errors "$receipt")"

    # Phase-transition legality: receipt phase must exist in manifest phases[]
    jq -e --arg p "$phase" '.phases | any(.name == $p)' "$mp" >/dev/null \
        || die_usage "unknown phase '$phase' (not in manifest phases[])"

    local tmp="$mp.tmp"
    jq --argjson r "$receipt" --arg s "${session:-}" '
        ($s | length) as $slen |
        if ($slen > 0 and ((.phases[] | select(.name == $r.phase) | .sessions | index($s)) == null)) then
            (.phases[] | select(.name == $r.phase) | .sessions) += [$s]
        else . end
        | (.phases[] | select(.name == $r.phase) | .receipts) += [$r]
    ' "$mp" > "$tmp" && mv "$tmp" "$mp" || die_usage "failed to append receipt to $mp"

    echo "appended seq=$seq phase=$phase kind=$kind"
    release_lock
}

# Pure check (no lock management — caller MUST hold the episode lock).
# Reads, computes, and writes verified flags while the lock is held.
# Returns 0 pass, 2 hard, 3 degraded. Echo findings.
run_verify() {
    local dir="$1" mp; mp="$(require_manifest "$dir")"
    local rc=0

    manifest_schema_errors "$mp" >/dev/null || { echo "$(manifest_schema_errors "$mp")"; return 2; }

    # Per-receipt schema + cross-receipt invariants
    if ! jq -e '
        (([.phases[].receipts[].seq] | length) == ([.phases[].receipts[].seq] | unique | length))  # seq unique
        and ([.phases[].receipts[].seq] == ([.phases[].receipts[].seq] | sort))                 # monotonic
    ' "$mp" >/dev/null 2>&1; then
        echo "receipt invariants failed (seq uniqueness/monotonicity) in $mp"
        return 2
    fi
    # receipt.phase must exist in phases[]
    local orphan
    orphan="$(jq -r '. as $m | .phases[].receipts[] | .phase as $p | select(($m.phases | any(.name == $p)) | not) | .seq' "$mp")" \
        || { echo "verify: failed to scan receipt phases in $mp"; return 2; }
    if [[ -n "$orphan" ]]; then
        echo "receipt references unknown phase (seq=$orphan)"
        return 2
    fi

    # Full receipt schema validation, per receipt (base64-framed records so
    # paths/excerpts with tabs or newlines cannot corrupt framing)
    local rfile
    rfile="$(mktemp)"
    if ! jq -r '.phases[].receipts[] | tojson | @base64' "$mp" > "$rfile" 2>/dev/null; then
        rm -f "$rfile"
        echo "verify: failed to enumerate receipts in $mp"
        return 2
    fi
    local bad_receipt=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local rec
        rec="$(printf '%s' "$line" | base64 -d 2>/dev/null)" || { bad_receipt="<undecodable receipt>"; break; }
        if ! receipt_schema_errors "$rec" >/dev/null 2>&1; then
            bad_receipt="$(printf '%s' "$rec" | jq -r '.seq' 2>/dev/null || echo '?')"
            break
        fi
    done < "$rfile"
    rm -f "$rfile"
    if [[ -n "$bad_receipt" ]]; then
        echo "receipt schema violation (seq=$bad_receipt) in $mp"
        return 2
    fi

    # Evidence checks per receipt. Records are base64-framed (one per line):
    # no program-string interpolation of seq/path/digest into jq.
    local efile
    efile="$(mktemp)"
    if ! jq -r '.phases[].receipts[]
            | .seq as $s
            | .evidence[]
            | {seq: $s, path: .path, sha256: .sha256, excerpt: (.excerpt // "")}
            | tojson | @base64' "$mp" > "$efile" 2>/dev/null; then
        rm -f "$efile"
        echo "verify: failed to enumerate evidence in $mp"
        return 2
    fi

    local findings="" results='[]'
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        local rec seq path want excerpt got ok
        rec="$(printf '%s' "$line" | base64 -d 2>/dev/null)" || { rm -f "$efile"; echo "verify: corrupt evidence record in $mp"; return 2; }
        seq="$(printf '%s' "$rec" | jq -r '.seq')" || { rm -f "$efile"; echo "verify: bad evidence record in $mp"; return 2; }
        path="$(printf '%s' "$rec" | jq -r '.path')" || { rm -f "$efile"; echo "verify: bad evidence record in $mp"; return 2; }
        want="$(printf '%s' "$rec" | jq -r '.sha256')" || { rm -f "$efile"; echo "verify: bad evidence record in $mp"; return 2; }
        excerpt="$(printf '%s' "$rec" | jq -r '.excerpt')" || { rm -f "$efile"; echo "verify: bad evidence record in $mp"; return 2; }
        if [[ "$path" == msg:* ]]; then
            got="$(printf '%s' "$excerpt" | sha256_of_stdin)"
        elif [[ -f "$path" ]]; then
            got="$(sha256_of_stdin < "$path")"
        else
            findings+="degraded: seq=$seq evidence missing: $path"$'\n'
            results="$(jq -cn --argjson rs "$results" --argjson s "$seq" \
                '$rs + [{seq: $s, ok: "missing"}]')" || { rm -f "$efile"; return 2; }
            [[ $rc -eq 2 ]] || rc=3
            continue
        fi
        if [[ "$got" != "$want" ]]; then
            findings+="hard: seq=$seq digest mismatch: $path"$'\n'
            ok="mismatch"
        else
            ok="pass"
        fi
        results="$(jq -cn --argjson rs "$results" --argjson s "$seq" --arg ok "$ok" \
            '$rs + [{seq: $s, ok: $ok}]')" || { rm -f "$efile"; return 2; }
        if [[ "$ok" == "mismatch" ]]; then rc=2; fi
    done < "$efile"
    rm -f "$efile"

    # Write verified flags (still under the caller's lock) via tmp+mv.
    local tmp="$mp.tmp"
    if ! jq --argjson results "$results" --arg ts "$(now_iso)" --argjson rc "$rc" '
        reduce $results[] as $r (.;
            (.phases[].receipts[] | select(.seq == $r.seq) | .verified) = ($r.ok == "pass")
            | (.phases[].receipts[] | select(.seq == $r.seq) | .verified_reason)
                = (if $r.ok == "pass" then null
                   elif $r.ok == "missing" then "evidence-missing"
                   else "digest-mismatch" end))
        | .last_verify = {ts: $ts,
            result: (if $rc == 0 then "pass" elif $rc == 2 then "hard-fail" else "degraded" end)}
    ' "$mp" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "verify: failed to write verified flags to $mp"
        return 2
    fi
    if ! mv "$tmp" "$mp"; then
        echo "verify: failed to replace manifest $mp"
        return 2
    fi

    printf '%s' "$findings"
    return "$rc"
}

cmd_verify() {
    local dir="${1:?usage: verify <episode_dir>}"
    acquire_lock "$dir"
    local rc=0
    run_verify "$dir" || rc=$?
    release_lock
    if [[ $rc -eq 0 ]]; then
        echo "verify: PASS"
    elif [[ $rc -eq 3 ]]; then
        echo "verify: DEGRADED (unresolvable evidence; receipts kept, verified:false)"
    else
        echo "verify: HARD FAIL"
    fi
    return "$rc"
}

cmd_advance() {
    local dir="${1:?usage: advance <episode_dir> <to_phase>}" to="${2:?usage: advance <episode_dir> <to_phase>}"
    local mp; mp="$(require_manifest "$dir")"

    # Single lock acquisition covers verify + advance write.
    acquire_lock "$dir"

    if ! jq -e --arg p "$to" '.phases | any(.name == $p)' "$mp" >/dev/null 2>&1; then
        release_lock
        echo "advance refused: unknown phase '$to'"
        return 4
    fi

    local vrc=0
    run_verify "$dir" >/dev/null || vrc=$?
    if [[ $vrc -ne 0 ]]; then
        release_lock
        echo "advance refused: verify did not pass (rc=$vrc)"
        return 4
    fi

    local tmp="$mp.tmp"
    if ! jq --arg to "$to" '. as $m |
        (.phases[] | select(.name == $m.current_phase) | .status) = "done"
        | (.phases[] | select(.name == $to) | .status) = "in_progress"
        | .current_phase = $to
    ' "$mp" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        release_lock
        echo "advance: failed to write manifest $mp"
        return 1
    fi
    if ! mv "$tmp" "$mp"; then
        release_lock
        echo "advance: failed to replace manifest $mp"
        return 1
    fi
    release_lock
    echo "advanced to $to"
}

cmd_lint() {
    local dir="${1:?usage: lint <episode_dir>}"
    local mp; mp="$(require_manifest "$dir")"

    local findings=0
    if jq -e '.status == "active"' "$mp" >/dev/null 2>&1; then
        # Last activity: last_verify.ts or newest receipt ts, falling back to started
        local last_epoch now
        last_epoch="$(jq -r '
            ([(.last_verify.ts // null)] + [.phases[].receipts[].ts] + [.started])
            | map(select(. != null))
            | map(fromdateiso8601) | max // 0' "$mp" 2>/dev/null)" || { echo "lint: failed to read timestamps in $mp"; return 1; }
        now="$(date -u +%s)"
        if (( now - last_epoch > 7 * 24 * 3600 )); then
            echo "lint: stale active episode: $dir (no activity in >7 days)"
            findings=1
        fi
        local has_cp
        has_cp="$(jq -r '[.phases[].receipts[] | select(.kind == "checkpoint")] | length > 0' "$mp" 2>/dev/null)" \
            || { echo "lint: failed to scan receipts in $mp"; return 1; }
        if [[ "$has_cp" != "true" ]]; then
            echo "lint: active episode has no checkpoint receipt: $dir"
            findings=1
        fi
    fi
    if [[ $findings -eq 0 ]]; then
        echo "lint: ok"
    fi
    return "$findings"
}

case "${1:-}" in
    append) shift; cmd_append "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    advance) shift; cmd_advance "$@" ;;
    lint) shift; cmd_lint "$@" ;;
    *) die_usage "$SCRIPT_NAME {append|verify|advance|lint} ..." ;;
esac
