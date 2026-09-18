#!/usr/bin/env bash
# parse-opencode-version.sh — shared version helpers for the -p<generation>
# suffix scheme from the patch-provenance plan (OPENCODE_VERSION=<upstream>-p<gen>,
# e.g. 1.18.5-p1).
#
# Sourced, not executed. Consumers:
#   scripts/build-and-install-opencode.sh (build version baking + compat gate)
# Planned consumers (Task 5): scripts/verify-live-patches.sh versions_match must
# accept <upstream>-p<N> in addition to <upstream> (see Task-5 note).

# opencode_version_base <version> — strip a trailing -p<digits> suffix.
# 1.18.5-p1 -> 1.18.5 ; 1.18.5 -> 1.18.5 ; 1.18.5-preview unchanged (no digit).
opencode_version_base() {
    printf '%s\n' "${1%%-p[0-9]*}"
}

# opencode_version_compatible <upstream> <actual> — true iff actual equals
# <upstream> exactly or <upstream> with a -p<N> generation suffix. Leading 'v'
# on actual is ignored. unknown/empty actual is NOT compatible.
opencode_version_compatible() {
    local upstream="$1" actual="$2"
    [[ -n "$actual" && "$actual" != "unknown" ]] || return 1
    actual="${actual#v}"
    [[ "$actual" == "$upstream" ]] && return 0
    [[ "$actual" == "$upstream"-p[0-9]* ]] && [[ ! "$actual" =~ -p[0-9]*[a-z] ]]
}

# opencode_version_generation <version> — print the integer of a trailing
# -p<N> suffix, or nothing when the version carries no suffix.
opencode_version_generation() {
    local actual="${1#v}"
    if [[ "$actual" =~ -p([0-9]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}
