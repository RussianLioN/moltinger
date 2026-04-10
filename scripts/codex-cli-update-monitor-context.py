#!/usr/bin/env python3

import json
import pathlib
import sys

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None


def collect_config(config_path: pathlib.Path) -> None:
    result = {"features": [], "notes": []}

    if not config_path.is_file():
        result["notes"].append(f"Config file not found: {config_path}")
        print(json.dumps(result))
        return

    if tomllib is None:
        result["notes"].append("python3 tomllib is unavailable; config traits not parsed")
        print(json.dumps(result))
        return

    try:
        data = tomllib.loads(config_path.read_text())
    except Exception as exc:
        result["notes"].append(f"Failed to parse config TOML: {exc}")
        print(json.dumps(result))
        return

    features = []

    if data.get("check_for_update_on_startup") is True:
        features.append("config.check_for_update_on_startup")

    for key in ("service_tier", "approval_policy", "sandbox_mode", "model"):
        value = data.get(key)
        if isinstance(value, str) and value:
            features.append(f"{key}.{value}")

    for key, label in (
        ("multi_agent", "feature.multi_agent"),
        ("js_repl", "feature.js_repl"),
        ("prevent_idle_sleep", "feature.prevent_idle_sleep"),
    ):
        if data.get("features", {}).get(key) is True:
            features.append(label)

    result["features"] = features
    print(json.dumps(result))


def detect_traits(root: pathlib.Path, local_features_json: str) -> None:
    local_features = set(json.loads(local_features_json))
    traits = []

    def add_trait(name: str) -> None:
        if name not in traits:
            traits.append(name)

    def safe_read(path: pathlib.Path) -> str:
        try:
            return path.read_text()
        except Exception:
            return ""

    operating_model = safe_read(root / "docs" / "CODEX-OPERATING-MODEL.md").lower()
    root_agents = safe_read(root / "AGENTS.md").lower()

    if "worktree" in operating_model or "worktree" in root_agents:
        add_trait("worktree-discipline")

    if "approval" in operating_model or "approval" in root_agents or "sandbox" in root_agents:
        add_trait("approval-boundaries")

    if (root / ".claude" / "skills").is_dir() or "skill" in root_agents:
        add_trait("skills-surface")

    if "feature.multi_agent" in local_features or "multi-agent" in operating_model:
        add_trait("agents-surface")

    if "feature.js_repl" in local_features or "js_repl" in operating_model:
        add_trait("js-repl-surface")

    research_text = safe_read(root / "docs" / "research" / "codex-cli-update-monitoring-2026-03-09.md").lower()
    if "non-interactive" in operating_model or "codex exec" in research_text:
        add_trait("noninteractive-surface")

    if (root / "AGENTS.md").is_file() and (root / "docs" / "AGENTS.md").is_file():
        add_trait("agents-md-boundaries")

    print(json.dumps(traits))


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: codex-cli-update-monitor-context.py <collect-config|detect-traits> ...", file=sys.stderr)
        return 2

    command = sys.argv[1]
    if command == "collect-config":
        collect_config(pathlib.Path(sys.argv[2]))
        return 0
    if command == "detect-traits":
        if len(sys.argv) < 4:
            print("Usage: codex-cli-update-monitor-context.py detect-traits <root> <local_features_json>", file=sys.stderr)
            return 2
        detect_traits(pathlib.Path(sys.argv[2]), sys.argv[3])
        return 0

    print(f"Unknown command: {command}", file=sys.stderr)
    return 2


raise SystemExit(main())
