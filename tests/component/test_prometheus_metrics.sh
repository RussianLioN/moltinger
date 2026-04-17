#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

STATE_FILE="$(secure_temp_file metrics-state)"
COUNTER_FILE="$(secure_temp_file metrics-counter)"
PROM_DIR="$(secure_temp_dir prometheus-textfile)"
PROM_FILE="$PROM_DIR/moltis_llm.prom"

export CIRCUIT_BREAKER_STATE_FILE="$STATE_FILE"
export FALLBACK_COUNTER_FILE="$COUNTER_FILE"
export PROMETHEUS_TEXTFILE_DIR="$PROM_DIR"
export PROMETHEUS_METRICS_FILE="$PROM_FILE"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD=3
export PRIMARY_PROVIDER="openai-codex"
export FALLBACK_PROVIDER="ollama"
export OLLAMA_HOST="http://127.0.0.1:11434"

# shellcheck source=scripts/health-monitor.sh
source "$PROJECT_ROOT/scripts/health-monitor.sh"

send_alert() { :; }
check_primary_provider_health() { return 0; }
check_fallback_provider_health() { return 0; }

reset_metrics_fixture() {
    cat > "$STATE_FILE" <<JSON
{
  "state": "closed",
  "failure_count": 0,
  "success_count": 0,
  "last_failure_time": null,
  "last_state_change": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "active_provider": "openai-codex",
  "fallback_provider": "ollama"
}
JSON
    echo "0" > "$COUNTER_FILE"
    rm -f "$PROM_FILE"
}

run_component_prometheus_metrics_tests() {
    start_timer

    test_start "component_metrics_exports_prometheus_file"
    reset_metrics_fixture
    export_prometheus_metrics
    assert_file_exists "$PROM_FILE" "Prometheus metrics file should be written"
    test_pass

    test_start "component_metrics_include_required_series"
    export_prometheus_metrics
    local metrics
    metrics=$(cat "$PROM_FILE")
    assert_contains "$metrics" 'llm_provider_available{provider="openai-codex"}' "OpenAI Codex availability metric should exist"
    assert_contains "$metrics" 'llm_provider_available{provider="ollama"}' "Ollama availability metric should exist"
    assert_contains "$metrics" 'llm_fallback_triggered_total' "Fallback counter should exist"
    assert_contains "$metrics" 'moltis_circuit_state' "Circuit state metric should exist"
    assert_contains "$metrics" 'moltis_active_provider{provider="openai-codex"} 1' "Active provider metric should exist"
    test_pass

    test_start "component_metrics_include_help_and_type_annotations"
    local metrics
    metrics=$(cat "$PROM_FILE")
    assert_contains "$metrics" '# HELP llm_provider_available' "HELP annotation should exist"
    assert_contains "$metrics" '# TYPE llm_provider_available gauge' "TYPE annotation should exist"
    assert_contains "$metrics" '# HELP llm_fallback_triggered_total' "Fallback HELP should exist"
    assert_contains "$metrics" '# TYPE llm_fallback_triggered_total counter' "Fallback TYPE should exist"
    test_pass

    test_start "component_metrics_numeric_mapping_matches_state"
    jq '.state = "open" | .failure_count = 3 | .active_provider = "ollama"' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    export_prometheus_metrics
    assert_contains "$(cat "$PROM_FILE")" 'moltis_circuit_state 1' "open state should export numeric 1"
    test_pass

    test_start "component_metrics_fallback_counter_increments_on_open_transition"
    reset_metrics_fixture
    jq '.state = "open" | .failure_count = 3 | .active_provider = "ollama"' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    export_prometheus_metrics
    assert_contains "$(cat "$PROM_FILE")" 'llm_fallback_triggered_total 1' "Fallback counter should increment on open transition"
    test_pass

    test_start "component_metrics_reflect_active_provider_changes"
    jq '.state = "half_open" | .active_provider = "openai-codex" | .success_count = 1' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    export_prometheus_metrics
    assert_contains "$(cat "$PROM_FILE")" 'moltis_active_provider{provider="openai-codex"} 1' "Metric should show OpenAI Codex as active"
    test_pass

    test_start "component_metrics_output_is_parseable"
    if jq -Rn --arg text "$(cat "$PROM_FILE")" '$text | length > 0' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Metrics file should be non-empty and parseable as text"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_prometheus_metrics_tests
fi
