#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ALLOW_DESTRUCTIVE_TESTS="${ALLOW_DESTRUCTIVE_TESTS:-0}"
GLM_API_KEY="${GLM_API_KEY:-}"
OLLAMA_HOST="${OLLAMA_HOST:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-15}"

run_resilience_failover_chain_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "resilience_failover_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "resilience_failover_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "resilience_failover_opt_in_required"
    if [[ "$ALLOW_DESTRUCTIVE_TESTS" != "1" ]]; then
        test_skip "Set ALLOW_DESTRUCTIVE_TESTS=1 to run failover-chain resilience checks"
        generate_report
        return
    fi
    test_pass

    test_start "resilience_failover_glm_health"
    require_secret_or_skip GLM_API_KEY "GLM_API_KEY" || {
        generate_report
        return
    }
    local glm_code
    glm_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" -H "Authorization: Bearer $GLM_API_KEY" "https://api.z.ai/v1/models" 2>/dev/null || echo '000')
    if [[ "$glm_code" =~ ^(200|201)$ ]]; then
        test_pass
    else
        test_fail "GLM provider should be reachable before failover drill (got $glm_code)"
    fi

    test_start "resilience_failover_ollama_health"
    if [[ -z "$OLLAMA_HOST" ]]; then
        test_skip "OLLAMA_HOST not configured for failover drill"
    else
        local ollama_code
        ollama_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" "${OLLAMA_HOST%/}/api/tags" 2>/dev/null || echo '000')
        if [[ "$ollama_code" == "200" ]]; then
            test_pass
        else
            test_fail "Ollama provider should be reachable before failover drill (got $ollama_code)"
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_resilience_failover_chain_tests
fi
