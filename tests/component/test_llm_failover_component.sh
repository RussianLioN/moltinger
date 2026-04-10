#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

STATE_FILE="$(secure_temp_file llm-failover-state)"
COUNTER_FILE="$(secure_temp_file llm-failover-counter)"
export CIRCUIT_BREAKER_STATE_FILE="$STATE_FILE"
export FALLBACK_COUNTER_FILE="$COUNTER_FILE"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=2
export CIRCUIT_BREAKER_RECOVERY_TIMEOUT=2
export CIRCUIT_BREAKER_SUCCESS_THRESHOLD=1
export PRIMARY_PROVIDER="openai-codex"
export FALLBACK_PROVIDER="ollama"
export GLM_API_KEY="fixture-glm"
export OLLAMA_HOST="http://127.0.0.1:11434"

# shellcheck source=scripts/health-monitor.sh
source "$PROJECT_ROOT/scripts/health-monitor.sh"

send_alert() { :; }

set_primary_health() {
    export TEST_PRIMARY_HEALTH="$1"
}

set_fallback_health() {
    export TEST_FALLBACK_HEALTH="$1"
}

check_primary_provider_health() {
    [[ "${TEST_PRIMARY_HEALTH:-healthy}" == "healthy" ]]
}

check_fallback_provider_health() {
    [[ "${TEST_FALLBACK_HEALTH:-healthy}" == "healthy" ]]
}

setup_component_llm_failover() {
    require_commands_or_skip jq flock || return 2
    return 0
}

reset_failover_fixture() {
    rm -f "$STATE_FILE" "$STATE_FILE.lock" "$COUNTER_FILE"
    unset TEST_PRIMARY_HEALTH TEST_FALLBACK_HEALTH
    init_circuit_breaker
}

write_old_open_state() {
    local old_ts
    old_ts=$(date -u -d '5 seconds ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(seconds=5)).strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
)
    cat > "$STATE_FILE" <<JSON
{
  "state": "open",
  "failure_count": 2,
  "success_count": 0,
  "last_failure_time": "$old_ts",
  "last_state_change": "$old_ts",
  "active_provider": "ollama",
  "fallback_provider": "ollama"
}
JSON
}

run_component_llm_failover_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_llm_failover
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "component_llm_failover_dependencies"
        test_skip "Missing jq/flock for portable failover component checks"
        generate_report
        return
    fi

    test_start "component_llm_status_json_shape"
    reset_failover_fixture
    local status_json
    status_json=$(get_llm_provider_status)
    if echo "$status_json" | jq -e '."openai-codex" and .ollama' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Provider status should include openai-codex and ollama keys"
    fi

    test_start "component_llm_evaluate_records_failure"
    reset_failover_fixture
    set_primary_health unhealthy
    set_fallback_health healthy
    evaluate_llm_health >/dev/null 2>&1 || true
    assert_eq "1" "$(jq -r '.failure_count' "$STATE_FILE")" "Failure count should increment after unhealthy primary"
    test_pass

    test_start "component_llm_evaluate_opens_circuit_after_threshold"
    evaluate_llm_health >/dev/null 2>&1 || true
    assert_eq "open" "$(jq -r '.state' "$STATE_FILE")" "Circuit should open after threshold"
    assert_eq "ollama" "$(jq -r '.active_provider' "$STATE_FILE")" "Fallback provider should become active"
    test_pass

    test_start "component_llm_recovery_path_returns_half_open_then_closed"
    reset_failover_fixture
    write_old_open_state
    set_primary_health healthy
    set_fallback_health healthy
    evaluate_llm_health >/dev/null 2>&1 || true
    assert_eq "closed" "$(jq -r '.state' "$STATE_FILE")" "Healthy primary should close circuit after half-open success"
    test_pass

    test_start "component_llm_lock_file_created_during_updates"
    reset_failover_fixture
    record_failure
    if [[ -f "${STATE_FILE}.lock" ]]; then
        test_pass
    else
        test_fail "Circuit breaker lock file should be created"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_llm_failover_tests
fi
