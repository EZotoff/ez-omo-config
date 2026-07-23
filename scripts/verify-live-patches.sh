#!/usr/bin/env bash
# verify-live-patches.sh — verify every tracked patch is present in a binary or install tree.
#
# Usage:
#   scripts/verify-live-patches.sh                         # verify live state (binary + plugin cache)
#   scripts/verify-live-patches.sh <binary-path>           # verify a candidate opencode binary before swap
#   scripts/verify-live-patches.sh --tree <install-path>   # verify a candidate install tree (e.g. OMO node_modules)
#   scripts/verify-live-patches.sh --json                  # machine-readable output
#
# Reads .sisyphus/patches/*.md frontmatter and runs each verification_pattern against
# the resolved target. Reports APPLIED / STALE / MISSING-TARGET / VERSION-DRIFT.
#
# Exit codes:
#   0  all patches APPLIED, no version drift
#   1  one or more patches STALE, MISSING-TARGET, or VERSION-DRIFT
#   2  usage error or registry unreadable
#
# See AGENTS.md "Patching OpenCode Binary" → NEVER #4: this script is the gate
# referenced by that rule.

set -euo pipefail

# Resolve repo root: prefer $EZ_OMO_CONFIG_REPO, then walk up looking for .sisyphus/patches/
# Final fallback: known repo path (single-user config repo)
REPO_ROOT="${EZ_OMO_CONFIG_REPO:-}"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/.sisyphus/patches" ]]; then
  cur="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for i in 1 2 3 4 5; do
    if [[ -d "$cur/.sisyphus/patches" ]]; then
      REPO_ROOT="$cur"
      break
    fi
    cur="$(dirname "$cur")"
    [[ "$cur" == "/" ]] && break
  done
fi
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/.sisyphus/patches" ]]; then
  REPO_ROOT="$HOME/ez-omo-config"
fi
PATCH_DIR="$REPO_ROOT/.sisyphus/patches"
OPENCODE_BIN="${HOME}/.opencode/bin/opencode"
OMO_CACHE_ROOT="${HOME}/snap/alacritty/common/.cache/opencode/packages"

# ---- arg parsing -----------------------------------------------------------
MODE="live"
TARGET=""
OUTPUT="text"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tree)   MODE="tree"; TARGET="${2:-}"; shift 2 ;;
    --json)   OUTPUT="json"; shift ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*)      echo "unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$TARGET" && "$MODE" == "live" ]]; then
        MODE="binary"
        TARGET="$1"
        shift
      else
        echo "unexpected argument: $1" >&2
        exit 2
      fi ;;
  esac
done

# ---- helpers ---------------------------------------------------------------
# yaml_frontmatter_value <file> <key> → prints first value, strips quotes
yaml_frontmatter_value() {
  local file="$1" key="$2"
  awk -v k="$key" '
    /^---$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^"k":" {
      sub("^"k": *", "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$file"
}

# resolve_runtime_version <dependency> → prints version string (or empty)
# Reads opencode.json to determine if dep is loaded via file:// (use that path's package.json)
# or @version (use npm cache). Falls back to npm cache if config unreadable.
# This is the fix for the two-source-of-truth trap identified in the 2026-07-23 handoff:
# target_install_path in patch entries may point at a fork while runtime loads from
# elsewhere. Config is the source of truth for which path is actually loaded.
resolve_runtime_version() {
  local dep="$1"
  local cfg="$HOME/.config/opencode/opencode.json"
  # Try to find a file:// reference for this dep in the config first
  local file_ref=""
  if [[ -f "$cfg" ]]; then
    file_ref=$(python3 -c "
import json, sys
try:
    d = json.load(open('$cfg'))
    for p in d.get('plugin', []):
        if 'file://' in p and ('$dep' in p or ('oh-my-openagent' in p and '$dep' in ('oh-my-openagent','oh-my-opencode'))):
            print(p.replace('file://',''))
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null)
  fi
  if [[ -n "$file_ref" && -f "$file_ref/package.json" ]]; then
    python3 -c "import json; d=json.load(open('$file_ref/package.json')); print(d.get('version',''))" 2>/dev/null || true
    return
  fi
  # Fall back to known dep→path patterns
  case "$dep" in
    opencode)
      [[ -x "$OPENCODE_BIN" ]] && "$OPENCODE_BIN" --version 2>/dev/null || true
      ;;
    oh-my-openagent|oh-my-opencode)
      local pkg="${OMO_CACHE_ROOT}/oh-my-openagent@latest/node_modules/oh-my-openagent/package.json"
      [[ -f "$pkg" ]] && python3 -c "import json,sys; d=json.load(open('$pkg')); print(d.get('version',''))" 2>/dev/null || true
      ;;
    opencode-dcp)
      [[ -x "$OPENCODE_BIN" ]] && "$OPENCODE_BIN" --version 2>/dev/null || true
      ;;
    *)
      local pkg="${OMO_CACHE_ROOT}/oh-my-openagent@latest/node_modules/${dep}/package.json"
      [[ -f "$pkg" ]] && python3 -c "import json,sys; d=json.load(open('$pkg')); print(d.get('version',''))" 2>/dev/null || true
      ;;
  esac
}

# resolve_runtime_install_path <dependency> → prints the actual loaded install path
# (file:// target if config uses it, otherwise target_install_path from the patch entry)
resolve_runtime_install_path() {
  local dep="$1" fallback="$2"
  local cfg="$HOME/.config/opencode/opencode.json"
  if [[ -f "$cfg" ]]; then
    local file_ref=$(python3 -c "
import json, sys
try:
    d = json.load(open('$cfg'))
    for p in d.get('plugin', []):
        if 'file://' in p and ('$dep' in p or ('oh-my-openagent' in p and '$dep' in ('oh-my-openagent','oh-my-opencode'))):
            print(p.replace('file://',''))
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null)
    if [[ -n "$file_ref" ]]; then
      echo "$file_ref"
      return
    fi
  fi
  echo "$fallback"
}

# version_matches <runtime> <spec> → 0 if matches, 1 otherwise
# Spec format: "X.Y.Z", ">=X.Y.Z", etc.
version_matches() {
  local runtime="$1" spec="$2"
  [[ -z "$runtime" || -z "$spec" ]] && return 1
  if [[ "$spec" =~ ^\>= ]]; then
    # >=X.Y.Z — simple comparison
    local target="${spec:2}"
    [[ "$(printf '%s\n%s\n' "$target" "$runtime" | sort -V | head -1)" == "$target" ]]
  elif [[ "$spec" =~ ^\> ]]; then
    local target="${spec:1}"
    [[ "$runtime" != "$target" ]] && [[ "$runtime" > "$target" ]]
  else
    # exact match
    [[ "$runtime" == "$spec" ]]
  fi
}

# ---- main ------------------------------------------------------------------
if [[ ! -d "$PATCH_DIR" ]]; then
  echo "no .sisyphus/patches/ at $PATCH_DIR — nothing to verify" >&2
  exit 0
fi

# Collect results
declare -a results
declare -i total=0 applied=0 stale=0 missing=0 drift=0

# Binary-style patches: target_file points at a single binary path; verification
# runs grep -c on the bytes.
# Tree-style patches: target_install_path is a directory; target_file is relative.

while IFS= read -r entry; do
  [[ -z "$entry" || "$(basename "$entry")" == "TEMPLATE.md" ]] && continue
  total+=1

  patch_id="$(yaml_frontmatter_value "$entry" patch_id)"
  dep="$(yaml_frontmatter_value "$entry" dependency)"
  target_ver="$(yaml_frontmatter_value "$entry" dep_version)"
  target_file="$(yaml_frontmatter_value "$entry" target_file)"
  target_install_path="$(yaml_frontmatter_value "$entry" target_install_path)"
  pattern="$(yaml_frontmatter_value "$entry" verification_pattern)"

  # Resolve target install path - PREFER config-resolved runtime path over entry's target_install_path
  # This fixes the two-source-of-truth bug: target_install_path may point at a fork while
  # runtime loads from npm cache (or vice versa). The runtime path is what matters.
  runtime_path=""
  if [[ "$MODE" == "live" ]]; then
    runtime_path="$(resolve_runtime_install_path "$dep" "$target_install_path")"
  else
    runtime_path="$target_install_path"
  fi

  case "$dep" in
    opencode|opencode-dcp)
      # Binary-style: verify against $OPENCODE_BIN unless we were given a candidate
      if [[ "$MODE" == "binary" ]]; then
        check_path="$TARGET"
        runtime_ver="$(\"$TARGET\" --version 2>/dev/null || echo 'unknown')"
      elif [[ "$MODE" == "tree" ]]; then
        check_path="$TARGET"
        runtime_ver="tree-mode"
      else
        check_path="$OPENCODE_BIN"
        runtime_ver="$(resolve_runtime_version "$dep")"
      fi
      ;;
    *)
      # Tree-style: prefer runtime path resolved from config
      if [[ "$MODE" == "binary" || "$MODE" == "tree" ]]; then
        check_path="${TARGET%/}/${target_file%%,*}"
      else
        check_path="${runtime_path%/}/${target_file%%,*}"
        runtime_ver="$(resolve_runtime_version "$dep")"
      fi
      ;;
  esac

  # target_file may be comma-separated list — check the first one
  first_target_file="${target_file%%,*}"
  if [[ "$dep" != "opencode" && "$dep" != "opencode-dcp" ]]; then
    if [[ "$MODE" == "binary" || "$MODE" == "tree" ]]; then
      check_path="${TARGET%/}/$first_target_file"
    else
      check_path="${runtime_path%/}/$first_target_file"
    fi
  fi

  # target_file may be comma-separated list — check the first one
  first_target_file="${target_file%%,*}"
  if [[ "$dep" != "opencode" && "$dep" != "opencode-dcp" ]]; then
    if [[ "$MODE" == "binary" || "$MODE" == "tree" ]]; then
      check_path="${TARGET%/}/$first_target_file"
    else
      check_path="${target_install_path%/}/$first_target_file"
    fi
  fi

  # Status determination
  status=""
  if [[ "$MODE" == "live" && "$dep" != "opencode" && "$dep" != "opencode-dcp" ]]; then
    # Version-drift check (tree-style only)
    if ! version_matches "$runtime_ver" "$target_ver"; then
      status="VERSION-DRIFT"
      drift+=1
    fi
  fi

  if [[ -z "$status" ]]; then
    if [[ ! -e "$check_path" ]]; then
      status="MISSING-TARGET"
      missing+=1
    elif [[ -f "$check_path" ]]; then
      # Binary file (size matters) → use python regex on bytes
      if [[ "$dep" == "opencode" || "$dep" == "opencode-dcp" ]]; then
        if python3 -c "
import re, sys
data = open('$check_path', 'rb').read()
text = data.decode('utf-8', errors='ignore')
sys.exit(0 if re.search('''$pattern''', text) else 1)
" 2>/dev/null; then
          status="APPLIED"
          applied+=1
        else
          status="STALE"
          stale+=1
        fi
      else
        # Text file → grep -E
        if grep -qE "$pattern" "$check_path" 2>/dev/null; then
          status="APPLIED"
          applied+=1
        else
          status="STALE"
          stale+=1
        fi
      fi
    else
      status="MISSING-TARGET"
      missing+=1
    fi
  fi

  results+=("$patch_id|$dep|$target_ver|$runtime_ver|$status|$check_path")
done < <(find "$PATCH_DIR" -name '*.md' -type f | sort)

# ---- output ----------------------------------------------------------------
if [[ "$OUTPUT" == "json" ]]; then
  printf '['
  for i in "${!results[@]}"; do
    IFS='|' read -r pid dep tver rver status path <<<"${results[$i]}"
    [[ $i -gt 0 ]] && printf ','
    printf '{"patch_id":"%s","dependency":"%s","target_version":"%s","runtime_version":"%s","status":"%s","path":"%s"}' \
      "$pid" "$dep" "$tver" "$rver" "$status" "$path"
  done
  printf ']\n'
else
  printf '%-55s %-18s %-10s %-10s %-15s %s\n' "PATCH_ID" "DEP" "TARGET" "RUNTIME" "STATUS" "PATH"
  printf '%.0s-' {1..150}; printf '\n'
  for r in "${results[@]}"; do
    IFS='|' read -r pid dep tver rver status path <<<"$r"
    printf '%-55s %-18s %-10s %-10s %-15s %s\n' "$pid" "$dep" "$tver" "$rver" "$status" "$path"
  done
  printf '\nSummary: %d total | %d applied | %d stale | %d missing-target | %d version-drift\n' \
    "$total" "$applied" "$stale" "$missing" "$drift"
fi

# Exit 0 only if everything is APPLIED and no drift
if [[ $applied -eq $total && $drift -eq 0 ]]; then
  exit 0
else
  exit 1
fi
