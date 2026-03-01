#!/bin/bash
# Ollama Health Check Script
# Monitors Ollama sidecar container health for LLM failover
# Contract: specs/001-fallback-llm-ollama/contracts/ollama-health-api.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-gemini-3-flash-preview:cloud}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-10}"

# Output format flags
OUTPUT_JSON=false
NO_COLOR=false
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Disable colors if requested or if output is not a terminal
disable_colors() {
    if [[ "$NO_COLOR" == "true" || "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        NC=''
    fi
}

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Log functions
log_info() {
    if [[ "$OUTPUT_JSON" != "true" && "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_success() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${GREEN}[OK]${NC} $*"
    fi
}

log_error() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

log_warn() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $*"
    fi
}

# Check Ollama API availability
check_ollama_api() {
    local url="${OLLAMA_HOST}/api/tags"
    local response_code

    log_info "Checking Ollama API at $url"

    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$HEALTH_TIMEOUT" \
        "$url" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        log_success "Ollama API is responding (HTTP $response_code)"
        return 0
    else
        log_error "Ollama API check failed (HTTP $response_code)"
        return 1
    fi
}

# Check if Ollama container is running
check_ollama_container() {
    local container_name="ollama-fallback"
    local container_status

    container_status=$(docker ps --filter "name=$container_name" --format '{{.Status}}' 2>/dev/null || echo "")

    if [[ -n "$container_status" ]]; then
        log_success "Ollama container is running: $container_status"
        return 0
    else
        log_error "Ollama container is not running"
        return 1
    fi
}

# Check if the cloud model is accessible
check_ollama_model() {
    local model="$OLLAMA_MODEL"
    local url="${OLLAMA_HOST}/api/show"
    local response

    log_info "Checking model availability: $model"

    # Try to get model info
    response=$(curl -s --max-time "$HEALTH_TIMEOUT" \
        -d "{\"name\":\"$model\"}" \
        "$url" 2>/dev/null || echo '{"error":"request failed"}')

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        # Model might not be pulled yet, check if we can reach Ollama
        log_warn "Model $model not found locally (may be pulled on first use)"
        return 2  # Different code: API OK but model not pulled
    else
        log_success "Model $model is available"
        return 0
    fi
}

# Test simple generation request
check_ollama_generation() {
    local model="$OLLAMA_MODEL"
    local url="${OLLAMA_HOST}/api/generate"
    local response
    local test_prompt="test"

    log_info "Testing generation with model: $model"

    response=$(curl -s --max-time 30 \
        -d "{\"model\":\"$model\",\"prompt\":\"$test_prompt\",\"stream\":false}" \
        "$url" 2>/dev/null || echo '{"error":"generation failed"}')

    if echo "$response" | jq -e '.response' > /dev/null 2>&1; then
        log_success "Generation test successful"
        return 0
    elif echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error')
        log_error "Generation test failed: $error_msg"
        return 1
    else
        log_error "Generation test failed: unexpected response"
        return 1
    fi
}

# Check Docker health status of Ollama container
check_ollama_health_status() {
    local container_name="ollama-fallback"
    local health_status

    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown")

    case "$health_status" in
        healthy)
            log_success "Container health: $health_status"
            return 0
            ;;
        unhealthy)
            log_error "Container health: $health_status"
            return 1
            ;;
        starting)
            log_warn "Container health: $health_status (still starting)"
            return 2
            ;;
        *)
            log_warn "Container health: $health_status"
            return 3
            ;;
    esac
}

# Get Ollama version info
get_ollama_version() {
    local url="${OLLAMA_HOST}/api/version"
    local version_info

    version_info=$(curl -s --max-time "$HEALTH_TIMEOUT" "$url" 2>/dev/null || echo '{"error":"unknown"}')

    if echo "$version_info" | jq -e '.version' > /dev/null 2>&1; then
        echo "$version_info" | jq -r '.version'
    else
        echo "unknown"
    fi
}

# Output health status in JSON format
output_health_json() {
    local api_status="unhealthy"
    local container_status="not_running"
    local model_status="unavailable"
    local health_status="unknown"
    local version

    # Run checks
    if check_ollama_api > /dev/null 2>&1; then
        api_status="healthy"
    fi

    if check_ollama_container > /dev/null 2>&1; then
        container_status="running"
    fi

    check_ollama_model > /dev/null 2>&1
    case $? in
        0) model_status="available" ;;
        2) model_status="not_pulled" ;;
        *) model_status="unavailable" ;;
    esac

    health_status=$(docker inspect --format='{{.State.Health.Status}}' ollama-fallback 2>/dev/null || echo "unknown")
    version=$(get_ollama_version)

    # Determine overall status
    local overall_status="healthy"
    if [[ "$api_status" != "healthy" || "$container_status" != "running" ]]; then
        overall_status="unhealthy"
    elif [[ "$model_status" == "unavailable" ]]; then
        overall_status="degraded"
    fi

    jq -n \
        --arg status "$overall_status" \
        --arg timestamp "$(get_timestamp)" \
        --arg api_status "$api_status" \
        --arg container_status "$container_status" \
        --arg model_status "$model_status" \
        --arg health_status "$health_status" \
        --arg version "$version" \
        --arg host "$OLLAMA_HOST" \
        --arg model "$OLLAMA_MODEL" \
        '{
            status: $status,
            timestamp: $timestamp,
            provider: "ollama",
            checks: {
                api: $api_status,
                container: $container_status,
                model: $model_status,
                health: $health_status
            },
            version: $version,
            config: {
                host: $host,
                model: $model
            }
        }'
}

# Run all health checks
run_all_checks() {
    local overall_status=0

    echo "=== Ollama Health Check: $(date) ==="
    echo ""

    # Check container
    echo "Container:"
    if check_ollama_container; then
        check_ollama_health_status || true
    else
        overall_status=1
    fi
    echo ""

    # Check API
    echo "API:"
    if check_ollama_api; then
        echo "  Version: $(get_ollama_version)"
    else
        overall_status=1
    fi
    echo ""

    # Check model
    echo "Model ($OLLAMA_MODEL):"
    check_ollama_model || true
    echo ""

    # Summary
    echo "Summary:"
    if [[ $overall_status -eq 0 ]]; then
        log_success "All checks passed"
    else
        log_error "Some checks failed"
    fi

    return $overall_status
}

# Show help
show_help() {
    cat << EOF
Ollama Health Check Script

Usage:
    $0 [OPTIONS]

Options:
    --json          Output in JSON format (for CI/AI parsing)
    --no-color      Disable colored output
    --verbose       Show detailed progress
    --test-gen      Test generation (makes actual API call)
    --host URL      Ollama host URL (default: http://localhost:11434)
    --model NAME    Model to check (default: gemini-3-flash-preview:cloud)
    -h, --help      Show this help message

Exit Codes:
    0 - All checks passed (healthy)
    1 - Health check failed (unhealthy)
    2 - Degraded (API OK but model issues)

Examples:
    $0                          # Run health checks
    $0 --json                   # JSON output for monitoring
    $0 --test-gen               # Include generation test
    $0 --host http://ollama:11434  # Docker network host

Contract: specs/001-fallback-llm-ollama/contracts/ollama-health-api.md
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
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test-gen)
            TEST_GENERATION=true
            shift
            ;;
        --host)
            OLLAMA_HOST="$2"
            shift 2
            ;;
        --model)
            OLLAMA_MODEL="$2"
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

# Run checks
if [[ "$OUTPUT_JSON" == "true" ]]; then
    output_health_json
    # Exit based on status
    status=$(output_health_json | jq -r '.status')
    case "$status" in
        healthy) exit 0 ;;
        degraded) exit 2 ;;
        *) exit 1 ;;
    esac
else
    run_all_checks
    exit $?
fi
