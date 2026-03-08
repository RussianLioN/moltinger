#!/usr/bin/env bash
set -euo pipefail

OUTPUT_JSON="${OUTPUT_JSON:-false}"
VERBOSE="${VERBOSE:-false}"
COLOR_ENABLED=true
TEST_REPORT_PATH="${TEST_REPORT_PATH:-}"
JUNIT_REPORT_PATH="${JUNIT_REPORT_PATH:-}"
TEST_SUITE_ID="${TEST_SUITE_ID:-}"
TEST_SUITE_NAME="${TEST_SUITE_NAME:-}"
TEST_LANE="${TEST_LANE:-}"

TEST_CURRENT=""
TEST_CURRENT_ID=""
TEST_CURRENT_STARTED_AT=""
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TESTS_TOTAL=0
TEST_START_TIME=""
TESTS_ALL_SKIPPED=true

declare -a TEST_FAILURES=()
declare -a TEST_SKIP_REASONS=()
declare -a TEST_CASES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

init_colors() {
    if [[ "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        COLOR_ENABLED=false
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        NC=''
    fi
}

log_info() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*" >&2
    fi
}

log_warn() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $*" >&2
    fi
}

log_error() {
    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

log_debug() {
    if [[ "$VERBOSE" == "true" && "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*" >&2
    fi
}

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_ms() {
    local seconds
    seconds=$(date +%s)
    printf '%s000' "$seconds"
}

slugify_case_id() {
    local raw="$1"
    printf '%s' "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//; s/__+/_/g'
}

xml_escape() {
    local input="$1"
    input=${input//&/&amp;}
    input=${input//</&lt;}
    input=${input//>/&gt;}
    input=${input//\"/&quot;}
    input=${input//\'/&apos;}
    printf '%s' "$input"
}

record_case() {
    local status="$1"
    local message="${2:-}"
    local ended_at duration_ms case_json
    ended_at=$(now_ms)
    if [[ -n "$TEST_CURRENT_STARTED_AT" ]]; then
        duration_ms=$((ended_at - TEST_CURRENT_STARTED_AT))
    else
        duration_ms=0
    fi

    case_json=$(jq -n \
        --arg id "$TEST_CURRENT_ID" \
        --arg name "$TEST_CURRENT" \
        --arg status "$status" \
        --arg message "$message" \
        --arg lane "$TEST_LANE" \
        --arg started_at "${TEST_CURRENT_STARTED_AT:-$ended_at}" \
        --arg ended_at "$ended_at" \
        --arg suite_id "$TEST_SUITE_ID" \
        --arg suite_name "${TEST_SUITE_NAME:-$TEST_SUITE_ID}" \
        --argjson duration_ms "$duration_ms" \
        '{
            id: $id,
            name: $name,
            status: $status,
            message: (if $message == "" then null else $message end),
            lane: (if $lane == "" then null else $lane end),
            duration_ms: $duration_ms,
            started_at_ms: ($started_at | tonumber),
            ended_at_ms: ($ended_at | tonumber),
            suite: {
                id: (if $suite_id == "" then null else $suite_id end),
                name: (if $suite_name == "" then null else $suite_name end)
            }
        }')
    TEST_CASES+=("$case_json")
}

test_start() {
    local test_name="$1"
    TEST_CURRENT="$test_name"
    TEST_CURRENT_ID=$(slugify_case_id "$test_name")
    TEST_CURRENT_STARTED_AT=$(now_ms)
    ((TESTS_TOTAL++)) || true

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo -e "${MAGENTA}▶ Test: ${test_name}${NC}"
    fi
}

test_pass() {
    local message="${1:-}"
    if [[ -z "$TEST_CURRENT" ]]; then
        return 0
    fi
    ((TESTS_PASSED++)) || true
    TESTS_ALL_SKIPPED=false
    record_case "passed" "$message"

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        if [[ -n "$message" ]]; then
            echo -e "${GREEN}  ✓ PASS${NC} ${TEST_CURRENT} - ${message}"
        else
            echo -e "${GREEN}  ✓ PASS${NC} ${TEST_CURRENT}"
        fi
    fi

    TEST_CURRENT=""
    TEST_CURRENT_ID=""
    TEST_CURRENT_STARTED_AT=""
}

test_fail() {
    local reason="$1"
    if [[ -z "$TEST_CURRENT" ]]; then
        return 0
    fi
    ((TESTS_FAILED++)) || true
    TESTS_ALL_SKIPPED=false
    TEST_FAILURES+=("${TEST_CURRENT}: ${reason}")
    record_case "failed" "$reason"

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${RED}  ✗ FAIL${NC} ${TEST_CURRENT}"
        echo -e "${RED}    Reason: ${reason}${NC}"
    fi

    TEST_CURRENT=""
    TEST_CURRENT_ID=""
    TEST_CURRENT_STARTED_AT=""
}

test_skip() {
    local reason="$1"
    if [[ -z "$TEST_CURRENT" ]]; then
        return 0
    fi
    ((TESTS_SKIPPED++)) || true
    TEST_SKIP_REASONS+=("${TEST_CURRENT}: ${reason}")
    record_case "skipped" "$reason"

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo -e "${YELLOW}  ⊘ SKIP${NC} ${TEST_CURRENT} - ${reason}"
    fi

    TEST_CURRENT=""
    TEST_CURRENT_ID=""
    TEST_CURRENT_STARTED_AT=""
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-values should be equal}"
    if [[ "$expected" == "$actual" ]]; then
        return 0
    fi
    test_fail "$message (expected: '$expected', got: '$actual')"
    return 0
}

assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local message="${3:-values should not be equal}"
    if [[ "$unexpected" != "$actual" ]]; then
        return 0
    fi
    test_fail "$message (both values: '$unexpected')"
    return 0
}

assert_true() {
    local actual="$1"
    local message="${2:-expected true/success}"
    if [[ "$actual" == "0" || "$actual" == "true" || "$actual" == "yes" ]]; then
        return 0
    fi
    test_fail "$message (got: '$actual')"
    return 0
}

assert_false() {
    local actual="$1"
    local message="${2:-expected false/failure}"
    if [[ "$actual" != "0" && "$actual" != "true" && "$actual" != "yes" ]]; then
        return 0
    fi
    test_fail "$message (got: '$actual')"
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-string should contain substring}"
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    fi
    test_fail "$message (needle: '$needle')"
    return 0
}

assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-string should match pattern}"
    if [[ "$string" =~ $pattern ]]; then
        return 0
    fi
    test_fail "$message (string: '$string', pattern: '$pattern')"
    return 0
}

assert_file_exists() {
    local filepath="$1"
    local message="${2:-file should exist}"
    if [[ -f "$filepath" ]]; then
        return 0
    fi
    test_fail "$message (file: '$filepath')"
    return 0
}

assert_dir_exists() {
    local dirpath="$1"
    local message="${2:-directory should exist}"
    if [[ -d "$dirpath" ]]; then
        return 0
    fi
    test_fail "$message (directory: '$dirpath')"
    return 0
}

assert_file_contains() {
    local filepath="$1"
    local needle="$2"
    local message="${3:-file should contain string}"
    if [[ -f "$filepath" ]] && grep -q "$needle" "$filepath"; then
        return 0
    fi
    test_fail "$message (file: '$filepath', needle: '$needle')"
    return 0
}

assert_http_code() {
    local expected="$1"
    local url="$2"
    local message="${3:-HTTP status code mismatch}"
    local timeout="${4:-10}"
    local actual
    actual=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || echo "000")
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    test_fail "$message (url: '$url', expected: $expected, got: $actual)"
    return 0
}

assert_http_contains() {
    local url="$1"
    local needle="$2"
    local message="${3:-HTTP response should contain string}"
    local timeout="${4:-10}"
    local response
    response=$(curl -s --max-time "$timeout" "$url" 2>/dev/null || echo "")
    if [[ "$response" == *"$needle"* ]]; then
        return 0
    fi
    test_fail "$message (url: '$url', needle: '$needle')"
    return 0
}

assert_json_value() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local message="${4:-JSON value mismatch}"
    local actual
    if ! command -v jq >/dev/null 2>&1; then
        test_fail "$message (jq not installed)"
        return 1
    fi
    actual=$(printf '%s' "$json" | jq -r "$path" 2>/dev/null || echo "")
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    test_fail "$message (path: '$path', expected: '$expected', got: '$actual')"
    return 0
}

assert_command_success() {
    local command="$1"
    local message="${2:-command should succeed}"
    if eval "$command" >/dev/null 2>&1; then
        return 0
    fi
    test_fail "$message (command: '$command')"
    return 0
}

assert_command_fails() {
    local command="$1"
    local message="${2:-command should fail}"
    if ! eval "$command" >/dev/null 2>&1; then
        return 0
    fi
    test_fail "$message (command: '$command')"
    return 0
}

assert_gt() {
    local left="$1"
    local right="$2"
    local message="${3:-$left should be greater than $right}"
    if [[ "$left" -gt "$right" ]]; then
        return 0
    fi
    test_fail "$message"
    return 0
}

assert_lt() {
    local left="$1"
    local right="$2"
    local message="${3:-$left should be less than $right}"
    if [[ "$left" -lt "$right" ]]; then
        return 0
    fi
    test_fail "$message"
    return 0
}

mock_glm_failure() {
    export GLM_API_ENDPOINT_REAL="${GLM_API_ENDPOINT:-https://open.bigmodel.cn/api/paas/v4/chat/completions}"
    export GLM_API_ENDPOINT="http://127.0.0.1:49999"
}

restore_glm() {
    if [[ -n "${GLM_API_ENDPOINT_REAL:-}" ]]; then
        export GLM_API_ENDPOINT="$GLM_API_ENDPOINT_REAL"
        unset GLM_API_ENDPOINT_REAL
    else
        unset GLM_API_ENDPOINT
    fi
}

mock_ollama_failure() {
    export OLLAMA_HOST_REAL="${OLLAMA_HOST:-http://127.0.0.1:11434}"
    export OLLAMA_HOST="http://127.0.0.1:49999"
}

restore_ollama() {
    if [[ -n "${OLLAMA_HOST_REAL:-}" ]]; then
        export OLLAMA_HOST="$OLLAMA_HOST_REAL"
        unset OLLAMA_HOST_REAL
    else
        unset OLLAMA_HOST
    fi
}

mock_container_state() {
    local container_name="$1"
    local state="$2"
    export "MOCK_CONTAINER_$(printf '%s' "$container_name" | tr '[:lower:]-' '[:upper:]_')=$state"
}

get_mocked_container_state() {
    local container_name="$1"
    local var_name="MOCK_CONTAINER_$(printf '%s' "$container_name" | tr '[:lower:]-' '[:upper:]_')"
    echo "${!var_name:-}"
}

suite_status() {
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "fail"
    elif [[ $TESTS_TOTAL -eq 0 || ($TESTS_SKIPPED -gt 0 && $TESTS_PASSED -eq 0 && $TESTS_FAILED -eq 0) ]]; then
        echo "skip"
    else
        echo "pass"
    fi
}

suite_duration_seconds() {
    if [[ -n "$TEST_START_TIME" ]]; then
        local end_time
        end_time=$(date +%s)
        echo $((end_time - TEST_START_TIME))
    else
        echo 0
    fi
}

write_junit_report() {
    local report_json="$1"
    local junit_path="$2"
    local suite_name
    suite_name=$(printf '%s' "$report_json" | jq -r '.suite.name // .suite.id // "suite"')
    local tests failures skipped time
    tests=$(printf '%s' "$report_json" | jq -r '.summary.total')
    failures=$(printf '%s' "$report_json" | jq -r '.summary.failed')
    skipped=$(printf '%s' "$report_json" | jq -r '.summary.skipped')
    time=$(printf '%s' "$report_json" | jq -r '(.summary.duration_seconds // 0 | tostring)')

    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<testsuite name="%s" tests="%s" failures="%s" skipped="%s" time="%s">\n' "$(xml_escape "$suite_name")" "$tests" "$failures" "$skipped" "$time"
        while IFS= read -r case_json; do
            [[ -z "$case_json" ]] && continue
            local case_name status duration message
            case_name=$(printf '%s' "$case_json" | jq -r '.name')
            status=$(printf '%s' "$case_json" | jq -r '.status')
            duration=$(printf '%s' "$case_json" | jq -r '((.duration_ms // 0) / 1000 | tostring)')
            message=$(printf '%s' "$case_json" | jq -r '.message // empty')
            printf '  <testcase name="%s" time="%s">' "$(xml_escape "$case_name")" "$duration"
            case "$status" in
                skipped)
                    printf '<skipped message="%s" />' "$(xml_escape "$message")"
                    ;;
                failed|error)
                    printf '<failure message="%s">%s</failure>' "$(xml_escape "$message")" "$(xml_escape "$message")"
                    ;;
            esac
            printf '</testcase>\n'
        done < <(printf '%s' "$report_json" | jq -c '.cases[]')
        printf '</testsuite>\n'
    } > "$junit_path"
}

generate_report_json() {
    local status duration failures_json skips_json cases_json report_json
    status=$(suite_status)
    duration=$(suite_duration_seconds)

    failures_json='[]'
    skips_json='[]'
    cases_json='[]'

    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
        failures_json=$(printf '%s\n' "${TEST_FAILURES[@]}" | jq -R . | jq -s .)
    fi
    if [[ ${#TEST_SKIP_REASONS[@]} -gt 0 ]]; then
        skips_json=$(printf '%s\n' "${TEST_SKIP_REASONS[@]}" | jq -R . | jq -s .)
    fi
    if [[ ${#TEST_CASES[@]} -gt 0 ]]; then
        cases_json=$(printf '%s\n' "${TEST_CASES[@]}" | jq -s '.')
    fi

    report_json=$(jq -n \
        --arg status "$status" \
        --arg timestamp "$(get_timestamp)" \
        --arg suite_id "$TEST_SUITE_ID" \
        --arg suite_name "${TEST_SUITE_NAME:-$TEST_SUITE_ID}" \
        --arg lane "$TEST_LANE" \
        --argjson total "$TESTS_TOTAL" \
        --argjson passed "$TESTS_PASSED" \
        --argjson failed "$TESTS_FAILED" \
        --argjson skipped "$TESTS_SKIPPED" \
        --argjson duration "$duration" \
        --argjson failures "$failures_json" \
        --argjson skipped_tests "$skips_json" \
        --argjson cases "$cases_json" \
        '{
            status: $status,
            timestamp: $timestamp,
            lane: (if $lane == "" then null else $lane end),
            suite: {
                id: (if $suite_id == "" then null else $suite_id end),
                name: (if $suite_name == "" then null else $suite_name end)
            },
            summary: {
                total: $total,
                passed: $passed,
                failed: $failed,
                skipped: $skipped,
                duration_seconds: $duration
            },
            failures: $failures,
            skipped_tests: $skipped_tests,
            cases: $cases
        }')

    if [[ -n "$TEST_REPORT_PATH" ]]; then
        mkdir -p "$(dirname "$TEST_REPORT_PATH")"
        printf '%s\n' "$report_json" > "$TEST_REPORT_PATH"
    fi

    if [[ -n "$JUNIT_REPORT_PATH" ]]; then
        mkdir -p "$(dirname "$JUNIT_REPORT_PATH")"
        write_junit_report "$report_json" "$JUNIT_REPORT_PATH"
    fi

    printf '%s\n' "$report_json"

    case "$status" in
        fail) return 1 ;;
        skip) return 2 ;;
        *) return 0 ;;
    esac
}

generate_report() {
    local exit_code status duration report_json
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        generate_report_json
        return $?
    fi

    status=$(suite_status)
    duration=$(suite_duration_seconds)

    echo ""
    echo "========================================="
    echo "  Test Results Summary"
    echo "========================================="
    echo ""

    case "$status" in
        pass)
            echo -e "${GREEN}✓ Test suite passed${NC}"
            ;;
        skip)
            echo -e "${YELLOW}⚠ Test suite skipped${NC}"
            ;;
        fail)
            echo -e "${RED}✗ ${TESTS_FAILED} test(s) failed${NC}"
            ;;
    esac

    echo ""
    echo "Total:   $TESTS_TOTAL"
    echo -e "Passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo "Duration: ${duration}s"

    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        for failure in "${TEST_FAILURES[@]}"; do
            echo "  - $failure"
        done
    fi

    if [[ ${#TEST_SKIP_REASONS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Skipped tests:${NC}"
        for skip in "${TEST_SKIP_REASONS[@]}"; do
            echo "  - $skip"
        done
    fi

    echo ""
    echo "========================================="

    if [[ -n "$TEST_REPORT_PATH" || -n "$JUNIT_REPORT_PATH" ]]; then
        OUTPUT_JSON=true generate_report_json >/dev/null
    fi

    case "$status" in
        fail) return 1 ;;
        skip) return 2 ;;
        *) return 0 ;;
    esac
}

set_json_output() {
    OUTPUT_JSON="$1"
    init_colors
}

set_verbose() {
    VERBOSE="$1"
}

start_timer() {
    TEST_START_TIME=$(date +%s)
}

get_elapsed_time() {
    suite_duration_seconds
}

init_colors
