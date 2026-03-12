#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

CONFIG_FILE="$PROJECT_ROOT/config/moltis.toml"

setup_component_moltis_codex_advisory_rollout_config() {
    require_commands_or_skip python3 || return 2
    return 0
}

run_component_moltis_codex_advisory_rollout_config_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_advisory_rollout_config
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local verdict

    test_start "component_moltis_codex_advisory_rollout_config_enables_interactive_router"
    verdict="$(python3 - <<'PY' "$CONFIG_FILE"
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

path = sys.argv[1]
with open(path, "rb") as fh:
    data = tomllib.load(fh)

env = data.get("env", {})
hooks = data.get("hooks", {}).get("hooks", [])
router = None
for item in hooks:
    if item.get("name") == "codex-advisory-router":
        router = item
        break

ok = (
    env.get("MOLTIS_CODEX_ADVISORY_INTERACTIVE_MODE") == "inline_callbacks"
    and env.get("MOLTIS_CODEX_ADVISORY_CALLBACK_PREFIX") == "codex-advisory"
    and isinstance(router, dict)
    and router.get("command") == "./scripts/moltis-codex-advisory-router.sh"
    and router.get("events") == ["MessageReceived"]
    and router.get("env", {}).get("MOLTIS_CODEX_ADVISORY_ROUTER_SEND_REPLY") == "true"
)
print("ok" if ok else "bad")
PY
)"
    assert_eq "ok" "$verdict" "Tracked Moltis config should enable interactive advisory router rollout"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_advisory_rollout_config_tests
fi
