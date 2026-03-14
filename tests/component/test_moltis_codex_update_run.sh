#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

RUN_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-update-run.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-skill"

setup_component_moltis_codex_update_run() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

run_component_moltis_codex_update_run_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_update_run
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir state_file report summary

    test_start "component_moltis_codex_update_run_manual_emits_russian_summary_for_new_upstream_state"
    work_dir="$(secure_temp_dir moltis-codex-update-run-manual)"
    state_file="$work_dir/state.json"
    bash "$RUN_SCRIPT" \
        --mode manual \
        --state-file "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    report="$work_dir/report.json"
    summary="$(cat "$work_dir/summary.md")"
    assert_file_exists "$report" "Run script should write a JSON report"
    assert_eq "0.114.0" "$(jq -r '.snapshot.latest_version' "$report")" "Run report should normalize the latest version"
    assert_eq "upgrade-now" "$(jq -r '.decision.decision' "$report")" "Fresh important upstream state should request immediate review"
    assert_eq "new" "$(jq -r '.snapshot.release_status' "$report")" "First run should treat the fingerprint as new"
    assert_contains "$summary" "Решение: разобрать сейчас" "Summary should render the decision in Russian"
    assert_contains "$summary" "Практические рекомендации" "Summary should include the recommendation block"
    test_pass

    test_start "component_moltis_codex_update_run_repeat_marks_known_state_without_false_new_alert"
    bash "$RUN_SCRIPT" \
        --mode manual \
        --state-file "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --json-out "$work_dir/report-repeat.json" \
        --summary-out "$work_dir/summary-repeat.md" \
        --stdout none
    report="$work_dir/report-repeat.json"
    assert_eq "known" "$(jq -r '.snapshot.release_status' "$report")" "Second run should recognize the already seen fingerprint"
    assert_eq "ignore" "$(jq -r '.decision.decision' "$report")" "Known upstream state should not produce a false new action"
    test_pass

    test_start "component_moltis_codex_update_run_uses_project_profile_for_project_specific_recommendations"
    work_dir="$(secure_temp_dir moltis-codex-update-run-profile)"
    state_file="$work_dir/state.json"
    bash "$RUN_SCRIPT" \
        --mode manual \
        --state-file "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --profile-file "$FIXTURE_DIR/project-profile-basic.json" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    report="$work_dir/report.json"
    assert_eq "loaded" "$(jq -r '.profile.status' "$report")" "Profile-backed run should load the project profile"
    assert_eq "true" "$(jq -r '.decision.project_specific' "$report")" "Profile-backed decision should be marked as project-specific"
    assert_contains "$(jq -r '.recommendation_bundle.profile_source' "$report")" "profile:" "Recommendation bundle should record the profile source"
    assert_contains "$(jq -r '.recommendation_bundle.items[0].rationale_ru' "$report")" "Проект" "Profile recommendation should use project-specific rationale"
    test_pass

    test_start "component_moltis_codex_update_run_honestly_degrades_when_official_source_is_missing"
    work_dir="$(secure_temp_dir moltis-codex-update-run-investigate)"
    state_file="$work_dir/state.json"
    set +e
    bash "$RUN_SCRIPT" \
        --mode manual \
        --state-file "$state_file" \
        --release-file "$work_dir/missing.html" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    set -e
    report="$work_dir/report.json"
    assert_eq "investigate" "$(jq -r '.decision.decision' "$report")" "Missing official source should produce investigate"
    assert_contains "$(jq -r '.notes[]' "$report")" "официального changelog" "Report notes should explain the fetch failure"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_update_run_tests
fi
