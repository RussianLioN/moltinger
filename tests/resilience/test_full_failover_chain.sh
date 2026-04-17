#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ALLOW_DESTRUCTIVE_TESTS="${ALLOW_DESTRUCTIVE_TESTS:-0}"
OLLAMA_HOST="${OLLAMA_HOST:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-15}"
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"

run_resilience_failover_chain_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "resilience_failover_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq docker || {
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

    test_start "resilience_failover_openai_codex_auth"
    local auth_output
    auth_output="$(docker exec "$MOLTIS_CONTAINER" moltis auth status 2>/dev/null || true)"
    if printf '%s\n' "$auth_output" | grep -F 'openai-codex [valid' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "OpenAI Codex auth should be valid before failover drill"
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
