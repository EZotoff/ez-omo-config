#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

scan_file="$(mktemp)"
env_file="$(mktemp)"
trap 'rm -f "$scan_file" "$env_file"' EXIT

(
    cd "$REPO_ROOT" || exit 1

    for path in commands configs plugins skills scripts extras install.sh README.md MANIFEST.md LICENSE; do
        if [[ -d "$path" ]]; then
            find "$path" -type f -print
        elif [[ -f "$path" ]]; then
            printf '%s\n' "$path"
        fi
    done | sort -u
) > "$scan_file"

assert_file_exists "$REPO_ROOT/install.sh"
assert_file_exists "$REPO_ROOT/README.md"
assert_file_exists "$REPO_ROOT/MANIFEST.md"
assert_file_exists "$REPO_ROOT/LICENSE"
assert_dir_exists "$REPO_ROOT/commands"
assert_dir_exists "$REPO_ROOT/configs"
assert_dir_exists "$REPO_ROOT/plugins"
assert_dir_exists "$REPO_ROOT/skills"
assert_dir_exists "$REPO_ROOT/scripts"
assert_dir_exists "$REPO_ROOT/extras"

assert_grep '^commands/' "$scan_file"
assert_grep '^configs/' "$scan_file"
assert_grep '^plugins/' "$scan_file"
assert_grep '^skills/' "$scan_file"
assert_grep '^scripts/' "$scan_file"
assert_grep '^extras/' "$scan_file"
assert_grep '^install\.sh$' "$scan_file"
assert_grep '^README\.md$' "$scan_file"
assert_grep '^MANIFEST\.md$' "$scan_file"
assert_grep '^LICENSE$' "$scan_file"

assert_no_grep '^tests/' "$scan_file"
assert_no_grep '^docs/' "$scan_file"
assert_no_grep '/tests/' "$scan_file"
assert_no_grep '/docs/' "$scan_file"

while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    absolute_path="$REPO_ROOT/$relative_path"

    assert_no_grep 'sk-[[:alnum:]]' "$absolute_path"
    assert_no_grep 'OPENAI_API_KEY' "$absolute_path"
    assert_no_grep 'ghp_[[:alnum:]]' "$absolute_path"
    assert_no_grep 'gho_[[:alnum:]]' "$absolute_path"
    assert_no_grep 'AIza[[:alnum:]_-]' "$absolute_path"
    assert_no_grep 'BEGIN.*PRIVATE KEY' "$absolute_path"
    assert_no_grep 'password[[:space:]]*=' "$absolute_path"
    assert_no_grep '/home/ezotoff' "$absolute_path"
    assert_no_grep '/Users/ezotoff' "$absolute_path"
done < "$scan_file"

(
    cd "$REPO_ROOT" || exit 1
    find . \( -path './.git' -o -path './.git/*' \) -prune -o -name '.env*' -print | sort
) > "$env_file"

assert_no_grep '.' "$env_file"

echo "Public safety checks: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
