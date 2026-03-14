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

    local work_dir report output helper_exit helper_status helper_error

    test_start "component_codex_telegram_consent_e2e_completes_acceptance_and_degraded_flow"
    work_dir="$(secure_temp_dir codex-consent-e2e)"
    report="$work_dir/report.json"
    set +e
    output="$(
        bash "$E2E_SCRIPT" \
            --mode hermetic \
            --output "$report"
    )"
    helper_exit=$?
    set -e
    if [[ -n "$output" ]]; then
        test_fail "Hermetic E2E helper should write the report to file without stdout noise"
    fi
    assert_file_exists "$report" "Hermetic E2E helper should write a JSON report"
    helper_status="$(jq -r '.status // "missing"' "$report" 2>/dev/null || echo missing)"
    helper_error="$(jq -r '.error_message // ""' "$report" 2>/dev/null || true)"
    if [[ $helper_exit -ne 0 ]]; then
        test_fail "Hermetic E2E helper exited ${helper_exit} with status ${helper_status}: ${helper_error:-unknown error}"
        generate_report
        return
    fi
    assert_json_value "$(cat "$report")" '.status' "completed" "Hermetic E2E helper should complete successfully"
    assert_json_value "$(cat "$report")" '.transport' "telegram_codex_consent_hermetic" "Hermetic E2E helper should expose its transport"
    assert_contains "$(jq -r '.context.alert.text' "$report")" "Что это может дать проекту" "Alert evidence should still surface project guidance"
    assert_contains "$(jq -r '.observed_response' "$report")" "Что это может дать проекту" "Observed response should reflect the delivered one-way alert"
    assert_contains "$(jq -r '.context.legacy_consent.question' "$report")" "Хотите получить практические рекомендации" "Report should preserve the retired consent question for operator evidence"
    if grep -Fq "Хотите получить практические рекомендации" < <(jq -r '.context.alert.text' "$report"); then
        test_fail "One-way alert must not ask the retired consent question"
    elif grep -Fq "/codex_da" < <(jq -r '.context.alert.text' "$report"); then
        test_fail "One-way alert must not expose the retired fallback command"
    elif grep -Fq "Хотите получить практические рекомендации" < <(jq -r '.context.degraded.text' "$report"); then
        test_fail "Degraded one-way alert must not ask the broken consent question"
    else
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_telegram_consent_e2e_tests
fi
