#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

ADVISOR_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-update-advisor.sh"
ADVISOR_REPORT_HELPER="$PROJECT_ROOT/scripts/codex-cli-update-advisor-report.py"
MONITOR_CONTEXT_HELPER="$PROJECT_ROOT/scripts/codex-cli-update-monitor-context.py"
MONITOR_REPORT_HELPER="$PROJECT_ROOT/scripts/codex-cli-update-monitor-report.py"
MONITOR_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-monitor"
ADVISOR_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-advisor"
FAKE_BD_BIN_DIR=""
FAKE_BD_STATE_DIR=""
FAKE_BD_DB=""

setup_component_codex_cli_update_advisor() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

setup_fake_bd_fixture() {
    FAKE_BD_BIN_DIR="$(secure_temp_dir fake-bd-bin)"
    FAKE_BD_STATE_DIR="$(secure_temp_dir fake-bd-state)"
    FAKE_BD_DB="$FAKE_BD_STATE_DIR/beads.db"
    : > "$FAKE_BD_DB"

    cat > "$FAKE_BD_BIN_DIR/bd" <<'BD'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${FAKE_BD_STATE_DIR:?}"
mkdir -p "$state_dir"
printf '%s\n' "$*" >> "$state_dir/calls.log"

cmd="${1:-}"
shift || true

case "$cmd" in
    create)
        if [[ "${FAKE_BD_CREATE_FAIL:-0}" == "1" ]]; then
            echo "fake bd create failure" >&2
            exit 1
        fi
        printf '%s\n' "$*" > "$state_dir/last_create_args.txt"
        printf '%s\n' "${FAKE_BD_CREATE_ID:-moltinger-advisor-created}"
        ;;
    update)
        if [[ "${FAKE_BD_UPDATE_FAIL:-0}" == "1" ]]; then
            echo "fake bd update failure" >&2
            exit 1
        fi
        printf '%s\n' "$*" > "$state_dir/last_update_args.txt"
        echo "updated"
        ;;
    *)
        echo "unsupported fake bd command: $cmd" >&2
        exit 1
        ;;
esac
BD
    chmod +x "$FAKE_BD_BIN_DIR/bd"
}

seed_component_advisor_fixture_repo() {
    local fixture_root="$1"
    local repo_dir
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger-advisor-fixture")"

    mkdir -p "$repo_dir/scripts"
    cp "$ADVISOR_SCRIPT" "$repo_dir/scripts/codex-cli-update-advisor.sh"
    cp "$ADVISOR_REPORT_HELPER" "$repo_dir/scripts/codex-cli-update-advisor-report.py"
    cp "$PROJECT_ROOT/scripts/codex-cli-update-monitor.sh" "$repo_dir/scripts/codex-cli-update-monitor.sh"
    cp "$MONITOR_CONTEXT_HELPER" "$repo_dir/scripts/codex-cli-update-monitor-context.py"
    cp "$MONITOR_REPORT_HELPER" "$repo_dir/scripts/codex-cli-update-monitor-report.py"
    cp "$PROJECT_ROOT/scripts/beads-resolve-db.sh" "$repo_dir/scripts/beads-resolve-db.sh"
    chmod +x "$repo_dir/scripts/codex-cli-update-advisor.sh" "$repo_dir/scripts/codex-cli-update-monitor.sh" "$repo_dir/scripts/beads-resolve-db.sh"

    (
        cd "$repo_dir"
        git add scripts/codex-cli-update-advisor.sh scripts/codex-cli-update-advisor-report.py scripts/codex-cli-update-monitor.sh scripts/codex-cli-update-monitor-context.py scripts/codex-cli-update-monitor-report.py scripts/beads-resolve-db.sh
        git commit -m "fixture: seed codex update advisor scripts" >/dev/null
    )

    printf '%s\n' "$repo_dir"
}

seed_component_local_beads_foundation() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads"
    cat > "${repo_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${repo_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed","status":"open","type":"task","priority":3}
EOF
}

canonicalize_fixture_path() {
    local target_path="$1"

    (
        cd "$target_path"
        pwd -P
    )
}

run_advisor_with_monitor_report_using_script() {
    local advisor_script="$1"
    local monitor_report="$2"
    local output_dir="$3"
    local state_file="$4"
    shift 4

    "$advisor_script" \
        --monitor-report "$monitor_report" \
        --state-file "$state_file" \
        --json-out "$output_dir/report.json" \
        --summary-out "$output_dir/summary.md" \
        --stdout none \
        "$@"
}

run_advisor_with_monitor_report() {
    local monitor_report="$1"
    local output_dir="$2"
    local state_file="$3"
    shift 3

    run_advisor_with_monitor_report_using_script "$ADVISOR_SCRIPT" "$monitor_report" "$output_dir" "$state_file" "$@"
}

run_advisor_via_monitor_passthrough() {
    local output_dir="$1"
    local state_file="$2"
    shift 2

    "$ADVISOR_SCRIPT" \
        --config-file "$MONITOR_FIXTURE_DIR/config.toml" \
        --release-file "$MONITOR_FIXTURE_DIR/releases.json" \
        --local-version 0.110.0 \
        --state-file "$state_file" \
        --json-out "$output_dir/report.json" \
        --summary-out "$output_dir/summary.md" \
        --stdout none \
        "$@"
}

run_component_codex_cli_update_advisor_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_codex_cli_update_advisor
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local work_dir state_file report summary stdout_capture original_path fixture_root repo_dir worktree_path
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    original_path="$PATH"

    test_start "component_codex_cli_update_advisor_emits_schema_shape"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file"
    report="$work_dir/report.json"
    summary="$work_dir/summary.md"
    assert_file_exists "$report" "Advisor report JSON should be written"
    assert_file_exists "$summary" "Advisor summary Markdown should be written"
    if jq -e '
        has("checked_at") and
        has("monitor_snapshot") and
        has("notification") and
        has("project_change_suggestions") and
        has("implementation_brief") and
        has("issue_action") and
        (.notification.status | IN("notify", "suppressed", "none", "investigate")) and
        (.issue_action.mode | IN("none", "suggested", "created", "updated", "skipped"))
    ' "$report" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Advisor report should match the required schema shape"
    fi

    test_start "component_codex_cli_update_advisor_marks_first_actionable_run_as_notify"
    assert_eq "notify" "$(jq -r '.notification.status' "$report")" "First actionable run should notify"
    assert_gt "$(jq -r '.project_change_suggestions | length' "$report")" "0" "Actionable report should include suggestions"
    assert_contains "$(cat "$summary")" "Notification: notify" "Summary should include notify status"
    assert_file_exists "$state_file" "Notify-worthy runs should persist advisor state"
    test_pass

    test_start "component_codex_cli_update_advisor_suppresses_duplicate_actionable_run"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file"
    report="$work_dir/report.json"
    assert_eq "suppressed" "$(jq -r '.notification.status' "$report")" "Repeated identical actionable run should be suppressed"
    assert_contains "$(jq -r '.notification.reason' "$report")" "already" "Suppressed path should explain duplicate handling"
    test_pass

    test_start "component_codex_cli_update_advisor_returns_none_for_ignore_recommendation"
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-ignore.json" "$work_dir" "$state_file"
    report="$work_dir/report.json"
    assert_eq "none" "$(jq -r '.notification.status' "$report")" "Ignore recommendation should stay below default threshold"
    assert_eq "0" "$(jq -r '.project_change_suggestions | length' "$report")" "Ignore recommendation should not create generic suggestion churn"
    test_pass

    test_start "component_codex_cli_update_advisor_surfaces_investigate_state"
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-investigate.json" "$work_dir" "$state_file"
    report="$work_dir/report.json"
    assert_eq "investigate" "$(jq -r '.notification.status' "$report")" "Investigate recommendation should surface as investigate on first run"
    assert_contains "$(jq -r '.project_change_suggestions | map(.title) | join("\n")' "$report")" "Investigate the underlying monitor gap" "Investigate path should produce a safe investigation suggestion"
    test_pass

    test_start "component_codex_cli_update_advisor_supports_wrapper_safe_json_stdout"
    stdout_capture="$($ADVISOR_SCRIPT \
        --monitor-report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" \
        --state-file "$(secure_temp_dir codex-update-advisor-stdout)/state.json" \
        --stdout json)"
    if printf '%s' "$stdout_capture" | jq -e '.notification.status and .monitor_snapshot.recommendation and .implementation_brief.summary' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "stdout json mode should emit valid advisor JSON"
    fi

    test_start "component_codex_cli_update_advisor_can_invoke_monitor_directly"
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_via_monitor_passthrough "$work_dir" "$state_file"
    report="$work_dir/report.json"
    assert_eq "upgrade-now" "$(jq -r '.monitor_snapshot.recommendation' "$report")" "Advisor passthrough should reuse the underlying monitor result"
    assert_eq "notify" "$(jq -r '.notification.status' "$report")" "Passthrough run should still notify on first actionable result"
    test_pass

    test_start "component_codex_cli_update_advisor_suggests_issue_without_mutation_by_default"
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file"
    report="$work_dir/report.json"
    assert_eq "suggested" "$(jq -r '.issue_action.mode' "$report")" "Fresh actionable result should suggest a follow-up by default"
    assert_eq "false" "$(jq -r '.issue_action.requested' "$report")" "Default path should remain read-only"
    test_pass

    test_start "component_codex_cli_update_advisor_uses_local_worktree_db_for_implicit_upsert"
    fixture_root="$(secure_temp_dir codex-update-advisor-fixture)"
    repo_dir="$(seed_component_advisor_fixture_repo "$fixture_root")"
    worktree_path="${fixture_root}/moltinger-advisor-worktree"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$worktree_path" "feat/advisor-local-upsert" "main"
    worktree_path="$(canonicalize_fixture_path "$worktree_path")"
    seed_component_local_beads_foundation "$worktree_path"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    export FAKE_BD_CREATE_ID="moltinger-advisor-created"
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report_using_script "$worktree_path/scripts/codex-cli-update-advisor.sh" "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file" \
        --issue-action upsert
    report="$work_dir/report.json"
    assert_eq "created" "$(jq -r '.issue_action.mode' "$report")" "Dedicated worktree advisor upsert should still resolve a local tracker automatically"
    assert_contains "$(cat "$FAKE_BD_STATE_DIR/calls.log")" "--db ${worktree_path}/.beads/beads.db" "Advisor implicit upsert should target the current worktree-local DB"
    test_pass

    test_start "component_codex_cli_update_advisor_blocks_implicit_canonical_root_upsert"
    fixture_root="$(secure_temp_dir codex-update-advisor-fixture)"
    repo_dir="$(seed_component_advisor_fixture_repo "$fixture_root")"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report_using_script "$repo_dir/scripts/codex-cli-update-advisor.sh" "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file" \
        --issue-action upsert
    report="$work_dir/report.json"
    assert_eq "skipped" "$(jq -r '.issue_action.mode' "$report")" "Canonical-root advisor upsert should fail closed without an explicit DB target"
    assert_contains "$(jq -r '.issue_action.notes | join("\n")' "$report")" "mutating canonical-root tracker commands are blocked by default" "Advisor canonical-root block should be reported explicitly"
    if [[ -f "$FAKE_BD_STATE_DIR/calls.log" ]]; then
        test_fail "Canonical-root advisor upsert must not invoke bd"
    else
        test_pass
    fi

    test_start "component_codex_cli_update_advisor_creates_issue_when_explicit_upsert_requested"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    export FAKE_BD_CREATE_ID="moltinger-advisor-created"
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file" \
        --issue-action upsert \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "created" "$(jq -r '.issue_action.mode' "$report")" "Explicit upsert without target should create a follow-up"
    assert_eq "moltinger-advisor-created" "$(jq -r '.issue_action.target' "$report")" "Created issue id should be preserved"
    assert_contains "$(cat "$FAKE_BD_STATE_DIR/calls.log")" "create" "Beads create should be invoked"
    test_pass

    test_start "component_codex_cli_update_advisor_updates_target_issue_when_requested"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file" \
        --issue-action upsert \
        --issue-target moltinger-222 \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "updated" "$(jq -r '.issue_action.mode' "$report")" "Explicit upsert with target should update existing issue"
    assert_eq "moltinger-222" "$(jq -r '.issue_action.target' "$report")" "Requested issue target should be preserved"
    assert_contains "$(cat "$FAKE_BD_STATE_DIR/calls.log")" "update" "Beads update should be invoked"
    test_pass

    test_start "component_codex_cli_update_advisor_skips_tracker_mutation_for_suppressed_results"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    work_dir="$(secure_temp_dir codex-update-advisor)"
    state_file="$work_dir/state.json"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file"
    run_advisor_with_monitor_report "$ADVISOR_FIXTURE_DIR/monitor-upgrade-now.json" "$work_dir" "$state_file" \
        --issue-action upsert \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "skipped" "$(jq -r '.issue_action.mode' "$report")" "Suppressed duplicate result should not mutate tracker state"
    assert_contains "$(jq -r '.issue_action.notes | join("\n")' "$report")" "No tracker mutation was performed" "Skip path should explain the non-mutation"
    test_pass

    export PATH="$original_path"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_cli_update_advisor_tests
fi
