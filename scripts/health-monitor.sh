#!/bin/bash
# Moltis Self-Healing Health Monitor
# Monitors container health and triggers recovery actions
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="${PROJECT_ROOT:-${MOLTIS_ACTIVE_ROOT:-$DEFAULT_PROJECT_ROOT}}"
COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_ROOT/docker-compose.prod.yml}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-moltinger}"
LOG_DIR="/var/log/moltis"
LOG_FILE="$LOG_DIR/health-monitor.log"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
MAX_RESTARTS=3
RESTART_WINDOW=300  # 5 minutes
HEALTH_CHECK_INTERVAL=60
DEPLOY_MUTEX_PATH="${DEPLOY_MUTEX_PATH:-/var/lock/moltinger/deploy.lock}"
DISK_AUTO_CLEANUP_ENABLED="${DISK_AUTO_CLEANUP_ENABLED:-true}"
DISK_CLEANUP_COOLDOWN_SECONDS="${DISK_CLEANUP_COOLDOWN_SECONDS:-3600}"
DISK_CLEANUP_STATE_FILE="${DISK_CLEANUP_STATE_FILE:-/tmp/moltis-disk-cleanup-state}"
DISK_BUILDER_PRUNE_UNTIL="${DISK_BUILDER_PRUNE_UNTIL:-168h}"

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

lock_meta_value() {
    local file="$1"
    local key="$2"

    [[ -r "$file" ]] || return 1

    awk -F= -v key="$key" '$1 == key { sub($1 FS, ""); print; exit }' "$file"
}

deploy_mutex_metadata_path() {
    local flock_meta="${DEPLOY_MUTEX_PATH}.meta"
    local mkdir_meta="${DEPLOY_MUTEX_PATH}.d/meta"

    if [[ -f "$flock_meta" ]]; then
        printf '%s\n' "$flock_meta"
        return 0
    fi

    if [[ -f "$mkdir_meta" ]]; then
        printf '%s\n' "$mkdir_meta"
        return 0
    fi

    return 1
}

deploy_mutex_active() {
    local metadata_path now_epoch expires_at

    metadata_path="$(deploy_mutex_metadata_path || true)"
    [[ -n "$metadata_path" ]] || return 1

    expires_at="$(lock_meta_value "$metadata_path" "expires_at" || true)"
    if [[ ! "$expires_at" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    now_epoch="$(date +%s)"
    (( now_epoch < expires_at ))
}

disk_cleanup_due() {
    local now_epoch last_epoch

    if [[ "$DISK_AUTO_CLEANUP_ENABLED" != "true" ]]; then
        return 1
    fi

    if [[ ! -f "$DISK_CLEANUP_STATE_FILE" ]]; then
        return 0
    fi

    last_epoch="$(cat "$DISK_CLEANUP_STATE_FILE" 2>/dev/null || true)"
    if [[ ! "$last_epoch" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    now_epoch="$(date +%s)"
    (( now_epoch - last_epoch >= DISK_CLEANUP_COOLDOWN_SECONDS ))
}

record_disk_cleanup_epoch() {
    date +%s > "$DISK_CLEANUP_STATE_FILE"
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

# Production chain defaults: OpenAI Codex OAuth -> Ollama -> Claude -> GLM.
PRIMARY_PROVIDER="${PRIMARY_PROVIDER:-openai-codex}"
FALLBACK_PROVIDER="${FALLBACK_PROVIDER:-ollama}"
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"

# GLM API configuration (official BigModel Coding Plan endpoint)
GLM_API_BASE="${GLM_API_BASE:-https://open.bigmodel.cn/api/coding/paas/v4}"
GLM_API_KEY="${GLM_API_KEY:-}"
GLM_MODEL="${GLM_MODEL:-glm-5.1}"
GLM_HEALTH_TIMEOUT="${GLM_HEALTH_TIMEOUT:-10}"

# Ollama API configuration
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-gemini-3-flash-preview:cloud}"
OLLAMA_HEALTH_TIMEOUT="${OLLAMA_HEALTH_TIMEOUT:-10}"

# OpenAI Codex OAuth configuration
OPENAI_CODEX_HEALTH_TIMEOUT="${OPENAI_CODEX_HEALTH_TIMEOUT:-10}"

check_openai_codex_health() {
    local timeout="${1:-$OPENAI_CODEX_HEALTH_TIMEOUT}"
    local auth_output provider_line

    if ! command -v docker >/dev/null 2>&1; then
        log_warn "docker is unavailable, cannot validate openai-codex auth state"
        return 2
    fi

    auth_output="$(timeout "$timeout" docker exec "$MOLTIS_CONTAINER" moltis auth status 2>/dev/null || true)"
    provider_line="$(printf '%s\n' "$auth_output" | grep -F 'openai-codex' | tail -1 || true)"

    if [[ -n "$provider_line" ]] && grep -Fq '[valid' <<<"$provider_line"; then
        log_info "OpenAI Codex auth is healthy"
        return 0
    fi

    log_error "OpenAI Codex auth is not valid"
    return 1
}

# Check official GLM (BigModel) API health
check_glm_health() {
    local timeout="${1:-$GLM_HEALTH_TIMEOUT}"
    local url="${GLM_API_BASE%/}/models"
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
    local primary_status="unknown"
    local fallback_status="unknown"

    if check_primary_provider_health > /dev/null 2>&1; then
        primary_status="healthy"
    else
        primary_status="unhealthy"
    fi

    if check_fallback_provider_health > /dev/null 2>&1; then
        fallback_status="healthy"
    else
        fallback_status="unhealthy"
    fi

    jq -nc \
        --arg primary_provider "$PRIMARY_PROVIDER" \
        --arg primary_status "$primary_status" \
        --arg fallback_provider "$FALLBACK_PROVIDER" \
        --arg fallback_status "$fallback_status" \
        '[{"key": $primary_provider, "value": $primary_status}, {"key": $fallback_provider, "value": $fallback_status}] | from_entries'
}

check_primary_provider_health() {
    case "$PRIMARY_PROVIDER" in
        openai-codex)
            check_openai_codex_health "$@"
            ;;
        glm)
            check_glm_health "$@"
            ;;
        ollama)
            check_ollama_health "$@"
            ;;
        *)
            log_warn "Unknown primary provider health contract: $PRIMARY_PROVIDER"
            return 2
            ;;
    esac
}

check_fallback_provider_health() {
    case "$FALLBACK_PROVIDER" in
        ollama)
            check_ollama_health "$@"
            ;;
        glm)
            check_glm_health "$@"
            ;;
        openai-codex)
            check_openai_codex_health "$@"
            ;;
        *)
            log_warn "Unknown fallback provider health contract: $FALLBACK_PROVIDER"
            return 2
            ;;
    esac
}

# ========================================================================
# CIRCUIT BREAKER STATE MACHINE
# ========================================================================
# States: CLOSED (normal) → OPEN (failed) → HALF-OPEN (testing recovery)
# Contract: specs/001-fallback-llm-ollama/contracts/circuit-breaker-state.md

# Circuit breaker configuration
CIRCUIT_BREAKER_FAILURE_THRESHOLD="${CIRCUIT_BREAKER_FAILURE_THRESHOLD:-3}"
CIRCUIT_BREAKER_RECOVERY_TIMEOUT="${CIRCUIT_BREAKER_RECOVERY_TIMEOUT:-300}"  # 5 minutes
CIRCUIT_BREAKER_SUCCESS_THRESHOLD="${CIRCUIT_BREAKER_SUCCESS_THRESHOLD:-2}"
CIRCUIT_BREAKER_STATE_FILE="${CIRCUIT_BREAKER_STATE_FILE:-/tmp/moltis-llm-state.json}"

# Circuit breaker states
CB_STATE_CLOSED="closed"        # Normal operation
CB_STATE_OPEN="open"            # Fallback mode
CB_STATE_HALF_OPEN="half_open"  # Testing recovery

# Initialize circuit breaker state file
init_circuit_breaker() {
    if [[ ! -f "$CIRCUIT_BREAKER_STATE_FILE" ]]; then
        local initial_state
        initial_state=$(cat <<EOF
{
    "state": "$CB_STATE_CLOSED",
    "failure_count": 0,
    "success_count": 0,
    "last_failure_time": null,
    "last_state_change": "$(get_timestamp)",
    "active_provider": "$PRIMARY_PROVIDER",
    "fallback_provider": "$FALLBACK_PROVIDER"
}
EOF
)
        echo "$initial_state" > "$CIRCUIT_BREAKER_STATE_FILE"
        log_info "Circuit breaker initialized in CLOSED state"
    fi
}

# Read circuit breaker state
get_circuit_breaker_state() {
    init_circuit_breaker

    local state
    state=$(cat "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null || echo "{}")

    if ! echo "$state" | jq -e '.state' > /dev/null 2>&1; then
        init_circuit_breaker
        state=$(cat "$CIRCUIT_BREAKER_STATE_FILE")
    fi

    echo "$state"
}

# Get current state name
get_current_state() {
    get_circuit_breaker_state | jq -r '.state'
}

# Get active provider
get_active_provider() {
    get_circuit_breaker_state | jq -r '.active_provider'
}

# Update circuit breaker state (with file locking)
update_circuit_breaker() {
    local new_state="$1"
    local active_provider="$2"
    local failure_count="${3:-0}"
    local success_count="${4:-0}"

    init_circuit_breaker

    local current_state
    current_state=$(get_circuit_breaker_state)
    local old_state
    old_state=$(echo "$current_state" | jq -r '.state')

    # Build new state
    local new_state_json
    new_state_json=$(echo "$current_state" | jq \
        --arg state "$new_state" \
        --arg provider "$active_provider" \
        --argjson failures "$failure_count" \
        --argjson successes "$success_count" \
        --arg timestamp "$(get_timestamp)" \
        '{
            state: $state,
            failure_count: $failures,
            success_count: $successes,
            last_failure_time: .last_failure_time,
            last_state_change: (if .state != $state then $timestamp else .last_state_change end),
            active_provider: $provider,
            fallback_provider: .fallback_provider
        }')

    # Write with locking (using flock)
    (
        flock -x 200
        echo "$new_state_json" > "$CIRCUIT_BREAKER_STATE_FILE"
    ) 200>"${CIRCUIT_BREAKER_STATE_FILE}.lock"

    # Log state change
    if [[ "$old_state" != "$new_state" ]]; then
        log_info "Circuit breaker: $old_state → $new_state (provider: $active_provider)"
        send_alert "Circuit Breaker State Change" "State changed from $old_state to $new_state"
    fi
}

# Record a failure
record_failure() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')
    local failure_count
    failure_count=$(echo "$current_state" | jq -r '.failure_count')

    failure_count=$((failure_count + 1))

    log_warn "Recording failure ($failure_count/$CIRCUIT_BREAKER_FAILURE_THRESHOLD)"

    # State transitions
    case "$state" in
        "$CB_STATE_CLOSED")
            if [[ $failure_count -ge $CIRCUIT_BREAKER_FAILURE_THRESHOLD ]]; then
                log_error "Failure threshold reached, opening circuit"
                update_circuit_breaker "$CB_STATE_OPEN" "$FALLBACK_PROVIDER" "$failure_count" 0
                # Update last_failure_time
                local updated_state
                updated_state=$(cat "$CIRCUIT_BREAKER_STATE_FILE" | jq --arg ts "$(get_timestamp)" '.last_failure_time = $ts')
                echo "$updated_state" > "$CIRCUIT_BREAKER_STATE_FILE"
            else
                update_circuit_breaker "$CB_STATE_CLOSED" "$PRIMARY_PROVIDER" "$failure_count" 0
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            log_error "Failure in HALF-OPEN state, returning to OPEN"
            update_circuit_breaker "$CB_STATE_OPEN" "$FALLBACK_PROVIDER" "$failure_count" 0
            local updated_state
            updated_state=$(cat "$CIRCUIT_BREAKER_STATE_FILE" | jq --arg ts "$(get_timestamp)" '.last_failure_time = $ts')
            echo "$updated_state" > "$CIRCUIT_BREAKER_STATE_FILE"
            ;;
        "$CB_STATE_OPEN")
            # Already open, just update failure count
            update_circuit_breaker "$CB_STATE_OPEN" "$FALLBACK_PROVIDER" "$failure_count" 0
            ;;
    esac
}

# Record a success
record_success() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')
    local success_count
    success_count=$(echo "$current_state" | jq -r '.success_count')

    success_count=$((success_count + 1))

    log_info "Recording success ($success_count/$CIRCUIT_BREAKER_SUCCESS_THRESHOLD)"

    case "$state" in
        "$CB_STATE_HALF_OPEN")
            if [[ $success_count -ge $CIRCUIT_BREAKER_SUCCESS_THRESHOLD ]]; then
                log_info "Success threshold reached, closing circuit"
                update_circuit_breaker "$CB_STATE_CLOSED" "$PRIMARY_PROVIDER" 0 "$success_count"
            else
                update_circuit_breaker "$CB_STATE_HALF_OPEN" "$PRIMARY_PROVIDER" 0 "$success_count"
            fi
            ;;
        "$CB_STATE_CLOSED")
            # Reset failure count on success
            update_circuit_breaker "$CB_STATE_CLOSED" "$PRIMARY_PROVIDER" 0 "$success_count"
            ;;
        "$CB_STATE_OPEN")
            # Should not happen - successes in OPEN state are from fallback
            ;;
    esac
}

# Check if we should transition from OPEN to HALF-OPEN
check_recovery_timeout() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')
    local last_failure
    last_failure=$(echo "$current_state" | jq -r '.last_failure_time')

    if [[ "$state" != "$CB_STATE_OPEN" ]]; then
        return 1
    fi

    if [[ "$last_failure" == "null" ]]; then
        return 1
    fi

    # Calculate time since last failure
    local last_epoch current_epoch elapsed
    last_epoch=$(date -d "$last_failure" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_failure}" +%s 2>/dev/null || echo "0")
    current_epoch=$(date +%s)
    elapsed=$((current_epoch - last_epoch))

    if [[ $elapsed -ge $CIRCUIT_BREAKER_RECOVERY_TIMEOUT ]]; then
        log_info "Recovery timeout reached ($elapsed >= $CIRCUIT_BREAKER_RECOVERY_TIMEOUT), transitioning to HALF-OPEN"
        update_circuit_breaker "$CB_STATE_HALF_OPEN" "$PRIMARY_PROVIDER" 0 0
        return 0
    fi

    return 1
}

# Evaluate provider health and update circuit breaker
evaluate_llm_health() {
    local current_state
    current_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$current_state" | jq -r '.state')

    # Check for recovery timeout (OPEN → HALF-OPEN)
    check_recovery_timeout

    # Re-read state after potential transition
    state=$(get_current_state)

    case "$state" in
        "$CB_STATE_CLOSED"|"$CB_STATE_HALF_OPEN")
            if check_primary_provider_health > /dev/null 2>&1; then
                record_success
            else
                record_failure
            fi
            ;;
        "$CB_STATE_OPEN")
            # In OPEN state, check if Ollama fallback is healthy
            if ! check_fallback_provider_health > /dev/null 2>&1; then
                log_error "FALLBACK CRITICAL: Both $PRIMARY_PROVIDER and $FALLBACK_PROVIDER are unavailable!"
                send_alert "CRITICAL: No LLM Provider Available" "Both $PRIMARY_PROVIDER and $FALLBACK_PROVIDER are down"
            fi
            ;;
    esac
}

# ========================================================================
# PROMETHEUS METRICS EXPORT
# ========================================================================
# Exports metrics for Prometheus node_exporter textfile collector
# Contract: specs/001-fallback-llm-ollama/contracts/prometheus-metrics.md

# Prometheus textfile directory
PROMETHEUS_TEXTFILE_DIR="${PROMETHEUS_TEXTFILE_DIR:-/var/lib/prometheus/textfile_exports}"
PROMETHEUS_METRICS_FILE="${PROMETHEUS_METRICS_FILE:-$PROMETHEUS_TEXTFILE_DIR/moltis_llm.prom}"

# Fallback triggered counter file (persists across restarts)
FALLBACK_COUNTER_FILE="${FALLBACK_COUNTER_FILE:-/tmp/moltis-fallback-counter}"

# Get or initialize fallback counter
get_fallback_counter() {
    if [[ -f "$FALLBACK_COUNTER_FILE" ]]; then
        cat "$FALLBACK_COUNTER_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Increment fallback counter
increment_fallback_counter() {
    local counter
    counter=$(get_fallback_counter)
    counter=$((counter + 1))
    echo "$counter" > "$FALLBACK_COUNTER_FILE"
    echo "$counter"
}

# Map circuit breaker state to numeric value
state_to_numeric() {
    local state="$1"
    case "$state" in
        "$CB_STATE_CLOSED")    echo "0" ;;
        "$CB_STATE_OPEN")      echo "1" ;;
        "$CB_STATE_HALF_OPEN") echo "2" ;;
        *)                     echo "-1" ;;
    esac
}

# Export Prometheus metrics
export_prometheus_metrics() {
    # Ensure directory exists
    mkdir -p "$PROMETHEUS_TEXTFILE_DIR" 2>/dev/null || {
        log_warn "Cannot create Prometheus textfile directory: $PROMETHEUS_TEXTFILE_DIR"
        return 1
    }

    local cb_state
    cb_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$cb_state" | jq -r '.state')
    local failure_count
    failure_count=$(echo "$cb_state" | jq -r '.failure_count')
    local success_count
    success_count=$(echo "$cb_state" | jq -r '.success_count')
    local active_provider
    active_provider=$(echo "$cb_state" | jq -r '.active_provider')

    # Check current provider availability
    local primary_available=0
    local fallback_available=0

    if check_primary_provider_health > /dev/null 2>&1; then
        primary_available=1
    fi

    if check_fallback_provider_health > /dev/null 2>&1; then
        fallback_available=1
    fi

    # Get fallback counter
    local fallback_total
    fallback_total=$(get_fallback_counter)

    # Check if we should increment fallback counter (state just changed to OPEN)
    if [[ "$state" == "$CB_STATE_OPEN" ]] && [[ "$failure_count" -eq "$CIRCUIT_BREAKER_FAILURE_THRESHOLD" ]]; then
        fallback_total=$(increment_fallback_counter)
    fi

    # Get state numeric value
    local state_numeric
    state_numeric=$(state_to_numeric "$state")

    # Build metrics file
    cat > "$PROMETHEUS_METRICS_FILE.tmp" << EOF
# HELP llm_provider_available Whether the LLM provider is available (1=available, 0=unavailable)
# TYPE llm_provider_available gauge
llm_provider_available{provider="$PRIMARY_PROVIDER"} $primary_available
llm_provider_available{provider="$FALLBACK_PROVIDER"} $fallback_available

# HELP llm_fallback_triggered_total Total number of times fallback was triggered
# TYPE llm_fallback_triggered_total counter
llm_fallback_triggered_total $fallback_total

# HELP moltis_circuit_state Circuit breaker state (0=closed, 1=open, 2=half-open)
# TYPE moltis_circuit_state gauge
moltis_circuit_state $state_numeric

# HELP moltis_circuit_failures Current failure count in circuit breaker
# TYPE moltis_circuit_failures gauge
moltis_circuit_failures $failure_count

# HELP moltis_circuit_successes Current success count in circuit breaker
# TYPE moltis_circuit_successes gauge
moltis_circuit_successes $success_count

# HELP moltis_active_provider Currently active LLM provider
# TYPE moltis_active_provider gauge
moltis_active_provider{provider="$active_provider"} 1
EOF

    # Atomic rename
    mv "$PROMETHEUS_METRICS_FILE.tmp" "$PROMETHEUS_METRICS_FILE" 2>/dev/null || {
        log_warn "Failed to write Prometheus metrics file"
        return 1
    }

    log_info "Prometheus metrics exported to $PROMETHEUS_METRICS_FILE"
}

# Output current metrics to stdout (for debugging)
show_prometheus_metrics() {
    local cb_state
    cb_state=$(get_circuit_breaker_state)
    local state
    state=$(echo "$cb_state" | jq -r '.state')

    echo "# LLM Provider Metrics"
    echo "llm_provider_available{provider=\"$PRIMARY_PROVIDER\"} $(check_primary_provider_health > /dev/null 2>&1 && echo 1 || echo 0)"
    echo "llm_provider_available{provider=\"$FALLBACK_PROVIDER\"} $(check_fallback_provider_health > /dev/null 2>&1 && echo 1 || echo 0)"
    echo "llm_fallback_triggered_total $(get_fallback_counter)"
    echo "moltis_circuit_state $(state_to_numeric "$state")"
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

    if deploy_mutex_active; then
        log_warn "Skipping container restart for $container while deploy mutex is active"
        return 1
    fi

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

    if deploy_mutex_active; then
        log_warn "Skipping full recovery for $container while deploy mutex is active"
        return 1
    fi

    log_error "Initiating full recovery for $container"
    send_alert "Full Recovery" "Starting full recovery for $container"

    # Stop container
    log_info "Stopping container $container"
    docker stop "$container" 2>/dev/null || true

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Compose file not found for recovery: $COMPOSE_FILE"
        send_alert "Recovery Failed" "Compose file missing: $COMPOSE_FILE"
        return 1
    fi

    # Recreate container from the active deploy root, not from whichever worktree installed the service.
    log_info "Recreating container from compose file $COMPOSE_FILE (project: $COMPOSE_PROJECT_NAME)"
    docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d --no-deps --force-recreate "$container"

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

        if [[ "$DISK_AUTO_CLEANUP_ENABLED" == "true" ]]; then
            if deploy_mutex_active; then
                log_warn "Skipping Docker image cleanup while deploy mutex is active"
            elif disk_cleanup_due; then
                # Keep cleanup scoped to unused images/build cache. Do not prune
                # containers or networks from a background monitor.
                log_info "Running Docker image/build-cache cleanup (cooldown ${DISK_CLEANUP_COOLDOWN_SECONDS}s)"
                docker image prune -af 2>/dev/null || true
                docker builder prune -af --filter "until=${DISK_BUILDER_PRUNE_UNTIL}" 2>/dev/null || true
                record_disk_cleanup_epoch
            else
                log_info "Skipping Docker image cleanup; cooldown window is still active"
            fi
        fi

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
    local deploy_suppressed=false

    while true; do
        if deploy_mutex_active; then
            if [[ "$deploy_suppressed" != "true" ]]; then
                log_info "Deploy mutex active; suspending mutating health-monitor actions"
                deploy_suppressed=true
            fi
            consecutive_failures=0
            sleep "$HEALTH_CHECK_INTERVAL"
            continue
        fi

        if [[ "$deploy_suppressed" == "true" ]]; then
            log_info "Deploy mutex cleared; resuming active health monitoring"
            deploy_suppressed=false
        fi

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
        check_disk_space 90 || true
        check_memory 90 || true

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

parse_args() {
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
}

# Signal handlers
cleanup() {
    log_info "Health monitor shutting down"
    exit 0
}

# Run main only when executed directly, not when sourced by tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    disable_colors
    trap cleanup SIGTERM SIGINT
    main "$@"
fi
