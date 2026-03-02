#!/bin/bash
# Moltis Security Test Runner
# Runs all security tests from tests/security/ directory
#
# Usage:
#   ./tests/run_security.sh [OPTIONS]
#
# Options:
#   --json       Output results in JSON format
#   --verbose    Enable verbose output
#   --filter PATTERN  Run only tests matching pattern
#   --severity LEVEL  Filter by severity (low|medium|high|critical)
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
SECURITY_DIR="$SCRIPT_DIR/security"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Output options
FILTER_PATTERN=""
OUTPUT_JSON=false
VERBOSE=false
SEVERITY_FILTER=""

# Security results
declare -ga SECURITY_FINDINGS=()
declare -g VULNERABILITY_COUNT=0

# ==============================================================================
# USAGE
# ==============================================================================

show_help() {
    cat << EOF
Moltis Security Test Runner

Runs all security tests from tests/security/ directory.

Security tests include:
- Authentication and authorization tests
- Input validation and sanitization
- XSS and injection attack vectors
- Secret and credential exposure
- Container security
- Network security

USAGE:
    ./tests/run_security.sh [OPTIONS]

OPTIONS:
    --json              Output results in JSON format
    --verbose           Enable verbose output
    --filter PATTERN    Run only tests matching pattern
    --severity LEVEL    Filter by severity (low|medium|high|critical)
    -h, --help          Show this help message

EXAMPLES:
    # Run all security tests
    ./tests/run_security.sh

    # Run only critical severity tests
    ./tests/run_security.sh --severity critical

    # Run authentication tests
    ./tests/run_security.sh --filter "auth"

    # Run with JSON output for security reports
    ./tests/run_security.sh --json

EXIT CODES:
    0 - All tests passed (no security issues found)
    1 - One or more tests failed (security issues found)
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
            --severity)
                SEVERITY_FILTER="$2"
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

    # Ensure security directory exists
    if [[ ! -d "$SECURITY_DIR" ]]; then
        log_warn "Security test directory not found: $SECURITY_DIR"
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
    done < <(find "$SECURITY_DIR" -type f -name "*.sh" -print0 2>/dev/null | sort -z)

    echo "${test_files[@]}"
}

# ==============================================================================
# SECURITY TEST HELPERS
# ==============================================================================

# Report a security finding
# Usage: report_finding "description" "severity" "location"
report_finding() {
    local description="$1"
    local severity="${2:-medium}"
    local location="${3:-unknown}"

    # Filter by severity if specified
    if [[ -n "$SEVERITY_FILTER" && "$severity" != "$SEVERITY_FILTER" ]]; then
        return 0
    fi

    ((VULNERABILITY_COUNT++)) || true
    SECURITY_FINDINGS+=("{\"description\":\"$description\",\"severity\":\"$severity\",\"location\":\"$location\"}")

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        case "$severity" in
            critical)
                echo -e "${RED}[CRITICAL]${NC} $description at $location" >&2
                ;;
            high)
                echo -e "${RED}[HIGH]${NC} $description at $location" >&2
                ;;
            medium)
                echo -e "${YELLOW}[MEDIUM]${NC} $description at $location" >&2
                ;;
            low)
                echo -e "${YELLOW}[LOW]${NC} $description at $location" >&2
                ;;
            *)
                echo -e "[INFO] $description at $location" >&2
                ;;
        esac
    fi
}

# Check for exposed secrets
# Usage: check_secrets_exposure
check_secrets_exposure() {
    log_debug "Checking for exposed secrets..."

    local secret_patterns=(
        "sk-[a-zA-Z0-9]{32,}"  # Stripe API keys
        "ghp_[a-zA-Z0-9]{36,}"  # GitHub personal access tokens
        "AKIA[0-9A-Z]{16}"      # AWS access keys
        "AIza[0-9A-Za-z\\-_]{35}"  # Google API keys
        "[0-9]+:[0-9A-Za-z\\-_]{33,}"  # Telegram bot tokens
    )

    # Check config files
    local config_files=(
        "$PROJECT_ROOT/docker-compose.yml"
        "$PROJECT_ROOT/docker-compose.prod.yml"
        "$PROJECT_ROOT/.env.example"
    )

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            for pattern in "${secret_patterns[@]}"; do
                if grep -rE "$pattern" "$file" 2>/dev/null; then
                    report_finding "Potential secret exposed in config" "critical" "$file"
                fi
            done
        fi
    done
}

# Check for weak authentication
# Usage: check_weak_authentication
check_weak_authentication() {
    log_debug "Checking for weak authentication..."

    # Check for default passwords
    if [[ -f "$PROJECT_ROOT/docker-compose.prod.yml" ]]; then
        if grep -qE "password.*=.*(password|123456|admin|root)" "$PROJECT_ROOT/docker-compose.prod.yml"; then
            report_finding "Default or weak password detected" "high" "docker-compose.prod.yml"
        fi
    fi
}

# Check for insecure HTTP usage
# Usage: check_insecure_http
check_insecure_http() {
    log_debug "Checking for insecure HTTP usage..."

    # Check for HTTP endpoints that should be HTTPS
    local insecure_patterns=(
        "http://api.openai.com"
        "http://www.googleapis.com"
        "http://api.telegram.org"
    )

    for file in "$PROJECT_ROOT"/config/*.toml; do
        if [[ -f "$file" ]]; then
            for pattern in "${insecure_patterns[@]}"; do
                if grep -qF "$pattern" "$file" 2>/dev/null; then
                    report_finding "Insecure HTTP endpoint detected" "medium" "$file"
                fi
            done
        fi
    done
}

# Run built-in security checks
run_builtin_checks() {
    log_info "Running built-in security checks..."

    check_secrets_exposure
    check_weak_authentication
    check_insecure_http
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

    # Source and run the test file
    if source "$test_file"; then
        log_debug "Test file sourced successfully: $test_file"
    else
        log_error "Failed to source test file: $test_file"
        test_fail "Failed to execute test file: $test_name"
        return 1
    fi
}

# Run all test files
run_all_tests() {
    local test_files
    mapfile -t test_files < <(find_test_files)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        if [[ -n "$FILTER_PATTERN" ]]; then
            log_warn "No tests found matching pattern: $FILTER_PATTERN"
        else
            log_warn "No security tests found in: $SECURITY_DIR"
        fi
        return 0
    fi

    log_info "Found ${#test_files[@]} security test(s)"

    for test_file in "${test_files[@]}"; do
        run_test_file "$test_file"
    done
}

# ==============================================================================
# REPORTING
# ==============================================================================

# Generate security report
generate_security_report() {
    local exit_code=0

    # Determine overall status
    local status="pass"
    if [[ $VULNERABILITY_COUNT -gt 0 ]]; then
        # Check for critical or high severity
        local critical_count=0
        local high_count=0

        for finding in "${SECURITY_FINDINGS[@]}"; do
            local severity
            severity=$(echo "$finding" | jq -r '.severity')
            if [[ "$severity" == "critical" ]]; then
                ((critical_count++)) || true
            elif [[ "$severity" == "high" ]]; then
                ((high_count++)) || true
            fi
        done

        if [[ $critical_count -gt 0 || $high_count -gt 0 ]]; then
            status="fail"
            exit_code=1
        else
            status="warning"
        fi
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        generate_security_report_json "$status"
    else
        generate_security_report_text "$status"
    fi

    return $exit_code
}

# Generate security report in text format
generate_security_report_text() {
    local status="$1"

    echo ""
    echo "========================================="
    echo "  Security Test Results"
    echo "========================================="
    echo ""

    # Overall status
    if [[ "$status" == "pass" ]]; then
        echo -e "${GREEN}✓ No security issues found${NC}"
    elif [[ "$status" == "fail" ]]; then
        echo -e "${RED}✗ Security vulnerabilities found${NC}"
    else
        echo -e "${YELLOW}⚠ Security warnings found${NC}"
    fi

    echo ""
    echo "Tests run: $TESTS_TOTAL"
    echo "Passed:   $TESTS_PASSED"
    echo "Failed:   $TESTS_FAILED"
    echo "Skipped:  $TESTS_SKIPPED"
    echo ""
    echo "Vulnerabilities found: $VULNERABILITY_COUNT"

    # Test failures
    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        for failure in "${TEST_FAILURES[@]}"; do
            echo "  - $failure"
        done
    fi

    # Security findings
    if [[ ${#SECURITY_FINDINGS[@]} -gt 0 ]]; then
        echo ""
        echo "Security findings:"
        for finding in "${SECURITY_FINDINGS[@]}"; do
            local desc severity loc
            desc=$(echo "$finding" | jq -r '.description')
            severity=$(echo "$finding" | jq -r '.severity')
            loc=$(echo "$finding" | jq -r '.location')
            echo "  - [$severity] $desc at $loc"
        done
    fi

    echo ""
    echo "========================================="
}

# Generate security report in JSON format
generate_security_report_json() {
    local status="$1"

    # Build findings array
    local findings_json="[]"
    if [[ ${#SECURITY_FINDINGS[@]} -gt 0 ]]; then
        findings_json=$(printf '%s\n' "${SECURITY_FINDINGS[@]}" | jq -s '.')
    fi

    # Count by severity
    local critical_count=0
    local high_count=0
    local medium_count=0
    local low_count=0

    for finding in "${SECURITY_FINDINGS[@]}"; do
        local severity
        severity=$(echo "$finding" | jq -r '.severity')
        case "$severity" in
            critical) ((critical_count++)) || true ;;
            high) ((high_count++)) || true ;;
            medium) ((medium_count++)) || true ;;
            low) ((low_count++)) || true ;;
        esac
    done

    # Output JSON
    jq -n \
        --arg status "$status" \
        --arg timestamp "$(get_timestamp)" \
        --argjson total "$TESTS_TOTAL" \
        --argjson passed "$TESTS_PASSED" \
        --argjson failed "$TESTS_FAILED" \
        --argjson skipped "$TESTS_SKIPPED" \
        --argjson vulnerability_count "$VULNERABILITY_COUNT" \
        --argjson findings "$findings_json" \
        --argjson critical_count "$critical_count" \
        --argjson high_count "$high_count" \
        --argjson medium_count "$medium_count" \
        --argjson low_count "$low_count" \
        '{
            status: $status,
            timestamp: $timestamp,
            summary: {
                total: $total,
                passed: $passed,
                failed: $failed,
                skipped: $skipped
            },
            vulnerabilities: {
                total: $vulnerability_count,
                by_severity: {
                    critical: $critical_count,
                    high: $high_count,
                    medium: $medium_count,
                    low: $low_count
                }
            },
            findings: $findings
        }'

    # Return exit code based on status
    if [[ "$status" == "fail" ]]; then
        return 1
    fi
    return 0
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
        echo "  Moltis Security Tests"
        echo "========================================="
        echo ""

        if [[ -n "$FILTER_PATTERN" ]]; then
            echo "Filter: $FILTER_PATTERN"
        fi

        if [[ -n "$SEVERITY_FILTER" ]]; then
            echo "Severity: $SEVERITY_FILTER"
        fi

        echo ""
    fi

    # Run built-in security checks
    run_builtin_checks

    # Run all test files
    run_all_tests

    # Generate security report
    generate_security_report
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
