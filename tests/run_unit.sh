#!/bin/bash
# Moltis Unit Test Runner
# Runs all unit tests from tests/unit/ directory
#
# Usage:
#   ./tests/run_unit.sh [OPTIONS]
#
# Options:
#   --json       Output results in JSON format
#   --verbose    Enable verbose output
#   --filter PATTERN  Run only tests matching pattern
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
UNIT_DIR="$SCRIPT_DIR/unit"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Output options
FILTER_PATTERN=""
OUTPUT_JSON=false
VERBOSE=false

# ==============================================================================
# USAGE
# ==============================================================================

show_help() {
    cat << EOF
Moltis Unit Test Runner

Runs all unit tests from tests/unit/ directory.

USAGE:
    ./tests/run_unit.sh [OPTIONS]

OPTIONS:
    --json           Output results in JSON format
    --verbose        Enable verbose output
    --filter PATTERN Run only tests matching pattern
    -h, --help       Show this help message

EXAMPLES:
    # Run all unit tests
    ./tests/run_unit.sh

    # Run with JSON output
    ./tests/run_unit.sh --json

    # Run only circuit breaker tests
    ./tests/run_unit.sh --filter "circuit_breaker"

    # Run with verbose output
    ./tests/run_unit.sh --verbose

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

    # Ensure unit directory exists
    if [[ ! -d "$UNIT_DIR" ]]; then
        log_warn "Unit test directory not found: $UNIT_DIR"
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
    done < <(find "$UNIT_DIR" -type f -name "*.sh" -print0 2>/dev/null | sort -z)

    echo "${test_files[@]}"
}

# Count test files
count_test_files() {
    local count=0
    if [[ -d "$UNIT_DIR" ]]; then
        count=$(find "$UNIT_DIR" -type f -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo "$count"
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

    # Source the test file and explicitly call run_all_tests
    # This ensures test functions are loaded in current shell
    source "$test_file"

    # Call run_all_tests if it exists
    if declare -f run_all_tests > /dev/null; then
        run_all_tests
    else
        log_error "run_all_tests function not found in: $test_file"
        test_fail "Test file missing run_all_tests function: $test_file"
        return 1
    fi
}

# Run all test files
run_all_tests() {
    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$UNIT_DIR" -type f -name "*.sh" -print0 2>/dev/null | sort -z)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        if [[ -n "$FILTER_PATTERN" ]]; then
            log_warn "No tests found matching pattern: $FILTER_PATTERN"
        else
            log_warn "No unit tests found in: $UNIT_DIR"
        fi
        return 0
    fi

    log_info "Found ${#test_files[@]} unit test(s)"

    for test_file in "${test_files[@]}"; do
        run_test_file "$test_file"
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
        echo "  Moltis Unit Tests"
        echo "========================================="
        echo ""

        if [[ -n "$FILTER_PATTERN" ]]; then
            echo "Filter: $FILTER_PATTERN"
            echo ""
        fi
    fi

    # Run all tests
    run_all_tests

    # Generate report
    generate_report
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
