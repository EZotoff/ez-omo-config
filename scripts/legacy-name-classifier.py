#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnusedCallResult=false, reportGeneralTypeIssues=false, reportIndexIssue=false
"""Classify legacy OpenCode/OMO naming occurrences in the config repo."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
TOKENS = ["oh-my-opencode", "oh_my_opencode", "OH_MY_OPENCODE", "oh-my-openagent", "omo-hub", ".omo", ".sisyphus"]


def git_files(repo: Path) -> list[str]:
    completed = subprocess.run(["git", "ls-files"], cwd=str(repo), text=True, stdout=subprocess.PIPE, check=True)
    return completed.stdout.splitlines()


def classify(path: str, token: str, line: str, source: str) -> str:
    lowered_path = path.lower()
    lowered_line = line.lower()
    if "schema" in source or "oh-my-opencode.schema.json" in lowered_line or "oh-my-openagent.schema.json" in lowered_line:
        return "required_upstream_legacy"
    if lowered_path.startswith(".sisyphus/patches/") or lowered_path.startswith(".sisyphus/plans/") or lowered_path.startswith(".sisyphus/evidence/") or lowered_path.startswith(".sisyphus/notepads/"):
        return "historical_reference"
    if lowered_path.startswith("docs/") or lowered_path in {"readme.md", "agents.md", "manifest.md"}:
        return "historical_reference"
    if lowered_path.startswith("configs/") or lowered_path.startswith("scripts/") or lowered_path.startswith("tests/"):
        return "deprecated_local_usage"
    if lowered_path.startswith("commands/"):
        return "historical_reference"
    if lowered_path.startswith("skills/"):
        return "historical_reference"
    if lowered_path == "install.sh":
        return "deprecated_local_usage"
    if token in {".sisyphus", ".omo"}:
        return "historical_reference"
    return "unclassified"


def scan(repo: Path) -> dict[str, object]:
    findings: list[dict[str, object]] = []
    for rel in git_files(repo):
        file_path = repo / rel
        try:
            text = file_path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line_no, line in enumerate(text.splitlines(), start=1):
            for token in TOKENS:
                if token in line:
                    findings.append({
                        "path": rel,
                        "line": line_no,
                        "token": token,
                        "classification": classify(rel, token, line, "git_ls_files"),
                        "source": "git_ls_files",
                    })

    opencode_config = repo / "configs" / "opencode" / "opencode.json"
    if opencode_config.is_file():
        data = json.loads(opencode_config.read_text(encoding="utf-8"))
        for index, plugin in enumerate(data.get("plugin", [])):
            if isinstance(plugin, str):
                for token in TOKENS:
                    if token in plugin:
                        findings.append({
                            "path": "configs/opencode/opencode.json",
                            "line": None,
                            "token": token,
                            "classification": classify("configs/opencode/opencode.json", token, plugin, "opencode_plugin_array"),
                            "source": "opencode_plugin_array",
                            "plugin_index": index,
                        })

    omo_config = repo / "configs" / "oh-my-openagent" / "oh-my-openagent.json"
    if omo_config.is_file():
        data = json.loads(omo_config.read_text(encoding="utf-8"))
        schema = data.get("$schema")
        if isinstance(schema, str):
            for token in TOKENS:
                if token in schema:
                    findings.append({
                        "path": "configs/oh-my-openagent/oh-my-openagent.json",
                        "line": None,
                        "token": token,
                        "classification": classify("configs/oh-my-openagent/oh-my-openagent.json", token, schema, "schema_url"),
                        "source": "schema_url",
                    })

    counts: dict[str, int] = {}
    for finding in findings:
        key = str(finding["classification"])
        counts[key] = counts.get(key, 0) + 1
    return {"findings": findings, "summary": {"total": len(findings), "by_classification": counts, "unclassified": counts.get("unclassified", 0)}}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Classify legacy naming occurrences")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    parser.add_argument("--repo-root", default=str(REPO_ROOT), help="Repository root")
    args = parser.parse_args(argv)
    result = scan(Path(args.repo_root))
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for finding in result["findings"]:  # type: ignore[index]
            print(f"{finding['classification']} {finding['token']} {finding['path']}:{finding['line']}")
    return 1 if result["summary"]["unclassified"] else 0  # type: ignore[index]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
