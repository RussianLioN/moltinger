#!/bin/bash
# Moltis Self-Healing Health Monitor
# Monitors container health and triggers recovery actions
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/moltis"
LOG_FILE="$LOG_DIR/health-monitor.log"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
MAX_RESTARTS=3
RESTART_WINDOW=300  # 5 minutes
HEALTH_CHECK_INTERVAL=60

# Output format flags
OUTPUT_JSON=false
NO_COLOR=false
RUN_ONCE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure log directory exists (with fallback for non-root)
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    LOG_DIR="/tmp/moltis"
    LOG_FILE="$LOG_DIR/health-monitor.log"
    mkdir -p "$LOG_DIR" 2>/dev/null || true
fi

# Disable colors if requested or if output is not a terminal
disable_colors() {
    if [[ "$NO_COLOR" == "true" || "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        NC=''
    fi
}

# Logging functions
log() {
    local level="$1"
    shift
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] ${NC}$*${NC}" | tee -a "$LOG_FILE"
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Alerting function
send_alert() {
    local subject="$1"
    local message="$2"

    log_info "ALERT: $subject - $message"

    # Webhook notification (Slack/Discord/Teams)
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"[Moltis] $subject: $message\"}" \
            > /dev/null 2>&1 || true
    fi

    # Email notification (if mail configured)
    if command -v mail &> /dev/null; then
        echo "$message" | mail -s "[Moltis] $subject" "${ALERT_EMAIL:-admin@localhost}" 2>/dev/null || true
    fi
}

# Check container health
check_container_health() {
    local container="$1"
    local health_status

    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")

    case "$health_status" in
        healthy)
            return 0
            ;;
        unhealthy)
            return 1
            ;;
        starting)
            return 2
            ;;
        *)
            log_warn "Unknown health status for $container: $health_status"
            return 3
            ;;
    esac
}

# Check HTTP endpoint
check_http_health() {
    local url="$1"
    local timeout="${2:-10}"
    local response_code

    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# ========================================================================
# LLM PROVIDER HEALTH CHECKS (Circuit Breaker Support)
# ========================================================================

# GLM API configuration
GLM_API_HOST="${GLM_API_HOST:-https://api.z.ai}"
GLM_API_KEY="${GLM_API_KEY:-}"
GLM_MODEL="${GLM_MODEL:-glm-5}"
GLM_HEALTH_TIMEOUT="${GLM_HEALTH_TIMEOUT:-10}"

# Ollama API configuration
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-gemini-3-flash-preview:cloud}"
OLLAMA_HEALTH_TIMEOUT="${OLLAMA_HEALTH_TIMEOUT:-10}"

# Check GLM (Z.ai) API health
check_glm_health() {
    local timeout="${1:-$GLM_HEALTH_TIMEOUT}"
    local url="${GLM_API_HOST}/v1/models"
    local response_code

    # If no API key, skip check
    if [[ -z "$GLM_API_KEY" ]]; then
        log_warn "GLM_API_KEY not set, skipping GLM health check"
        return 2  # Degraded - can't check
    fi

    log_info "Checking GLM API health at $url"

    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$timeout" \
        -H "Authorization: Bearer $GLM_API_KEY" \
        "$url" 2>/dev/null || echo "000")

    case "$response_code" in
        200|201)
            log_info "GLM API is healthy (HTTP $response_code)"
            return 0
            ;;
        401|403)
            log_error "GLM API authentication failed (HTTP $response_code)"
            return 1
            ;;
        429)
            log_warn "GLM API rate limited (HTTP $response_code)"
            return 1
            ;;
        500|502|503|504)
            log_error "GLM API server error (HTTP $response_code)"
            return 1
            ;;
        000)
            log_error "GLM API unreachable (timeout or connection refused)"
            return 1
            ;;
        *)
            log_warn "GLM API unexpected response (HTTP $response_code)"
            return 1
            ;;
    esac
}

# Check Ollama API health
check_ollama_health() {
    local timeout="${1:-$OLLAMA_HEALTH_TIMEOUT}"
    local url="${OLLAMA_HOST}/api/tags"
    local response_code

    log_info "Checking Ollama API health at $url"

    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$timeout" \
        "$url" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        log_info "Ollama API is healthy (HTTP $response_code)"
        return 0
    else
        log_error "Ollama API check failed (HTTP $response_code)"
        return 1
    fi
}

# Get current LLM provider status for JSON output
get_llm_provider_status() {
    local glm_status="unknown"
    local ollama_status="unknown"

    if [[ -n "$GLM_API_KEY" ]]; then
        if check_glm_health > /dev/null 2>&1; then
            glm_status="healthy"
        else
            glm_status="unhealthy"
        fi
    else
        glm_status="not_configured"
    fi

    if check_ollama_health > /dev/null 2>&1; then
        ollama_status="healthy"
    else
        ollama_status="unhealthy"
    fi

    echo "{\"glm\":\"$glm_status\",\"ollama\":\"$ollama_status\"}"
}

# Get container restart count in window
get_restart_count() {
    local container="$1"
    local window="${2:-300}"

    docker events \
        --filter "container=$container" \
        --filter "event=restart" \
        --since "$(date -d "${window} seconds ago" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-"${window}"S '+%Y-%m-%dT%H:%M:%S')" \
        --until "$(date '+%Y-%m-%dT%H:%M:%S')" \
        2>/dev/null | wc -l | tr -d ' '
}

# Restart container with backoff
restart_container() {
    local container="$1"
    local restart_count

    restart_count=$(get_restart_count "$container" "$RESTART_WINDOW")

    if [[ "$restart_count" -ge "$MAX_RESTARTS" ]]; then
        log_error "Container $container exceeded max restarts ($MAX_RESTARTS) in window"
        send_alert "Container Restart Limit" "$container exceeded $MAX_RESTARTS restarts"
        return 1
    fi

    log_warn "Restarting container: $container (attempt $((restart_count + 1))/$MAX_RESTARTS)"

    # Exponential backoff
    local delay=$((2 ** restart_count))
    log_info "Waiting ${delay}s before restart..."
    sleep "$delay"

    docker restart "$container"
    log_info "Container $container restarted"

    # Wait for health check
    sleep 30
    if check_container_health "$container"; then
        log_info "Container $container is healthy after restart"
        return 0
    else
        log_error "Container $container still unhealthy after restart"
        return 1
    fi
}

# Full recovery procedure
full_recovery() {
    local container="$1"

    log_error "Initiating full recovery for $container"
    send_alert "Full Recovery" "Starting full recovery for $container"

    # Stop container
    log_info "Stopping container $container"
    docker stop "$container" 2>/dev/null || true

    # Clean up resources
    log_info "Cleaning up Docker resources"
    docker system prune -f 2>/dev/null || true

    # Recreate container
    log_info "Recreating container from compose"
    cd "$PROJECT_ROOT"
    docker compose up -d --force-recreate "$container"

    # Wait for startup
    sleep 60

    if check_container_health "$container"; then
        log_info "Full recovery successful for $container"
        send_alert "Recovery Success" "$container recovered successfully"
        return 0
    else
        log_error "Full recovery failed for $container"
        send_alert "Recovery Failed" "$container recovery failed - manual intervention required"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    local threshold="${1:-90}"
    local usage

    usage=$(df -P /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

    if [[ -n "$usage" ]] && [[ "$usage" -gt "$threshold" ]]; then
        log_warn "Disk usage at ${usage}% (threshold: ${threshold}%)"
        send_alert "Disk Space Warning" "Disk usage at ${usage}%"

        # Auto cleanup (SAFE: without --volumes to preserve data)
        log_info "Running Docker cleanup (images only, volumes preserved)"
        docker system prune -af 2>/dev/null || true
        # NOTE: Intentionally NOT using --volumes to prevent data loss
        # If volume cleanup needed, run manually: docker volume prune

        return 1
    fi

    return 0
}

# Check memory usage
check_memory() {
    local threshold="${1:-90}"
    local usage

    usage=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2) * 100}')

    if [[ "$usage" -gt "$threshold" ]]; then
        log_warn "Memory usage at ${usage}%"
        send_alert "Memory Warning" "Memory usage at ${usage}%"
        return 1
    fi

    return 0
}

# Get container uptime in seconds
get_container_uptime() {
    local container="$1"
    local started_at
    started_at=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null | tr -d '\n' || echo "")

    if [[ -z "$started_at" ]]; then
        echo "0"
        return
    fi

    # Parse ISO timestamp and calculate uptime
    local started_epoch
    started_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%%.*}" +%s 2>/dev/null || echo "0")

    if [[ "$started_epoch" == "0" ]]; then
        echo "0"
    else
        echo $(( $(date +%s) - started_epoch ))
    fi
}

# Output health status in JSON format
output_health_json() {
    local overall_status="healthy"
    declare -a services_json
    declare -a alerts_json

    # Check moltis container (strip newlines for clean JSON)
    local moltis_health
    moltis_health=$(docker inspect --format='{{.State.Health.Status}}' moltis 2>/dev/null | tr -d '\n\r' || echo "unknown")
    local moltis_uptime
    moltis_uptime=$(get_container_uptime "moltis")

    if [[ "$moltis_health" != "healthy" ]]; then
        overall_status="unhealthy"
    fi

    services_json+=("{\"name\":\"moltis\",\"status\":\"$moltis_health\",\"uptime_seconds\":$moltis_uptime,\"health_endpoint\":\"http://localhost:13131/health\"}")

    # Check watchtower container if exists
    if docker ps --format '{{.Names}}' | grep -q '^watchtower$'; then
        local watchtower_health="healthy"  # watchtower doesn't have health checks
        local watchtower_uptime
        watchtower_uptime=$(get_container_uptime "watchtower")
        services_json+=("{\"name\":\"watchtower\",\"status\":\"$watchtower_health\",\"uptime_seconds\":$watchtower_uptime}")
    fi

    # Build JSON output
    local services_array
    services_array=$(printf '%s\n' "${services_json[@]}" | jq -s '.')
    local alerts_array="[]"

    jq -n \
        --arg status "$overall_status" \
        --arg timestamp "$(get_timestamp)" \
        --argjson services "$services_array" \
        --argjson alerts "$alerts_array" \
        '{
            status: $status,
            timestamp: $timestamp,
            services: $services,
            alerts: $alerts
        }'
}

# Single health check (for --once mode)
run_single_check() {
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_health_json
    else
        echo "=== Health Check: $(date) ==="
        echo ""

        # Check moltis
        local moltis_health
        moltis_health=$(docker inspect --format='{{.State.Health.Status}}' moltis 2>/dev/null || echo "unknown")
        local moltis_uptime
        moltis_uptime=$(get_container_uptime "moltis")

        echo "Moltis:"
        echo "  Status: $moltis_health"
        echo "  Uptime: ${moltis_uptime}s"
        echo "  Health: http://localhost:13131/health"

        # HTTP check
        if check_http_health "http://localhost:13131/health"; then
            echo "  HTTP: OK"
        else
            echo "  HTTP: FAILED"
        fi
        echo ""

        # Check watchtower
        if docker ps --format '{{.Names}}' | grep -q '^watchtower$'; then
            local watchtower_uptime
            watchtower_uptime=$(get_container_uptime "watchtower")
            echo "Watchtower:"
            echo "  Status: running"
            echo "  Uptime: ${watchtower_uptime}s"
            echo ""
        fi

        # System resources
        echo "System:"
        check_disk_space 90 && echo "  Disk: OK" || echo "  Disk: WARNING"
        check_memory 90 && echo "  Memory: OK" || echo "  Memory: WARNING"
    fi
}

# Main monitoring loop
main() {
    # Handle --once mode
    if [[ "$RUN_ONCE" == "true" ]]; then
        run_single_check
        exit 0
    fi

    log_info "Starting Moltis health monitor"
    log_info "Check interval: ${HEALTH_CHECK_INTERVAL}s"
    log_info "Max restarts: ${MAX_RESTARTS} per ${RESTART_WINDOW}s window"

    local consecutive_failures=0

    while true; do
        # Check container health
        if ! check_container_health "moltis"; then
            consecutive_failures=$((consecutive_failures + 1))
            log_warn "Moltis unhealthy (failure $consecutive_failures)"

            if [[ $consecutive_failures -ge 3 ]]; then
                if ! restart_container "moltis"; then
                    if ! full_recovery "moltis"; then
                        log_error "All recovery attempts failed"
                    fi
                fi
                consecutive_failures=0
            fi
        else
            if [[ $consecutive_failures -gt 0 ]]; then
                log_info "Moltis recovered"
            fi
            consecutive_failures=0
        fi

        # Check HTTP endpoint
        if ! check_http_health "http://localhost:13131/health"; then
            log_warn "HTTP health check failed"
        fi

        # Check system resources
        check_disk_space 90
        check_memory 90

        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Show help
show_help() {
    cat << EOF
Moltis Self-Healing Health Monitor

Usage:
    $0 [OPTIONS]

Options:
    --json          Output in JSON format (for CI/AI parsing)
    --no-color      Disable colored output
    --once          Check once and exit (no monitoring loop)
    --interval SEC  Check interval in seconds (default: 60)
    -h, --help      Show this help message

Exit Codes:
    0 - All checks passed
    1 - Health check failed

Examples:
    $0                    # Start monitoring loop
    $0 --once             # Single health check
    $0 --once --json      # Single check with JSON output

Contract: specs/001-docker-deploy-improvements/contracts/scripts.md
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_JSON=true
            NO_COLOR=true
            shift
            ;;
        --no-color)
            NO_COLOR=true
            shift
            ;;
        --once)
            RUN_ONCE=true
            shift
            ;;
        --interval)
            HEALTH_CHECK_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Apply color settings
disable_colors

# Signal handlers
cleanup() {
    log_info "Health monitor shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Run main
main "$@"
