#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

STATE_FILE="$(secure_temp_file circuit-breaker-state)"
COUNTER_FILE="$(secure_temp_file circuit-breaker-counter)"
export CIRCUIT_BREAKER_STATE_FILE="$STATE_FILE"
export FALLBACK_COUNTER_FILE="$COUNTER_FILE"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=3
export CIRCUIT_BREAKER_RECOVERY_TIMEOUT=2
export CIRCUIT_BREAKER_SUCCESS_THRESHOLD=2
export GLM_API_KEY="fixture-glm"
export OLLAMA_HOST="http://127.0.0.1:11434"

# shellcheck source=scripts/health-monitor.sh
source "$PROJECT_ROOT/scripts/health-monitor.sh"

send_alert() { :; }
check_glm_health() { return 0; }
check_ollama_health() { return 0; }

setup_component_circuit_breaker() {
    require_commands_or_skip jq flock || return 2
    return 0
}

reset_state() {
    rm -f "$STATE_FILE" "$STATE_FILE.lock" "$COUNTER_FILE"
}

write_open_state_with_old_failure() {
    local old_ts
    old_ts=$(date -u -d '5 seconds ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(seconds=5)).strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
)
    cat > "$STATE_FILE" <<JSON
{
  "state": "open",
  "failure_count": 3,
  "success_count": 0,
  "last_failure_time": "$old_ts",
  "last_state_change": "$old_ts",
  "active_provider": "ollama",
  "fallback_provider": "ollama"
}
JSON
}

run_component_circuit_breaker_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_circuit_breaker
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "component_circuit_breaker_dependencies"
        test_skip "Missing jq/flock for portable component state-machine checks"
        generate_report
        return
    fi

    test_start "component_circuit_breaker_initializes_closed"
    reset_state
    init_circuit_breaker
    assert_eq "closed" "$(get_current_state)" "Circuit breaker should initialize in CLOSED state"
    assert_eq "glm" "$(get_active_provider)" "Active provider should default to glm"
    test_pass

    test_start "component_circuit_breaker_opens_after_threshold"
    reset_state
    init_circuit_breaker
    record_failure
    record_failure
    record_failure
    assert_eq "open" "$(get_current_state)" "Circuit breaker should OPEN after threshold"
    assert_eq "ollama" "$(get_active_provider)" "Active provider should switch to ollama"
    test_pass

    test_start "component_circuit_breaker_half_open_after_recovery_timeout"
    reset_state
    init_circuit_breaker
    write_open_state_with_old_failure
    if check_recovery_timeout; then
        assert_eq "half_open" "$(get_current_state)" "Circuit breaker should move to HALF-OPEN after timeout"
        test_pass
    else
        test_fail "Recovery timeout did not transition to HALF-OPEN"
    fi

    test_start "component_circuit_breaker_closes_after_success_threshold"
    reset_state
    init_circuit_breaker
    write_open_state_with_old_failure
    check_recovery_timeout >/dev/null 2>&1 || true
    record_success
    record_success
    assert_eq "closed" "$(get_current_state)" "Circuit breaker should CLOSE after success threshold"
    test_pass

    test_start "component_circuit_breaker_reopens_on_half_open_failure"
    reset_state
    init_circuit_breaker
    write_open_state_with_old_failure
    check_recovery_timeout >/dev/null 2>&1 || true
    record_failure
    assert_eq "open" "$(get_current_state)" "Failure in HALF-OPEN should reopen the circuit"
    test_pass

    test_start "component_circuit_breaker_state_persists"
    reset_state
    init_circuit_breaker
    record_failure
    assert_file_exists "$STATE_FILE" "State file should exist after updates"
    assert_contains "$(cat "$STATE_FILE")" '"failure_count": 1' "State file should persist failure count"
    test_pass

    test_start "component_circuit_breaker_success_resets_failure_count"
    reset_state
    init_circuit_breaker
    record_failure
    record_success
    assert_eq "0" "$(jq -r '.failure_count' "$STATE_FILE")" "Success should reset failure count in CLOSED state"
    test_pass

    test_start "component_circuit_breaker_numeric_mapping"
    assert_eq "0" "$(state_to_numeric closed)" "closed should map to 0"
    assert_eq "1" "$(state_to_numeric open)" "open should map to 1"
    assert_eq "2" "$(state_to_numeric half_open)" "half_open should map to 2"
    test_pass

    test_start "component_circuit_breaker_no_early_recovery"
    reset_state
    init_circuit_breaker
    record_failure
    record_failure
    record_failure
    if check_recovery_timeout; then
        test_fail "Circuit breaker should not recover immediately"
    else
        assert_eq "open" "$(get_current_state)" "Circuit breaker should remain OPEN before timeout"
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_circuit_breaker_tests
fi
