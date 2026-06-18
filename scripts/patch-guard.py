#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnusedCallResult=false, reportGeneralTypeIssues=false, reportIndexIssue=false
"""Guard active patch install targets against forbidden stack zones."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
PATCH_DIR = REPO_ROOT / ".sisyphus" / "patches"


def load_path_classifier() -> Any:
    spec = importlib.util.spec_from_file_location("path_classifier", SCRIPT_DIR / "path-classifier.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load path-classifier.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def frontmatter(text: str) -> dict[str, object]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    lines = text[3:end].strip().splitlines()
    data: dict[str, object] = {}
    current: str | None = None
    for line in lines:
        if re.match(r"^[A-Za-z0-9_-]+:\s*", line):
            key, value = line.split(":", 1)
            current = key.strip()
            value = value.strip().strip('"')
            data[current] = [] if value == "" else value
        elif current and line.strip().startswith("-"):
            existing = data.setdefault(current, [])
            if isinstance(existing, list):
                existing.append(line.strip()[1:].strip().strip('"'))
    return data


def target_paths(data: dict[str, object]) -> list[str]:
    paths: list[str] = []
    for key in ("target_install_path", "target_install_paths"):
        value = data.get(key)
        if isinstance(value, str):
            paths.append(value)
        elif isinstance(value, list):
            paths.extend(str(item) for item in value)
    return paths


def extra_forbidden(path: str) -> str | None:
    lowered = path.lower()
    if any(token in lowered for token in ("/.cache/", "/cache/", "/logs/", "/log/", "/sessions/", "/session/", "/tasks/", "/task-state/", "/worktree-state/")):
        return "cache_log_session_or_task_state"
    return None


def scan(patch_dir: Path) -> dict[str, object]:
    classifier = load_path_classifier()
    policy_path = REPO_ROOT / "configs" / "stack-locations.json"
    findings: list[dict[str, object]] = []
    for patch in sorted(patch_dir.glob("*.md")):
        if patch.name == "TEMPLATE.md":
            continue
        data = frontmatter(patch.read_text(encoding="utf-8"))
        if str(data.get("status", "")).strip('"') != "active":
            continue
        patch_id = str(data.get("patch_id", patch.stem)).strip('"')
        for raw_target in target_paths(data):
            classified = classifier.result_for(raw_target, policy_path)
            classification = str(classified["classification"])
            reason = extra_forbidden(raw_target)
            forbidden = classification in {"unknown", "forbidden_zone", "control_managed_runtime_child", "secret_or_auth"} or reason is not None
            try:
                patch_file = str(patch.resolve(strict=False).relative_to(REPO_ROOT))
            except ValueError:
                patch_file = str(patch.resolve(strict=False))
            findings.append({
                "patch_id": patch_id,
                "patch_file": patch_file,
                "target_install_path": raw_target,
                "path": classified["path"],
                "classification": classification,
                "guard": "forbidden_zone" if forbidden else "allowed",
                "reason": reason or classification,
            })
    forbidden_count = sum(1 for item in findings if item["guard"] == "forbidden_zone")
    return {"findings": findings, "summary": {"checked": len(findings), "forbidden": forbidden_count}}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Scan patch registry install targets for forbidden zones")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    parser.add_argument("--patch-dir", default=str(PATCH_DIR), help="Patch directory")
    args = parser.parse_args(argv)
    result = scan(Path(args.patch_dir))
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for finding in result["findings"]:  # type: ignore[index]
            print(f"{finding['guard']} {finding['target_install_path']}")
    return 1 if result["summary"]["forbidden"] else 0  # type: ignore[index]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
