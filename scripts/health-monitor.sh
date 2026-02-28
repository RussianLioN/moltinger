#!/bin/bash
# Moltis Self-Healing Health Monitor
# Monitors container health and triggers recovery actions

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

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

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

# Main monitoring loop
main() {
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

# Signal handlers
cleanup() {
    log_info "Health monitor shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Run main
main "$@"
