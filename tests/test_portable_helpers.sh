#!/usr/bin/env bash
# Unit test for the portable helpers in scripts/wisdom/wisdom-common.sh.
# Verifies happy paths, malformed-input handling, failure injection, and the
# stdin-buffering + mode-preservation invariants that the BSD/macOS fallbacks
# rely on. Passes on Linux with all assertions including PATH-shim failure
# injection.
set -euo pipefail

source "$(dirname "$0")/../scripts/wisdom/wisdom-common.sh"

# Scratch cleanup (set -u-safe against declared-empty arrays).
_CLEANUP_DIRS=()
_CLEANUP_FILES=()
cleanup() {
    if [ "${#_CLEANUP_FILES[@]}" -gt 0 ]; then
        for f in "${_CLEANUP_FILES[@]}"; do rm -f "$f"; done
    fi
    if [ "${#_CLEANUP_DIRS[@]}" -gt 0 ]; then
        for d in "${_CLEANUP_DIRS[@]}"; do rm -rf "$d"; done
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. wisdom_portable_now_ms — numeric AND within ±2000ms of python3 reference
# ---------------------------------------------------------------------------
now_ms="$(wisdom_portable_now_ms)"
ref_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
[[ "$now_ms" =~ ^[0-9]+$ ]] || { echo "FAIL: now_ms not numeric: $now_ms" >&2; exit 1; }
delta=$((now_ms - ref_ms))
[ "$delta" -ge 0 ] || delta=$((-delta))
[ "$delta" -le 2000 ] || { echo "FAIL: now_ms delta $delta exceeds 2000ms (now=$now_ms ref=$ref_ms)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. wisdom_portable_epoch_from_iso — valid ISO equals GNU date
# ---------------------------------------------------------------------------
got="$(wisdom_portable_epoch_from_iso "2020-01-01T00:00:00Z")"
want="$(date -d "2020-01-01T00:00:00Z" +%s)"
[ "$got" = "$want" ] || { echo "FAIL: epoch_from_iso(valid) got=$got want=$want" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 3. wisdom_portable_epoch_from_iso — malformed input yields 0
# ---------------------------------------------------------------------------
got="$(wisdom_portable_epoch_from_iso "not-a-date")"
[ "$got" = "0" ] || { echo "FAIL: epoch_from_iso(malformed) got=$got want=0" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 4. wisdom_portable_epoch_days_ago — within ±60s of GNU date -d "-7 days"
# ---------------------------------------------------------------------------
got="$(wisdom_portable_epoch_days_ago 7)"
want="$(date -d "-7 days" +%s)"
delta=$((got - want))
[ "$delta" -ge 0 ] || delta=$((-delta))
[ "$delta" -le 60 ] || { echo "FAIL: epoch_days_ago(7) delta $delta exceeds 60s (got=$got want=$want)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 5. wisdom_portable_iso_utc_plus_days — exact match with GNU date
# ---------------------------------------------------------------------------
got="$(wisdom_portable_iso_utc_plus_days 30)"
want="$(date -u -d "+30 days" +%Y-%m-%dT%H:%M:%SZ)"
[ "$got" = "$want" ] || { echo "FAIL: iso_utc_plus_days(30) got=$got want=$want" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 6. PATH-shim failure injection — bad `date` → iso_utc_plus_days nonzero,
#    empty output (no "now" fallback that would create overdue review_due).
# ---------------------------------------------------------------------------
tmpbin="$(mktemp -d)"; _CLEANUP_DIRS+=("$tmpbin")
cat > "$tmpbin/date" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$tmpbin/date"
set +e
shim_out="$(PATH="$tmpbin:$PATH" wisdom_portable_iso_utc_plus_days 30 2>/dev/null)"
shim_rc=$?
set -e
[ "$shim_rc" -ne 0 ] || { echo "FAIL: iso_utc_plus_days should exit nonzero with failing date, rc=$shim_rc" >&2; exit 1; }
[ -z "$shim_out" ] || { echo "FAIL: iso_utc_plus_days should emit no output on total failure, got=$shim_out" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 7. wisdom_portable_b64_decode — decodes aGVsbG8= to hello
# ---------------------------------------------------------------------------
got="$(printf 'aGVsbG8=' | wisdom_portable_b64_decode)"
[ "$got" = "hello" ] || { echo "FAIL: b64_decode got=$got want=hello" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 8. b64 buffering — shim base64 -d to fail; -D fallback must still see stdin.
#    Proves _input="$(cat)" buffers once (naive retry would consume stdin).
# ---------------------------------------------------------------------------
real_base64="$(command -v base64)"
cat > "$tmpbin/base64" <<SH
#!/usr/bin/env bash
if [ "\$1" = "-d" ]; then
    exit 1
elif [ "\$1" = "-D" ]; then
    "$real_base64" -d
else
    exit 1
fi
SH
chmod +x "$tmpbin/base64"
got="$(printf 'aGVsbG8=' | PATH="$tmpbin:$PATH" wisdom_portable_b64_decode)"
[ "$got" = "hello" ] || { echo "FAIL: b64 buffering/fallback got=$got want=hello (stdin not buffered or fallback broken)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 9. wisdom_portable_sed_inplace — rewrites content AND preserves 0644 mode
# ---------------------------------------------------------------------------
tmpfile="$(mktemp)"; _CLEANUP_FILES+=("$tmpfile")
printf 'foo\n' > "$tmpfile"
chmod 0644 "$tmpfile"
wisdom_portable_sed_inplace 's/foo/bar/' "$tmpfile"
content="$(cat "$tmpfile")"
[ "$content" = "bar" ] || { echo "FAIL: sed_inplace content got=$content want=bar" >&2; exit 1; }
mode="$(stat -c %a "$tmpfile")"
[ "$mode" = "644" ] || { echo "FAIL: sed_inplace mode not preserved got=$mode want=644" >&2; exit 1; }

echo "All portable helper assertions passed"
