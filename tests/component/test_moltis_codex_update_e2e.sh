#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

E2E_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-update-e2e.sh"

setup_component_moltis_codex_update_e2e() {
    require_commands_or_skip bash jq mktemp python3 || return 2
    return 0
}

run_component_moltis_codex_update_e2e_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_update_e2e
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir report output

    test_start "component_moltis_codex_update_e2e_proves_manual_profile_and_scheduler_delivery_path"
    work_dir="$(secure_temp_dir moltis-codex-update-e2e)"
    report="$work_dir/report.json"
    output="$(
        bash "$E2E_SCRIPT" \
            --mode hermetic \
            --output "$report"
    )"
    if [[ -n "$output" ]]; then
        test_fail "Hermetic Moltis Codex update E2E helper should write the report to file without stdout noise"
    fi
    assert_file_exists "$report" "Hermetic Moltis Codex update E2E helper should write a JSON report"
    assert_json_value "$(cat "$report")" '.status' "completed" "Hermetic Moltis Codex update E2E helper should complete successfully"
    assert_json_value "$(cat "$report")" '.context.manual.profile_status' "loaded" "Manual path should prove profile loading"
    assert_json_value "$(cat "$report")" '.context.manual.decision' "upgrade-now" "Manual path should prove actionable upstream detection"
    assert_json_value "$(cat "$report")" '.context.scheduler.first.delivery_status' "sent" "First scheduler run should send one Telegram alert"
    assert_json_value "$(cat "$report")" '.context.scheduler.second.delivery_status' "suppressed" "Second scheduler run should suppress the duplicate fingerprint"
    assert_json_value "$(cat "$report")" '.context.scheduler.sender_call_count' "1" "Hermetic sender should be called only once"
    assert_contains "$(jq -r '.context.manual.recommendation_title_ru' "$report")" "Обновить" "Manual path should expose project-shaped recommendations"
    assert_contains "$(jq -r '.context.scheduler.alert_text' "$report")" "Обновление Codex CLI" "Scheduler alert should use the Moltis-native Russian headline"
    assert_file_exists "$(jq -r '.context.manual.audit_record_path' "$report")" "Manual path should leave an audit JSON record"
    assert_file_exists "$(jq -r '.context.scheduler.first.audit_record_path' "$report")" "Scheduler path should leave an audit JSON record"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_update_e2e_tests
fi
