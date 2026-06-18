#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnusedCallResult=false
"""Fail closed when tracked paths look like secrets or auth material."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import PurePosixPath


SECRET_BASENAMES = {".env", ".env.local", ".envrc", "credentials.json", "auth.json"}
SECRET_PARTS = {"credentials", "secrets", "api-keys", "api_keys"}


def is_secret_path(raw: str) -> bool:
    path = PurePosixPath(raw.strip())
    if not str(path) or str(path).startswith("#"):
        return False
    lowered_parts = [part.lower() for part in path.parts]
    basename = path.name.lower()
    if basename in SECRET_BASENAMES or basename.endswith(".pem") or basename.endswith(".key"):
        return True
    if ".local/share/opencode/auth.json" in str(path).lower():
        return True
    return any(part in SECRET_PARTS for part in lowered_parts)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Audit tracked file paths for secret/auth locations")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    args = parser.parse_args(argv)
    paths = sys.stdin.read().splitlines()
    findings = [{"path": path, "classification": "secret_path"} for path in paths if is_secret_path(path)]
    result = {"findings": findings, "summary": {"checked": len(paths), "secrets_found": len(findings)}}
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        for finding in findings:
            print(f"secret_path {finding['path']}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
