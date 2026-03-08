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

setup_workflow_repo() {
    local fixture_root="$1"
    local repo_dir
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    git_topology_fixture_seed_registry_assets "$repo_dir" "$PROJECT_ROOT"
    write_workflow_intent "$repo_dir"

    (
        cd "$repo_dir"
        ./scripts/git-topology-registry.sh refresh --write-doc >/dev/null
    )

    printf '%s\n' "$repo_dir"
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

    (
        cd "$repo_dir"
        ./scripts/git-topology-registry.sh refresh --write-doc >/dev/null
    )

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" '`007-demo-feature`' "Managed start should refresh branch entry"
    assert_contains "$doc" '`parallel-feature-007`' "Managed start should refresh worktree entry"
    assert_contains "$doc" '`origin/007-demo-feature`' "Managed start should refresh remote entry"

    git_topology_fixture_remove_worktree "$repo_dir" "$worktree_path"
    git_topology_fixture_delete_branch "$repo_dir" "007-demo-feature"

    (
        cd "$repo_dir"
        ./scripts/git-topology-registry.sh refresh --write-doc >/dev/null
    )

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_not_contains_literal "$doc" '`007-demo-feature`' "Cleanup should remove deleted branch from registry"
    assert_not_contains_literal "$doc" '`parallel-feature-007`' "Cleanup should remove deleted worktree from registry"
    assert_not_contains_literal "$doc" '`origin/007-demo-feature`' "Cleanup should remove deleted remote branch from registry"

    rm -rf "$fixture_root"
    test_pass
}

test_hooks_and_session_boundary_reconcile_out_of_band_drift() {
    test_start "git_topology_registry_hooks_and_session_boundary_reconcile_out_of_band_drift"

    local fixture_root repo_dir worktree_path health_file status_after_hook status_after_doctor doc pre_push_output pre_push_rc
    fixture_root="$(mktemp -d /tmp/git-topology-e2e.XXXXXX)"
    repo_dir="$(setup_workflow_repo "$fixture_root")"
    worktree_path="$fixture_root/repo-008-worktree"
    health_file="$repo_dir/.git/topology-registry/health.env"

    git_topology_fixture_add_branch "$repo_dir" "008-out-of-band"
    git_topology_fixture_add_worktree "$repo_dir" "$worktree_path" "008-out-of-band"

    (
        cd "$repo_dir"
        ./.githooks/post-checkout >/dev/null 2>&1 || true
    )

    status_after_hook="$(grep '^status=' "$health_file" | cut -d'=' -f2)"
    assert_eq "stale" "$status_after_hook" "Post-checkout hook should mark stale topology"

    pre_push_output="$(
        cd "$repo_dir" &&
        set +e &&
        ./.githooks/pre-push 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    pre_push_rc="$(printf '%s\n' "$pre_push_output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "1" "$pre_push_rc" "Pre-push hook should block stale topology pushes"
    assert_contains "$pre_push_output" 'Push blocked until docs/GIT-TOPOLOGY-REGISTRY.md matches live git state.' "Pre-push hook should print actionable guidance"

    (
        cd "$repo_dir"
        ./scripts/git-topology-registry.sh doctor --prune --write-doc >/dev/null
    )

    status_after_doctor="$(grep '^status=' "$health_file" | cut -d'=' -f2)"
    assert_eq "ok" "$status_after_doctor" "Session-boundary doctor should reconcile stale topology"

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" '`008-out-of-band`' "Doctor reconciliation should refresh branch entry"
    assert_contains "$doc" '`parallel-feature-008`' "Doctor reconciliation should refresh worktree entry"

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

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
