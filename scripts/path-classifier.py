#!/usr/bin/env python3
"""Classify canonical stack paths against configs/stack-locations.json."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import TypedDict, cast


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_POLICY_PATH = REPO_ROOT / "configs" / "stack-locations.json"


class PlaneSpec(TypedDict):
    writable: bool
    paths: list[str]
    notes: str


class Policy(TypedDict):
    planes: dict[str, PlaneSpec]


def canonicalize(raw_path: str) -> Path:
    """Return an absolute, symlink-resolved path without requiring existence."""
    return Path(raw_path).expanduser().resolve(strict=False)


def is_same_or_child(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def load_policy(policy_path: Path) -> Policy:
    with policy_path.open("r", encoding="utf-8") as fh:
        raw_policy = cast(object, json.load(fh))
    if not isinstance(raw_policy, dict):
        raise ValueError("Policy missing object key: planes")
    raw_mapping = cast(dict[str, object], raw_policy)
    raw_planes_object = raw_mapping.get("planes")
    if not isinstance(raw_planes_object, dict):
        raise ValueError("Policy missing object key: planes")
    raw_planes = cast(dict[str, object], raw_planes_object)
    planes: dict[str, PlaneSpec] = {}
    for name, raw_spec_object in raw_planes.items():
        if not isinstance(raw_spec_object, dict):
            raise ValueError("Policy plane entries must be objects")
        raw_spec = cast(dict[str, object], raw_spec_object)
        raw_paths = raw_spec.get("paths", [])
        if not isinstance(raw_paths, list):
            raise ValueError(f"Policy plane {name} paths must be a string list")
        paths: list[str] = []
        for raw_path in cast(list[object], raw_paths):
            if not isinstance(raw_path, str):
                raise ValueError(f"Policy plane {name} paths must be a string list")
            paths.append(raw_path)
        planes[name] = {
            "writable": bool(raw_spec.get("writable", False)),
            "paths": paths,
            "notes": str(raw_spec.get("notes", "")),
        }
    return {"planes": planes}


def classify(path: Path, policy: Policy) -> tuple[str, bool]:
    matches: list[tuple[int, str, bool]] = []
    for classification, spec in policy["planes"].items():
        writable = spec["writable"]
        for raw_root in spec["paths"]:
            root = canonicalize(str(raw_root))
            if is_same_or_child(path, root):
                matches.append((len(root.parts), classification, writable))

    if not matches:
        return "unknown", False

    matches.sort(key=lambda item: item[0], reverse=True)
    _, classification, writable = matches[0]
    if classification in {"unknown", "forbidden_zone"}:
        return classification, False
    return classification, writable


def result_for(raw_path: str, policy_path: Path) -> dict[str, str | bool]:
    policy = load_policy(policy_path)
    path = canonicalize(raw_path)
    classification, writable = classify(path, policy)
    return {
        "path": str(path),
        "classification": classification,
        "writable": writable,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Classify canonicalized paths by OpenCode/OMO stack ownership."
    )
    _ = parser.add_argument("path", help="Path to classify")
    _ = parser.add_argument(
        "--policy",
        default=str(DEFAULT_POLICY_PATH),
        help="Ownership policy JSON path (default: configs/stack-locations.json)",
    )
    _ = parser.add_argument("--json", action="store_true", help="Emit JSON output")
    _ = parser.add_argument(
        "--writable",
        action="store_true",
        help="Fail closed with exit 1 when the classified path is not writable",
    )
    _ = parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 for unknown or forbidden classifications",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    path_arg = cast(str, args.path)
    policy_arg = cast(str, args.policy)
    wants_json = cast(bool, args.json)
    wants_writable = cast(bool, args.writable)
    wants_strict = cast(bool, args.strict)
    try:
        result = result_for(path_arg, canonicalize(policy_arg))
    except Exception as exc:  # fail closed for malformed policy or input handling
        error: dict[str, str | bool] = {"path": str(canonicalize(path_arg)), "classification": "unknown", "writable": False, "error": str(exc)}
        if wants_json:
            print(json.dumps(error, sort_keys=True))
        else:
            print(f"unknown writable=false error={exc}", file=sys.stderr)
        return 1

    if wants_json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(f"{result['classification']} writable={str(result['writable']).lower()} path={result['path']}")

    if wants_strict and result["classification"] in {"unknown", "forbidden_zone"}:
        return 1
    if wants_writable and not result["writable"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
