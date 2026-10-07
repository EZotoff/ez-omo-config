#!/usr/bin/env bash
# git-hygiene.sh — unpushed-work monitor backing the tiered push discipline
# (plugins/agent-git-workflow.ts "Push discipline" section, 2026-10-05).
#
# What it does:
#   - Scans known workspace roots for git repos with recent activity
#     (last commit <= MAX_AGE days).
#   - Classifies each repo's origin by ownership: PERSONAL (URL contains
#     /<OWNER>/), SHARED (any other owner), or NO-REMOTE.
#   - Reports unpushed commit counts (current branch + other local branches).
#   - MODE=observe (default): report only — no network writes.
#   - MODE=push: for PERSONAL repos only, push the CURRENT branch when it has
#     an upstream. Plain `git push` semantics: non-fast-forward pushes FAIL
#     and are reported as DIVERGED — force is never attempted (git-safety
#     blocks it interactively; this script never passes --force either).
#     SHARED and NO-REMOTE repos are never pushed, only reported.
#
# Rollout: shipped in observe mode. Enabling MODE=push is a gate unlock per
# docs/rollout-protocol.md — edit the systemd unit's Environment= line and
# `systemctl --user daemon-reload` (see systemd/user/git-hygiene.*).
#
# Env:
#   GIT_HYGIENE_MODE    observe|push                 (default: observe)
#   GIT_HYGIENE_ROOTS   colon-separated repo roots   (default: ~/:~/AI_projects:~/src:~/projects)
#   GIT_HYGIENE_OWNER   remote-owner path segment    (default: EZotoff)
#   GIT_HYGIENE_MAX_AGE activity filter, days        (default: 60)
#   GIT_HYGIENE_STATE   state dir                    (default: ~/.local/state/git-hygiene)
#
# Output: human report on stdout (journal via systemd); one JSON object per
# repo appended to $STATE/log.jsonl; full report snapshot at $STATE/report.txt.
# Exit codes: 0 = scan completed (piles are reported, not fatal);
#             2 = invocation/infrastructure error.

set -euo pipefail

MODE="${GIT_HYGIENE_MODE:-observe}"
OWNER="${GIT_HYGIENE_OWNER:-EZotoff}"
MAX_AGE="${GIT_HYGIENE_MAX_AGE:-60}"
STATE="${GIT_HYGIENE_STATE:-$HOME/.local/state/git-hygiene}"
ROOTS="${GIT_HYGIENE_ROOTS:-$HOME:$HOME/AI_projects:$HOME/src:$HOME/projects}"

if [[ "$MODE" != "observe" && "$MODE" != "push" ]]; then
    echo "git-hygiene: invalid GIT_HYGIENE_MODE '$MODE' (observe|push)" >&2
    exit 2
fi

mkdir -p "$STATE"
REPORT_TMP="$(mktemp)"
NOW=$(date +%s)

json_escape() { printf '%s' "$1" | tr -d '"' | tr '\n' ' '; }

log_json() { # key=value pairs already JSON-safe
    printf '%s\n' "$1" >> "$STATE/log.jsonl"
}

repo_class() { # $1 = origin URL
    local url="$1"
    if [[ "$url" == *"/$OWNER/"* || "$url" == *":$OWNER/"* ]]; then
        echo PERSONAL
    else
        echo SHARED
    fi
}

pushed_count=0
diverged_count=0
skipped_shared=0
no_remote_count=0
observed_piles=0

for root in ${ROOTS//:/ }; do
    [[ -d "$root" ]] || continue
    while IFS= read -r gitdir; do
        repo="$(dirname "$gitdir")"
        # activity filter
        lc=$(git -C "$repo" log -1 --format=%ct 2>/dev/null) || continue
        [[ -n "${lc:-}" ]] || continue
        age=$(( (NOW - lc) / 86400 ))
        [[ $age -le $MAX_AGE ]] || continue

        br=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
        origin_url=$(git -C "$repo" remote get-url origin 2>/dev/null) || origin_url=""

        # unpushed on current branch
        if [[ -n "$origin_url" ]] && git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            unpushed=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null) || unpushed="?"
            ahead_of_up_origin=$(git -C "$repo" rev-list --count 'HEAD..@{u}' 2>/dev/null) || ahead_of_up_origin=0
        else
            unpushed="NO-UPSTREAM"
            ahead_of_up_origin=0
        fi

        # unpushed on other local branches (report-only, never auto-pushed)
        other=""
        while IFS= read -r b; do
            [[ "$b" == "$br" ]] && continue
            bu=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "$b@{u}" 2>/dev/null) || continue
            n=$(git -C "$repo" rev-list --count "$bu..$b" 2>/dev/null) || continue
            [[ "$n" -gt 0 ]] && other="$other $b:$n"
        done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
        [[ -n "$other" ]] || other="-"

        if [[ -z "$origin_url" ]]; then
            cls=NO-REMOTE
            action=report
            no_remote_count=$((no_remote_count + 1))
            [[ "$unpushed" != "0" && "$unpushed" != "NO-UPSTREAM" ]] && observed_piles=$((observed_piles + 1))
            line="NO-REMOTE   $repo [$br] unpushed=$unpushed other:$other — commits are machine-local"
        else
            cls=$(repo_class "$origin_url")
            if [[ "$cls" == "PERSONAL" ]]; then
                if [[ "$MODE" == "push" && "$unpushed" =~ ^[0-9]+$ && "$unpushed" -gt 0 ]]; then
                    if git -C "$repo" push origin >/dev/null 2>&1; then
                        action=pushed
                        pushed_count=$((pushed_count + 1))
                        line="PUSHED      $repo [$br] pushed $unpushed commit(s) to origin"
                    else
                        action=diverged
                        diverged_count=$((diverged_count + 1))
                        line="DIVERGED    $repo [$br] push rejected (non-FF) — needs merge/rebase decision, NOT forced"
                    fi
                else
                    action=observe
                    [[ "$unpushed" =~ ^[0-9]+$ && "$unpushed" -gt 0 ]] && observed_piles=$((observed_piles + 1))
                    line="PERSONAL    $repo [$br] unpushed=$unpushed behind=$ahead_of_up_origin other:$other mode=$MODE"
                fi
            else
                action=report
                skipped_shared=$((skipped_shared + 1))
                [[ "$unpushed" =~ ^[0-9]+$ && "$unpushed" -gt 0 ]] && observed_piles=$((observed_piles + 1))
                line="SHARED      $repo [$br] unpushed=$unpushed other:$other — fork-push only (Tier B), never auto-pushed"
            fi
        fi

        printf '%s\n' "$line" | tee -a "$REPORT_TMP"
        log_json "{\"ts\":$(date +%s),\"repo\":\"$(json_escape "$repo")\",\"class\":\"$cls\",\"branch\":\"$(json_escape "$br")\",\"unpushed\":\"$unpushed\",\"other\":\"$(json_escape "$other")\",\"mode\":\"$MODE\",\"action\":\"$action\"}"
    done < <(find "$root" -maxdepth 3 -name .git \( -type d -o -type f \) 2>/dev/null)
done | sort

{
    echo "---"
    echo "summary: mode=$MODE repos-with-piles=$observed_piles pushed=$pushed_count diverged=$diverged_count shared-reported=$skipped_shared no-remote=$no_remote_count"
} | tee -a "$REPORT_TMP"

cp "$REPORT_TMP" "$STATE/report.txt"
rm -f "$REPORT_TMP"
exit 0
