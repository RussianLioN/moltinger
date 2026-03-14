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

    local work_dir state_file report summary sender_script

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
    assert_file_exists "$(jq -r '.audit.record_path' "$report")" "Run script should persist an audit JSON mirror for manual runs"
    assert_file_exists "$(jq -r '.audit.summary_path' "$report")" "Run script should persist an audit summary mirror for manual runs"
    assert_eq "$(jq -r '.run_id' "$report")" "$(jq -r '.last_run_id' "$state_file")" "State should retain the latest run id"
    assert_eq "$(jq -r '.audit.record_path' "$report")" "$(jq -r '.last_audit_record' "$state_file")" "State should point to the latest audit JSON"
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

    test_start "component_moltis_codex_update_run_scheduler_sends_once_and_suppresses_duplicate_fingerprint"
    work_dir="$(secure_temp_dir moltis-codex-update-run-scheduler)"
    state_file="$work_dir/state.json"
    sender_script="$work_dir/fake-telegram-send.sh"
    cat > "$sender_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log_path="${FAKE_TELEGRAM_LOG:?}"
text_path="${FAKE_TELEGRAM_TEXT:?}"
args_path="${FAKE_TELEGRAM_ARGS:?}"
raw_args="$*"
chat_id=""
text=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --chat-id)
            chat_id="${2:-}"
            shift 2
            ;;
        --text)
            text="${2:-}"
            shift 2
            ;;
        --json|--disable-notification)
            shift
            ;;
        *)
            shift
            ;;
    esac
done
printf 'call\n' >> "$log_path"
printf '%s\n' "$text" > "$text_path"
printf '%s\n' "$raw_args" > "$args_path"
printf '{"ok":true,"result":{"message_id":701,"chat":{"id":"%s"}}}\n' "$chat_id"
EOF
    chmod +x "$sender_script"

    FAKE_TELEGRAM_LOG="$work_dir/telegram.log" \
    FAKE_TELEGRAM_TEXT="$work_dir/telegram.txt" \
    FAKE_TELEGRAM_ARGS="$work_dir/telegram-args.txt" \
    bash "$RUN_SCRIPT" \
        --mode scheduler \
        --state-file "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --telegram-enabled \
        --telegram-chat-id 262872984 \
        --telegram-send-script "$sender_script" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    report="$work_dir/report.json"
    assert_eq "sent" "$(jq -r '.delivery.status' "$report")" "First scheduler run should send one Telegram alert"
    assert_eq "262872984" "$(jq -r '.delivery.chat_id' "$report")" "Scheduler run should record the Telegram chat id"
    assert_eq "701" "$(jq -r '.delivery.message_id' "$report")" "Successful delivery should persist the Telegram message id"
    assert_file_exists "$(jq -r '.audit.record_path' "$report")" "Scheduler run should persist an audit JSON mirror"
    assert_eq "1" "$(wc -l < "$work_dir/telegram.log" | tr -d ' ')" "Sender should be invoked exactly once for a fresh fingerprint"
    assert_contains "$(cat "$work_dir/telegram.txt")" "Обновление Codex CLI" "Telegram text should use the Russian alert headline"
    assert_contains "$(cat "$work_dir/telegram-args.txt")" "--reply-markup-json {\"remove_keyboard\":true}" "Scheduler delivery should clear the stale legacy Telegram keyboard"
    assert_eq "$(jq -r '.snapshot.fingerprint' "$report")" "$(jq -r '.last_alert_fingerprint' "$state_file")" "State should checkpoint the delivered fingerprint"

    FAKE_TELEGRAM_LOG="$work_dir/telegram.log" \
    FAKE_TELEGRAM_TEXT="$work_dir/telegram.txt" \
    FAKE_TELEGRAM_ARGS="$work_dir/telegram-args.txt" \
    bash "$RUN_SCRIPT" \
        --mode scheduler \
        --state-file "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --include-issue-signals \
        --issue-signals-file "$FIXTURE_DIR/issue-signals.json" \
        --telegram-enabled \
        --telegram-chat-id 262872984 \
        --telegram-send-script "$sender_script" \
        --json-out "$work_dir/report-repeat.json" \
        --summary-out "$work_dir/summary-repeat.md" \
        --stdout none
    report="$work_dir/report-repeat.json"
    assert_eq "suppressed" "$(jq -r '.delivery.status' "$report")" "Second scheduler run should suppress duplicate delivery"
    assert_eq "1" "$(wc -l < "$work_dir/telegram.log" | tr -d ' ')" "Suppressed duplicate should not invoke the sender again"
    assert_eq "suppressed" "$(jq -r '.last_delivery_status' "$state_file")" "State should retain duplicate suppression outcome"
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
    assert_eq "Обновить topology и worktree guidance" "$(jq -r '.recommendation_bundle.items[0].title_ru' "$report")" "Profile recommendation should be shaped by the linked template"
    assert_contains "$(jq -r '.recommendation_bundle.items[0].rationale_ru' "$report")" "Проект" "Profile recommendation should use project-specific rationale"
    assert_eq "worktree-flow" "$(jq -r '.recommendation_bundle.items[0].source_rule_id' "$report")" "Profile recommendation should keep audit link to the matched rule"
    test_pass

    test_start "component_moltis_codex_update_run_profile_fallback_still_returns_project_specific_guidance"
    work_dir="$(secure_temp_dir moltis-codex-update-run-profile-fallback)"
    state_file="$work_dir/state.json"
    bash "$RUN_SCRIPT" \
        --mode manual \
        --state-file "$state_file" \
        --release-file "$FIXTURE_DIR/releases-0.114.0.html" \
        --profile-file "$FIXTURE_DIR/project-profile-fallback.json" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    report="$work_dir/report.json"
    assert_eq "loaded" "$(jq -r '.profile.status' "$report")" "Fallback profile run should still load the profile"
    assert_eq "true" "$(jq -r '.decision.project_specific' "$report")" "Fallback recommendation should still count as project-specific"
    assert_eq "Сделать короткую project-specific оценку для Moltinger" "$(jq -r '.recommendation_bundle.items[0].title_ru' "$report")" "Fallback recommendation should come from profile fallback contract"
    assert_eq "" "$(jq -r '.recommendation_bundle.items[0].source_rule_id' "$report")" "Fallback recommendation should not pretend a rule was matched"
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
