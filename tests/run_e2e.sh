#!/bin/bash
# Moltis E2E Test Runner
# Runs all end-to-end tests from tests/e2e/ directory
#
# Usage:
#   ./tests/run_e2e.sh [OPTIONS]
#
# Options:
#   --json       Output results in JSON format
#   --verbose    Enable verbose output
#   --timeout N  Set test timeout in seconds (default: 300)
#   --startup-timeout N  Set container startup timeout in seconds (default: 180)
#   --filter PATTERN  Run only tests matching pattern
#   --keep-containers  Don't stop containers after tests
#   -h, --help   Show help message
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Test execution error
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$SCRIPT_DIR/lib"
E2E_DIR="$SCRIPT_DIR/e2e"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Output options
FILTER_PATTERN=""
OUTPUT_JSON=false
VERBOSE=false
TIMEOUT=300
STARTUP_TIMEOUT=180
KEEP_CONTAINERS=false
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-traefik-net}"

# Container management
CONTAINERS_STARTED=false
STARTED_CONTAINERS=()

# ==============================================================================
# USAGE
# ==============================================================================

show_help() {
    cat << EOF
Moltis E2E Test Runner

Runs all end-to-end tests from tests/e2e/ directory.

E2E tests require:
- Full Docker stack running
- All services healthy
- Network connectivity
- Sufficient test timeout

USAGE:
    ./tests/run_e2e.sh [OPTIONS]

OPTIONS:
    --json              Output results in JSON format
    --verbose           Enable verbose output
    --timeout N         Set test timeout in seconds (default: 300)
    --startup-timeout N Set startup timeout in seconds (default: 180)
    --filter PATTERN    Run only tests matching pattern
    --keep-containers   Don't stop containers after tests
    -h, --help          Show this help message

EXAMPLES:
    # Run all E2E tests with default timeout
    ./tests/run_e2e.sh

    # Run with custom timeout (10 minutes)
    ./tests/run_e2e.sh --timeout 600

    # Run only chat flow tests
    ./tests/run_e2e.sh --filter "chat_flow"

    # Run with JSON output and keep containers running
    ./tests/run_e2e.sh --json --keep-containers

EXIT CODES:
    0 - All tests passed
    1 - One or more tests failed
    2 - Test execution error

EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                set_json_output true
                shift
                ;;
            --verbose)
                set_verbose true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --startup-timeout)
                STARTUP_TIMEOUT="$2"
                shift 2
                ;;
            --filter)
                FILTER_PATTERN="$2"
                shift 2
                ;;
            --keep-containers)
                KEEP_CONTAINERS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 2
                ;;
        esac
    done
}

# ==============================================================================
# TEST DISCOVERY
# ==============================================================================

# Find all test files
find_test_files() {
    local test_files=()

    # Ensure e2e directory exists
    if [[ ! -d "$E2E_DIR" ]]; then
        log_warn "E2E test directory not found: $E2E_DIR"
        return 0
    fi

    # Find all test scripts
    while IFS= read -r -d '' file; do
        # Apply filter if specified
        if [[ -n "$FILTER_PATTERN" ]]; then
            if [[ "$file" =~ $FILTER_PATTERN ]]; then
                test_files+=("$file")
            fi
        else
            test_files+=("$file")
        fi
    done < <(find "$E2E_DIR" -type f -name "*.sh" -print0 2>/dev/null | sort -z)

    printf '%s\n' "${test_files[@]}"
}

# ==============================================================================
# CONTAINER MANAGEMENT
# ==============================================================================

# Ensure external Traefik network exists for docker-compose.prod.yml
ensure_traefik_network() {
    if docker network ls --format '{{.Name}}' | grep -qx "$TRAEFIK_NETWORK" 2>/dev/null; then
        return 0
    fi

    log_warn "Network $TRAEFIK_NETWORK not found, creating..."
    if docker network create "$TRAEFIK_NETWORK" > /dev/null 2>&1; then
        log_info "Created network $TRAEFIK_NETWORK"
        return 0
    fi

    log_error "Failed to create required network: $TRAEFIK_NETWORK"
    return 1
}

# Ensure required bind-mount directories from compose file exist
ensure_bind_mount_dirs() {
    local required_dirs=(
        "$PROJECT_ROOT/data"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || {
                log_error "Failed to create required directory: $dir"
                return 1
            }
        fi
    done

    return 0
}

# Start compose command with an internal timeout (portable, no external timeout binary)
run_compose_up_with_timeout() {
    local log_file="/tmp/moltis-e2e-compose-up-$$.log"
    local compose_pid=0
    local waited=0
    local exit_code=0

    docker compose -f docker-compose.prod.yml up -d moltis > "$log_file" 2>&1 &
    compose_pid=$!

    while kill -0 "$compose_pid" 2>/dev/null; do
        if [[ $waited -ge $STARTUP_TIMEOUT ]]; then
            kill "$compose_pid" 2>/dev/null || true
            wait "$compose_pid" 2>/dev/null || true
            if [[ "$OUTPUT_JSON" != "true" ]] && [[ -s "$log_file" ]]; then
                cat "$log_file"
            fi
            rm -f "$log_file"
            return 124
        fi

        sleep 1
        ((waited += 1)) || true
    done

    set +e
    wait "$compose_pid"
    exit_code=$?
    set -e

    if [[ "$OUTPUT_JSON" != "true" ]] && [[ -s "$log_file" ]]; then
        cat "$log_file"
    fi
    rm -f "$log_file"

    return "$exit_code"
}

# Start required containers for E2E tests
start_containers() {
    log_info "Starting containers for E2E tests..."

    cd "$PROJECT_ROOT"

    # Check if containers are already running
    if docker ps --format '{{.Names}}' | grep -q '^moltis$'; then
        log_info "Moltis container already running"
        CONTAINERS_STARTED=false
        return 0
    fi

    if ! ensure_traefik_network; then
        return 1
    fi

    if ! ensure_bind_mount_dirs; then
        return 1
    fi

    # Start only the service required for E2E API checks
    local compose_exit=0
    if run_compose_up_with_timeout; then
        compose_exit=0
    else
        compose_exit=$?
    fi

    if [[ $compose_exit -eq 0 ]]; then
        log_info "Containers started successfully"
        CONTAINERS_STARTED=true
        STARTED_CONTAINERS=("moltis")

        # Wait for health check
        log_info "Waiting for containers to be healthy..."
        local max_wait=60
        local waited=0

        while [[ $waited -lt $max_wait ]]; do
            if docker inspect --format='{{.State.Health.Status}}' moltis 2>/dev/null | grep -q "healthy"; then
                log_info "Moltis is healthy"
                break
            fi
            sleep 2
            ((waited += 2)) || true
        done

        if [[ $waited -ge $max_wait ]]; then
            log_warn "Moltis did not become healthy within ${max_wait}s"
        fi
    else
        if [[ $compose_exit -eq 124 ]]; then
            log_error "Timed out starting containers after ${STARTUP_TIMEOUT}s"
        else
            log_error "Failed to start containers"
        fi
        return 1
    fi
}

# Stop containers that were started for E2E tests
stop_containers() {
    if [[ "$KEEP_CONTAINERS" == "true" ]]; then
        log_info "Keeping containers running (--keep-containers)"
        return 0
    fi

    if [[ "$CONTAINERS_STARTED" == "true" ]]; then
        log_info "Stopping containers..."

        cd "$PROJECT_ROOT"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            docker compose -f docker-compose.prod.yml stop moltis > /dev/null 2>&1 || true
        else
            docker compose -f docker-compose.prod.yml stop moltis 2>&1 || true
        fi

        log_info "Containers stopped"
    fi
}

# Cleanup on exit
cleanup() {
    local exit_code=$?

    log_info "Cleaning up..."

    # Stop containers
    stop_containers

    exit $exit_code
}

# Register cleanup handler
trap cleanup EXIT INT TERM

# ==============================================================================
# TEST EXECUTION
# ==============================================================================

# Run a single test file with timeout
run_test_file() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)

    test_start "$test_name"
    log_info "Running: $test_name (timeout: ${TIMEOUT}s)"

    local output
    local exit_code

    set +e
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        timeout "$TIMEOUT" bash "$test_file" > /dev/null 2>&1
        exit_code=$?
    else
        output=$(timeout "$TIMEOUT" bash "$test_file" 2>&1)
        exit_code=$?
    fi
    set -e

    if [[ "$OUTPUT_JSON" != "true" ]] && [[ -n "${output:-}" ]]; then
        echo "$output"
    fi

    case "${exit_code:-0}" in
        0)
            test_pass
            ;;
        2)
            test_skip "Test prerequisites not met"
            ;;
        124)
            log_error "Test timed out after ${TIMEOUT}s: $test_name"
            test_fail "Test timed out: $test_name"
            ;;
        *)
            log_error "Test failed with exit code ${exit_code:-unknown}: $test_name"
            test_fail "Test failed: $test_name"
            ;;
    esac
}

# Run all test files
run_all_tests() {
    local test_files=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && test_files+=("$line")
    done < <(find_test_files)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        if [[ -n "$FILTER_PATTERN" ]]; then
            log_warn "No tests found matching pattern: $FILTER_PATTERN"
        else
            log_warn "No E2E tests found in: $E2E_DIR"
        fi
        return 0
    fi

    log_info "Found ${#test_files[@]} E2E test(s)"

    for test_file in "${test_files[@]}"; do
        if ! run_test_file "$test_file"; then
            log_warn "Unexpected runner failure: $test_file"
        fi
    done
}

# ==============================================================================
# TIMING METRICS
# ==============================================================================

# Format seconds as human-readable duration
format_duration() {
    local seconds="$1"

    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    # Parse arguments
    parse_args "$@"

    # Start timer
    start_timer

    # Print header (only in text mode)
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Moltis End-to-End Tests"
        echo "========================================="
        echo ""

        if [[ -n "$FILTER_PATTERN" ]]; then
            echo "Filter: $FILTER_PATTERN"
        fi

        echo "Timeout: $(format_duration "$TIMEOUT")"
        echo ""
    fi

    # Start containers
    if ! start_containers; then
        test_start "environment_startup"
        test_fail "Failed to start required containers for E2E tests"
        generate_report
        return 1
    fi

    # Run all tests
    run_all_tests

    # Generate report
    local elapsed
    elapsed=$(get_elapsed_time)

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        # Append timing to JSON
        generate_report | jq --argjson duration "$elapsed" '.summary.timing = {duration_seconds: $duration, formatted: "'$(format_duration "$elapsed")'"}'
    else
        echo ""
        echo "Total time: $(format_duration "$elapsed")"
        generate_report
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
