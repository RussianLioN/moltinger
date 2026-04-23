#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

PREFLIGHT_SCRIPT="$PROJECT_ROOT/scripts/preflight-check.sh"

run_component_preflight_check_tests() {
    start_timer

    test_start "component_preflight_ci_detects_enabled_ollama_contract_without_false_negative"
    local output_json
    output_json="$(mktemp)"

    if ! bash "$PREFLIGHT_SCRIPT" --ci --json >"$output_json" 2>/dev/null; then
        test_fail "preflight-check.sh --ci --json should succeed against the tracked Moltis config"
        rm -f "$output_json"
        generate_report
        return
    fi

    if jq -e '
        .target == "moltis"
        and ((.checks // []) | any(.name == "ollama_base_url" and .status == "pass"))
        and ((.checks // []) | any(.name == "ollama_model" and .status == "pass"))
        and ((.checks // []) | any(.name == "failover_config" and .status == "pass"))
        and ((.checks // []) | any(.name == "ollama_config" and (.message | contains("not enabled"))) | not)
    ' "$output_json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "preflight-check.sh must parse tracked TOML correctly and must not report a false disabled-Ollama warning when providers.ollama.enabled=true"
    fi

    rm -f "$output_json"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_preflight_check_tests
fi
