#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

MONITOR_SCRIPT="$PROJECT_ROOT/scripts/codex-cli-update-monitor.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-monitor"
UPSTREAM_WATCHER_FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-upstream-watcher"
FAKE_BD_BIN_DIR=""
FAKE_BD_STATE_DIR=""
FAKE_BD_DB=""
BROKEN_GIT_BIN_DIR=""

setup_component_codex_update_monitor() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

setup_fake_bd_fixture() {
    FAKE_BD_BIN_DIR="$(secure_temp_dir fake-bd-bin)"
    FAKE_BD_STATE_DIR="$(secure_temp_dir fake-bd-state)"
    FAKE_BD_DB="$FAKE_BD_STATE_DIR/beads.db"
    : > "$FAKE_BD_DB"

    cat > "$FAKE_BD_BIN_DIR/bd" <<'EOF'
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
        printf '%s\n' "${FAKE_BD_CREATE_ID:-moltinger-test-created}"
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
EOF
    chmod +x "$FAKE_BD_BIN_DIR/bd"
}

setup_broken_git_fixture() {
    BROKEN_GIT_BIN_DIR="$(secure_temp_dir broken-git-bin)"

    cat > "$BROKEN_GIT_BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$BROKEN_GIT_BIN_DIR/git"
}

seed_component_monitor_fixture_repo() {
    local fixture_root="$1"
    local repo_dir
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger-monitor-fixture")"

    mkdir -p "$repo_dir/scripts"
    cp "$MONITOR_SCRIPT" "$repo_dir/scripts/codex-cli-update-monitor.sh"
    cp "$PROJECT_ROOT/scripts/beads-resolve-db.sh" "$repo_dir/scripts/beads-resolve-db.sh"
    chmod +x "$repo_dir/scripts/codex-cli-update-monitor.sh" "$repo_dir/scripts/beads-resolve-db.sh"

    (
        cd "$repo_dir"
        git add scripts/codex-cli-update-monitor.sh scripts/beads-resolve-db.sh
        git commit -m "fixture: seed codex update monitor scripts" >/dev/null
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

run_monitor_fixture_with_script() {
    local monitor_script="$1"
    local local_version="$2"
    local output_dir="$3"
    shift 3

    CODEX_UPDATE_MONITOR_LOCAL_VERSION="$local_version" \
        "$monitor_script" \
        --config-file "$FIXTURE_DIR/config.toml" \
        --release-file "$FIXTURE_DIR/releases.json" \
        --json-out "$output_dir/report.json" \
        --summary-out "$output_dir/summary.md" \
        --stdout none \
        "$@"
}

run_monitor_fixture() {
    local local_version="$1"
    local output_dir="$2"
    shift 2

    run_monitor_fixture_with_script "$MONITOR_SCRIPT" "$local_version" "$output_dir" "$@"
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

    local work_dir report summary stdout_capture original_path fixture_root repo_dir worktree_path
    work_dir="$(secure_temp_dir codex-update-monitor)"
    original_path="$PATH"

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

    test_start "component_codex_update_monitor_parses_current_live_html_heading_shape"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    CODEX_UPDATE_MONITOR_LOCAL_VERSION="0.112.0" \
        "$MONITOR_SCRIPT" \
        --config-file "$FIXTURE_DIR/config.toml" \
        --release-file "$FIXTURE_DIR/releases-live-html.html" \
        --json-out "$work_dir/report.json" \
        --summary-out "$work_dir/summary.md" \
        --stdout none
    report="$work_dir/report.json"
    assert_eq "0.112.0" "$(jq -r '.latest_version' "$report")" "HTML changelog fixture should yield the latest version"
    assert_eq "current" "$(jq -r '.version_status' "$report")" "HTML changelog fixture should compare current version correctly"
    assert_eq "ignore" "$(jq -r '.recommendation' "$report")" "HTML changelog fixture should not force investigate when the heading shape changes"
    assert_contains "$(jq -r '.evidence | join("\n")' "$report")" "Compared against latest upstream release 0.112.0" "Evidence should show the parsed latest version from HTML"
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

    test_start "component_codex_update_monitor_accepts_list_root_issue_signals"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.112.0" "$work_dir" \
        --include-issue-signals \
        --issue-signals-file "$UPSTREAM_WATCHER_FIXTURE_DIR/issue-signals.json"
    report="$work_dir/report.json"
    assert_eq "ignore" "$(jq -r '.recommendation' "$report")" "List-root issue signals alone must remain advisory"
    assert_contains "$(jq -r '.evidence | join("\n")' "$report")" "Issue-signal intake reviewed 2 advisory item(s)." "Evidence should count advisory issues from list-root JSON"
    if grep -Fq "Failed to parse issue-signal source" < <(jq -r '.evidence | join("\n")' "$report"); then
        test_fail "List-root issue signals should not trigger a parse failure"
    else
        test_pass
    fi

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

    test_start "component_codex_update_monitor_suggests_issue_without_mutation_by_default"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.110.0" "$work_dir"
    report="$work_dir/report.json"
    assert_eq "suggested" "$(jq -r '.issue_action.mode' "$report")" "Upgrade-worthy results should suggest a follow-up without explicit sync"
    assert_eq "false" "$(jq -r '.issue_action.requested' "$report")" "Suggestion path should remain non-mutating"
    assert_contains "$(jq -r '.issue_action.notes | join("\n")' "$report")" "Re-run with --issue-action upsert" "Suggestion path should explain the opt-in sync step"
    test_pass

    test_start "component_codex_update_monitor_uses_local_worktree_db_for_implicit_upsert"
    fixture_root="$(secure_temp_dir codex-update-monitor-fixture)"
    repo_dir="$(seed_component_monitor_fixture_repo "$fixture_root")"
    worktree_path="${fixture_root}/moltinger-monitor-worktree"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$worktree_path" "feat/monitor-local-upsert" "main"
    worktree_path="$(canonicalize_fixture_path "$worktree_path")"
    seed_component_local_beads_foundation "$worktree_path"
    setup_fake_bd_fixture
    setup_broken_git_fixture
    export FAKE_BD_STATE_DIR
    export FAKE_BD_CREATE_ID="moltinger-test-created"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    PATH="$FAKE_BD_BIN_DIR:$BROKEN_GIT_BIN_DIR:$original_path" \
        run_monitor_fixture_with_script "$worktree_path/scripts/codex-cli-update-monitor.sh" "0.110.0" "$work_dir" \
        --issue-action upsert \
        --issue-threshold upgrade-later
    report="$work_dir/report.json"
    assert_eq "created" "$(jq -r '.issue_action.mode' "$report")" "Dedicated worktree upsert should still resolve a local tracker automatically"
    assert_contains "$(cat "$FAKE_BD_STATE_DIR/calls.log")" "--db ${worktree_path}/.beads/beads.db" "Implicit upsert should target the current worktree-local DB"
    test_pass

    test_start "component_codex_update_monitor_blocks_implicit_canonical_root_upsert"
    fixture_root="$(secure_temp_dir codex-update-monitor-fixture)"
    repo_dir="$(seed_component_monitor_fixture_repo "$fixture_root")"
    setup_fake_bd_fixture
    setup_broken_git_fixture
    export FAKE_BD_STATE_DIR
    work_dir="$(secure_temp_dir codex-update-monitor)"
    PATH="$FAKE_BD_BIN_DIR:$BROKEN_GIT_BIN_DIR:$original_path" \
        run_monitor_fixture_with_script "$repo_dir/scripts/codex-cli-update-monitor.sh" "0.110.0" "$work_dir" \
        --issue-action upsert \
        --issue-threshold upgrade-later
    report="$work_dir/report.json"
    assert_eq "skipped" "$(jq -r '.issue_action.mode' "$report")" "Canonical-root upsert should fail closed without an explicit DB target"
    assert_contains "$(jq -r '.issue_action.notes | join("\n")' "$report")" "mutating canonical-root tracker commands are blocked by default" "Canonical-root block should be reported explicitly"
    if [[ -f "$FAKE_BD_STATE_DIR/calls.log" ]]; then
        test_fail "Canonical-root implicit upsert must not invoke bd"
    else
        test_pass
    fi

    test_start "component_codex_update_monitor_creates_issue_when_explicit_upsert_requested"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    export FAKE_BD_CREATE_ID="moltinger-test-created"
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.111.0" "$work_dir" \
        --issue-action upsert \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "created" "$(jq -r '.issue_action.mode' "$report")" "Explicit upsert without target should create a follow-up"
    assert_eq "true" "$(jq -r '.issue_action.requested' "$report")" "Issue action request should be recorded"
    assert_eq "moltinger-test-created" "$(jq -r '.issue_action.target' "$report")" "Created issue id should be preserved in the report"
    assert_contains "$(cat "$FAKE_BD_STATE_DIR/calls.log")" "create" "Beads create should be invoked"
    test_pass

    test_start "component_codex_update_monitor_updates_target_issue_when_requested"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    unset FAKE_BD_CREATE_ID
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.111.0" "$work_dir" \
        --issue-action upsert \
        --issue-target moltinger-222 \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "updated" "$(jq -r '.issue_action.mode' "$report")" "Explicit upsert with a target should update the existing issue"
    assert_eq "moltinger-222" "$(jq -r '.issue_action.target' "$report")" "Requested issue target should be preserved"
    assert_contains "$(cat "$FAKE_BD_STATE_DIR/calls.log")" "update" "Beads update should be invoked"
    test_pass

    test_start "component_codex_update_monitor_skips_tracker_mutation_below_threshold"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.112.0" "$work_dir" \
        --issue-action upsert \
        --issue-threshold upgrade-now \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "skipped" "$(jq -r '.issue_action.mode' "$report")" "Below-threshold recommendations should not mutate tracker state"
    assert_contains "$(jq -r '.issue_action.notes | join("\n")' "$report")" "does not meet threshold" "Skip path should explain why tracker sync did not run"
    if [[ -f "$FAKE_BD_STATE_DIR/calls.log" ]]; then
        test_fail "No bd call should be made when recommendation is below threshold"
    else
        test_pass
    fi

    test_start "component_codex_update_monitor_reports_update_failure"
    setup_fake_bd_fixture
    export PATH="$FAKE_BD_BIN_DIR:$original_path"
    export FAKE_BD_STATE_DIR
    export FAKE_BD_UPDATE_FAIL=1
    work_dir="$(secure_temp_dir codex-update-monitor)"
    run_monitor_fixture "0.111.0" "$work_dir" \
        --issue-action upsert \
        --issue-target moltinger-222 \
        --beads-db "$FAKE_BD_DB"
    report="$work_dir/report.json"
    assert_eq "skipped" "$(jq -r '.issue_action.mode' "$report")" "Failed tracker update should be surfaced as skipped"
    assert_contains "$(jq -r '.issue_action.notes | join("\n")' "$report")" "Failed to update Beads issue" "Failure path should be explicit in the report"
    unset FAKE_BD_UPDATE_FAIL
    export PATH="$original_path"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_codex_cli_update_monitor_tests
fi
