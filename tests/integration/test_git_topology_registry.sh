#!/bin/bash
# Integration tests for git topology registry refresh/check behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/test_helpers.sh"
source "$LIB_DIR/git_topology_fixture.sh"

REGISTRY_SCRIPT="$PROJECT_ROOT/scripts/git-topology-registry.sh"

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

write_demo_intent() {
    local repo_dir="$1"
    cat > "$repo_dir/docs/GIT-TOPOLOGY-INTENT.yaml" <<'EOF'
version: 1
defaults:
  missing_intent: needs-decision
records:
  - subject_type: branch
    subject_key: 099-retired-feature
    intent: protected
    note: Preserve this reviewed note until the sidecar is pruned.
  - subject_type: branch
    subject_key: main
    intent: active
    note: Canonical source of truth.
  - subject_type: branch
    subject_key: 007-demo-feature
    intent: active
    note: Demo feature branch.
  - subject_type: remote
    subject_key: origin/007-demo-feature
    intent: active
    note: Demo remote feature branch.
  - subject_type: worktree
    subject_key: parallel-feature-007
    intent: active
    note: Demo feature worktree.
  - subject_type: worktree
    subject_key: primary-root
    intent: active
    note: Canonical root worktree.
EOF
}

setup_demo_repo() {
    local fixture_root="$1"
    local repo_dir worktree_path
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    git_topology_fixture_add_branch "$repo_dir" "007-demo-feature"
    git_topology_fixture_add_local_branch "$repo_dir" "008-unreviewed"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"
    worktree_path="$fixture_root/repo-007-worktree"
    git_topology_fixture_add_worktree "$repo_dir" "$worktree_path" "007-demo-feature"
    printf '%s\n' "$repo_dir"
}

test_refresh_writes_sanitized_registry() {
    test_start "git_topology_registry_refresh_writes_sanitized_registry"

    local fixture_root repo_dir doc
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"
    (
        cd "$repo_dir"
        "$REGISTRY_SCRIPT" check >/dev/null
    )

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" 'Generated artifact from shared remote-governance topology' "Registry should be rendered as the shared remote-governance snapshot"
    assert_contains "$doc" 'Demo remote feature branch.' "Registry should render reviewed remote intent"
    assert_contains "$doc" '`origin/007-demo-feature`' "Registry should include the unmerged remote branch row"
    assert_not_contains_literal "$doc" '## Current Worktrees' "Tracked registry should not publish local worktree inventory"
    assert_not_contains_literal "$doc" '## Active Local Branches' "Tracked registry should not publish local branch inventory"
    assert_not_contains_literal "$doc" 'Demo feature worktree.' "Tracked registry should keep worktree-only intent out of the shared snapshot"

    if [[ "$doc" == *"$fixture_root"* ]] || [[ "$doc" == *"$repo_dir"* ]]; then
        test_fail "Registry leaked absolute integration fixture paths"
        rm -rf "$fixture_root"
        return 1
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_refresh_is_noop_when_topology_is_unchanged() {
    test_start "git_topology_registry_refresh_is_noop_when_topology_is_unchanged"

    local fixture_root repo_dir status_output
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"

    (
        cd "$repo_dir"
        git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"
        git add docs/GIT-TOPOLOGY-REGISTRY.md docs/GIT-TOPOLOGY-INTENT.yaml
        git commit -m "fixture: add generated registry" >/dev/null
        git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"
        status_output="$(git status --short docs/GIT-TOPOLOGY-REGISTRY.md)"
        printf '%s\n' "$status_output" > "$fixture_root/status.out"
    )

    status_output="$(cat "$fixture_root/status.out")"
    assert_eq "" "$status_output" "Repeated refresh should not dirty the generated registry"

    rm -rf "$fixture_root"
    test_pass
}

test_orphan_intent_and_default_needs_decision_are_rendered() {
    test_start "git_topology_registry_orphan_intent_and_default_needs_decision_are_rendered"

    local fixture_root repo_dir doc
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" '## Reviewed Intent Awaiting Reconciliation' "Registry should surface orphan reviewed intent"
    assert_contains "$doc" '099-retired-feature' "Registry should list orphan subject key"
    assert_contains "$doc" 'Preserve this reviewed note until the sidecar is pruned.' "Registry should preserve orphan reviewed note"
    assert_not_contains_literal "$doc" '008-unreviewed' "Unreviewed local-only branches should stay out of the tracked remote-governance snapshot"
    assert_not_contains_literal "$doc" '| `branch` | `007-demo-feature` |' "Branch intent backed by a live remote branch should not linger as an orphan"
    if [[ "$doc" == *"parallel-feature-007"* ]]; then
        test_fail "Legacy numeric feature alias should not render as a separate orphan record"
        rm -rf "$fixture_root"
        return 1
    fi
    assert_not_contains_literal "$doc" 'Demo feature worktree.' "Tracked registry should not surface worktree-only intent in orphan output"

    rm -rf "$fixture_root"
    test_pass
}

test_check_is_observer_independent_across_sibling_worktrees() {
    test_start "git_topology_registry_check_is_observer_independent_across_sibling_worktrees"

    local fixture_root repo_dir worktree_path
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"
    worktree_path="$fixture_root/repo-007-worktree"

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"

    (
        cd "$worktree_path"
        mkdir -p docs
        cp "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md" docs/GIT-TOPOLOGY-REGISTRY.md
        cp "$repo_dir/docs/GIT-TOPOLOGY-INTENT.yaml" docs/GIT-TOPOLOGY-INTENT.yaml
        git add docs/GIT-TOPOLOGY-REGISTRY.md docs/GIT-TOPOLOGY-INTENT.yaml
        git commit -m "fixture: record registry snapshot from sibling observer" >/dev/null
        "$REGISTRY_SCRIPT" check >/dev/null
    )

    rm -rf "$fixture_root"
    test_pass
}

test_lock_timeout_reports_owner_diagnostics() {
    test_start "git_topology_registry_lock_timeout_reports_owner_diagnostics"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"

    git_topology_fixture_switch_branch "$repo_dir" "$(git_topology_fixture_publish_branch_name)"

    mkdir -p "$repo_dir/.git/topology-registry/lock"
    cat > "$repo_dir/.git/topology-registry/lock/owner.env" <<'EOF'
pid=999999
ppid=1
action=refresh
branch=uat/006-git-topology-registry
cwd=/tmp/fake-lock-owner
git_root=/tmp/fake-repo
host=unknown
started_at=2026-03-09T00:00:00Z
EOF

    output="$(
        cd "$repo_dir" &&
        set +e &&
        GIT_TOPOLOGY_REGISTRY_LOCK_WAIT_ATTEMPTS=1 "$REGISTRY_SCRIPT" refresh --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "$rc" "Refresh should fail fast when the topology lock is already held"
    assert_contains "$output" 'Lock owner action: refresh' "Timeout diagnostics should report the owner action"
    assert_contains "$output" 'Lock owner branch: uat/006-git-topology-registry' "Timeout diagnostics should report the owner branch"
    assert_contains "$output" 'Lock owner cwd: /tmp/fake-lock-owner' "Timeout diagnostics should report the owner worktree path"
    assert_contains "$output" 'stale lock is likely' "Timeout diagnostics should distinguish a dead owner from an active sibling process"

    rm -rf "$fixture_root"
    test_pass
}

test_lock_timeout_without_owner_metadata_reports_actionable_fallback() {
    test_start "git_topology_registry_lock_timeout_without_owner_metadata_reports_actionable_fallback"

    local fixture_root repo_dir output rc expected_lock_dir common_dir
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"
    common_dir="$(cd "$repo_dir" && git rev-parse --git-common-dir)"
    expected_lock_dir="${common_dir}/topology-registry/lock"

    (
        cd "$repo_dir"
        git_topology_fixture_switch_branch "$repo_dir" "$(git_topology_fixture_publish_branch_name)"
        mkdir -p "$expected_lock_dir"
    )

    output="$(
        cd "$repo_dir" &&
        set +e &&
        GIT_TOPOLOGY_REGISTRY_LOCK_WAIT_ATTEMPTS=1 "$REGISTRY_SCRIPT" refresh --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "$rc" "Refresh should fail fast when the topology lock directory exists without metadata"
    assert_contains "$output" 'Lock owner metadata is unavailable.' "Timeout diagnostics should report missing owner metadata explicitly"
    assert_contains "$output" 'older topology script or a previous refresh/doctor exited before writing owner metadata' "Missing metadata diagnostics should explain the most likely causes"
    assert_contains "$output" "remove: ${expected_lock_dir}" "Missing metadata diagnostics should include the exact cleanup path"

    rm -rf "$fixture_root"
    test_pass
}

test_lock_permission_boundary_reports_non_lock_failure() {
    test_start "git_topology_registry_lock_permission_boundary_reports_non_lock_failure"

    local fixture_root repo_dir output rc common_dir state_dir lock_dir
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"
    common_dir="$(cd "$repo_dir" && git rev-parse --git-common-dir)"
    state_dir="${common_dir}/topology-registry"
    lock_dir="${state_dir}/lock"

    (
        cd "$repo_dir"
        git_topology_fixture_switch_branch "$repo_dir" "$(git_topology_fixture_publish_branch_name)"
        mkdir -p "$state_dir"
        : > "$lock_dir"
    )

    output="$(
        cd "$repo_dir" &&
        set +e &&
        GIT_TOPOLOGY_REGISTRY_LOCK_WAIT_ATTEMPTS=1 "$REGISTRY_SCRIPT" refresh --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "$rc" "Refresh should fail when the shared topology state is not writable"
    assert_contains "$output" 'Cannot create lock directory:' "Permission-boundary failure should not masquerade as a held lock"
    assert_contains "$output" 'The shared topology state is not writable from this session.' "Permission-boundary failure should explain the actual class of problem"
    assert_contains "$output" 'outside the current sandbox or permission boundary' "Permission-boundary failure should point to sandbox-style restrictions"

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_write_doc_requires_dedicated_publish_branch() {
    test_start "git_topology_registry_doctor_write_doc_requires_dedicated_publish_branch"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"
    git_topology_fixture_add_branch "$repo_dir" "010-drift"

    output="$(
        cd "$repo_dir" &&
        set +e &&
        "$REGISTRY_SCRIPT" doctor --prune --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "$rc" "Doctor publish should refuse ordinary branches"
    assert_contains "$output" 'Refusing to publish docs/GIT-TOPOLOGY-REGISTRY.md from main.' "Doctor refusal should report the current branch"
    assert_contains "$output" "Switch to the dedicated non-main topology publish branch 'chore/topology-registry-publish'" "Doctor refusal should point to the exact dedicated branch"

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_write_doc_rejects_ordinary_and_detached_lanes() {
    test_start "git_topology_registry_doctor_write_doc_rejects_ordinary_and_detached_lanes"

    local fixture_root repo_dir branch output rc
    fixture_root="$(mktemp -d /tmp/git-topology-integration.XXXXXX)"
    repo_dir="$(setup_demo_repo "$fixture_root")"

    for branch in "feat/demo-topology" "uat/demo-topology" "chore/topology-registry-publish-demo"; do
        (
            cd "$repo_dir"
            git switch -C "$branch" main >/dev/null
        )
        output="$(
            cd "$repo_dir" &&
            set +e &&
            "$REGISTRY_SCRIPT" doctor --prune --write-doc 2>&1
            printf '\n__RC__=%s\n' "$?"
        )"
        rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
        assert_eq "1" "$rc" "Doctor publish should refuse non-canonical publish branches"
        assert_contains "$output" "Refusing to publish docs/GIT-TOPOLOGY-REGISTRY.md from ${branch}." "Doctor refusal should report the current branch"
        assert_contains "$output" "Switch to the dedicated non-main topology publish branch 'chore/topology-registry-publish'" "Doctor refusal should point to the exact dedicated branch"
    done

    git_topology_fixture_detach_head "$repo_dir" main
    output="$(
        cd "$repo_dir" &&
        set +e &&
        "$REGISTRY_SCRIPT" doctor --prune --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "1" "$rc" "Doctor publish should refuse detached HEAD"
    assert_contains "$output" 'Refusing to publish docs/GIT-TOPOLOGY-REGISTRY.md from detached HEAD.' "Doctor refusal should report detached HEAD explicitly"
    assert_contains "$output" "Switch to the dedicated non-main topology publish branch 'chore/topology-registry-publish'" "Detached HEAD refusal should point to the exact dedicated branch"

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Git Topology Registry Integration Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$REGISTRY_SCRIPT" ]]; then
        test_fail "Registry script missing or not executable: $REGISTRY_SCRIPT"
        generate_report
        return 1
    fi

    test_refresh_writes_sanitized_registry
    test_refresh_is_noop_when_topology_is_unchanged
    test_orphan_intent_and_default_needs_decision_are_rendered
    test_check_is_observer_independent_across_sibling_worktrees
    test_lock_timeout_reports_owner_diagnostics
    test_lock_timeout_without_owner_metadata_reports_actionable_fallback
    test_lock_permission_boundary_reports_non_lock_failure
    test_doctor_write_doc_requires_dedicated_publish_branch
    test_doctor_write_doc_rejects_ordinary_and_detached_lanes

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
