#!/usr/bin/env bash
# knowledge-constants.sh — Shared constants for knowledge capture subsystem
# Source guard
[[ -n "${_KNOWLEDGE_CONSTANTS_SOURCED:-}" ]] && return 0
_KNOWLEDGE_CONSTANTS_SOURCED=1

# === Knowledge Base Directories ===
KNOWLEDGE_BASE_DIR="${HOME}/.sisyphus/knowledge"
KNOWLEDGE_MANIFESTS_DIR="${KNOWLEDGE_BASE_DIR}/manifests"
KNOWLEDGE_OVERLAYS_DIR="${KNOWLEDGE_BASE_DIR}/overlays"
KNOWLEDGE_SYSTEM_DIR="${KNOWLEDGE_MANIFESTS_DIR}/system"
KNOWLEDGE_WORKSPACE_DIR="${KNOWLEDGE_MANIFESTS_DIR}/workspace"
KNOWLEDGE_PROJECT_DIR="${KNOWLEDGE_MANIFESTS_DIR}/project"

# === Wisdom Directories ===
WISDOM_BASE_DIR="${HOME}/.sisyphus/wisdom"
WISDOM_SYSTEM_DIR="${WISDOM_BASE_DIR}/system.jsonl"
WISDOM_WORKSPACE_DIR="${WISDOM_BASE_DIR}/workspace.jsonl"

# === Authority Levels ===
AUTHORITY_MANIFEST="manifest"
AUTHORITY_VERIFIED="verified"
AUTHORITY_WISDOM="wisdom"

# === Provenance Types ===
PROVENANCE_CLOSEOUT="closeout"
PROVENANCE_NOMINATION="nomination"
PROVENANCE_PROMOTION="promotion"
PROVENANCE_MANUAL="manual"

# === Manifest Status ===
STATUS_ACTIVE="active"
STATUS_DEPRECATED="deprecated"
STATUS_SUPERSEDED="superseded"

# === Scope Levels ===
SCOPE_SYSTEM="system"
SCOPE_WORKSPACE="workspace"
SCOPE_PROJECT="project"

# === File Lock ===
KNOWLEDGE_LOCK_DIR="${HOME}/.sisyphus/knowledge/.locks"
KNOWLEDGE_LOCK_TIMEOUT=30

# === Token Budgets ===
KNOWLEDGE_MAX_MANIFEST_TOKENS=2000
KNOWLEDGE_MAX_WISDOM_TOKENS=3000
KNOWLEDGE_MAX_TOTAL_TOKENS=4000

# === Snapshot Budgets ===
KNOWLEDGE_SNAPSHOT_CHAR_LIMIT=6000
KNOWLEDGE_SNAPSHOT_TOKEN_LIMIT=1500

# === Closeout ===
CLOSEOUT_PROMPT_PATH="${HOME}/.sisyphus/scripts/knowledge-closeout-prompt.md"
KNOWLEDGE_SNAPSHOT_DIR="${HOME}/.sisyphus/knowledge/.snapshots"

# === Scope Mapping (Wisdom → Manifest) ===
# Wisdom scopes: system, project, plan
# Manifest scopes: system, workspace, project
# Mapping: workspace (manifest) ≈ project (wisdom) for promotion purposes
# plan (wisdom) requires --scope override during promotion

# === Type Mapping (Wisdom → Manifest) ===
# Wisdom types map to manifest types during promotion:
#   gotcha     → provider-gotcha | env-caveat | anti-pattern
#   pattern    → conventions | runbook
#   fact       → deployment | topology | ownership | observability
#   decision   → conventions | cross-repo | preferences
#   warning    → anti-pattern | env-caveat
# When promoting, use the most specific manifest type for the content.

# === Validation ===
KNOWLEDGE_VALID_AUTHORITIES=("${AUTHORITY_MANIFEST}" "${AUTHORITY_VERIFIED}" "${AUTHORITY_WISDOM}")
KNOWLEDGE_VALID_PROVENANCES=("${PROVENANCE_CLOSEOUT}" "${PROVENANCE_NOMINATION}" "${PROVENANCE_PROMOTION}" "${PROVENANCE_MANUAL}")
KNOWLEDGE_VALID_STATUSES=("${STATUS_ACTIVE}" "${STATUS_DEPRECATED}" "${STATUS_SUPERSEDED}")
KNOWLEDGE_VALID_SCOPES=("${SCOPE_SYSTEM}" "${SCOPE_WORKSPACE}" "${SCOPE_PROJECT}")