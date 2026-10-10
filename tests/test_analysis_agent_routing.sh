#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$REPO" <<'PY'
import copy
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
omo = json.loads((root / "configs/oh-my-openagent/oh-my-openagent.json").read_text())
core = json.loads((root / "configs/opencode/opencode.json").read_text())
strong = {"openai/gpt-6.1-sol", "zai-coding-plan/glm-5.3", "kimi-for-coding-oauth/k3", "mimo/mimo-v2.6-pro"}

def problems(agent):
    routes = [agent["model"], *agent.get("fallback_models", [])]
    return [route for route in routes if route not in strong]

# 2026-10-01: explore/librarian reverted to cheap minimax-m3 routing by operator
# directive (supersedes 4b4cce5); oracle keeps the reasoning-grade requirement.
# 2026-10-06: operator-directed reassignment (1ca8ff7) moved oracle to
# mimo/mimo-v2.6-pro (metis bench leader 0.929) and dropped its variant.
# directive (supersedes 4b4cce5); oracle keeps the reasoning-grade requirement.
for name in ("oracle",):
    agent = omo["agents"][name]
    bad = problems(agent)
    assert not bad, f"{name}: analysis routes must not silently degrade to data-collection models: {bad}"
    assert agent.get("variant") in ("high", "xhigh", "max", None), f"{name}: reasoning effort required"
    for route in [agent["model"], *agent.get("fallback_models", [])]:
        provider, model = route.split("/", 1)
        assert provider in core["enabled_providers"], f"{name}: provider disabled: {provider}"
        entry = core["provider"][provider]
        assert model in entry["models"], f"{name}: model undefined: {route}"
        assert not entry.get("whitelist") or model in entry["whitelist"], f"{name}: model hidden: {route}"
    weak = copy.deepcopy(agent)
    weak["model"] = "ollama-cloud/minimax-m3"
    assert problems(weak), f"{name}: negative control must reject a weak primary"
    weak = copy.deepcopy(agent)
    weak["fallback_models"] = ["zai-coding-plan/glm-5.3-flash"]
    assert problems(weak), f"{name}: negative control must reject a weak fallback"
    print(f"PASS: {name} strong primary/fallbacks, registered models, weak-route negative controls")
PY
