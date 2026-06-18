#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnusedCallResult=false
"""Report package and git identity for a source checkout."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


def run_git(cwd: Path, *args: str) -> str | None:
    try:
        completed = subprocess.run(
            ["git", *args], cwd=str(cwd), text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return completed.stdout.strip()


def load_package(path: Path) -> tuple[str | None, str | None]:
    package_path = path / "package.json"
    if not package_path.is_file():
        return None, None
    try:
        raw: Any = json.loads(package_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None, None
    if not isinstance(raw, dict):
        return None, None
    name = raw.get("name") if isinstance(raw.get("name"), str) else None
    version = raw.get("version") if isinstance(raw.get("version"), str) else None
    return name, version


def inspect(path: Path) -> dict[str, str | None]:
    canonical = path.expanduser().resolve(strict=False)
    name, version = load_package(canonical)
    inside = run_git(canonical, "rev-parse", "--is-inside-work-tree")
    remote = run_git(canonical, "remote", "get-url", "origin")
    branch = run_git(canonical, "branch", "--show-current")
    head = run_git(canonical, "rev-parse", "HEAD")
    status = run_git(canonical, "status", "--porcelain")
    return {
        "package_name": name,
        "package_version": version,
        "git_remote": remote,
        "git_branch": branch,
        "git_head": head,
        "dirty_status": "dirty" if status else ("clean" if status == "" else None),
        "canonical_path": str(canonical),
        "valid_source_checkout": "true" if inside == "true" and (name or remote or head) else "false",
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Inspect source checkout identity")
    parser.add_argument("directory", help="Directory to inspect")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    args = parser.parse_args(argv)
    result = inspect(Path(args.directory))
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for key, value in result.items():
            print(f"{key}={value or ''}")
    return 0 if result["valid_source_checkout"] == "true" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
