#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

E2E_SCRIPT="$PROJECT_ROOT/scripts/codex-advisory-e2e.sh"

setup_component_codex_advisory_e2e() {
    require_commands_or_skip bash jq mktemp python3 || return 2
    return 0
}

run_component_codex_advisory_e2e_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_advisory_e2e
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir report output

    test_start "component_codex_advisory_e2e_completes_healthy_and_degraded_paths"
    work_dir="$(secure_temp_dir codex-advisory-e2e)"
    report="$work_dir/report.json"
    output="$(
        bash "$E2E_SCRIPT" \
            --mode hermetic \
            --output "$report"
    )"
    if [[ -n "$output" ]]; then
        test_fail "Hermetic advisory E2E helper should write the report to file without stdout noise"
    fi
    assert_file_exists "$report" "Hermetic advisory E2E helper should write a JSON report"
    assert_json_value "$(cat "$report")" '.status' "completed" "Hermetic advisory E2E helper should complete successfully"
    assert_json_value "$(cat "$report")" '.transport' "telegram_codex_advisory_hermetic" "Hermetic advisory E2E helper should expose its transport"
    assert_json_value "$(cat "$report")" '.context.healthy.session_id != null' "true" "Report should expose the healthy session id"
    assert_contains "$(jq -r '.context.healthy.alert_text' "$report")" "Если нужны практические рекомендации" "Healthy alert evidence should advertise inline callback actions"
    assert_contains "$(jq -r '.observed_response' "$report")" "Практические рекомендации" "Observed response should be the immediate follow-up recommendations"
    assert_contains "$(jq -r '.context.healthy.followup_text' "$report")" "Что проверить в первую очередь" "Healthy follow-up evidence should include priority checks"
    assert_json_value "$(cat "$report")" '.context.healthy.session_audit_record.interaction_record.followup_status' "sent" "Interactive audit record should show sent follow-up status"
    if grep -Fq "Если нужны практические рекомендации" < <(jq -r '.context.degraded.alert_text' "$report"); then
        test_fail "Degraded one-way alert must not advertise interactive follow-up"
    else
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_advisory_e2e_tests
fi
