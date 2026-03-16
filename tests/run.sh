#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$SCRIPT_DIR/lib"

# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

LANE="pr"
OUTPUT_JSON=false
WRITE_JUNIT=false
VERBOSE=false
FILTER_PATTERN=""
TEST_LIVE="${TEST_LIVE:-0}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
TEST_REPORT_DIR="${TEST_REPORT_DIR:-$PROJECT_ROOT/test-results}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-moltinger-test}"
TEST_IN_CONTAINER="${TEST_IN_CONTAINER:-0}"
KEEP_STACK="${KEEP_STACK:-0}"

show_help() {
    cat <<HELP
Moltis test runner

Usage:
  ./tests/run.sh --lane <lane|group> [--json] [--junit] [--filter PATTERN] [--verbose] [--live] [--compose-project NAME]

Canonical lanes:
  static
  component
  topology_registry
  integration_local
  security_api
  mcp_fake
  e2e_browser
  resilience
  live_external

Additional live-only aliases:
  security_runtime_smoke
  clawdiy_live_deploy
  mcp_real
  telegram_live
  provider_live

Groups:
  pr      = static + component + topology_registry + integration_local + security_api + mcp_fake
  main    = pr + e2e_browser
  nightly = resilience + live_external + security_runtime_smoke
  all     = main + nightly
HELP
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lane)
                LANE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --junit)
                WRITE_JUNIT=true
                shift
                ;;
            --filter)
                FILTER_PATTERN="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --live)
                TEST_LIVE=1
                shift
                ;;
            --compose-project)
                COMPOSE_PROJECT_NAME="$2"
                shift 2
                ;;
            --keep-stack)
                KEEP_STACK=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 3
                ;;
        esac
    done
}

lane_needs_stack() {
    case "$1" in
        integration_local|security_api|e2e_browser) return 0 ;;
        *) return 1 ;;
    esac
}

lane_is_live_only() {
    case "$1" in
        resilience|live_external|security_runtime_smoke|clawdiy_live_deploy|mcp_real|telegram_live|provider_live) return 0 ;;
        *) return 1 ;;
    esac
}

group_to_lanes() {
    case "$1" in
        pr)
            printf '%s\n' static component topology_registry integration_local security_api mcp_fake
            ;;
        unit_legacy)
            printf '%s\n' static component topology_registry
            ;;
        integration_legacy)
            printf '%s\n' topology_registry integration_local provider_live telegram_live mcp_real
            ;;
        security_legacy)
            printf '%s\n' security_api security_runtime_smoke
            ;;
        e2e_legacy)
            printf '%s\n' e2e_browser resilience
            ;;
        main)
            printf '%s\n' static component topology_registry integration_local security_api mcp_fake e2e_browser
            ;;
        nightly)
            printf '%s\n' resilience security_runtime_smoke clawdiy_live_deploy telegram_live provider_live mcp_real
            ;;
        all)
            printf '%s\n' static component topology_registry integration_local security_api mcp_fake e2e_browser resilience security_runtime_smoke clawdiy_live_deploy telegram_live provider_live mcp_real
            ;;
        live_external)
            printf '%s\n' clawdiy_live_deploy telegram_live provider_live mcp_real
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

suite_entries_for_lane() {
    case "$1" in
        static)
            cat <<LIST
bash|static_config_validation|Config validation|$SCRIPT_DIR/static/test_config_validation.sh
bash|static_fleet_registry|Fleet registry and policy|$SCRIPT_DIR/static/test_fleet_registry.sh
bash|static_dev_mcp_smoke|Dev MCP smoke|$SCRIPT_DIR/static/test_dev_mcp_smoke.sh
bash|static_beads_worktree_ownership|Beads worktree ownership guardrails|$SCRIPT_DIR/static/test_beads_worktree_ownership.sh
LIST
            ;;
        component)
            cat <<LIST
bash|component_backup_restore_readiness|Backup restore-readiness component|$SCRIPT_DIR/component/test_backup_restore_readiness.sh
bash|component_moltis_version_helper|Moltis version helper component|$SCRIPT_DIR/component/test_moltis_version_helper.sh
bash|component_circuit_breaker|Circuit breaker component|$SCRIPT_DIR/component/test_circuit_breaker.sh
bash|component_prometheus_metrics|Prometheus metrics component|$SCRIPT_DIR/component/test_prometheus_metrics.sh
bash|component_llm_failover|LLM failover component|$SCRIPT_DIR/component/test_llm_failover_component.sh
bash|component_docker_helpers|Docker helper component|$SCRIPT_DIR/component/test_docker_helpers.sh
bash|component_sync_claude_skills_bridge|Claude skills bridge component|$SCRIPT_DIR/component/test_sync_claude_skills_bridge.sh
bash|component_codex_cli_update_monitor|Codex CLI update monitor component|$SCRIPT_DIR/component/test_codex_cli_update_monitor.sh
bash|component_codex_cli_upstream_watcher|Codex CLI upstream watcher component|$SCRIPT_DIR/component/test_codex_cli_upstream_watcher.sh
bash|component_codex_cli_update_advisor|Codex CLI update advisor component|$SCRIPT_DIR/component/test_codex_cli_update_advisor.sh
bash|component_codex_cli_update_delivery|Codex CLI update delivery component|$SCRIPT_DIR/component/test_codex_cli_update_delivery.sh
bash|component_codex_profile_launch|Codex profile launch component|$SCRIPT_DIR/component/test_codex_profile_launch.sh
bash|component_codex_advisory_e2e|Codex advisory E2E component|$SCRIPT_DIR/component/test_codex_advisory_e2e.sh
bash|component_codex_telegram_consent_e2e|Codex Telegram consent E2E component|$SCRIPT_DIR/component/test_codex_telegram_consent_e2e.sh
bash|component_moltis_codex_consent_router|Moltis Codex consent router component|$SCRIPT_DIR/component/test_moltis_codex_consent_router.sh
bash|component_moltis_codex_advisory_intake|Moltis Codex advisory intake component|$SCRIPT_DIR/component/test_moltis_codex_advisory_intake.sh
bash|component_moltis_codex_advisory_router|Moltis Codex advisory router component|$SCRIPT_DIR/component/test_moltis_codex_advisory_router.sh
bash|component_moltis_codex_update_run|Moltis Codex update run component|$SCRIPT_DIR/component/test_moltis_codex_update_run.sh
bash|component_moltis_codex_update_state|Moltis Codex update state component|$SCRIPT_DIR/component/test_moltis_codex_update_state.sh
bash|component_moltis_codex_update_profile|Moltis Codex update profile component|$SCRIPT_DIR/component/test_moltis_codex_update_profile.sh
bash|component_moltis_codex_update_e2e|Moltis Codex update E2E component|$SCRIPT_DIR/component/test_moltis_codex_update_e2e.sh
bash|component_telegram_bot_send_remote|Telegram remote send component|$SCRIPT_DIR/component/test_telegram_bot_send_remote.sh
bash|component_telegram_web_probe_correlation|Telegram Web probe correlation|$SCRIPT_DIR/component/test_telegram_web_probe_correlation.sh
bash|component_telegram_web_user_monitor_debug|Telegram Web monitor debug flag|$SCRIPT_DIR/component/test_telegram_web_user_monitor_debug.sh
bash|component_telegram_remote_uat_contract|Telegram remote UAT contract|$SCRIPT_DIR/component/test_telegram_remote_uat_contract.sh
LIST
            ;;
        topology_registry)
            cat <<LIST
bash|topology_registry_unit|Git topology registry unit|$SCRIPT_DIR/unit/test_git_topology_registry.sh
bash|topology_registry_integration|Git topology registry integration|$SCRIPT_DIR/integration/test_git_topology_registry.sh
bash|topology_registry_e2e|Git topology registry workflow E2E|$SCRIPT_DIR/e2e/test_git_topology_registry_workflow.sh
LIST
            ;;
        integration_local)
            cat <<LIST
bash|integration_local_api_endpoints|Local API endpoints|$SCRIPT_DIR/integration_local/test_api_endpoints.sh
bash|integration_local_clawdiy_handoff|Clawdiy handoff contract|$SCRIPT_DIR/integration_local/test_clawdiy_handoff.sh
bash|integration_local_clawdiy_extraction_readiness|Clawdiy extraction readiness|$SCRIPT_DIR/integration_local/test_clawdiy_extraction_readiness.sh
LIST
            ;;
        security_api)
            cat <<LIST
bash|security_api_authentication|Authentication security|$SCRIPT_DIR/security_api/test_authentication.sh
bash|security_api_input_validation|Input validation security|$SCRIPT_DIR/security_api/test_input_validation.sh
bash|security_api_auth_rate_limit|Authentication rate limit|$SCRIPT_DIR/security_api/test_auth_rate_limit.sh
bash|security_api_clawdiy_auth_boundaries|Clawdiy auth boundaries|$SCRIPT_DIR/security_api/test_clawdiy_auth_boundaries.sh
LIST
            ;;
        mcp_fake)
            cat <<LIST
node|mcp_fake_runtime|MCP fake runtime|$SCRIPT_DIR/mcp_fake/runtime_mcp_fake.mjs
LIST
            ;;
        e2e_browser)
            cat <<LIST
node|e2e_browser_chat_flow|Browser chat flow|$SCRIPT_DIR/e2e_browser/chat_flow.mjs
LIST
            ;;
        resilience)
            cat <<LIST
bash|resilience_rate_limiting|Rate limiting resilience|$SCRIPT_DIR/resilience/test_rate_limiting.sh
bash|resilience_full_failover_chain|Full failover chain|$SCRIPT_DIR/resilience/test_full_failover_chain.sh
bash|resilience_deployment_recovery|Deployment recovery|$SCRIPT_DIR/resilience/test_deployment_recovery.sh
bash|resilience_clawdiy_rollback|Clawdiy rollback and restore|$SCRIPT_DIR/resilience/test_clawdiy_rollback.sh
LIST
            ;;
        security_runtime_smoke)
            cat <<LIST
bash|security_runtime_smoke|Security runtime smoke|$SCRIPT_DIR/live_external/test_security_runtime_smoke.sh
LIST
            ;;
        clawdiy_live_deploy)
            cat <<LIST
bash|live_clawdiy_deploy_smoke|Clawdiy deploy smoke|$SCRIPT_DIR/live_external/test_clawdiy_deploy_smoke.sh
LIST
            ;;
        mcp_real)
            cat <<LIST
bash|live_mcp_real|Real MCP smoke|$SCRIPT_DIR/live_external/test_mcp_real.sh
LIST
            ;;
        telegram_live)
            cat <<LIST
bash|live_telegram_smoke|Telegram live smoke|$SCRIPT_DIR/live_external/test_telegram_external_smoke.sh
LIST
            ;;
        provider_live)
            cat <<LIST
bash|live_provider_smoke|Provider live smoke|$SCRIPT_DIR/live_external/test_provider_live.sh
LIST
            ;;
        *)
            return 1
            ;;
    esac
}

run_compose() {
    docker compose -f "$PROJECT_ROOT/compose.test.yml" -p "$COMPOSE_PROJECT_NAME" "$@"
}

collect_stack_diagnostics() {
    mkdir -p "$TEST_REPORT_DIR/diagnostics"
    run_compose ps > "$TEST_REPORT_DIR/diagnostics/compose-ps.txt" 2>&1 || true
    run_compose logs --no-color > "$TEST_REPORT_DIR/diagnostics/compose-logs.txt" 2>&1 || true
}

ensure_stack_ready() {
    run_compose up -d --build ollama moltis test-runner >/dev/null
    if ! compose_wait_healthy "$PROJECT_ROOT/compose.test.yml" "$COMPOSE_PROJECT_NAME" "moltis" 180; then
        return 1
    fi
    return 0
}

bootstrap_stack_onboarding() {
    mkdir -p "$TEST_REPORT_DIR"
    local bootstrap_report="$TEST_REPORT_DIR/bootstrap-onboarding.json"

    set +e
    run_compose run --rm -T \
        -e TEST_BASE_URL="http://moltis:13131" \
        -e TEST_TIMEOUT="$TEST_TIMEOUT" \
        -e MOLTIS_PASSWORD="${MOLTIS_PASSWORD:-test_password}" \
        test-runner node tests/fixtures/bootstrap_onboarding.mjs >"$bootstrap_report"
    local exit_code=$?
    set -e

    [[ $exit_code -eq 0 ]]
}

ensure_runner_prereqs() {
    command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; return 1; }
    [[ "${BASH_VERSINFO[0]:-0}" -ge 5 ]] || { echo "bash >= 5 is required" >&2; return 1; }
    return 0
}

write_suite_json() {
    local suite_json_file="$1"
    local status="$2"
    local suite_id="$3"
    local suite_name="$4"
    local lane_name="$5"
    local message="$6"

    jq -nc \
        --arg status "$status" \
        --arg suite_id "$suite_id" \
        --arg suite_name "$suite_name" \
        --arg lane "$lane_name" \
        --arg message "$message" \
        '{
          status: $status,
          lane: $lane,
          suite: {id: $suite_id, name: $suite_name},
          summary: {total: 1, passed: (if $status == "pass" then 1 else 0 end), failed: (if $status == "fail" then 1 else 0 end), skipped: (if $status == "skip" then 1 else 0 end), duration_seconds: 0},
          failures: (if $status == "fail" then [$message] else [] end),
          skipped_tests: (if $status == "skip" then [$message] else [] end),
          cases: [{
            id: $suite_id,
            name: $suite_name,
            status: (if $status == "pass" then "passed" elif $status == "fail" then "failed" else "skipped" end),
            message: $message,
            lane: $lane,
            duration_ms: 0,
            suite: {id: $suite_id, name: $suite_name}
          }]
        }' > "$suite_json_file"
}

suite_client_ip() {
    local suite_id="$1"
    local checksum third_octet fourth_octet
    checksum=$(printf '%s' "$suite_id" | cksum | awk '{print $1}')
    third_octet=$((((checksum / 250) % 250) + 1))
    fourth_octet=$(((checksum % 250) + 1))
    printf '10.250.%s.%s\n' "$third_octet" "$fourth_octet"
}

execute_suite() {
    local runtime="$1"
    local lane_name="$2"
    local suite_id="$3"
    local suite_name="$4"
    local suite_path="$5"
    local suite_json_file="$6"
    local suite_log_file="$7"
    local suite_junit_file="$8"
    local stdout_file="$suite_log_file.stdout"
    local client_ip

    client_ip=$(suite_client_ip "$suite_id")

    mkdir -p "$(dirname "$suite_json_file")" "$(dirname "$suite_log_file")"
    : > "$suite_log_file"
    : > "$stdout_file"

    local base_url="${TEST_BASE_URL:-http://localhost:13131}"
    local exit_code=0

    case "$runtime" in
        bash)
            set +e
            OUTPUT_JSON=true \
            VERBOSE="$VERBOSE" \
            TEST_REPORT_PATH="$suite_json_file" \
            JUNIT_REPORT_PATH="$suite_junit_file" \
            TEST_SUITE_ID="$suite_id" \
            TEST_SUITE_NAME="$suite_name" \
            TEST_LANE="$lane_name" \
            TEST_LIVE="$TEST_LIVE" \
            TEST_TIMEOUT="$TEST_TIMEOUT" \
            TEST_BASE_URL="$base_url" \
            TEST_CLIENT_IP="$client_ip" \
            bash "$suite_path" >"$stdout_file" 2>"$suite_log_file"
            exit_code=$?
            set -e
            ;;
        node)
            set +e
            TEST_SUITE_ID="$suite_id" \
            TEST_SUITE_NAME="$suite_name" \
            TEST_LANE="$lane_name" \
            TEST_LIVE="$TEST_LIVE" \
            TEST_TIMEOUT="$TEST_TIMEOUT" \
            TEST_BASE_URL="$base_url" \
            TEST_CLIENT_IP="$client_ip" \
            node "$suite_path" >"$suite_json_file" 2>"$suite_log_file"
            exit_code=$?
            set -e
            ;;
        *)
            write_suite_json "$suite_json_file" fail "$suite_id" "$suite_name" "$lane_name" "Unknown runtime: $runtime"
            return 3
            ;;
    esac

    if [[ ! -s "$suite_json_file" ]] && jq -e . "$stdout_file" >/dev/null 2>&1; then
        mv "$stdout_file" "$suite_json_file"
    else
        cat "$stdout_file" >> "$suite_log_file" 2>/dev/null || true
        rm -f "$stdout_file"
    fi

    if [[ ! -s "$suite_json_file" ]]; then
        write_suite_json "$suite_json_file" fail "$suite_id" "$suite_name" "$lane_name" "Suite produced no JSON report (exit $exit_code)"
        return 1
    fi

    return "$exit_code"
}

write_aggregate_json() {
    local aggregate_json="$1"
    shift
    local suite_files=("$@")
    jq -s \
      --arg lane "$LANE" \
      --arg timestamp "$(get_timestamp)" \
      '
      . as $suites |
      {
        lane: $lane,
        timestamp: $timestamp,
        status: (
          if ([ $suites[] | select(.status == "fail") ] | length) > 0 then "failed"
          elif ([ $suites[] | select(.status == "pass") ] | length) == 0 then "skipped"
          else "passed"
          end
        ),
        summary: {
          total_suites: ($suites | length),
          total_cases: ([ $suites[] | .summary.total ] | add // 0),
          passed: ([ $suites[] | .summary.passed ] | add // 0),
          failed: ([ $suites[] | .summary.failed ] | add // 0),
          skipped: ([ $suites[] | .summary.skipped ] | add // 0)
        },
        suites: [ $suites[] | {lane: .lane, suite: .suite, status: .status, summary: .summary} ],
        cases: [ $suites[] | .cases[] ]
      }
      ' "${suite_files[@]}" > "$aggregate_json"
}

write_junit_report() {
    local aggregate_json="$1"
    local junit_file="$2"
    local jq_filter
    jq_filter=$(cat <<'JQ'
[
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
  "<testsuite name=\"moltis-tests\" tests=\"" + ((.summary.total_cases // 0) | tostring) + "\" failures=\"" + ((.summary.failed // 0) | tostring) + "\" skipped=\"" + ((.summary.skipped // 0) | tostring) + "\">",
  (
    .cases[] |
    if .status == "failed" or .status == "error" then
      "  <testcase classname=\"" + (.suite.id // .suite.name // .lane // "suite") + "\" name=\"" + .id + "\"><failure message=\"" + ((.message // "failure") | gsub("\""; "&quot;")) + "\"/></testcase>"
    elif .status == "skipped" then
      "  <testcase classname=\"" + (.suite.id // .suite.name // .lane // "suite") + "\" name=\"" + .id + "\"><skipped message=\"" + ((.message // "skipped") | gsub("\""; "&quot;")) + "\"/></testcase>"
    else
      "  <testcase classname=\"" + (.suite.id // .suite.name // .lane // "suite") + "\" name=\"" + .id + "\"/>"
    end
  ),
  "</testsuite>"
] | .[]
JQ
)
    jq -r "$jq_filter" "$aggregate_json" > "$junit_file"
}

run_inside_current_context() {
    ensure_runner_prereqs
    mkdir -p "$TEST_REPORT_DIR/suites" "$TEST_REPORT_DIR/logs"

    local -a suite_json_files=()
    local selected_any=false
    local lane_name runtime suite_id suite_name suite_path

    while IFS= read -r lane_name; do
        [[ -n "$lane_name" ]] || continue

        if lane_is_live_only "$lane_name" && ! is_live_mode; then
            local skipped_suite_json="$TEST_REPORT_DIR/suites/${lane_name}.json"
            write_suite_json "$skipped_suite_json" skip "$lane_name" "$lane_name" "$lane_name" "Suite requires --live"
            suite_json_files+=("$skipped_suite_json")
            selected_any=true
            continue
        fi

        while IFS='|' read -r runtime suite_id suite_name suite_path; do
            [[ -n "$suite_id" ]] || continue
            if [[ -n "$FILTER_PATTERN" ]] && [[ ! "$suite_id" =~ $FILTER_PATTERN ]] && [[ ! "$suite_path" =~ $FILTER_PATTERN ]]; then
                continue
            fi
            if [[ ! -f "$suite_path" ]]; then
                local missing_json="$TEST_REPORT_DIR/suites/${suite_id}.json"
                write_suite_json "$missing_json" fail "$suite_id" "$suite_name" "$lane_name" "Missing suite file: $suite_path"
                suite_json_files+=("$missing_json")
                selected_any=true
                continue
            fi

            local suite_json_file="$TEST_REPORT_DIR/suites/${suite_id}.json"
            local suite_log_file="$TEST_REPORT_DIR/logs/${suite_id}.log"
            local suite_junit_file="$TEST_REPORT_DIR/suites/${suite_id}.xml"
            execute_suite "$runtime" "$lane_name" "$suite_id" "$suite_name" "$suite_path" "$suite_json_file" "$suite_log_file" "$suite_junit_file" || true
            suite_json_files+=("$suite_json_file")
            selected_any=true
        done < <(suite_entries_for_lane "$lane_name")
    done < <(group_to_lanes "$LANE")

    if [[ "$selected_any" != "true" ]]; then
        echo "No suites selected for lane/group '$LANE'" >&2
        return 3
    fi

    local aggregate_json="$TEST_REPORT_DIR/summary.json"
    write_aggregate_json "$aggregate_json" "${suite_json_files[@]}"

    if [[ "$WRITE_JUNIT" == "true" ]]; then
        write_junit_report "$aggregate_json" "$TEST_REPORT_DIR/junit.xml"
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        cat "$aggregate_json"
    else
        jq -r '
          "Lane: " + .lane,
          "Status: " + .status,
          "Total suites: " + (.summary.total_suites|tostring),
          "Total cases: " + (.summary.total_cases|tostring),
          "Passed: " + (.summary.passed|tostring),
          "Failed: " + (.summary.failed|tostring),
          "Skipped: " + (.summary.skipped|tostring)
        ' "$aggregate_json"
    fi

    case "$(jq -r '.status' "$aggregate_json")" in
        passed) return 0 ;;
        skipped) return 2 ;;
        *) return 1 ;;
    esac
}

run_locally_in_container() {
    ensure_stack_ready || {
        collect_stack_diagnostics
        echo "Failed to bring up compose.test.yml" >&2
        return 1
    }

    mkdir -p "$TEST_REPORT_DIR"

    bootstrap_stack_onboarding || {
        collect_stack_diagnostics
        echo "Failed to bootstrap hermetic onboarding fixture" >&2
        return 1
    }

    local report_dir_in_container
    local -a extra_volume_args=()

    if [[ "$TEST_REPORT_DIR" == "$PROJECT_ROOT"* ]]; then
        report_dir_in_container="/workspace/${TEST_REPORT_DIR#$PROJECT_ROOT/}"
    else
        report_dir_in_container="/tmp/test-results"
        extra_volume_args=(-v "$TEST_REPORT_DIR:$report_dir_in_container")
    fi

    local -a forward_args=(--lane "$LANE" --compose-project "$COMPOSE_PROJECT_NAME")
    [[ "$OUTPUT_JSON" == "true" ]] && forward_args+=(--json)
    [[ "$WRITE_JUNIT" == "true" ]] && forward_args+=(--junit)
    [[ "$VERBOSE" == "true" ]] && forward_args+=(--verbose)
    [[ -n "$FILTER_PATTERN" ]] && forward_args+=(--filter "$FILTER_PATTERN")
    [[ "$TEST_LIVE" == "1" ]] && forward_args+=(--live)
    [[ "$KEEP_STACK" == "1" ]] && forward_args+=(--keep-stack)

    set +e
    run_compose run --rm -T \
        "${extra_volume_args[@]}" \
        -e TEST_IN_CONTAINER=1 \
        -e TEST_REPORT_DIR="$report_dir_in_container" \
        -e TEST_BASE_URL="http://moltis:13131" \
        -e TEST_LIVE="$TEST_LIVE" \
        -e TEST_TIMEOUT="$TEST_TIMEOUT" \
        test-runner ./tests/run.sh "${forward_args[@]}"
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        collect_stack_diagnostics
    fi

    if [[ "$KEEP_STACK" != "1" ]]; then
        run_compose down -v >/dev/null 2>&1 || true
    fi

    return "$exit_code"
}

main() {
    parse_args "$@"

    local recurse_in_container=false
    local lane_name
    while IFS= read -r lane_name; do
        if lane_needs_stack "$lane_name"; then
            recurse_in_container=true
            break
        fi
    done < <(group_to_lanes "$LANE")

    if [[ "$TEST_IN_CONTAINER" != "1" && "$recurse_in_container" == "true" && "$TEST_LIVE" != "1" && -f "$PROJECT_ROOT/compose.test.yml" ]]; then
        run_locally_in_container
        return $?
    fi

    run_inside_current_context
}

main "$@"
