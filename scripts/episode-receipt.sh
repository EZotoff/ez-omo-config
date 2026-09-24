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
#     "evidence": [ { "path": "<abs>", "sha256": "<hex>" }... ],
#     "session": "<ses_...>|null",
#     "resume_pointer": "<text>|null",  # checkpoints only
#     "verified": null|true|false,      # null=pending, set by verify
#     "verified_reason": null|"<evidence-missing|digest-mismatch|...>"
#   }
#
# Subcommands:
#   append  <episode_dir> --phase P --claims '<json array>' [--evidence p1,p2]
#          [--session ses_x] [--checkpoint] [--intent T]
#       Canonicalizes receipt JSON (jq -S), hashes evidence file bytes (sha256)
#       at append time, validates against schema v0.2, appends under flock on
#       <episode_dir>/.lock, assigns monotonic seq. Atomic write (tmp + mv).
#       --checkpoint: with no manifest, auto-creates a minimal v0.2 manifest
#       (lane in-session, single "session" phase) and puts the receipt in it —
#       single source of truth, no sidecar files. --intent required in that case.
#   verify  <episode_dir>
#       Consumer-side check: manifest schema validity, receipt schema validity,
#       evidence-file existence + sha256 digest match, phase-transition legality
#       (receipt.phase must exist in phases[]; seq unique + monotonic).
#       Unresolvable evidence (missing file) → receipt KEPT, marked
#       "verified": false (degraded). Writes updated verified flags under flock.
#   advance <episode_dir> <to_phase>
#       Runs verify in-process; moves the phase pointer ONLY after a passing
#       verify (current phase → done, to_phase → in_progress, current_phase
#       updated). Refuses otherwise. There is no manual-advance path.
#
# Exit codes:
#   0  success (verify: all receipts verified)
#   1  usage error / invalid input / internal error
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

# Validate manifest against schema v0.2 (structural). Echo "ok" or error text; rc!=0 on failure.
manifest_schema_errors() {
    local mp="$1"
    jq -e '
        .schema == "0.2"
        and (.episode | type == "string" and length > 0)
        and (.project | type == "string")
        and (.intent | type == "string")
        and (.started | type == "string")
        and (["active","paused","closed","superseded"] | index(.status))
        and (["full","lite","in-session"] | index(.lane))
        and (.owner | type == "string")
        and (.phases | type == "array" and length > 0)
        and (.phases | all(.name | type == "string" and length > 0))
        and (.phases | all(.status | type == "string"))
        and (.phases | all(.receipts | type == "array"))
        and (.phases | all(.sessions | type == "array"))
        and ((.learnings // []) | type == "array")
        and ((.follow_ups // []) | type == "array")
    ' "$mp" >/dev/null 2>&1 && { echo ok; return 0; }
    echo "manifest fails schema v0.2: $mp"
    return 1
}

# Validate a receipt object (jq input). rc!=0 + message on failure.
receipt_schema_errors() {
    local r="$1"
    printf '%s' "$r" | jq -e '
        (.seq | type == "number")
        and (.ts | type == "string")
        and (.phase | type == "string" and length > 0)
        and (["receipt","checkpoint"] | index(.kind))
        and (.claims | type == "array" and length > 0 and all(type == "string"))
        and (.evidence | type == "array"
             and all((.path | type == "string") and (.sha256 | type == "string")))
        and ((.session // null) | (. == null or type == "string"))
    ' >/dev/null 2>&1 && return 0
    echo "receipt fails schema: $r"
    return 1
}

next_seq() {
    jq '[.phases[].receipts[].seq] | (max // 0) + 1'
}

cmd_append() {
    local dir="" phase="" claims="" evidence="" session="" checkpoint=false intent=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase) phase="${2:?}"; shift 2 ;;
            --claims) claims="${2:?}"; shift 2 ;;
            --evidence) evidence="${2:?}"; shift 2 ;;
            --session) session="${2:?}"; shift 2 ;;
            --intent) intent="${2:?}"; shift 2 ;;
            --checkpoint) checkpoint=true; shift ;;
            *) [[ -z "$dir" ]] || die_usage "unexpected arg: $1"; dir="$1"; shift ;;
        esac
    done
    [[ -n "$dir" ]] || die_usage "append <episode_dir> --phase P --claims '<json array>' [...]"
    [[ -n "$phase" ]] || die_usage "append: --phase required"
    [[ -n "$claims" ]] || die_usage "append: --claims required"
    mkdir -p "$dir"

    # Validate claims input early
    printf '%s' "$claims" | jq -e 'type == "array" and length > 0 and all(type == "string")' >/dev/null \
        || die_usage "--claims must be a non-empty JSON array of strings"

    local mp="$(manifest_path "$dir")"
    if [[ ! -f "$mp" ]]; then
        $checkpoint || die_usage "no manifest at $mp (append --checkpoint auto-creates one)"
        [[ -n "$intent" ]] || die_usage "--checkpoint auto-create requires --intent"
        local slug; slug="$(basename "$dir")"
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
            }' > "$mp"
    fi

    manifest_schema_errors "$mp" >/dev/null || die_usage "$(manifest_schema_errors "$mp")"

    # Hash evidence file bytes at append time
    local ev_json='[]'
    if [[ -n "$evidence" ]]; then
        local IFS=','
        for p in $evidence; do
            [[ -f "$p" ]] || die_usage "evidence file not found: $p"
            local abs digest
            abs="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
            if command -v sha256sum >/dev/null 2>&1; then
                digest="$(sha256sum "$p" | awk '{print $1}')"
            else
                digest="$(shasum -a 256 "$p" | awk '{print $1}')"  # macOS fallback
            fi
            ev_json="$(printf '%s' "$ev_json" | jq -c --arg p "$abs" --arg d "$digest" '. + [{path: $p, sha256: $d}]')"
        done
        unset IFS
    fi

    local kind="receipt"
    $checkpoint && kind="checkpoint"

    exec 9>"$dir/.lock"
    flock 9

    local seq
    seq="$(jq -r "$(next_seq)" "$mp")"

    local receipt
    receipt="$(jq -S -c -n \
        --argjson seq "$seq" \
        --arg ts "$(now_iso)" \
        --arg phase "$phase" \
        --arg kind "$kind" \
        --argjson claims "$claims" \
        --argjson evidence "$ev_json" \
        --argjson session "${session:-null}" \
        '{
            seq: $seq, ts: $ts, phase: $phase, kind: $kind,
            claims: $claims, evidence: $evidence, session: $session,
            resume_pointer: null, verified: null, verified_reason: null
        }')"
    receipt_schema_errors "$receipt" >/dev/null || die_usage "$(receipt_schema_errors "$receipt")"

    # Phase-transition legality: receipt phase must exist in manifest phases[]
    jq -e --arg p "$phase" '.phases | any(.name == $p)' "$mp" >/dev/null \
        || die_usage "unknown phase '$phase' (not in manifest phases[])"

    local tmp="$mp.tmp"
    jq --argjson r "$receipt" --argjson s "${session:-null}" '
        if $s != null and ((.phases[] | select(.name == $r.phase) | .sessions | index($s)) == null) then
            (.phases[] | select(.name == $r.phase) | .sessions) += [$s]
        else . end
        | (.phases[] | select(.name == $r.phase) | .receipts) += [$r]
    ' "$mp" > "$tmp" && mv "$tmp" "$mp"

    echo "appended seq=$seq phase=$phase kind=$kind"
    exec 9>&-
}

# Pure check (no writes). Returns 0 pass, 2 hard, 3 degraded. Echo findings.
run_verify() {
    local dir="$1" mp; mp="$(require_manifest "$dir")"
    local rc=0

    manifest_schema_errors "$mp" >/dev/null || { echo "$(manifest_schema_errors "$mp")"; return 2; }

    # Per-receipt schema + cross-receipt invariants
    if ! jq -e '
        ([.phases[].receipts[].seq] | length == ([.phases[].receipts[].seq] | unique | length))  # seq unique
        and ([.phases[].receipts[] | .seq] == ([.phases[].receipts[] | .seq] | sort))                 # monotonic
    ' "$mp" >/dev/null 2>&1; then
        echo "receipt invariants failed (seq uniqueness/monotonicity) in $mp"
        return 2
    fi
    local bad
    bad="$(jq -r '.phases[].receipts[] | select((.claims | type != "array") or (.claims | length == 0)) | .seq' "$mp" || true)"
    if [[ -n "$bad" ]]; then
        echo "receipt schema violation (claims) seq=$bad"
        return 2
    fi
    # receipt.phase must exist in phases[]
    local orphan
    orphan="$(jq -r '. as $m | .phases[].receipts[] | select(($m.phases | any(.name == .phase)) | not) | .seq' "$mp")"
    if [[ -n "$orphan" ]]; then
        echo "receipt references unknown phase (seq=$orphan)"
        return 2
    fi

    # Evidence checks per receipt
    local updated='.' findings=""
    while IFS=$'\t' read -r seq path want; do
        if [[ ! -f "$path" ]]; then
            findings+="degraded: seq=$seq evidence missing: $path"$'\n'
            updated+=" | (.phases[].receipts[] | select(.seq == $seq) | .verified) = false"
            updated+=" | (.phases[].receipts[] | select(.seq == $seq) | .verified_reason) = \"evidence-missing\""
            rc=3
        else
            local got
            if command -v sha256sum >/dev/null 2>&1; then
                got="$(sha256sum "$path" | awk '{print $1}')"
            else
                got="$(shasum -a 256 "$path" | awk '{print $1}')"
            fi
            if [[ "$got" != "$want" ]]; then
                findings+="hard: seq=$seq digest mismatch: $path"$'\n'
                updated+=" | (.phases[].receipts[] | select(.seq == $seq) | .verified) = false"
                updated+=" | (.phases[].receipts[] | select(.seq == $seq) | .verified_reason) = \"digest-mismatch\""
                rc=2
            else
                updated+=" | (.phases[].receipts[] | select(.seq == $seq) | .verified) = true"
                updated+=" | (.phases[].receipts[] | select(.seq == $seq) | .verified_reason) = null"
            fi
        fi
    done < <(jq -r '.phases[].receipts[] | .seq as $s | .evidence[] | "\($s)\t\(.path)\t\(.sha256)"' "$mp")

    # Write verified flags under flock (manifest rewritten only via tmp+mv)
    exec 9>"$dir/.lock"
    flock 9
    local tmp="$mp.tmp"
    jq "$updated | .last_verify = {ts: \"$(now_iso)\", result: (if $rc == 0 then \"pass\" elif $rc == 2 then \"hard-fail\" else \"degraded\" end)}" "$mp" > "$tmp" && mv "$tmp" "$mp"
    exec 9>&-

    printf '%s' "$findings"
    return "$rc"
}

cmd_verify() {
    local dir="${1:?usage: verify <episode_dir>}"
    local rc=0
    run_verify "$dir" || rc=$?
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
    jq -e --arg p "$to" '.phases | any(.name == $p)' "$mp" >/dev/null \
        || { echo "advance refused: unknown phase '$to'"; return 4; }

    local vrc=0
    run_verify "$dir" >/dev/null || vrc=$?
    if [[ $vrc -ne 0 ]]; then
        echo "advance refused: verify did not pass (rc=$vrc)"
        return 4
    fi

    exec 9>"$dir/.lock"
    flock 9
    local tmp="$mp.tmp"
    jq --arg to "$to" '. as $m |
        (.phases[] | select(.name == $m.current_phase) | .status) = "done"
        | (.phases[] | select(.name == $to) | .status) = "in_progress"
        | .current_phase = $to
    ' "$mp" > "$tmp" && mv "$tmp" "$mp"
    exec 9>&-
    echo "advanced to $to"
}

case "${1:-}" in
    append) shift; cmd_append "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    advance) shift; cmd_advance "$@" ;;
    *) die_usage "$SCRIPT_NAME {append|verify|advance} ..." ;;
esac
