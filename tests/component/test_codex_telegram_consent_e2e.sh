#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

E2E_SCRIPT="$PROJECT_ROOT/scripts/codex-telegram-consent-e2e.sh"

setup_component_codex_telegram_consent_e2e() {
    require_commands_or_skip bash jq mktemp python3 || return 2
    return 0
}

run_component_codex_telegram_consent_e2e_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_telegram_consent_e2e
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir report output

    test_start "component_codex_telegram_consent_e2e_completes_one_way_baseline_and_degraded_flow"
    work_dir="$(secure_temp_dir codex-consent-e2e)"
    report="$work_dir/report.json"
    output="$(
        bash "$E2E_SCRIPT" \
            --mode hermetic \
            --output "$report"
    )"
    if [[ -n "$output" ]]; then
        test_fail "Hermetic E2E helper should write the report to file without stdout noise"
    fi
    assert_file_exists "$report" "Hermetic E2E helper should write a JSON report"
    assert_json_value "$(cat "$report")" '.status' "completed" "Hermetic E2E helper should complete successfully"
    assert_json_value "$(cat "$report")" '.transport' "telegram_codex_consent_hermetic" "Hermetic E2E helper should expose its transport"
    assert_json_value "$(cat "$report")" '.observed_response == null' "true" "Retired repo-side helper should not claim an interactive follow-up response"
    assert_json_value "$(cat "$report")" '.context.alert.followup_status' "disabled" "Baseline alert should keep consent disabled"
    assert_json_value "$(cat "$report")" '.context.alert.router_mode' "one_way_only" "Baseline alert should stay one-way only"
    assert_json_value "$(cat "$report")" '.context.alert.consent_requested' "false" "Baseline alert must not request consent"
    assert_json_value "$(cat "$report")" '.context.degraded.followup_status' "disabled" "Degraded alert should keep consent disabled"
    assert_json_value "$(cat "$report")" '.context.degraded.router_mode' "one_way_only" "Degraded alert should stay one-way only"
    assert_json_value "$(cat "$report")" '.context.degraded.consent_requested' "false" "Degraded alert must not request consent"
    if grep -Fq "Хотите получить практические рекомендации" < <(jq -r '.context.alert.text' "$report") \
        || grep -Fq "/codex_da" < <(jq -r '.context.alert.text' "$report") \
        || grep -Fq "Хотите получить практические рекомендации" < <(jq -r '.context.degraded.text' "$report") \
        || grep -Fq "/codex_da" < <(jq -r '.context.degraded.text' "$report"); then
        test_fail "One-way alerts must not advertise the retired consent question or command path"
    else
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_telegram_consent_e2e_tests
fi
