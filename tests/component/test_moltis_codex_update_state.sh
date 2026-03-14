#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

STATE_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-update-state.sh"

setup_component_moltis_codex_update_state() {
    require_commands_or_skip jq || return 2
    return 0
}

run_component_moltis_codex_update_state_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_update_state
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir state_file output

    test_start "component_moltis_codex_update_state_get_bootstraps_default_shape"
    work_dir="$(secure_temp_dir moltis-codex-update-state-default)"
    state_file="$work_dir/state.json"
    output="$(bash "$STATE_SCRIPT" get --state-file "$state_file" --json)"
    assert_file_exists "$state_file" "State helper should create a default state file"
    assert_eq "moltis-codex-update-state/v1" "$(jq -r '.schema_version' <<<"$output")" "Default state should expose the expected schema version"
    assert_eq "" "$(jq -r '.last_seen_fingerprint' <<<"$output")" "Default state should start without a fingerprint"
    assert_eq "" "$(jq -r '.last_audit_record' <<<"$output")" "Default state should start without an audit pointer"
    test_pass

    test_start "component_moltis_codex_update_state_update_persists_last_seen_run_metadata"
    output="$(bash "$STATE_SCRIPT" update \
        --state-file "$state_file" \
        --run-mode manual \
        --fingerprint abc12345 \
        --latest-version 0.114.0 \
        --decision upgrade-now \
        --run-id run-123 \
        --delivery-status not-attempted \
        --degraded-reason 'manual slice only' \
        --json)"
    assert_eq "abc12345" "$(jq -r '.last_seen_fingerprint' <<<"$output")" "Update should persist the latest fingerprint"
    assert_eq "0.114.0" "$(jq -r '.last_seen_version' <<<"$output")" "Update should persist the latest version"
    assert_eq "manual" "$(jq -r '.last_run_mode' <<<"$output")" "Update should persist run mode"
    assert_eq "run-123" "$(jq -r '.last_run_id' <<<"$output")" "Update should persist the run id"
    assert_eq "upgrade-now" "$(jq -r '.last_result' <<<"$output")" "Update should persist the latest decision"
    assert_eq "not-attempted" "$(jq -r '.last_delivery_status' <<<"$output")" "Update should persist the delivery status for the last run"
    test_pass

    test_start "component_moltis_codex_update_state_mark_delivery_persists_alert_checkpoint_and_message_id"
    output="$(bash "$STATE_SCRIPT" mark-delivery \
        --state-file "$state_file" \
        --delivery-status sent \
        --alert-fingerprint abc12345 \
        --alert-at 2026-03-14T09:00:00Z \
        --message-id 701 \
        --json)"
    assert_eq "abc12345" "$(jq -r '.last_alert_fingerprint' <<<"$output")" "mark-delivery should persist the last alert fingerprint"
    assert_eq "2026-03-14T09:00:00Z" "$(jq -r '.last_alert_at' <<<"$output")" "mark-delivery should persist the alert timestamp"
    assert_eq "701" "$(jq -r '.last_alert_message_id' <<<"$output")" "mark-delivery should persist the Telegram message id"
    assert_eq "sent" "$(jq -r '.last_delivery_status' <<<"$output")" "mark-delivery should record the delivery status"
    test_pass

    test_start "component_moltis_codex_update_state_mark_delivery_persists_failure_without_overwriting_checkpoint"
    output="$(bash "$STATE_SCRIPT" mark-delivery \
        --state-file "$state_file" \
        --delivery-status failed \
        --delivery-error 'telegram timeout' \
        --json)"
    assert_eq "failed" "$(jq -r '.last_delivery_status' <<<"$output")" "Failed delivery should be reflected in state"
    assert_eq "telegram timeout" "$(jq -r '.last_delivery_error' <<<"$output")" "Failure reason should be persisted"
    assert_eq "abc12345" "$(jq -r '.last_alert_fingerprint' <<<"$output")" "Failure without alert fingerprint should not overwrite the previous checkpoint"
    test_pass

    test_start "component_moltis_codex_update_state_mark_audit_persists_last_audit_record_paths"
    output="$(bash "$STATE_SCRIPT" mark-audit \
        --state-file "$state_file" \
        --audit-record "$work_dir/run-123.json" \
        --audit-summary "$work_dir/run-123.summary.md" \
        --audit-written-at 2026-03-14T09:05:00Z \
        --json)"
    assert_eq "$work_dir/run-123.json" "$(jq -r '.last_audit_record' <<<"$output")" "mark-audit should persist the audit JSON path"
    assert_eq "$work_dir/run-123.summary.md" "$(jq -r '.last_audit_summary' <<<"$output")" "mark-audit should persist the audit summary path"
    assert_eq "2026-03-14T09:05:00Z" "$(jq -r '.last_audit_written_at' <<<"$output")" "mark-audit should persist the audit timestamp"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_update_state_tests
fi
