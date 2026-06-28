---
description: Patch the live OpenCode binary with a minimal fix. Use when fixing bugs in OpenCode's Go/TypeScript binary — checkout the exact live version, apply the fix, build, install, and test. NEVER build from dev branch to patch a stable release.
---

# Patch OpenCode Binary

This skill applies a minimal source fix to the **live** OpenCode binary. It builds from the exact release tag that matches the running version — never from `dev` or any other branch.

## Pre-flight Checks

Before starting, gather the facts:

```bash
# 1. Identify the live version
LIVE_VERSION=$(~/.opencode/bin/opencode --version 2>&1)
echo "Live version: $LIVE_VERSION"

# 2. Identify the source repo
SOURCE_DIR="${OPENCODE_SOURCE:-$HOME/src/opencode}"
cd "$SOURCE_DIR"

# 3. Verify the release tag exists
git tag --list "v${LIVE_VERSION}"
# Expected: v1.17.9 (or whatever the live version is)
# If empty, the version tag doesn't exist — do NOT proceed with dev branch

# 4. Check for running servers
ps -ef | grep 'opencode serve' | grep -v grep
```

## Critical Rules

1. **NEVER** build from `origin/dev` or any branch other than the release tag
2. **NEVER** replace the live binary with a build that reports a different version
3. **ALWAYS** backup the live binary before replacing
4. **ALWAYS** build with `--single --skip-install --skip-embed-web-ui` for speed
5. **ALWAYS** verify the build version matches the live version before installing
6. **ALWAYS** test the fix on the real surface after installing

## Procedure

### Step 1: Check out the release source

```bash
SOURCE_DIR="${OPENCODE_SOURCE:-$HOME/src/opencode}"
cd "$SOURCE_DIR"

LIVE_VERSION=$(~/.opencode/bin/opencode --version 2>&1)

# Fetch latest tags
git fetch --tags origin

# Verify the source tree is clean before checkout
if [ -n "$(git status --porcelain)" ]; then
  echo "FATAL: Source tree is dirty. Commit or stash before checking out the release tag."
  git status --porcelain
  exit 1
fi

# Create a fix branch from the EXACT release tag
git checkout "v${LIVE_VERSION}" -b "fix/${FIX_NAME}"
```

**Guard**: If `v${LIVE_VERSION}` tag doesn't exist, STOP. Do not proceed with any other branch. The version tag is the contract.

**Warning**: Tags like `v0.1.17*` are NOT the same as `v1.17*`. Verify the tag matches the live version output.

### Step 2: Apply the minimal fix

Edit only the file(s) that need changing. Do not touch unrelated code. The diff should be minimal and surgical.

```bash
# Make your edit(s)
# ...

# Verify the diff is clean
git diff --stat
```

### Step 3: Build from the release source

```bash
cd "$SOURCE_DIR/packages/opencode"
OPENCODE_VERSION="$LIVE_VERSION" bun run script/build.ts --single --skip-install --skip-embed-web-ui
# CRITICAL: OPENCODE_VERSION must be set explicitly. Without it, the build script
# derives version from the branch name and produces 0.0.0-fix/... instead of $LIVE_VERSION
```

Flags:
- `--single`: Build for current platform only (faster)
- `--skip-install`: Don't install globally (we'll do it manually)
- `--skip-embed-web-ui`: Skip web UI bundle (faster, not needed for server/TUI fixes)

Build output: `dist/opencode-linux-x64/bin/opencode`

### Step 4: Verify the build version

```bash
BUILT_VERSION=$(dist/opencode-linux-x64/bin/opencode --version 2>&1)
echo "Built version: $BUILT_VERSION"

# CRITICAL: The built version MUST match the live version
if [ "$BUILT_VERSION" != "$LIVE_VERSION" ]; then
  echo "FATAL: Version mismatch! Built $BUILT_VERSION, expected $LIVE_VERSION"
  echo "Do NOT install this binary. The source was not checked out at the right tag."
  echo "If the version is 0.0.0-fix/..., you forgot to set OPENCODE_VERSION in Step 3."
  exit 1
fi

# Verify the patch is present in the built binary
# Replace <PATCHED_SYMBOL> with a string unique to your fix
# Note: Bun minifies locals, so grep for a string literal you added, not a function name
PATCH_PROOF=$(grep -c '<PATCHED_SYMBOL>' dist/opencode-linux-x64/bin/opencode || true)
if [ "$PATCH_PROOF" -eq 0 ]; then
  echo "WARNING: Could not verify patch presence via grep. Minified binaries rename locals."
  echo "Record source + test evidence before installing this binary."
fi
```

### Step 5: Backup the live binary

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="opencode.backup-${LIVE_VERSION}-${FIX_NAME}-${TIMESTAMP}"
BACKUP_PATH="$HOME/.opencode/bin/${BACKUP_NAME}"
cp "$HOME/.opencode/bin/opencode" "$BACKUP_PATH"
test -x "$BACKUP_PATH" || { echo "FATAL: backup was not created: $BACKUP_PATH"; exit 1; }
echo "Backed up to: ${BACKUP_PATH}"
```

### Step 6: Stop servers, swap binary, restart

```bash
# Stop servers
systemctl --user stop omo-tg.service opencode.service 2>/dev/null

# If the binary is still busy, inspect remaining matching processes before killing anything.
mapfile -t remaining < <(pgrep -af 'opencode serve' || true)
if [ "${#remaining[@]}" -gt 0 ]; then
  printf '%s\n' "${remaining[@]}"
  echo "FATAL: opencode serve process(es) still running. Stop the specific service-owned PID shown above, then rerun."
  exit 1
fi

# Swap binary
cp dist/opencode-linux-x64/bin/opencode "$HOME/.opencode/bin/opencode"
chmod +x "$HOME/.opencode/bin/opencode"

# Restart servers
systemctl --user start omo-tg.service opencode.service 2>/dev/null

# Verify version
"$HOME/.opencode/bin/opencode" --version
```

### Step 7: Test the fix

Test on the real surface that was broken:

```bash
# Example: verify SSE events flow for sessions in different directories
# 1. Open a TUI session
# 2. Dispatch a background sub-agent
# 3. End the turn
# 4. Wait for background task completion
# 5. Verify the continuation message appears live in the TUI
```

### Step 8: Roll back if needed

If anything breaks:

```bash
systemctl --user stop omo-tg.service opencode.service 2>/dev/null
cp "$BACKUP_PATH" "$HOME/.opencode/bin/opencode"
chmod +x "$HOME/.opencode/bin/opencode"
systemctl --user start omo-tg.service opencode.service 2>/dev/null
```

## Filing a PR

After the fix is verified live:

```bash
cd "$SOURCE_DIR"

# Push to fork
git remote add fork https://github.com/EZotoff/opencode.git 2>/dev/null || true
git push fork "fix/${FIX_NAME}"

# Create PR
# VERIFY the base branch — it may be 'main' depending on repo state
PR_BASE="${PR_BASE:-dev}"
gh pr create \
  --repo anomalyco/opencode \
  --head "EZotoff:fix/${FIX_NAME}" \
  --base "$PR_BASE" \
  --title "fix: <description>" \
  --body "<PR body with reproduction, root cause, and fix description>"
```

### PR Template Compliance

The OpenCode compliance bot auto-closes PRs within hours if the description does not match the template headers verbatim. Required headers:
- `### Issue for this PR`
- `### Type of change`

Do not use AI-generated prose that ignores the template. The bot gives roughly a 2-hour window before auto-closing.

## Common Pitfalls

| Pitfall | Consequence | Prevention |
|---------|-------------|------------|
| Building from `dev` branch | Version mismatch, unstable binary, broken environment | Always checkout `v${LIVE_VERSION}` tag |
| Not backing up the live binary | Cannot roll back | Always backup before swap |
| Using `mv` instead of `cp` | Loses the original binary | Use `cp` for backup, `cp` for install |
| Not verifying build version | Installing wrong version into production | Always check `--version` after build |
| Not stopping servers before swap | "Text file busy" error | Stop servers, swap, restart |
| Building for wrong architecture | Binary won't run | Use `--single` flag (builds for current platform) |
| Including unrelated changes from dev branch | Hundreds of unreviewed changes in production binary | Checkout release tag, apply minimal fix only |
| Building without `OPENCODE_VERSION` env var | Binary reports `0.0.0-fix/...` instead of live version; Step 4 fails | Always set `OPENCODE_VERSION=$LIVE_VERSION` before `bun run build` |
| Non-systemd `opencode serve` still running | `cp` to live binary fails with `Text file busy` | Inspect matching PIDs and stop only the specific service-owned process before swapping |
| Dirty source tree at checkout | Uncommitted changes from prior work carried into fix branch | Verify `git status --porcelain` is empty before `git checkout` |
| PR closed by compliance bot | Hours of delay; must reopen | Match `### Issue for this PR` / `### Type of change` template headers verbatim |
