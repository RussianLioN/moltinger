#!/bin/bash
# E2E workflow coverage for git topology registry managed mutations and recovery.
# E2E_REQUIRES_CONTAINERS=false

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/test_helpers.sh"
source "$LIB_DIR/git_topology_fixture.sh"

REGISTRY_SCRIPT="$PROJECT_ROOT/scripts/git-topology-registry.sh"

write_workflow_intent() {
    local repo_dir="$1"

    cat > "$repo_dir/docs/GIT-TOPOLOGY-INTENT.yaml" <<'EOF'
version: 1
defaults:
  missing_intent: needs-decision
records:
  - subject_type: branch
    subject_key: main
    intent: active
    note: Canonical source of truth.
  - subject_type: worktree
    subject_key: primary-root
    intent: active
    note: Canonical root worktree.
EOF
}

append_out_of_band_reviewed_intent() {
  local repo_dir="$1"

    cat >> "$repo_dir/docs/GIT-TOPOLOGY-INTENT.yaml" <<'EOF'
  - subject_type: branch
    subject_key: 008-out-of-band
    intent: active
    note: Reviewed branch note retained across doctor.
  - subject_type: remote
    subject_key: origin/008-out-of-band
    intent: active
    note: Reviewed remote note retained across doctor.
  - subject_type: worktree
    subject_key: parallel-feature-008
    intent: protected
    note: Reviewed worktree note retained across doctor.
EOF
}

write_feature_authority_intent() {
    local repo_dir="$1"

    cat > "$repo_dir/docs/GIT-TOPOLOGY-INTENT.yaml" <<'EOF'
version: 1
defaults:
  missing_intent: needs-decision
records:
  - subject_type: branch
    subject_key: main
    intent: active
    note: Canonical source of truth.
  - subject_type: branch
    subject_key: 006-demo-feature
    intent: active
    note: Active demo feature branch.
  - subject_type: worktree
    subject_key: primary-feature-006
    intent: active
    note: Authoritative worktree for demo feature.
  - subject_type: worktree
    subject_key: primary-root
    intent: active
    note: Canonical root worktree.
EOF
}

setup_workflow_repo() {
    local fixture_root="$1"
    local repo_dir
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    git_topology_fixture_seed_registry_assets "$repo_dir" "$PROJECT_ROOT"
    write_workflow_intent "$repo_dir"
    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "./scripts/git-topology-registry.sh"

    printf '%s\n' "$repo_dir"
}

seed_broken_registry_check_stub() {
    local repo_dir="$1"
    cat > "$repo_dir/scripts/git-topology-registry.sh" <<'EOF'
#!/bin/bash
echo "[git-topology-registry] simulated internal error" >&2
exit 2
EOF
    chmod +x "$repo_dir/scripts/git-topology-registry.sh"
}

assert_not_contains_literal() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        test_fail "$message (needle: '$needle')"
        return 1
    fi

    return 0
}

test_managed_start_and_cleanup_refresh_registry() {
    test_start "git_topology_registry_managed_start_and_cleanup_refresh_registry"

    local fixture_root repo_dir worktree_path doc
    fixture_root="$(mktemp -d /tmp/git-topology-e2e.XXXXXX)"
    repo_dir="$(setup_workflow_repo "$fixture_root")"
    worktree_path="$fixture_root/repo-007-worktree"

    git_topology_fixture_add_branch "$repo_dir" "007-demo-feature"
    git_topology_fixture_add_worktree "$repo_dir" "$worktree_path" "007-demo-feature"

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "./scripts/git-topology-registry.sh"

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" '`007-demo-feature`' "Managed start should refresh branch entry"
    assert_contains "$doc" '`primary-feature-007`' "Managed start should refresh worktree entry"
    assert_contains "$doc" '`origin/007-demo-feature`' "Managed start should refresh remote entry"

    git_topology_fixture_remove_worktree "$repo_dir" "$worktree_path"
    git_topology_fixture_delete_branch "$repo_dir" "007-demo-feature"

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "./scripts/git-topology-registry.sh"

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_not_contains_literal "$doc" '`007-demo-feature`' "Cleanup should remove deleted branch from registry"
    assert_not_contains_literal "$doc" '`primary-feature-007`' "Cleanup should remove deleted worktree from registry"
    assert_not_contains_literal "$doc" '`origin/007-demo-feature`' "Cleanup should remove deleted remote branch from registry"

    rm -rf "$fixture_root"
    test_pass
}

test_hooks_and_session_boundary_reconcile_out_of_band_drift() {
    test_start "git_topology_registry_hooks_and_session_boundary_reconcile_out_of_band_drift"

    local fixture_root repo_dir worktree_path publish_worktree health_file draft_file backup_dir latest_backup
    local status_after_hook status_after_doctor doc doc_before_doctor post_checkout_output post_checkout_rc pre_push_output pre_push_rc
    local publish_pre_push_output publish_pre_push_rc doctor_output doctor_rc
    fixture_root="$(mktemp -d /tmp/git-topology-e2e.XXXXXX)"
    repo_dir="$(setup_workflow_repo "$fixture_root")"
    worktree_path="$fixture_root/repo-008-worktree"
    health_file="$repo_dir/.git/topology-registry/health.env"
    draft_file="$repo_dir/.git/topology-registry/registry.draft.md"
    backup_dir="$repo_dir/.git/topology-registry/backups"

    append_out_of_band_reviewed_intent "$repo_dir"

    git_topology_fixture_add_branch "$repo_dir" "008-out-of-band"
    git_topology_fixture_add_worktree "$repo_dir" "$worktree_path" "008-out-of-band"
    rm -f "$draft_file"

    doc_before_doctor="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"

    post_checkout_output="$(
        cd "$repo_dir" &&
        set +e &&
        ./.githooks/post-checkout 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    post_checkout_rc="$(printf '%s\n' "$post_checkout_output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "0" "$post_checkout_rc" "Post-checkout hook should remain non-blocking"
    assert_contains "$post_checkout_output" 'status=stale' "Post-checkout hook should surface stale topology"
    assert_contains "$post_checkout_output" 'post-checkout detected topology drift.' "Post-checkout hook should print actionable stale guidance"
    assert_false "$(test -f "$draft_file"; printf '%s' "$?")" "Post-checkout hook should not create a recovery draft"
    status_after_hook="$(grep '^status=' "$health_file" | cut -d'=' -f2)"
    assert_eq "ok" "$status_after_hook" "Read-only hook check should preserve the last successful health state"

    pre_push_output="$(
        cd "$repo_dir" &&
        set +e &&
        ./.githooks/pre-push 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    pre_push_rc="$(printf '%s\n' "$pre_push_output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "0" "$pre_push_rc" "Pre-push hook should stay non-blocking on ordinary branches"
    assert_contains "$pre_push_output" 'Push allowed with stale topology snapshot.' "Ordinary pre-push hook should explain the warning-only path"

    publish_worktree="$(git_topology_fixture_prepare_publish_worktree "$repo_dir" "$(git_topology_fixture_publish_branch_name)")"
    git_topology_fixture_copy_registry_assets_between_worktrees "$repo_dir" "$repo_dir" "$publish_worktree"
    publish_pre_push_output="$(
        cd "$publish_worktree" &&
        set +e &&
        ./.githooks/pre-push 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    publish_pre_push_rc="$(printf '%s\n' "$publish_pre_push_output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "1" "$publish_pre_push_rc" "Pre-push hook should block stale topology pushes on the dedicated publish branch"
    assert_contains "$publish_pre_push_output" 'Push blocked until docs/GIT-TOPOLOGY-REGISTRY.md matches live git state on this topology-publish branch.' "Publish-branch pre-push hook should print actionable guidance"

    doctor_output="$(
        cd "$repo_dir" &&
        set +e &&
        ./scripts/git-topology-registry.sh doctor --prune 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    doctor_rc="$(printf '%s\n' "$doctor_output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "1" "$doctor_rc" "Doctor without --write-doc should exit stale"
    assert_contains "$doctor_output" 'draft saved to' "Doctor stale path should write a recovery draft"
    assert_file_exists "$draft_file" "Doctor stale path should save the rendered draft"
    assert_eq "$doc_before_doctor" "$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")" "Doctor without --write-doc should preserve the last committed registry"
    assert_contains "$(cat "$draft_file")" 'Reviewed branch note retained across doctor.' "Recovery draft should preserve reviewed branch intent"
    assert_contains "$(cat "$draft_file")" 'Reviewed worktree note retained across doctor.' "Recovery draft should preserve reviewed worktree intent"

    git_topology_fixture_doctor_write_doc_from_publish_branch "$repo_dir" "./scripts/git-topology-registry.sh"

    status_after_doctor="$(grep '^status=' "$health_file" | cut -d'=' -f2)"
    assert_eq "ok" "$status_after_doctor" "Session-boundary doctor should reconcile stale topology"

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" 'Reviewed branch note retained across doctor.' "Doctor reconciliation should preserve reviewed branch annotation"
    assert_contains "$doc" 'Reviewed remote note retained across doctor.' "Doctor reconciliation should preserve reviewed remote annotation"
    assert_contains "$doc" 'Reviewed worktree note retained across doctor.' "Doctor reconciliation should preserve reviewed worktree annotation"
    assert_contains "$doc" '`008-out-of-band`' "Doctor reconciliation should refresh branch entry"
    assert_contains "$doc" '`primary-feature-008`' "Doctor reconciliation should refresh worktree entry"
    assert_not_contains_literal "$doc" '`branch` | `008-out-of-band`' "Reconciled branch should no longer appear in orphan intent table"
    assert_dir_exists "$backup_dir" "Doctor reconciliation should create backup directory"
    latest_backup="$(find "$backup_dir" -type f -name 'registry-*.md' | sort | tail -1)"
    assert_file_exists "$latest_backup" "Doctor reconciliation should save a backup of the previous registry"
    assert_eq "$doc_before_doctor" "$(cat "$latest_backup")" "Backup should preserve the last good committed registry"

    rm -rf "$fixture_root"
    test_pass
}

test_pre_push_fails_closed_when_registry_check_errors() {
    test_start "git_topology_registry_pre_push_fails_closed_when_registry_check_errors"

    local fixture_root repo_dir pre_push_output pre_push_rc
    fixture_root="$(mktemp -d /tmp/git-topology-e2e.XXXXXX)"
    repo_dir="$(setup_workflow_repo "$fixture_root")"
    seed_broken_registry_check_stub "$repo_dir"

    pre_push_output="$(
        cd "$repo_dir" &&
        set +e &&
        ./.githooks/pre-push 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    pre_push_rc="$(printf '%s\n' "$pre_push_output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "1" "$pre_push_rc" "Pre-push hook should fail closed when topology check errors unexpectedly"
    assert_contains "$pre_push_output" 'simulated internal error' "Pre-push hook should surface the underlying topology check failure"
    assert_contains "$pre_push_output" 'Topology registry check failed unexpectedly; refusing push until scripts/git-topology-registry.sh check succeeds.' "Pre-push hook should print explicit fail-closed guidance"

    rm -rf "$fixture_root"
    test_pass
}

test_child_branch_doctor_preserves_authoritative_feature_identity() {
    test_start "git_topology_registry_child_branch_doctor_preserves_authoritative_feature_identity"

    local fixture_root repo_dir feature_worktree child_worktree doc
    fixture_root="$(mktemp -d /tmp/git-topology-e2e.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    git_topology_fixture_seed_registry_assets "$repo_dir" "$PROJECT_ROOT"
    mkdir -p "$repo_dir/docs"
    write_feature_authority_intent "$repo_dir"

    (
        cd "$repo_dir"
        git add docs scripts .githooks
        git commit -m "fixture: seed topology registry assets" >/dev/null
        git switch -c 006-demo-feature >/dev/null
        printf 'demo\n' > demo-feature.txt
        git add demo-feature.txt
        git commit -m "fixture: add demo feature branch" >/dev/null
        git push -u origin 006-demo-feature >/dev/null
        git switch main >/dev/null
    )

    feature_worktree="$fixture_root/repo-006-worktree"
    child_worktree="$fixture_root/repo-child-worktree"
    git_topology_fixture_add_worktree "$repo_dir" "$feature_worktree" "006-demo-feature"

    git_topology_fixture_refresh_registry_from_publish_branch "$feature_worktree" "./scripts/git-topology-registry.sh"
    (
        cd "$feature_worktree"
        git add docs/GIT-TOPOLOGY-REGISTRY.md
        git commit -m "fixture: commit authoritative feature registry" >/dev/null
    )

    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$child_worktree" "feat/demo-child" "006-demo-feature"

    git_topology_fixture_doctor_write_doc_from_publish_branch "$child_worktree" "./scripts/git-topology-registry.sh"

    doc="$(cat "$child_worktree/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" '`primary-feature-006`' "Child-branch reconcile should preserve canonical authoritative feature worktree id"
    assert_contains "$doc" 'Authoritative worktree for demo feature.' "Child-branch reconcile should preserve authoritative worktree note"
    assert_contains "$doc" '`demo-child`' "Child-branch reconcile should include the new task worktree"
    assert_not_contains_literal "$doc" '`parallel-feature-006`' "Child-branch reconcile must not downgrade authoritative feature worktree to a parallel id"
    assert_not_contains_literal "$doc" '| `worktree` | `primary-feature-006` |' "Canonical authoritative worktree must not be rendered as orphan intent"

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Git Topology Registry Workflow E2E Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$REGISTRY_SCRIPT" ]]; then
        test_fail "Registry script missing or not executable: $REGISTRY_SCRIPT"
        generate_report
        return 1
    fi

    test_managed_start_and_cleanup_refresh_registry
    test_hooks_and_session_boundary_reconcile_out_of_band_drift
    test_pre_push_fails_closed_when_registry_check_errors
    test_child_branch_doctor_preserves_authoritative_feature_identity

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
