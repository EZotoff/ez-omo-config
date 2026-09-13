#!/usr/bin/env bash
# check-live-config-drift.sh — detect uncommitted damage to the live config store.
#
# Why: the 2026-09-10 and 2026-09-12 incidents both wrote a gutted/sandbox-style
# opencode.json through the live symlinks into this repo, UNCOMMITTED. Running
# servers masked the damage until the next restart/reboot reloaded the config —
# OMO outage surfaced hours after the write. This check collapses that window to
# the integrity timer's 30-minute cadence: any uncommitted change under configs/
# fails the unit, which fires opencode-integrity-alert.service.
#
# Legit in-progress edits in the repo also trip this — that is intentional: the
# operator should either commit or revert config changes within 30 minutes.
set -euo pipefail

REPO="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
cd "$REPO"

if ! git diff --quiet -- configs/ || ! git diff --cached --quiet -- configs/ || [ -n "$(git status --porcelain -- configs/)" ]; then
  echo "LIVE-CONFIG DRIFT: uncommitted changes under configs/:" >&2
  git status --porcelain -- configs/ >&2
  echo >&2
  echo "If these are yours: commit or revert them. If not: inspect for sandbox" >&2
  echo "leakage (see configs/opencode/live-config-guard.mjs incident history)." >&2
  exit 1
fi

echo "live-config drift check: clean"
