#!/bin/bash
# Clawdiy rollout verification stages for same-host deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CLAWDIY_CONFIG_FILE="${CLAWDIY_CONFIG_FILE:-$PROJECT_ROOT/config/clawdiy/openclaw.json}"
CLAWDIY_CONTAINER="${CLAWDIY_CONTAINER:-clawdiy}"
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"
FLEET_INTERNAL_NETWORK="${FLEET_INTERNAL_NETWORK:-fleet-internal}"
MONITORING_NETWORK="${MONITORING_NETWORK:-moltinger_monitoring}"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-traefik-net}"
STAGE="${STAGE:-same-host}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-90}"
OUTPUT_JSON=false
NO_COLOR=false

CLAWDIY_PUBLIC_BASE_URL=""
CLAWDIY_PUBLIC_HEALTH_URL=""
CLAWDIY_LOCAL_HEALTH_URL=""
CLAWDIY_LOCAL_METRICS_URL=""
MOLTIS_HEALTH_URL="${MOLTIS_HEALTH_URL:-http://127.0.0.1:13131/health}"

declare -a CHECKS=()
declare -a ERRORS=()
declare -a WARNINGS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

disable_colors() {
    if [[ "$NO_COLOR" == "true" || "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        NC=''
    fi
}

log() {
    local level="$1"
    shift
    local message="$*"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        return
    fi

    case "$level" in
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; WARNINGS+=("$1"); }
log_error() { log ERROR "$@"; ERRORS+=("$1"); }
log_success() { log SUCCESS "$@"; }

add_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    local severity="${4:-error}"

    CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"message\":\"$message\",\"severity\":\"$severity\"}")

    case "$status" in
        pass) log_success "$message" ;;
        warning) log_warn "$message" ;;
        fail)
            if [[ "$severity" == "warning" ]]; then
                log_warn "$message"
            else
                log_error "$message"
            fi
            ;;
    esac
}

timestamp_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

output_json_result() {
    local status="$1"
    local checks_json="[]"
    local warnings_json="[]"
    local errors_json="[]"

    if [[ ${#CHECKS[@]} -gt 0 ]]; then
        checks_json=$(printf '%s\n' "${CHECKS[@]}" | jq -s '.')
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '.')
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        errors_json=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
    fi

    jq -n \
        --arg status "$status" \
        --arg stage "$STAGE" \
        --arg timestamp "$(timestamp_utc)" \
        --arg clawdiy_container "$CLAWDIY_CONTAINER" \
        --arg moltis_container "$MOLTIS_CONTAINER" \
        --arg clawdiy_public_url "$CLAWDIY_PUBLIC_BASE_URL" \
        --arg clawdiy_local_health "$CLAWDIY_LOCAL_HEALTH_URL" \
        --arg moltis_health "$MOLTIS_HEALTH_URL" \
        --argjson checks "$checks_json" \
        --argjson warnings "$warnings_json" \
        --argjson errors "$errors_json" \
        '{
            status: $status,
            stage: $stage,
            timestamp: $timestamp,
            details: {
                clawdiy_container: $clawdiy_container,
                moltis_container: $moltis_container,
                clawdiy_public_url: $clawdiy_public_url,
                clawdiy_local_health_url: $clawdiy_local_health,
                moltis_health_url: $moltis_health
            },
            checks: $checks,
            warnings: $warnings,
            errors: $errors
        }'
}

require_commands() {
    local missing=()
    local cmd
    for cmd in curl docker jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        add_check "dependencies" "fail" "Missing required commands: ${missing[*]}" "error"
        return 1
    fi

    add_check "dependencies" "pass" "Required commands available: curl docker jq" "error"
    return 0
}

load_runtime_config() {
    if [[ ! -f "$CLAWDIY_CONFIG_FILE" ]]; then
        add_check "runtime_config" "fail" "Clawdiy runtime config not found: $CLAWDIY_CONFIG_FILE" "error"
        return 1
    fi

    if ! jq empty "$CLAWDIY_CONFIG_FILE" >/dev/null 2>&1; then
        add_check "runtime_config" "fail" "Clawdiy runtime config is invalid JSON: $CLAWDIY_CONFIG_FILE" "error"
        return 1
    fi

    local base_url server_port health_path metrics_path
    base_url="$(jq -r '.server.base_url' "$CLAWDIY_CONFIG_FILE")"
    server_port="$(jq -r '.server.port // 18789' "$CLAWDIY_CONFIG_FILE")"
    health_path="$(jq -r '.server.health_path // "/health"' "$CLAWDIY_CONFIG_FILE")"
    metrics_path="$(jq -r '.server.metrics_path // "/metrics"' "$CLAWDIY_CONFIG_FILE")"

    CLAWDIY_PUBLIC_BASE_URL="${base_url%/}"
    CLAWDIY_PUBLIC_HEALTH_URL="${CLAWDIY_PUBLIC_BASE_URL}${health_path}"
    CLAWDIY_LOCAL_HEALTH_URL="http://127.0.0.1:${server_port}${health_path}"
    CLAWDIY_LOCAL_METRICS_URL="http://127.0.0.1:${server_port}${metrics_path}"

    add_check "runtime_config" "pass" "Loaded Clawdiy runtime config from $CLAWDIY_CONFIG_FILE" "error"
    return 0
}

http_code() {
    local url="$1"
    local timeout="${2:-10}"
    curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || echo "000"
}

wait_for_http_200() {
    local url="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if [[ "$(http_code "$url" 5)" == "200" ]]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

container_exists() {
    docker inspect "$1" >/dev/null 2>&1
}

container_running() {
    local value
    value="$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null || echo "false")"
    [[ "$value" == "true" ]]
}

container_health() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "unknown"
}

container_label() {
    local container="$1"
    local label="$2"
    docker inspect "$container" | jq -r --arg label "$label" '.[0].Config.Labels[$label] // empty'
}

container_mount_source() {
    local container="$1"
    local destination="$2"
    docker inspect "$container" | jq -r --arg destination "$destination" '
        .[0].Mounts[]
        | select(.Destination == $destination)
        | .Source
    ' | head -1
}

container_network_present() {
    local container="$1"
    local network_name="$2"
    docker inspect "$container" | jq -e --arg network_name "$network_name" '.[0].NetworkSettings.Networks | has($network_name)' >/dev/null 2>&1
}

verify_same_host_stage() {
    if container_exists "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_exists" "pass" "Clawdiy container $CLAWDIY_CONTAINER exists" "error"
    else
        add_check "clawdiy_container_exists" "fail" "Clawdiy container $CLAWDIY_CONTAINER is missing" "error"
        return 1
    fi

    if container_running "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_running" "pass" "Clawdiy container $CLAWDIY_CONTAINER is running" "error"
    else
        add_check "clawdiy_container_running" "fail" "Clawdiy container $CLAWDIY_CONTAINER is not running" "error"
    fi

    local clawdiy_health
    clawdiy_health="$(container_health "$CLAWDIY_CONTAINER")"
    if [[ "$clawdiy_health" == "healthy" || "$clawdiy_health" == "none" ]]; then
        add_check "clawdiy_container_health" "pass" "Clawdiy container health is $clawdiy_health" "error"
    else
        add_check "clawdiy_container_health" "fail" "Clawdiy container health is $clawdiy_health" "error"
    fi

    if wait_for_http_200 "$CLAWDIY_LOCAL_HEALTH_URL" "$TIMEOUT_SECONDS"; then
        add_check "clawdiy_local_health" "pass" "Clawdiy local health endpoint returned 200: $CLAWDIY_LOCAL_HEALTH_URL" "error"
    else
        add_check "clawdiy_local_health" "fail" "Clawdiy local health endpoint did not return 200: $CLAWDIY_LOCAL_HEALTH_URL" "error"
    fi

    if [[ "$(http_code "$CLAWDIY_LOCAL_METRICS_URL" 10)" == "200" ]]; then
        add_check "clawdiy_local_metrics" "pass" "Clawdiy local metrics endpoint returned 200: $CLAWDIY_LOCAL_METRICS_URL" "error"
    else
        add_check "clawdiy_local_metrics" "fail" "Clawdiy local metrics endpoint did not return 200: $CLAWDIY_LOCAL_METRICS_URL" "error"
    fi

    if [[ "$(http_code "$CLAWDIY_PUBLIC_HEALTH_URL" 15)" == "200" ]]; then
        add_check "clawdiy_public_health" "pass" "Clawdiy public health endpoint returned 200: $CLAWDIY_PUBLIC_HEALTH_URL" "error"
    else
        add_check "clawdiy_public_health" "fail" "Clawdiy public health endpoint did not return 200: $CLAWDIY_PUBLIC_HEALTH_URL" "error"
    fi

    if [[ "$(http_code "$MOLTIS_HEALTH_URL" 10)" == "200" ]]; then
        add_check "moltis_health_unchanged" "pass" "Moltis health endpoint remained 200: $MOLTIS_HEALTH_URL" "error"
    else
        add_check "moltis_health_unchanged" "fail" "Moltis health endpoint did not return 200: $MOLTIS_HEALTH_URL" "error"
    fi

    local config_source registry_source state_source audit_source
    config_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw")"
    registry_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw/registry")"
    state_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw-data/state")"
    audit_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw-data/audit")"

    if [[ "$config_source" == */config/clawdiy && "$registry_source" == */config/fleet && "$state_source" == */data/clawdiy/state && "$audit_source" == */data/clawdiy/audit ]]; then
        add_check "clawdiy_mounts" "pass" "Clawdiy mounts are isolated for config, registry, state, and audit roots" "error"
    else
        add_check "clawdiy_mounts" "fail" "Clawdiy mounts are not wired to the expected isolated roots" "error"
    fi

    if [[ "$state_source" != "$audit_source" && "$config_source" != "$registry_source" ]]; then
        add_check "clawdiy_mounts_distinct" "pass" "Clawdiy persistent and control-plane mounts remain distinct" "error"
    else
        add_check "clawdiy_mounts_distinct" "fail" "Clawdiy mounts unexpectedly collapse onto shared paths" "error"
    fi

    local missing_networks=()
    local network_name
    for network_name in "$TRAEFIK_NETWORK" "$FLEET_INTERNAL_NETWORK" "$MONITORING_NETWORK"; do
        if ! container_network_present "$CLAWDIY_CONTAINER" "$network_name"; then
            missing_networks+=("$network_name")
        fi
    done

    if [[ ${#missing_networks[@]} -eq 0 ]]; then
        add_check "clawdiy_networks" "pass" "Clawdiy is attached to $TRAEFIK_NETWORK, $FLEET_INTERNAL_NETWORK, and $MONITORING_NETWORK" "error"
    else
        add_check "clawdiy_networks" "fail" "Clawdiy is missing expected networks: ${missing_networks[*]}" "error"
    fi

    local traefik_rule
    traefik_rule="$(container_label "$CLAWDIY_CONTAINER" "traefik.http.routers.clawdiy.rule")"
    if [[ "$traefik_rule" == *"clawdiy.ainetic.tech"* ]]; then
        add_check "clawdiy_traefik_rule" "pass" "Clawdiy Traefik router label targets clawdiy.ainetic.tech" "error"
    else
        add_check "clawdiy_traefik_rule" "fail" "Clawdiy Traefik router label is missing or misconfigured" "error"
    fi
}

verify_restart_isolation_stage() {
    if ! container_exists "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_exists" "fail" "Clawdiy container $CLAWDIY_CONTAINER is missing" "error"
        return 1
    fi

    if ! container_exists "$MOLTIS_CONTAINER"; then
        add_check "moltis_container_exists" "fail" "Moltis container $MOLTIS_CONTAINER is missing" "error"
        return 1
    fi

    local moltis_id_before moltis_started_before
    moltis_id_before="$(docker inspect --format '{{.Id}}' "$MOLTIS_CONTAINER")"
    moltis_started_before="$(docker inspect --format '{{.State.StartedAt}}' "$MOLTIS_CONTAINER")"
    add_check "restart_capture_baseline" "pass" "Captured Moltis baseline before Clawdiy restart" "error"

    docker restart "$CLAWDIY_CONTAINER" >/dev/null
    add_check "clawdiy_restart_invoked" "pass" "Restarted Clawdiy container $CLAWDIY_CONTAINER" "error"

    if wait_for_http_200 "$CLAWDIY_LOCAL_HEALTH_URL" "$TIMEOUT_SECONDS"; then
        add_check "clawdiy_restart_health" "pass" "Clawdiy returned healthy after restart" "error"
    else
        add_check "clawdiy_restart_health" "fail" "Clawdiy did not become healthy after restart" "error"
    fi

    local moltis_id_after moltis_started_after
    moltis_id_after="$(docker inspect --format '{{.Id}}' "$MOLTIS_CONTAINER")"
    moltis_started_after="$(docker inspect --format '{{.State.StartedAt}}' "$MOLTIS_CONTAINER")"

    if [[ "$moltis_id_before" == "$moltis_id_after" && "$moltis_started_before" == "$moltis_started_after" ]]; then
        add_check "moltis_restart_isolation" "pass" "Moltis container identity and start time did not change during Clawdiy restart" "error"
    else
        add_check "moltis_restart_isolation" "fail" "Moltis container changed during Clawdiy restart" "error"
    fi

    if [[ "$(http_code "$MOLTIS_HEALTH_URL" 10)" == "200" ]]; then
        add_check "moltis_health_after_restart" "pass" "Moltis health endpoint remained 200 after Clawdiy restart" "error"
    else
        add_check "moltis_health_after_restart" "fail" "Moltis health endpoint did not return 200 after Clawdiy restart" "error"
    fi
}

show_help() {
    cat <<EOF
Usage: $0 [--stage same-host|restart-isolation] [--json] [--timeout seconds]

Options:
  --stage <name>      Verification stage to run (default: same-host)
  --json              Emit JSON instead of human-readable logs
  --timeout <sec>     Wait timeout for health checks (default: ${TIMEOUT_SECONDS})
  --no-color          Disable colorized logs
  -h, --help          Show this help text
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stage)
                STAGE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 2
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    disable_colors

    require_commands || {
        output_json_result "fail"
        exit 1
    }

    load_runtime_config || {
        output_json_result "fail"
        exit 1
    }

    case "$STAGE" in
        same-host)
            verify_same_host_stage
            ;;
        restart-isolation)
            verify_restart_isolation_stage
            ;;
        *)
            add_check "stage" "fail" "Unsupported Clawdiy smoke stage: $STAGE" "error"
            ;;
    esac

    local final_status="pass"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        final_status="fail"
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        final_status="warning"
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json_result "$final_status"
    fi

    [[ "$final_status" == "fail" ]] && exit 1
    exit 0
}

main "$@"
