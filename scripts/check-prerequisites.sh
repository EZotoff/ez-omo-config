#!/usr/bin/env bash
# check-prerequisites.sh — Verify the host has everything needed to run the
# ez-omo-config stack. Run this after `./install.sh` to catch missing
# prerequisites before starting OpenCode.
set -euo pipefail

PASS=0
WARN=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$1"; WARN=$((WARN+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "=== ez-omo-config Prerequisites Check ==="
echo

# --- Core runtime ---
echo "Core Runtime"

if command -v opencode &>/dev/null; then
  ok "OpenCode CLI: $(opencode --version 2>/dev/null || echo 'installed')"
else
  fail "OpenCode CLI not found. Install: https://opencode.ai"
fi

if command -v bun &>/dev/null; then
  ok "bun: $(bun --version)"
else
  fail "bun not found. OpenCode uses bun for TypeScript plugin loading. Install: https://bun.sh"
fi

# jq (worktree hooks, wisdom scripts)
if command -v jq &>/dev/null; then ok "jq: $(jq --version)"
else
  fail "jq not found. Required by worktree hooks and wisdom scripts.
    macOS:  brew install jq
    Debian/Ubuntu/WSL:  sudo apt-get install -y jq
    Fedora:  sudo dnf install -y jq
  Install: https://stedolan.github.io/jq/download/"
fi

# python3 (auth.json parsing, helper fallbacks)
if command -v python3 &>/dev/null; then ok "python3: $(python3 --version 2>&1)"
else
  fail "python3 not found. Required by check-prerequisites and wisdom portable helpers.
    macOS:  brew install python
    Debian/Ubuntu/WSL:  sudo apt-get install -y python3"
fi

# Bash version (wisdom scripts use local -n namerefs → 4.3+)
if [[ "${BASH_VERSINFO[0]:-0}" -gt 4 || ( "${BASH_VERSINFO[0]:-0}" -eq 4 && "${BASH_VERSINFO[1]:-0}" -ge 3 ) ]]; then
  ok "bash: ${BASH_VERSION}"
else
  fail "bash ${BASH_VERSION} is too old. Wisdom scripts require bash 4.3+ (namerefs).
    macOS stock /bin/bash is 3.2 — install Homebrew bash:
      brew install bash, then ensure /opt/homebrew/bin/bash (or /usr/local/bin/bash) is first in PATH
    Linux:  sudo apt-get install -y bash (or distro equivalent)"
fi

echo

# --- OMO (npm package) ---
echo "Oh-My-OpenAgent"

OMO_CACHE="$HOME/.cache/opencode/packages/oh-my-openagent@latest"
if [ -d "$OMO_CACHE" ]; then
  ok "oh-my-openagent@latest in npm cache ($OMO_CACHE)"
else
  warn "oh-my-openagent@latest not found in cache. It will be auto-installed on first OpenCode launch."
fi

echo

# --- Config files ---
echo "Configuration Files"

CONFIG_DIR="$HOME/.config/opencode"
PLUGIN_DIR="$HOME/.opencode/plugin"

for f in \
  "$CONFIG_DIR/opencode.json" \
  "$CONFIG_DIR/oh-my-openagent.json" \
  "$CONFIG_DIR/provider-connect-retry.mjs" \
  "$CONFIG_DIR/retry-errors.json" \
  "$CONFIG_DIR/AGENTS.md" \
  "$HOME/.opencode/opencode.jsonc" \
  "$HOME/.opencode/worktree.jsonc"; do
  if [ -e "$f" ] || [ -L "$f" ]; then
    ok "$f"
  else
    fail "$f — run: ./install.sh --configs"
  fi
done

echo

# --- Local plugins ---
echo "Local Plugins"

for p in \
  clickable-links.ts \
  session-info.ts \
  session-id.ts \
  vscode.ts \
  worktree.ts \
  git-safety.ts \
  review-enforcer.ts \
  auto-checkpoint.ts; do
  if [ -e "$PLUGIN_DIR/$p" ] || [ -L "$PLUGIN_DIR/$p" ]; then
    ok "$p"
  else
    fail "$PLUGIN_DIR/$p — run: ./install.sh --plugins"
  fi
done

echo

# --- API keys ---
echo "API Keys (auth.json)"

AUTH_FILE="$HOME/.local/share/opencode/auth.json"
if [ ! -f "$AUTH_FILE" ]; then
  fail "auth.json not found at $AUTH_FILE"
  fail "  Copy auth.json.example and fill in your keys:"
  fail "  cp auth.json.example $AUTH_FILE"
else
  ok "auth.json exists"
  # Check for each enabled provider
  for prov in google openai opencode-go kimi-for-coding-oauth zai-coding-plan deepseek inception uni-lux; do
    if python3 -c "import json,sys; a=json.load(open('$AUTH_FILE')); sys.exit(0 if '$prov' in a else 1)" 2>/dev/null; then
      ok "  $prov: key present"
    else
      fail "  $prov: missing from auth.json"
    fi
  done
fi

echo

# --- Skills ---
echo "Skills"

for s in wisdom deployment patch-tracker atlas-review-handler review-protocol; do
  if [ -d "$CONFIG_DIR/skills/$s" ] || [ -L "$CONFIG_DIR/skills/$s" ]; then
    ok "skills/$s"
  else
    warn "skills/$s — run: ./install.sh --skills"
  fi
done

echo

# --- Optional: Docker (worktree isolation) ---
echo "Optional: Docker (worktree isolation)"

if command -v docker &>/dev/null; then
  ok "docker: $(docker --version 2>/dev/null || echo 'installed')"
else
  warn "docker not found. Worktree Docker isolation disabled (worktrees still work without containers)."
fi

echo

# --- Optional: Binary patches ---
echo "Optional: Binary Patches"

PATCH_DIR="$(cd "$(dirname "$0")/.." && pwd)/.sisyphus/patches"
if [ -d "$PATCH_DIR" ]; then
  patch_count=$(find "$PATCH_DIR" -name '*.md' ! -name 'TEMPLATE.md' | wc -l)
  ok "$patch_count patch docs in .sisyphus/patches/"
  warn "Patches are NOT auto-applied by install.sh. See .sisyphus/patches/ for manual apply instructions."
  warn "Features requiring patches: true no-LLM /session-id, /session-info, /vscode cancellation."
else
  warn "No patch directory found."
fi

echo
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Warnings: $WARN"
echo "  Failed: $FAIL"
echo

if [ "$FAIL" -gt 0 ]; then
  printf '\033[31m%d prerequisite(s) missing. Fix the items marked ✗ above.\033[0m\n' "$FAIL"
  exit 1
else
  printf '\033[32mAll required prerequisites present. %d warning(s) for optional features.\033[0m\n' "$WARN"
  exit 0
fi
