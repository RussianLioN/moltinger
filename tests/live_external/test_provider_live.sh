#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

OLLAMA_HOST="${OLLAMA_HOST:-}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"

run_live_provider_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "live_provider_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip curl jq || {
        test_start "live_provider_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "live_provider_ollama_tags_endpoint"
    if [[ -z "$OLLAMA_HOST" ]]; then
        test_skip "OLLAMA_HOST not configured for live provider check"
    else
        local ollama_code
        ollama_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" "${OLLAMA_HOST%/}/api/tags" 2>/dev/null || echo '000')
        if [[ "$ollama_code" == "200" ]]; then
            test_pass
        else
            test_fail "Ollama tags endpoint should return 200 (got $ollama_code)"
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_live_provider_tests
fi
