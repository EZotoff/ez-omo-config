#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnusedCallResult=false, reportGeneralTypeIssues=false, reportIndexIssue=false
"""Detect drift between repo store files and live OpenCode targets."""

from __future__ import annotations

import argparse
import filecmp
import json
import os
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def compare(repo_root: Path, home: Path) -> dict[str, object]:
    mappings = [
        (repo_root / "configs" / "opencode" / "opencode.json", home / ".config" / "opencode" / "opencode.json"),
        (repo_root / "configs" / "opencode" / "provider-connect-retry.mjs", home / ".config" / "opencode" / "provider-connect-retry.mjs"),
        (repo_root / "configs" / "retry-errors.json", home / ".config" / "opencode" / "retry-errors.json"),
        (repo_root / "configs" / "oh-my-openagent" / "oh-my-openagent.json", home / ".config" / "opencode" / "oh-my-openagent.json"),
    ]
    findings: list[dict[str, object]] = []
    for store, live in mappings:
        item: dict[str, object] = {"store_path": str(store), "live_path": str(live), "drift": False, "classification": "in_sync"}
        if not store.exists():
            item.update({"drift": True, "classification": "missing_store"})
        elif not live.exists():
            item.update({"drift": True, "classification": "missing_live"})
        elif live.is_symlink() and live.resolve(strict=False) == store.resolve(strict=False):
            item.update({"classification": "same_symlink", "live_target": os.readlink(live)})
        elif filecmp.cmp(store, live, shallow=False):
            item.update({"classification": "same_content_regular_or_indirect"})
        else:
            item.update({"drift": True, "classification": "content_mismatch"})
        findings.append(item)
    drift = sum(1 for item in findings if item["drift"])
    return {"findings": findings, "summary": {"checked": len(findings), "drift": drift}}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Detect store/live config drift")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    parser.add_argument("--repo-root", default=str(REPO_ROOT), help="Repository root")
    parser.add_argument("--home", default=str(Path.home()), help="Home directory")
    args = parser.parse_args(argv)
    result = compare(Path(args.repo_root), Path(args.home))
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for item in result["findings"]:  # type: ignore[index]
            print(f"{item['classification']} {item['store_path']} -> {item['live_path']}")
    return 1 if result["summary"]["drift"] else 0  # type: ignore[index]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
