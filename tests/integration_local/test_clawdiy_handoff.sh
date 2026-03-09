#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MOLTIS_URL="${TEST_BASE_URL:-${MOLTIS_URL:-http://127.0.0.1:13131}}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
SAMPLE_HANDOFF_FILE="$PROJECT_ROOT/specs/001-clawdiy-agent-platform/contracts/sample-handoff-submit.json"
MOLTIS_CONFIG_FILE="$PROJECT_ROOT/config/moltis.toml"
FIXTURE_MOLTIS_CONFIG_FILE="$PROJECT_ROOT/tests/fixtures/config/moltis.toml"
CLAWDIY_CONFIG_FILE="$PROJECT_ROOT/config/clawdiy/openclaw.json"
REGISTRY_FILE="$PROJECT_ROOT/config/fleet/agents-registry.json"
POLICY_FILE="$PROJECT_ROOT/config/fleet/policy.json"
MOCK_SERVER_FILE="$PROJECT_ROOT/tests/fixtures/handoff_mock_server.mjs"

PORT_FILE="$(secure_temp_file clawdiy-handoff-port)"
SERVER_LOG_FILE="$(secure_temp_file clawdiy-handoff-server-log)"
RESPONSE_FILE="$(secure_temp_file clawdiy-handoff-response)"
ACK_RESPONSE_FILE="$(secure_temp_file clawdiy-handoff-ack-response)"
STATUS_FILE="$(secure_temp_file clawdiy-handoff-status)"
MAIN_ENV_FILE="$(secure_temp_file clawdiy-handoff-main-env)"
FIXTURE_ENV_FILE="$(secure_temp_file clawdiy-handoff-fixture-env)"
SERVER_PID=""
HANDOFF_BASE_URL=""
HANDOFF_SUBMIT_PATH="/internal/v1/agent-handoffs"
HANDOFF_ACK_PATH_TEMPLATE="/internal/v1/agent-handoffs/{correlation_id}/acks"
HANDOFF_STATUS_PATH_TEMPLATE="/internal/v1/agent-handoffs/{correlation_id}"
HANDOFF_AUTHORIZATION_HEADER="Authorization"
HANDOFF_AGENT_HEADER="X-Agent-Id"
HANDOFF_CORRELATION_HEADER="X-Correlation-Id"
HANDOFF_IDEMPOTENCY_HEADER="Idempotency-Key"

extract_toml_env_json() {
    local input_file="$1"
    local output_file="$2"
    python3 - "$input_file" >"$output_file" <<'PY'
import json
import sys

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)

json.dump(data.get("env", {}), sys.stdout)
PY
}

template_path() {
    local template="$1"
    local correlation_id="$2"
    printf '%s' "${template//\{correlation_id\}/$correlation_id}"
}

load_handoff_contract() {
    extract_toml_env_json "$MOLTIS_CONFIG_FILE" "$MAIN_ENV_FILE"
    extract_toml_env_json "$FIXTURE_MOLTIS_CONFIG_FILE" "$FIXTURE_ENV_FILE"

    HANDOFF_SUBMIT_PATH="$(jq -r '.MOLTIS_FLEET_HANDOFF_SUBMIT_PATH' "$MAIN_ENV_FILE")"
    HANDOFF_ACK_PATH_TEMPLATE="$(jq -r '.MOLTIS_FLEET_HANDOFF_ACK_PATH_TEMPLATE' "$MAIN_ENV_FILE")"
    HANDOFF_STATUS_PATH_TEMPLATE="$(jq -r '.MOLTIS_FLEET_HANDOFF_STATUS_PATH_TEMPLATE' "$MAIN_ENV_FILE")"
    HANDOFF_AUTHORIZATION_HEADER="$(jq -r '.MOLTIS_FLEET_AUTHORIZATION_HEADER // "Authorization"' "$MAIN_ENV_FILE")"
    HANDOFF_AGENT_HEADER="$(jq -r '.MOLTIS_FLEET_AGENT_HEADER' "$MAIN_ENV_FILE")"
    HANDOFF_CORRELATION_HEADER="$(jq -r '.MOLTIS_FLEET_CORRELATION_HEADER' "$MAIN_ENV_FILE")"
    HANDOFF_IDEMPOTENCY_HEADER="$(jq -r '.MOLTIS_FLEET_IDEMPOTENCY_HEADER' "$MAIN_ENV_FILE")"
}

cleanup_handoff_server() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

trap cleanup_handoff_server EXIT

setup_integration_local_handoff() {
    require_commands_or_skip curl jq node python3 || return 2
    local health_code
    health_code=$(health_status_code "$MOLTIS_URL" 5)
    if [[ "$health_code" != "200" ]]; then
        return 1
    fi
    if [[ ! -f "$SAMPLE_HANDOFF_FILE" || ! -f "$MOLTIS_CONFIG_FILE" || ! -f "$FIXTURE_MOLTIS_CONFIG_FILE" || ! -f "$CLAWDIY_CONFIG_FILE" || ! -f "$REGISTRY_FILE" || ! -f "$POLICY_FILE" || ! -f "$MOCK_SERVER_FILE" ]]; then
        return 1
    fi
    return 0
}

json_with_times() {
    local correlation_id="$1"
    local idempotency_key="$2"
    local submitted_at="$3"
    local expires_at="$4"
    local capability="${5:-coding.orchestration}"

    jq -c \
        --arg correlation_id "$correlation_id" \
        --arg idempotency_key "$idempotency_key" \
        --arg submitted_at "$submitted_at" \
        --arg expires_at "$expires_at" \
        --arg capability "$capability" \
        '
        .message_id = $correlation_id
        | .correlation_id = $correlation_id
        | .idempotency_key = $idempotency_key
        | .submitted_at = $submitted_at
        | .expires_at = $expires_at
        | .recipient.capability = $capability
        ' "$SAMPLE_HANDOFF_FILE"
}

start_handoff_server() {
    HANDOFF_REGISTRY_FILE="$REGISTRY_FILE" \
    HANDOFF_POLICY_FILE="$POLICY_FILE" \
    HANDOFF_PORT_FILE="$PORT_FILE" \
    HANDOFF_SUBMIT_PATH="$HANDOFF_SUBMIT_PATH" \
    HANDOFF_ACK_PATH_TEMPLATE="$HANDOFF_ACK_PATH_TEMPLATE" \
    HANDOFF_STATUS_PATH_TEMPLATE="$HANDOFF_STATUS_PATH_TEMPLATE" \
    HANDOFF_AUTHORIZATION_HEADER="$HANDOFF_AUTHORIZATION_HEADER" \
    HANDOFF_AGENT_HEADER="$HANDOFF_AGENT_HEADER" \
    HANDOFF_CORRELATION_HEADER="$HANDOFF_CORRELATION_HEADER" \
    HANDOFF_IDEMPOTENCY_HEADER="$HANDOFF_IDEMPOTENCY_HEADER" \
        node "$MOCK_SERVER_FILE" >"$SERVER_LOG_FILE" 2>&1 &
    SERVER_PID=$!

    local tries=0
    while [[ $tries -lt 50 ]]; do
        if [[ -s "$PORT_FILE" ]]; then
            HANDOFF_BASE_URL="http://127.0.0.1:$(cat "$PORT_FILE")"
            if [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$HANDOFF_BASE_URL/health" 2>/dev/null || echo 000)" == "200" ]]; then
                return 0
            fi
        fi
        sleep 0.1
        tries=$((tries + 1))
    done

    return 1
}

submit_handoff() {
    local payload="$1"
    local correlation_id="$2"
    local idempotency_key="$3"

    curl -sS \
        -H "${HANDOFF_AUTHORIZATION_HEADER}: Bearer fixture-token" \
        -H "${HANDOFF_AGENT_HEADER}: moltinger" \
        -H "${HANDOFF_CORRELATION_HEADER}: $correlation_id" \
        -H "${HANDOFF_IDEMPOTENCY_HEADER}: $idempotency_key" \
        -H 'Content-Type: application/json' \
        -o "$RESPONSE_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" \
        -X POST "${HANDOFF_BASE_URL}${HANDOFF_SUBMIT_PATH}" \
        -d "$payload"
}

post_ack() {
    local correlation_id="$1"
    local ack_type="$2"
    local status_summary="$3"
    local emitted_at
    emitted_at=$(node -e 'console.log(new Date().toISOString())')

    curl -sS \
        -H 'Content-Type: application/json' \
        -o "$ACK_RESPONSE_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" \
        -X POST "${HANDOFF_BASE_URL}$(template_path "$HANDOFF_ACK_PATH_TEMPLATE" "$correlation_id")" \
        -d "$(jq -nc \
            --arg ack_type "$ack_type" \
            --arg emitted_at "$emitted_at" \
            --arg status_summary "$status_summary" \
            '{
                ack_id: $emitted_at,
                ack_type: $ack_type,
                emitted_by: "clawdiy",
                emitted_at: $emitted_at,
                status_summary: $status_summary,
                evidence_ref: null
            }')"
}

fetch_status() {
    local correlation_id="$1"
    curl -sS \
        -o "$STATUS_FILE" \
        -w '%{http_code}' \
        --max-time "$TEST_TIMEOUT" \
        "${HANDOFF_BASE_URL}$(template_path "$HANDOFF_STATUS_PATH_TEMPLATE" "$correlation_id")"
}

run_integration_local_clawdiy_handoff_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_integration_local_handoff
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        test_start "integration_local_clawdiy_handoff_setup"
        if [[ $setup_code -eq 2 ]]; then
            test_skip "Dependencies not available"
        else
            test_fail "Hermetic stack or handoff fixtures are not ready"
        fi
        generate_report
        return
    fi

    load_handoff_contract

    test_start "integration_local_clawdiy_handoff_config_alignment"
    assert_eq "$HANDOFF_SUBMIT_PATH" "$(jq -r '.control_plane.submit_path' "$CLAWDIY_CONFIG_FILE")" "Handoff submit path must match Clawdiy runtime config"
    assert_eq "$HANDOFF_ACK_PATH_TEMPLATE" "$(jq -r '.control_plane.ack_path_template' "$CLAWDIY_CONFIG_FILE")" "Handoff ack path template must match Clawdiy runtime config"
    assert_eq "$HANDOFF_STATUS_PATH_TEMPLATE" "$(jq -r '.control_plane.status_path_template' "$CLAWDIY_CONFIG_FILE")" "Handoff status path template must match Clawdiy runtime config"
    assert_eq "$HANDOFF_AUTHORIZATION_HEADER" "$(jq -r '.control_plane.correlation_headers.authorization' "$CLAWDIY_CONFIG_FILE")" "Authorization header must match Clawdiy runtime config"
    assert_eq "$HANDOFF_AGENT_HEADER" "$(jq -r '.control_plane.correlation_headers.agent_id' "$CLAWDIY_CONFIG_FILE")" "Agent header must match Clawdiy runtime config"
    assert_eq "$HANDOFF_CORRELATION_HEADER" "$(jq -r '.control_plane.correlation_headers.correlation_id' "$CLAWDIY_CONFIG_FILE")" "Correlation header must match Clawdiy runtime config"
    assert_eq "$HANDOFF_IDEMPOTENCY_HEADER" "$(jq -r '.control_plane.correlation_headers.idempotency_key' "$CLAWDIY_CONFIG_FILE")" "Idempotency header must match Clawdiy runtime config"
    assert_eq "$(jq -r '.MOLTIS_FLEET_DELIVERY_ACK_DEADLINE_SECONDS' "$MAIN_ENV_FILE")" "$(jq -r '.control_plane.delivery_ack_deadline_seconds' "$CLAWDIY_CONFIG_FILE")" "Delivery ack deadline must match"
    assert_eq "$(jq -r '.MOLTIS_FLEET_START_ACK_DEADLINE_SECONDS' "$MAIN_ENV_FILE")" "$(jq -r '.control_plane.start_ack_deadline_seconds' "$CLAWDIY_CONFIG_FILE")" "Start ack deadline must match"
    assert_eq "$(jq -r '.MOLTIS_FLEET_PROGRESS_HEARTBEAT_SECONDS' "$MAIN_ENV_FILE")" "$(jq -r '.control_plane.progress_heartbeat_seconds' "$CLAWDIY_CONFIG_FILE")" "Progress heartbeat must match"
    assert_eq "$(jq -r '.MOLTIS_FLEET_TERMINAL_TIMEOUT_SECONDS' "$MAIN_ENV_FILE")" "$(jq -r '.control_plane.terminal_timeout_seconds' "$CLAWDIY_CONFIG_FILE")" "Terminal timeout must match"
    if ! diff -u <(jq -S . "$MAIN_ENV_FILE") <(jq -S . "$FIXTURE_ENV_FILE") >/dev/null; then
        test_fail "Fixture moltis.toml must mirror handoff env metadata from config/moltis.toml"
    fi
    if ! jq -e --arg auth "$HANDOFF_AUTHORIZATION_HEADER" --arg agent "$HANDOFF_AGENT_HEADER" --arg corr "$HANDOFF_CORRELATION_HEADER" --arg idem "$HANDOFF_IDEMPOTENCY_HEADER" '
        .service_auth.required_headers as $headers
        | ($headers | index($agent)) != null
        and ($headers | index($corr)) != null
        and ($headers | index($idem)) != null
        and .service_auth.authorization_header == $auth
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_fail "Fleet policy service auth headers must align with Moltinger/Clawdiy handoff config"
    fi
    if [[ -n "${TEST_CURRENT:-}" ]]; then
        test_pass
    fi

    test_start "integration_local_clawdiy_handoff_server_boots"
    if start_handoff_server; then
        test_pass
    else
        test_fail "Mock handoff server did not become healthy"
        generate_report
        return
    fi

    local now_iso future_iso past_iso
    now_iso=$(node -e 'console.log(new Date().toISOString())')
    future_iso=$(node -e 'console.log(new Date(Date.now() + 30 * 60 * 1000).toISOString())')
    past_iso=$(node -e 'console.log(new Date(Date.now() - 1000).toISOString())')

    local accept_correlation accept_idempotency accept_payload submit_code status_code
    accept_correlation="11111111-1111-4111-8111-111111111111"
    accept_idempotency="moltinger-clawdiy-accept-001"
    accept_payload=$(json_with_times "$accept_correlation" "$accept_idempotency" "$now_iso" "$future_iso")

    test_start "integration_local_clawdiy_handoff_accept_flow"
    submit_code=$(submit_handoff "$accept_payload" "$accept_correlation" "$accept_idempotency")
    if [[ "$submit_code" == "202" ]] \
        && jq -e '.status == "accepted_for_delivery" and .correlation_id == "'"$accept_correlation"'"' "$RESPONSE_FILE" >/dev/null 2>&1 \
        && [[ "$(post_ack "$accept_correlation" "delivery" "delivered")" == "200" ]] \
        && [[ "$(post_ack "$accept_correlation" "accept" "accepted")" == "200" ]] \
        && [[ "$(post_ack "$accept_correlation" "start" "started")" == "200" ]] \
        && [[ "$(post_ack "$accept_correlation" "terminal" "completed")" == "200" ]]; then
        status_code=$(fetch_status "$accept_correlation")
        if [[ "$status_code" == "200" ]] && jq -e '.state == "completed" and .correlation_id == "'"$accept_correlation"'"' "$STATUS_FILE" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Completed handoff should expose terminal completed state"
        fi
    else
        test_fail "Accepted handoff should produce delivery and terminal lifecycle"
    fi

    local reject_correlation reject_idempotency reject_payload
    reject_correlation="22222222-2222-4222-8222-222222222222"
    reject_idempotency="moltinger-clawdiy-reject-001"
    reject_payload=$(json_with_times "$reject_correlation" "$reject_idempotency" "$now_iso" "$future_iso" "unsupported.capability")

    test_start "integration_local_clawdiy_handoff_reject_flow"
    submit_code=$(submit_handoff "$reject_payload" "$reject_correlation" "$reject_idempotency")
    if [[ "$submit_code" == "422" ]] && jq -e '.status == "rejected" and .reason == "unknown_or_unauthorized_capability"' "$RESPONSE_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Unsupported capability should be rejected explicitly"
    fi

    local timeout_correlation timeout_idempotency timeout_payload
    timeout_correlation="33333333-3333-4333-8333-333333333333"
    timeout_idempotency="moltinger-clawdiy-timeout-001"
    timeout_payload=$(json_with_times "$timeout_correlation" "$timeout_idempotency" "$now_iso" "$past_iso")

    test_start "integration_local_clawdiy_handoff_timeout_flow"
    submit_code=$(submit_handoff "$timeout_payload" "$timeout_correlation" "$timeout_idempotency")
    if [[ "$submit_code" == "202" ]]; then
        status_code=$(fetch_status "$timeout_correlation")
        if [[ "$status_code" == "200" ]] && jq -e '.state == "timed_out" and .terminal_reason == "delivery_ack_deadline_exceeded"' "$STATUS_FILE" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Expired handoff should surface timed_out state"
        fi
    else
        test_fail "Timeout scenario should still create a submitted handoff"
    fi

    local duplicate_correlation duplicate_idempotency duplicate_payload first_correlation second_correlation
    duplicate_correlation="44444444-4444-4444-8444-444444444444"
    duplicate_idempotency="moltinger-clawdiy-duplicate-001"
    duplicate_payload=$(json_with_times "$duplicate_correlation" "$duplicate_idempotency" "$now_iso" "$future_iso")

    test_start "integration_local_clawdiy_handoff_idempotency"
    submit_code=$(submit_handoff "$duplicate_payload" "$duplicate_correlation" "$duplicate_idempotency")
    first_correlation=$(jq -r '.correlation_id // empty' "$RESPONSE_FILE")
    if [[ "$submit_code" == "202" && "$first_correlation" == "$duplicate_correlation" ]]; then
        submit_code=$(submit_handoff "$duplicate_payload" "$duplicate_correlation" "$duplicate_idempotency")
        second_correlation=$(jq -r '.correlation_id // empty' "$RESPONSE_FILE")
        status_code=$(fetch_status "$duplicate_correlation")
        if [[ "$submit_code" == "200" ]] \
            && jq -e '.status == "duplicate" and .state == "submitted"' "$RESPONSE_FILE" >/dev/null 2>&1 \
            && [[ "$second_correlation" == "$first_correlation" ]] \
            && [[ "$status_code" == "200" ]] \
            && jq -e '.attempt_count == 1' "$STATUS_FILE" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Duplicate idempotency key should reuse the original handoff state"
        fi
    else
        test_fail "Initial idempotent submission should succeed"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_clawdiy_handoff_tests
fi
