#!/bin/bash
# Moltis Integration Test Runner
# Runs all integration tests from tests/integration/ directory
#
# Usage:
#   ./tests/run_integration.sh [OPTIONS]
#
# Options:
#   --json       Output results in JSON format
#   --verbose    Enable verbose output
#   --filter PATTERN  Run only tests matching pattern
#   --parallel   Run tests in parallel (experimental)
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
INTEGRATION_DIR="$SCRIPT_DIR/integration"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Output options
FILTER_PATTERN=""
OUTPUT_JSON=false
VERBOSE=false
PARALLEL=false

# Parallel execution
PARALLEL_JOBS=4

# ==============================================================================
# USAGE
# ==============================================================================

show_help() {
    cat << EOF
Moltis Integration Test Runner

Runs all integration tests from tests/integration/ directory.

Integration tests require:
- Docker daemon running
- Moltis container running (or ability to start it)
- Network connectivity for external service tests

USAGE:
    ./tests/run_integration.sh [OPTIONS]

OPTIONS:
    --json           Output results in JSON format
    --verbose        Enable verbose output
    --filter PATTERN Run only tests matching pattern
    --parallel       Run tests in parallel (experimental)
    -h, --help       Show this help message

EXAMPLES:
    # Run all integration tests
    ./tests/run_integration.sh

    # Run with JSON output for CI/CD
    ./tests/run_integration.sh --json

    # Run only LLM failover tests
    ./tests/run_integration.sh --filter "failover"

    # Run in parallel (faster but less ordered output)
    ./tests/run_integration.sh --parallel

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
            --filter)
                FILTER_PATTERN="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL=true
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

    # Ensure integration directory exists
    if [[ ! -d "$INTEGRATION_DIR" ]]; then
        log_warn "Integration test directory not found: $INTEGRATION_DIR"
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
    done < <(find "$INTEGRATION_DIR" -type f -name "*.sh" -print0 2>/dev/null | sort -z)

    # Print each file on its own line so the reader loop keeps entries separated.
    printf '%s\n' "${test_files[@]}"
}

# ==============================================================================
# PRE-CHECKS
# ==============================================================================

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi

    return 0
}

# Check if required containers are running
check_moltis_container() {
    if docker ps --format '{{.Names}}' | grep -q '^moltis$'; then
        log_debug "Moltis container is running"
        return 0
    else
        log_warn "Moltis container is not running (some tests may fail)"
        return 1
    fi
}

# Run pre-flight checks
run_preflight_checks() {
    local all_passed=true

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "Running pre-flight checks..."
    fi

    if ! check_docker; then
        all_passed=false
    fi

    # Moltis container check is optional (some tests may not need it)
    check_moltis_container || true

    if [[ "$all_passed" == "true" ]]; then
        if [[ "$OUTPUT_JSON" != "true" ]]; then
            echo -e "${GREEN}✓ Pre-flight checks passed${NC}"
        fi
    else
        if [[ "$OUTPUT_JSON" != "true" ]]; then
            echo -e "${YELLOW}⚠ Some pre-flight checks failed${NC}"
        fi
    fi

    echo ""
}

# ==============================================================================
# TEST EXECUTION
# ==============================================================================

# Run a single test file
run_test_file() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)

    log_info "Running: $test_name"

    # Source the test file and explicitly call run_all_tests.
    source "$test_file"

    if declare -f run_all_tests > /dev/null; then
        run_all_tests
    else
        log_error "run_all_tests function not found in: $test_file"
        test_fail "Test file missing run_all_tests function: $test_file"
        return 1
    fi
}

# Run all test files sequentially
run_all_tests() {
    local test_files=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && test_files+=("$line")
    done < <(find_test_files)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        if [[ -n "$FILTER_PATTERN" ]]; then
            log_warn "No tests found matching pattern: $FILTER_PATTERN"
        else
            log_warn "No integration tests found in: $INTEGRATION_DIR"
        fi
        return 0
    fi

    log_info "Found ${#test_files[@]} integration test(s)"

    for test_file in "${test_files[@]}"; do
        run_test_file "$test_file"
    done
}

# Run tests in parallel (experimental)
run_all_tests_parallel() {
    local test_files=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && test_files+=("$line")
    done < <(find_test_files)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warn "No integration tests found"
        return 0
    fi

    log_info "Running ${#test_files[@]} tests in parallel (max $PARALLEL_JOBS jobs)"

    local pids=()
    local results=()

    for test_file in "${test_files[@]}"; do
        # Wait if we have too many background jobs
        while [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    # Process has finished
                    wait "${pids[$i]}" || true
                    unset "pids[$i]"
                fi
            done
            pids=("${pids[@]}")  # Reindex array
            sleep 0.1
        done

        # Run test in background
        (
            source "$LIB_DIR/test_helpers.sh"
            set_json_output "$OUTPUT_JSON"
            source "$test_file"
            if declare -f run_all_tests > /dev/null; then
                run_all_tests
            else
                echo "Missing run_all_tests in $test_file" >&2
                exit 1
            fi
        ) &
        pids+=($!)
    done

    # Wait for all remaining tests
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
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
        echo "  Moltis Integration Tests"
        echo "========================================="
        echo ""

        if [[ -n "$FILTER_PATTERN" ]]; then
            echo "Filter: $FILTER_PATTERN"
        fi

        if [[ "$PARALLEL" == "true" ]]; then
            echo "Parallel: enabled (max $PARALLEL_JOBS jobs)"
        fi

        echo ""
    fi

    # Run pre-flight checks
    run_preflight_checks

    # Run all tests
    if [[ "$PARALLEL" == "true" ]]; then
        run_all_tests_parallel
    else
        run_all_tests
    fi

    # Individual test files generate their own report.
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
