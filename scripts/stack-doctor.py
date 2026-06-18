#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnusedCallResult=false, reportGeneralTypeIssues=false, reportIndexIssue=false
"""Run read-only health checks for the OpenCode/OMO stack."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


REPO_ROOT = Path(__file__).resolve().parent.parent
BROKEN_PLUGIN_URL = "file:///home/ezotoff/omo-hub/browser-lifecycle-plugin/index.mjs"


def finding(check: str, severity: str, message: str, **extra: object) -> dict[str, object]:
    return {"check": check, "severity": severity, "message": message, **extra}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def iter_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        strings: list[str] = []
        for item in value:
            strings.extend(iter_strings(item))
        return strings
    if isinstance(value, dict):
        strings = []
        for item in value.values():
            strings.extend(iter_strings(item))
        return strings
    return []


def file_url_to_path(url: str) -> Path:
    parsed = urlparse(url)
    return Path(unquote(parsed.path)).expanduser().resolve(strict=False)


def git_tracked(repo: Path, path: str) -> bool:
    completed = subprocess.run(["git", "ls-files", "--error-unmatch", path], cwd=str(repo), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return completed.returncode == 0


def opencode_version() -> str | None:
    try:
        completed = subprocess.run(["opencode", "--version"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    return completed.stdout.strip() or completed.stderr.strip() or None


def run(repo: Path, home: Path) -> dict[str, object]:
    findings: list[dict[str, object]] = []
    live_map = {
        "opencode.json": home / ".config" / "opencode" / "opencode.json",
        "provider-connect-retry.mjs": home / ".config" / "opencode" / "provider-connect-retry.mjs",
        "retry-errors.json": home / ".config" / "opencode" / "retry-errors.json",
    }
    for name, live in live_map.items():
        if not live.is_symlink():
            findings.append(finding("symlink_targets", "blocking", f"{name} is not a symlink", path=str(live)))
        elif not live.exists():
            findings.append(finding("symlink_targets", "blocking", f"{name} symlink target is missing", path=str(live), target=os.readlink(live)))
        else:
            findings.append(finding("symlink_targets", "info", f"{name} symlink target exists", path=str(live), target=str(live.resolve(strict=False))))

    config_paths = [repo / "configs" / "opencode" / "opencode.json", repo / "configs" / "oh-my-openagent" / "oh-my-openagent.json"]
    parsed_configs: list[Any] = []
    for config in config_paths:
        try:
            parsed_configs.append(load_json(config))
            findings.append(finding("config_json", "info", "JSON parses", path=str(config)))
        except Exception as exc:
            findings.append(finding("config_json", "blocking", f"JSON parse failed: {exc}", path=str(config)))

    for config, data in zip(config_paths, parsed_configs):
        for value in iter_strings(data):
            if value.startswith("file://"):
                target = file_url_to_path(value)
                severity = "info" if target.exists() else "blocking"
                findings.append(finding("file_url_exists", severity, "file:// target exists" if target.exists() else "file:// target missing", config=str(config), url=value, path=str(target)))
                if value == BROKEN_PLUGIN_URL:
                    findings.append(finding("broken_plugin_paths", "blocking", "known broken browser lifecycle plugin path is configured", url=value, path=str(target), exists=target.exists()))

    auth_candidates = [".local/share/opencode/auth.json", str(home / ".local" / "share" / "opencode" / "auth.json")]
    tracked_auth = [candidate for candidate in auth_candidates if git_tracked(repo, candidate)]
    findings.append(finding("auth_not_tracked", "blocking" if tracked_auth else "info", "auth path is tracked" if tracked_auth else "auth paths are not tracked", paths=tracked_auth))

    repo_omo = repo / ".omo"
    findings.append(finding("repo_root_omo", "blocking" if repo_omo.exists() else "info", "repo-root .omo exists" if repo_omo.exists() else "repo-root .omo absent", path=str(repo_omo)))

    version = opencode_version()
    findings.append(finding("version_discovery", "info" if version else "warning", "opencode version discovered" if version else "opencode version unavailable", version=version))

    omo_config = repo / "configs" / "oh-my-openagent" / "oh-my-openagent.json"
    try:
        schema = load_json(omo_config).get("$schema")
    except Exception:
        schema = None
    findings.append(finding("schema_reality", "info" if isinstance(schema, str) else "warning", "schema URL recorded" if isinstance(schema, str) else "schema URL missing", schema=schema))

    blocking = sum(1 for item in findings if item["severity"] == "blocking")
    return {"findings": findings, "summary": {"blocking": blocking, "warning": sum(1 for item in findings if item["severity"] == "warning"), "info": sum(1 for item in findings if item["severity"] == "info")}}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="OpenCode/OMO stack doctor")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    parser.add_argument("--repo-root", default=str(REPO_ROOT), help="Repository root")
    parser.add_argument("--home", default=str(Path.home()), help="Home directory")
    args = parser.parse_args(argv)
    result = run(Path(args.repo_root), Path(args.home))
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for item in result["findings"]:  # type: ignore[index]
            print(f"{item['severity']} {item['check']} {item['message']}")
    return 1 if result["summary"]["blocking"] else 0  # type: ignore[index]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
