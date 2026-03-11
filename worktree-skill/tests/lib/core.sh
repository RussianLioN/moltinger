#!/usr/bin/env bash
set -euo pipefail

OUTPUT_JSON="${OUTPUT_JSON:-false}"
VERBOSE="${VERBOSE:-false}"
TEST_CURRENT=""
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TESTS_TOTAL=0
TEST_START_TIME=""

declare -a TEST_FAILURES=()
declare -a TEST_SKIP_REASONS=()

test_start() {
  TEST_CURRENT="$1"
  ((TESTS_TOTAL++)) || true

  if [[ "$OUTPUT_JSON" != "true" ]]; then
    printf '\n▶ Test: %s\n' "$TEST_CURRENT"
  fi
}

test_pass() {
  local message="${1:-}"
  [[ -z "$TEST_CURRENT" ]] && return 0

  ((TESTS_PASSED++)) || true
  if [[ "$OUTPUT_JSON" != "true" ]]; then
    if [[ -n "$message" ]]; then
      printf '  ✓ PASS %s - %s\n' "$TEST_CURRENT" "$message"
    else
      printf '  ✓ PASS %s\n' "$TEST_CURRENT"
    fi
  fi
  TEST_CURRENT=""
}

test_fail() {
  local reason="$1"
  [[ -z "$TEST_CURRENT" ]] && return 0

  ((TESTS_FAILED++)) || true
  TEST_FAILURES+=("${TEST_CURRENT}: ${reason}")
  if [[ "$OUTPUT_JSON" != "true" ]]; then
    printf '  ✗ FAIL %s\n' "$TEST_CURRENT"
    printf '    Reason: %s\n' "$reason"
  fi
  TEST_CURRENT=""
}

test_skip() {
  local reason="$1"
  [[ -z "$TEST_CURRENT" ]] && return 0

  ((TESTS_SKIPPED++)) || true
  TEST_SKIP_REASONS+=("${TEST_CURRENT}: ${reason}")
  if [[ "$OUTPUT_JSON" != "true" ]]; then
    printf '  ⊘ SKIP %s - %s\n' "$TEST_CURRENT" "$reason"
  fi
  TEST_CURRENT=""
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-values should be equal}"
  [[ "$expected" == "$actual" ]] && return 0
  test_fail "$message (expected: '$expected', got: '$actual')"
  return 0
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-string should contain substring}"
  [[ "$haystack" == *"$needle"* ]] && return 0
  test_fail "$message (needle: '$needle')"
  return 0
}

assert_file_exists() {
  local filepath="$1"
  local message="${2:-file should exist}"
  [[ -f "$filepath" ]] && return 0
  test_fail "$message (file: '$filepath')"
  return 0
}

assert_dir_exists() {
  local dirpath="$1"
  local message="${2:-directory should exist}"
  [[ -d "$dirpath" ]] && return 0
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

start_timer() {
  TEST_START_TIME=$(date +%s)
}

suite_status() {
  if [[ $TESTS_FAILED -gt 0 ]]; then
    printf 'fail\n'
  elif [[ $TESTS_TOTAL -eq 0 || ($TESTS_SKIPPED -gt 0 && $TESTS_PASSED -eq 0) ]]; then
    printf 'skip\n'
  else
    printf 'pass\n'
  fi
}

suite_duration_seconds() {
  if [[ -z "$TEST_START_TIME" ]]; then
    printf '0\n'
    return 0
  fi
  printf '%s\n' "$(( $(date +%s) - TEST_START_TIME ))"
}

generate_report() {
  local status duration
  status="$(suite_status)"
  duration="$(suite_duration_seconds)"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{"status":"%s","total":%s,"passed":%s,"failed":%s,"skipped":%s,"duration_seconds":%s}\n' \
      "$status" "$TESTS_TOTAL" "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_SKIPPED" "$duration"
  else
    printf '\n=========================================\n'
    printf '  Test Results Summary\n'
    printf '=========================================\n\n'
    printf 'Status:   %s\n' "$status"
    printf 'Total:    %s\n' "$TESTS_TOTAL"
    printf 'Passed:   %s\n' "$TESTS_PASSED"
    printf 'Failed:   %s\n' "$TESTS_FAILED"
    printf 'Skipped:  %s\n' "$TESTS_SKIPPED"
    printf 'Duration: %ss\n' "$duration"

    if [[ ${#TEST_FAILURES[@]} -gt 0 ]]; then
      printf '\nFailed tests:\n'
      printf '  - %s\n' "${TEST_FAILURES[@]}"
    fi

    if [[ ${#TEST_SKIP_REASONS[@]} -gt 0 ]]; then
      printf '\nSkipped tests:\n'
      printf '  - %s\n' "${TEST_SKIP_REASONS[@]}"
    fi

    printf '\n=========================================\n'
  fi

  case "$status" in
    fail) return 1 ;;
    skip) return 2 ;;
    *) return 0 ;;
  esac
}
