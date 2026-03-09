#!/bin/bash
# Unit tests for worktree-ready helper planning and one-shot UX.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

WORKTREE_READY_SCRIPT="$PROJECT_ROOT/scripts/worktree-ready.sh"

create_fake_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "worktree" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  printf '[]\n'
  exit 0
fi

printf 'unsupported fake bd invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

run_worktree_plan() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" plan --repo "$repo_dir" "$@"
}

run_worktree_attach() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" "$@"
}

run_worktree_create() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" "$@"
}

create_fake_direnv_permission_denied_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/direnv-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/direnv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "export" && "${2:-}" == "json" ]]; then
  printf 'direnv: error open /Users/test/.local/share/direnv/allow/demo: operation not permitted\n' >&2
  exit 1
fi

printf 'unsupported fake direnv invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/direnv"

    printf '%s\n' "${fake_bin}"
}

test_plan_creates_clean_slug_without_issue() {
    test_start "worktree_ready_plan_creates_clean_slug_without_issue"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening)"

    assert_contains "$output" 'Branch: feat/remote-uat-hardening' "Slug-only plan should derive a clean feature branch"
    assert_contains "$output" 'Preview: ../moltinger-remote-uat-hardening' "Slug-only plan should derive a clean sibling worktree path"
    assert_contains "$output" 'Decision: create_clean' "Slug-only plan should choose clean creation when there are no collisions"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_normalizes_issue_short_in_worktree_path() {
    test_start "worktree_ready_plan_normalizes_issue_short_in_worktree_path"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --issue moltinger-dmi --slug telegram-webhook-rollout)"

    assert_contains "$output" 'Branch: feat/moltinger-dmi-telegram-webhook-rollout' "Issue-aware plan should keep the full issue id in the branch name"
    assert_contains "$output" 'Preview: ../moltinger-dmi-telegram-webhook-rollout' "Issue-aware plan should strip the repo prefix from the worktree suffix"
    assert_contains "$output" 'Decision: create_clean' "Issue-aware plan should stay clean when no collisions exist"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_reuses_existing_attached_worktree() {
    test_start "worktree_ready_plan_reuses_existing_attached_worktree"

    local fixture_root repo_dir fake_bin output existing_path
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening)"

    assert_contains "$output" 'Decision: reuse_existing' "Exact attached branch should be reused instead of duplicated"
    assert_contains "$output" "$existing_path" "Plan should point to the existing worktree path"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_reports_clean_preview_for_existing_feature_branch() {
    test_start "worktree_ready_attach_reports_clean_preview_for_existing_feature_branch"

    local fixture_root repo_dir fake_bin output existing_path
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"

    output="$(run_worktree_attach "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --handoff manual)"

    assert_contains "$output" 'Preview: ../moltinger-remote-uat-hardening' "Attach flow should reuse the normalized sibling preview for feature branches"
    assert_contains "$output" "$existing_path" "Attach flow should report the already-attached worktree path"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_attaches_existing_local_branch() {
    test_start "worktree_ready_plan_attaches_existing_local_branch"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening" "main"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening)"

    assert_contains "$output" 'Decision: attach_existing_branch' "Existing unattached local branch should switch the plan into attach mode"
    assert_contains "$output" 'Question: A local branch already exists for this request.' "Attach plan should explain why creation is not the default"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_asks_once_when_similar_branch_exists() {
    test_start "worktree_ready_plan_asks_once_when_similar_branch_exists"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening-v2" "main"

    output="$(
        set +e
        run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "10" "$rc" "Similar branch names should now return the clarification exit code"
    assert_contains "$output" 'Decision: needs_clarification' "Similar branch names should trigger one clarification instead of silent duplication"
    assert_contains "$output" 'clean worktree' "Clarification question should keep the clean-new option explicit"
    assert_contains "$output" 'feat/remote-uat-hardening-v2' "Clarification output should include the strongest similar candidate"

    rm -rf "$fixture_root"
    test_pass
}

test_create_treats_direnv_permission_denied_as_needs_env_approval() {
    test_start "worktree_ready_create_treats_direnv_permission_denied_as_needs_env_approval"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-remote-uat-hardening"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/remote-uat-hardening --path "$probe_dir"
    )"

    assert_contains "$output" 'Status: needs_env_approval' "Permission-denied direnv probe should still guide the user through env approval"
    assert_contains "$output" 'direnv allow' "Permission-denied direnv probe should suggest the safe recovery step"
    assert_contains "$output" '```bash' "Manual handoff should render a fenced bash block for copy-paste"
    assert_contains "$output" "cd ${probe_dir}" "Manual handoff bash block should include the target worktree path"
    assert_contains "$output" 'codex' "Manual handoff bash block should end with the Codex launch command"

    rm -rf "$fixture_root"
    test_pass
}

test_create_env_format_emits_handoff_boundary_contract() {
    test_start "worktree_ready_create_env_format_emits_handoff_boundary_contract"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-remote-uat-hardening"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/remote-uat-hardening --path "$probe_dir" --format env
    )"

    assert_contains "$output" 'schema=worktree-handoff/v1' "Create env output should expose the handoff schema"
    assert_contains "$output" 'phase=create' "Create env output should declare the create phase"
    assert_contains "$output" 'boundary=stop_after_create' "Create env output should declare the hard handoff boundary"
    assert_contains "$output" 'final_state=handoff_needs_env_approval' "Blocked env approval should map to the env-approval final state"
    assert_contains "$output" 'approval_required=true' "Blocked env approval should require approval explicitly"
    assert_contains "$output" 'handoff_mode=manual' "Default handoff mode should remain manual"

    rm -rf "$fixture_root"
    test_pass
}

test_create_uses_explicit_pending_summary() {
    test_start "worktree_ready_create_uses_explicit_pending_summary"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-openclaw-control-plane"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/openclaw-control-plane --path "$probe_dir" \
          --pending-summary "Start Speckit for the OpenClaw Control Plane epic in the target worktree."
    )"

    assert_contains "$output" 'Pending: Start Speckit for the OpenClaw Control Plane epic in the target worktree.' "Explicit downstream intent should replace the generic pending handoff text"
    assert_contains "$output" '```text' "Explicit downstream intent should append the advisory Phase B text block"
    assert_contains "$output" 'Phase B only.' "Explicit downstream intent should use the fixed Phase B seed prompt header"
    assert_contains "$output" 'Task: Start Speckit for the OpenClaw Control Plane epic in the target worktree.' "Phase B seed prompt should preserve the exact downstream task"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/openclaw-control-plane --path "$probe_dir" \
          --pending-summary "Start Speckit for the OpenClaw Control Plane epic in the target worktree." --format env
    )"

    assert_contains "$output" 'pending=Start\ Speckit\ for\ the\ OpenClaw\ Control\ Plane\ epic\ in\ the\ target\ worktree.' "Env contract should preserve explicit pending handoff intent"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_needs_clarification_returns_exit_code_10() {
    test_start "worktree_ready_plan_needs_clarification_returns_exit_code_10"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening-v2" "main"

    output="$(
        set +e
        run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening --format env 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "10" "$rc" "Ambiguous plan output should return the clarification exit code"
    assert_contains "$output" 'schema=worktree-plan/v1' "Plan env output should expose the planning schema"
    assert_contains "$output" 'decision=needs_clarification' "Plan env output should preserve the clarification decision"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_missing_branch_returns_blocked_missing_branch() {
    test_start "worktree_ready_attach_missing_branch_returns_blocked_missing_branch"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(
        set +e
        run_worktree_attach "$repo_dir" "$fake_bin" --branch feat/missing-line --format env 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "22" "$rc" "Missing existing branch should return the blocked-missing-branch exit code"
    assert_contains "$output" 'final_state=blocked_missing_branch' "Missing existing branch should map to the blocked missing branch final state"
    assert_contains "$output" 'repair_command=Create\ or\ fetch\ the\ branch' "Missing existing branch should emit an exact repair command"

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Worktree Ready Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$WORKTREE_READY_SCRIPT" ]]; then
        test_fail "Worktree-ready helper missing or not executable: $WORKTREE_READY_SCRIPT"
        generate_report
        return 1
    fi

    test_plan_creates_clean_slug_without_issue
    test_plan_normalizes_issue_short_in_worktree_path
    test_plan_reuses_existing_attached_worktree
    test_attach_reports_clean_preview_for_existing_feature_branch
    test_plan_attaches_existing_local_branch
    test_plan_asks_once_when_similar_branch_exists
    test_create_treats_direnv_permission_denied_as_needs_env_approval
    test_create_env_format_emits_handoff_boundary_contract
    test_create_uses_explicit_pending_summary
    test_plan_needs_clarification_returns_exit_code_10
    test_attach_missing_branch_returns_blocked_missing_branch
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
