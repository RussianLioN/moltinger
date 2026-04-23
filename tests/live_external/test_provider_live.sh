#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOLTIS_API_SMOKE_SCRIPT="$PROJECT_ROOT/scripts/test-moltis-api.sh"
LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
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

    test_start "live_provider_primary_openai_codex_contract"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL for primary provider proof"
    elif [[ ! -x "$MOLTIS_API_SMOKE_SCRIPT" ]]; then
        test_fail "Missing executable helper: $MOLTIS_API_SMOKE_SCRIPT"
    elif ! require_secret_or_skip MOLTIS_PASSWORD "MOLTIS_PASSWORD"; then
        :
    elif ! command -v node >/dev/null 2>&1; then
        test_skip "node is required for RPC-backed primary provider proof"
    elif MOLTIS_URL="$LIVE_MOLTIS_URL" \
        TEST_TIMEOUT="$TEST_TIMEOUT" \
        EXPECTED_PROVIDER="openai-codex" \
        EXPECTED_MODEL="openai-codex::gpt-5.4" \
        bash "$MOLTIS_API_SMOKE_SCRIPT" "/status" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Primary live provider proof should confirm openai-codex / gpt-5.4 through the current auth + RPC surfaces"
    fi

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
