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

    test_start "component_codex_telegram_consent_e2e_completes_acceptance_and_degraded_flow"
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
    assert_json_value "$(cat "$report")" '.context.alert.request_id != null' "true" "Report should expose the shared consent request id"
    assert_contains "$(jq -r '.context.alert.text' "$report")" "Хотите получить практические рекомендации" "Alert evidence should show the consent question"
    assert_contains "$(jq -r '.observed_response' "$report")" "Практические рекомендации по обновлению Codex CLI" "Observed response should be the immediate follow-up recommendations"
    assert_contains "$(jq -r '.context.consent.followup_text' "$report")" "Что можно сделать в проекте" "Follow-up evidence should include project guidance"
    if grep -Fq "Хотите получить практические рекомендации" < <(jq -r '.context.degraded.text' "$report"); then
        test_fail "Degraded one-way alert must not ask the broken consent question"
    else
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_telegram_consent_e2e_tests
fi
