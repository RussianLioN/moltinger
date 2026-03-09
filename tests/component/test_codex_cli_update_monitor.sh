#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MONITOR_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-update-monitor.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-monitor"

setup_component_codex_update_monitor() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

run_monitor_fixture() {
    local local_version="$1"
    local output_dir="$2"
    shift 2

    CODEX_UPDATE_MONITOR_LOCAL_VERSION="$local_version" \
        "$MONITOR_SCRIPT" \
        --config-file "$FIXTURE_DIR/config.toml" \
        --release-file "$FIXTURE_DIR/releases.json" \
        --json-out "$output_dir/report.json" \
        --summary-out "$output_dir/summary.md" \
        --stdout none \
        "$@"
}

run_component_codex_cli_update_monitor_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_update_monitor
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir report summary stdout_capture
    work_dir="$(secure_temp_dir codex-update-monitor)"

    test_start "component_codex_update_monitor_emits_schema_shape_for_current_version"
    run_monitor_fixture "0.112.0" "$work_dir"
    report="$work_dir/report.json"
    summary="$work_dir/summary.md"
    assert_file_exists "$report" "Report JSON should be written"
    assert_file_exists "$summary" "Summary Markdown should be written"
    if jq -e '
        has("checked_at") and
        has("local_version") and
        has("latest_version") and
        has("version_status") and
        has("local_features") and
        has("repo_workflow_traits") and
        has("sources") and
        has("relevant_changes") and
        has("non_relevant_changes") and
        has("recommendation") and
        has("evidence") and
        has("issue_action") and
        (.recommendation | IN("upgrade-now", "upgrade-later", "ignore", "investigate")) and
        (.version_status | IN("ahead", "current", "behind", "unknown")) and
        (.issue_action.mode | IN("none", "suggested", "created", "updated", "skipped"))
    ' "$report" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Report JSON should match the required schema shape"
    fi

    test_start "component_codex_update_monitor_marks_current_release_as_ignore"
    assert_eq "0.112.0" "$(jq -r '.latest_version' "$report")" "Latest fixture version should be 0.112.0"
    assert_eq "current" "$(jq -r '.version_status' "$report")" "Current fixture should report version_status=current"
    assert_eq "ignore" "$(jq -r '.recommendation' "$report")" "Current fixture should recommend ignore"
    assert_contains "$(cat "$summary")" "Recommendation: ignore" "Summary should include ignore recommendation"
    test_pass

    test_start "component_codex_update_monitor_escalates_behind_relevant_changes"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.110.0" "$work_dir" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json"
    report="$work_dir/report.json"
    assert_eq "behind" "$(jq -r '.version_status' "$report")" "Older local version should be behind"
    assert_eq "upgrade-now" "$(jq -r '.recommendation' "$report")" "High-relevance behind changes should recommend upgrade-now"
    assert_gt "$(jq -r '.relevant_changes | length' "$report")" "0" "Relevant changes should be recorded"
    assert_contains "$(jq -r '.relevant_changes | map(.summary) | join("\n")' "$report")" "worktree" "Relevant changes should include worktree-related upstream changes"
    assert_eq "true" "$(jq -r '.sources.issue_signals_included' "$report")" "Issue signals should be marked as included"
    test_pass

    test_start "component_codex_update_monitor_keeps_issue_signals_advisory"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.112.0" "$work_dir" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json"
    report="$work_dir/report.json"
    assert_eq "ignore" "$(jq -r '.recommendation' "$report")" "Issue signals alone must not force an upgrade"
    assert_contains "$(jq -r '.evidence | join("\n")' "$report")" "advisory item" "Evidence should record advisory issue review"
    test_pass

    test_start "component_codex_update_monitor_returns_investigate_when_release_source_fails"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    CODEX_UPDATE_MONITOR_LOCAL_VERSION="0.110.0" \
        "$MONITOR_SCRIPT" \
        --config-file "$FIXTURE_DIR/config.toml" \
        --release-file "$FIXTURE_DIR/missing-releases.json" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    report="$work_dir/report.json"
    assert_eq "unknown" "$(jq -r '.latest_version' "$report")" "Missing release source should produce unknown latest version"
    assert_eq "investigate" "$(jq -r '.recommendation' "$report")" "Missing release source should recommend investigate"
    assert_contains "$(jq -r '.evidence | join("\n")' "$report")" "Primary upstream release source was unavailable" "Evidence should call out the failed primary source"
    test_pass

    test_start "component_codex_update_monitor_supports_wrapper_safe_json_stdout"
    stdout_capture="$(
        CODEX_UPDATE_MONITOR_LOCAL_VERSION="0.111.0" \
            "$MONITOR_SCRIPT" \
            --config-file "$FIXTURE_DIR/config.toml" \
            --release-file "$FIXTURE_DIR/releases.json" \
            --stdout json
    )"
    if printf '%s' "$stdout_capture" | jq -e '.recommendation and .local_version and .latest_version' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "stdout json mode should emit valid machine-readable JSON"
    fi

    test_start "component_codex_update_monitor_records_non_mutating_issue_request"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.111.0" "$work_dir" \
        --issue-action upsert \
        --issue-target moltinger-222
    report="$work_dir/report.json"
    assert_eq "skipped" "$(jq -r '.issue_action.mode' "$report")" "Forward-compatible issue action should remain non-mutating in the first slice"
    assert_eq "true" "$(jq -r '.issue_action.requested' "$report")" "Issue action request should be recorded"
    assert_eq "moltinger-222" "$(jq -r '.issue_action.target' "$report")" "Requested issue target should be preserved"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_cli_update_monitor_tests
fi
