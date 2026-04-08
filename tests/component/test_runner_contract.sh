#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

RUNNER_SCRIPT="$PROJECT_ROOT/tests/run.sh"

setup_component_runner_contract() {
    require_commands_or_skip bash jq mktemp cat cp rm tail sed chmod stat || return 2
    return 0
}

portable_mode() {
    stat -c "%a" "$1" 2>/dev/null || stat -f "%Lp" "$1"
}

write_runner_source_fixture() {
    local target_path="$1"

    cat > "$target_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$PROJECT_ROOT/tests"
PROJECT_ROOT="$PROJECT_ROOT"
LIB_DIR="$PROJECT_ROOT/tests/lib"

# shellcheck source=tests/lib/test_helpers.sh
source "\$LIB_DIR/test_helpers.sh"
EOF
    tail -n +11 "$RUNNER_SCRIPT" | sed '$d' >> "$target_path"
}

write_fake_suite() {
    local suite_path="$1"
    local status="$2"
    local summary_total="$3"
    local summary_passed="$4"
    local summary_failed="$5"
    local summary_skipped="$6"
    local case_status="$7"
    local exit_code="$8"

    cat > "$suite_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cat > "\${TEST_REPORT_PATH:?}" <<'JSON'
{
  "status": "$status",
  "lane": "component",
  "suite": {
    "id": "fixture-suite",
    "name": "Fixture Suite"
  },
  "summary": {
    "total": $summary_total,
    "passed": $summary_passed,
    "failed": $summary_failed,
    "skipped": $summary_skipped,
    "duration_seconds": 0
  },
  "failures": [],
  "skipped_tests": [],
  "cases": [
    {
      "id": "fixture-case",
      "name": "fixture-case",
      "status": "$case_status",
      "message": "fixture result",
      "lane": "component",
      "duration_ms": 0,
      "suite": {
        "id": "fixture-suite",
        "name": "Fixture Suite"
      }
    }
  ]
}
JSON

exit $exit_code
EOF
    chmod +x "$suite_path"
}

run_component_runner_contract_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_runner_contract
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local fixture_root runner_lib
    fixture_root="$(secure_temp_dir runner-contract)"
    runner_lib="$fixture_root/run-lib.sh"
    write_runner_source_fixture "$runner_lib"

    test_start "component_runner_contract_normalizes_pass_report_when_suite_process_fails"

    local suite_pass suite_json suite_log suite_junit aggregate_json rc rc_file
    suite_pass="$fixture_root/pass-then-fail.sh"
    suite_json="$fixture_root/pass-then-fail.json"
    suite_log="$fixture_root/pass-then-fail.log"
    suite_junit="$fixture_root/pass-then-fail.xml"
    aggregate_json="$fixture_root/aggregate.json"
    rc_file="$fixture_root/pass-then-fail.rc"
    write_fake_suite "$suite_pass" "pass" 1 1 0 0 "passed" 1

    if ! RUNNER_LIB="$runner_lib" \
        SUITE_ID="runner_pass_then_fail" \
        SUITE_NAME="Runner Pass Then Fail" \
        SUITE_PATH="$suite_pass" \
        SUITE_JSON="$suite_json" \
        SUITE_LOG="$suite_log" \
        SUITE_JUNIT="$suite_junit" \
        RC_FILE="$rc_file" \
        AGGREGATE_JSON="$aggregate_json" \
        bash <<'EOF'
set -euo pipefail
source "$RUNNER_LIB"
LANE=component

set +e
execute_suite bash component "$SUITE_ID" "$SUITE_NAME" "$SUITE_PATH" "$SUITE_JSON" "$SUITE_LOG" "$SUITE_JUNIT"
rc=$?
set -e

printf '%s\n' "$rc" > "$RC_FILE"
write_aggregate_json "$AGGREGATE_JSON" "$SUITE_JSON"
EOF
    then
        test_fail "Isolated runner harness helper should execute successfully"
        rm -rf "$fixture_root"
        generate_report
        return
    fi
    rc="$(tr -d '\n' < "$rc_file")"

    assert_eq "1" "$rc" "Runner should surface non-zero suite exits as failure"
    assert_eq "fail" "$(jq -r '.status' "$suite_json")" "Pass JSON with process exit 1 must be normalized to fail"
    assert_eq "2" "$(jq -r '.summary.total' "$suite_json")" "Normalized suite should add a synthetic runtime failure case"
    assert_eq "1" "$(jq -r '.summary.failed' "$suite_json")" "Normalized suite should record one failed case"
    assert_contains "$(jq -r '.failures | join("\n")' "$suite_json")" "Suite exited with code 1" "Normalized suite should explain the runtime mismatch"
    assert_file_exists "$fixture_root/pass-then-fail.raw.json" "Runner should preserve the pre-normalization report for diagnostics"
    assert_eq "644" "$(portable_mode "$suite_json")" "Normalized suite report must stay artifact-readable"

    assert_eq "failed" "$(jq -r '.status' "$aggregate_json")" "Aggregate summary must fail after normalization"
    assert_eq "1" "$(jq -r '.summary.failed' "$aggregate_json")" "Aggregate summary should count the synthetic failure"
    test_pass

    test_start "component_runner_contract_preserves_reported_fail_when_process_exit_is_zero"

    local suite_fail fail_json fail_log fail_junit fail_rc_file
    suite_fail="$fixture_root/fail-then-zero.sh"
    fail_json="$fixture_root/fail-then-zero.json"
    fail_log="$fixture_root/fail-then-zero.log"
    fail_junit="$fixture_root/fail-then-zero.xml"
    fail_rc_file="$fixture_root/fail-then-zero.rc"
    write_fake_suite "$suite_fail" "fail" 1 0 1 0 "failed" 0

    if ! RUNNER_LIB="$runner_lib" \
        SUITE_ID="runner_fail_then_zero" \
        SUITE_NAME="Runner Fail Then Zero" \
        SUITE_PATH="$suite_fail" \
        SUITE_JSON="$fail_json" \
        SUITE_LOG="$fail_log" \
        SUITE_JUNIT="$fail_junit" \
        RC_FILE="$fail_rc_file" \
        bash <<'EOF'
set -euo pipefail
source "$RUNNER_LIB"
LANE=component

set +e
execute_suite bash component "$SUITE_ID" "$SUITE_NAME" "$SUITE_PATH" "$SUITE_JSON" "$SUITE_LOG" "$SUITE_JUNIT"
rc=$?
set -e

printf '%s\n' "$rc" > "$RC_FILE"
EOF
    then
        test_fail "Isolated runner harness helper should execute fail->zero scenario"
        rm -rf "$fixture_root"
        generate_report
        return
    fi
    rc="$(tr -d '\n' < "$fail_rc_file")"

    assert_eq "1" "$rc" "Reported failing suites must stay failed even if the shell exits 0"
    assert_eq "fail" "$(jq -r '.status' "$fail_json")" "Existing fail reports must stay failed"
    assert_contains "$(jq -r '.failures | join("\n")' "$fail_json")" "expected exit 1" "Runner should record the exit/report mismatch"
    test_pass

    test_start "component_runner_contract_preserves_skip_exit_contract"

    local suite_skip skip_json skip_log skip_junit skip_rc_file
    suite_skip="$fixture_root/skip-then-two.sh"
    skip_json="$fixture_root/skip-then-two.json"
    skip_log="$fixture_root/skip-then-two.log"
    skip_junit="$fixture_root/skip-then-two.xml"
    skip_rc_file="$fixture_root/skip-then-two.rc"
    write_fake_suite "$suite_skip" "skip" 1 0 0 1 "skipped" 2

    if ! RUNNER_LIB="$runner_lib" \
        SUITE_ID="runner_skip_then_two" \
        SUITE_NAME="Runner Skip Then Two" \
        SUITE_PATH="$suite_skip" \
        SUITE_JSON="$skip_json" \
        SUITE_LOG="$skip_log" \
        SUITE_JUNIT="$skip_junit" \
        RC_FILE="$skip_rc_file" \
        bash <<'EOF'
set -euo pipefail
source "$RUNNER_LIB"
LANE=component

set +e
execute_suite bash component "$SUITE_ID" "$SUITE_NAME" "$SUITE_PATH" "$SUITE_JSON" "$SUITE_LOG" "$SUITE_JUNIT"
rc=$?
set -e

printf '%s\n' "$rc" > "$RC_FILE"
EOF
    then
        test_fail "Isolated runner harness helper should execute skip scenario"
        rm -rf "$fixture_root"
        generate_report
        return
    fi
    rc="$(tr -d '\n' < "$skip_rc_file")"

    assert_eq "2" "$rc" "Skip suites must preserve exit code 2"
    assert_eq "skip" "$(jq -r '.status' "$skip_json")" "Skip suites with exit 2 should not be normalized to fail"
    test_pass

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_runner_contract_tests
fi
