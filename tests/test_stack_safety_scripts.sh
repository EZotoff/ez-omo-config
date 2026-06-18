#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

assert_json() {
  python3 -m json.tool "$1" >/dev/null
}

test_source_identity() {
  local repo="${TMP}/source"
  mkdir -p "${repo}"
  printf '{"name":"oh-my-opencode","version":"3.17.5"}\n' >"${repo}/package.json"
  git -C "${repo}" init -q
  git -C "${repo}" add package.json
  python3 "${ROOT}/scripts/source-identity-check.py" "${repo}" --json >"${TMP}/source.json"
  assert_json "${TMP}/source.json"
  python3 - "${TMP}/source.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data["package_name"] == "oh-my-opencode"
assert data["package_version"] == "3.17.5"
assert data["valid_source_checkout"] == "true"
PY
}

test_legacy_classifier() {
  local repo="${TMP}/legacy"
  mkdir -p "${repo}/configs/oh-my-openagent" "${repo}/configs/opencode" "${repo}/.sisyphus/patches" "${repo}/docs" "${repo}/tests"
  git -C "${repo}" init -q
  printf '{"$schema":"https://example.invalid/oh-my-openagent.schema.json"}\n' >"${repo}/configs/oh-my-openagent/oh-my-openagent.json"
  printf '{"plugin":["file:///home/ezotoff/omo-hub/projects/oh-my-openagent","file:///tmp/.omo/plugin.mjs"]}\n' >"${repo}/configs/opencode/opencode.json"
  printf 'oh-my-opencode oh_my_opencode OH_MY_OPENCODE .sisyphus\n' >"${repo}/docs/history.md"
  printf '.omo omo-hub oh-my-openagent\n' >"${repo}/tests/local.txt"
  git -C "${repo}" add .
  python3 "${ROOT}/scripts/legacy-name-classifier.py" --json --repo-root "${repo}" >"${TMP}/legacy.json"
  assert_json "${TMP}/legacy.json"
  python3 - "${TMP}/legacy.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data["summary"]["unclassified"] == 0
tokens={item["token"] for item in data["findings"]}
for token in ["oh-my-opencode","oh_my_opencode","OH_MY_OPENCODE","oh-my-openagent","omo-hub",".omo",".sisyphus"]:
    assert token in tokens, token
PY
}

test_stack_doctor() {
  local repo="${TMP}/doctor-repo" home="${TMP}/doctor-home"
  mkdir -p "${repo}/configs/opencode" "${repo}/configs/oh-my-openagent" "${repo}/configs" "${home}/.config/opencode"
  git -C "${repo}" init -q
  printf '{"plugin":["file:///home/ezotoff/omo-hub/browser-lifecycle-plugin/index.mjs"]}\n' >"${repo}/configs/opencode/opencode.json"
  printf '{"$schema":"https://example.invalid/oh-my-openagent.schema.json"}\n' >"${repo}/configs/oh-my-openagent/oh-my-openagent.json"
  printf 'export default {}\n' >"${repo}/configs/opencode/provider-connect-retry.mjs"
  printf '{}\n' >"${repo}/configs/retry-errors.json"
  ln -s "${repo}/configs/opencode/opencode.json" "${home}/.config/opencode/opencode.json"
  ln -s "${repo}/configs/opencode/provider-connect-retry.mjs" "${home}/.config/opencode/provider-connect-retry.mjs"
  ln -s "${repo}/configs/retry-errors.json" "${home}/.config/opencode/retry-errors.json"
  if python3 "${ROOT}/scripts/stack-doctor.py" --json --repo-root "${repo}" --home "${home}" >"${TMP}/doctor.json"; then
    echo "stack doctor should report blocking broken plugin" >&2
    return 1
  fi
  assert_json "${TMP}/doctor.json"
  python3 - "${TMP}/doctor.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data["summary"]["blocking"] >= 1
assert any(item["check"] == "broken_plugin_paths" for item in data["findings"])
PY
}

test_patch_guard() {
  local patches="${TMP}/patches"
  mkdir -p "${patches}"
  cat >"${patches}/bad.md" <<'MD'
---
patch_id: "bad"
target_install_paths:
  - "/home/ezotoff/.config/opencode/plugin.js"
  - "/definitely/unknown/path"
status: "active"
---
MD
  if python3 "${ROOT}/scripts/patch-guard.py" --json --patch-dir "${patches}" >"${TMP}/patch-guard.json"; then
    echo "patch guard should reject forbidden targets" >&2
    return 1
  fi
  assert_json "${TMP}/patch-guard.json"
  python3 - "${TMP}/patch-guard.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data["summary"]["forbidden"] == 2
PY
}

test_drift_detector() {
  local repo="${TMP}/drift-repo" home="${TMP}/drift-home"
  mkdir -p "${repo}/configs/opencode" "${repo}/configs/oh-my-openagent" "${repo}/configs" "${home}/.config/opencode"
  printf '{}\n' >"${repo}/configs/opencode/opencode.json"
  printf 'retry\n' >"${repo}/configs/opencode/provider-connect-retry.mjs"
  printf '{}\n' >"${repo}/configs/retry-errors.json"
  printf '{}\n' >"${repo}/configs/oh-my-openagent/oh-my-openagent.json"
  ln -s "${repo}/configs/opencode/opencode.json" "${home}/.config/opencode/opencode.json"
  ln -s "${repo}/configs/opencode/provider-connect-retry.mjs" "${home}/.config/opencode/provider-connect-retry.mjs"
  ln -s "${repo}/configs/retry-errors.json" "${home}/.config/opencode/retry-errors.json"
  cp "${repo}/configs/oh-my-openagent/oh-my-openagent.json" "${home}/.config/opencode/oh-my-openagent.json"
  python3 "${ROOT}/scripts/drift-detector.py" --json --repo-root "${repo}" --home "${home}" >"${TMP}/drift.json"
  assert_json "${TMP}/drift.json"
  python3 - "${TMP}/drift.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data["summary"]["drift"] == 0
PY
}

test_secrets_audit() {
  printf 'configs/opencode/opencode.json\ndocs/readme.md\n' | python3 "${ROOT}/scripts/secrets-path-audit.py" --json >"${TMP}/secrets-clean.json"
  assert_json "${TMP}/secrets-clean.json"
  if printf '.env\nconfigs/credentials.json\n' | python3 "${ROOT}/scripts/secrets-path-audit.py" --json >"${TMP}/secrets-bad.json"; then
    echo "secrets audit should reject secret paths" >&2
    return 1
  fi
  assert_json "${TMP}/secrets-bad.json"
}

test_source_identity
test_legacy_classifier
test_stack_doctor
test_patch_guard
test_drift_detector
test_secrets_audit

echo "stack safety script tests passed"
