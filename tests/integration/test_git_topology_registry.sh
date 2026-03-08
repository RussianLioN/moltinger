#!/bin/bash
# Integration tests for git topology registry refresh/check behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/test_helpers.sh"
source "$LIB_DIR/git_topology_fixture.sh"

REGISTRY_SCRIPT="$PROJECT_ROOT/scripts/git-topology-registry.sh"

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

    (
        cd "$repo_dir"
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
        "$REGISTRY_SCRIPT" check >/dev/null
    )

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" 'Generated artifact from live git topology' "Registry should be rendered by generator"
    assert_contains "$doc" 'Demo feature branch.' "Registry should merge reviewed branch intent"
    assert_contains "$doc" '`primary-feature-007`' "Registry should canonicalize numeric feature worktree identifiers"
    assert_contains "$doc" 'Demo feature worktree.' "Canonical feature row should preserve legacy reviewed note"

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
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
        git add docs/GIT-TOPOLOGY-REGISTRY.md docs/GIT-TOPOLOGY-INTENT.yaml
        git commit -m "fixture: add generated registry" >/dev/null
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
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

    (
        cd "$repo_dir"
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
    )

    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    assert_contains "$doc" '## Reviewed Intent Awaiting Reconciliation' "Registry should surface orphan reviewed intent"
    assert_contains "$doc" '099-retired-feature' "Registry should list orphan subject key"
    assert_contains "$doc" 'Preserve this reviewed note until the sidecar is pruned.' "Registry should preserve orphan reviewed note"
    assert_contains "$doc" '| `008-unreviewed` | `none` | Needs decision |' "Unreviewed local branch should fall back to needs-decision"
    if [[ "$doc" == *"parallel-feature-007"* ]]; then
        test_fail "Legacy numeric feature alias should not render as a separate orphan record"
        rm -rf "$fixture_root"
        return 1
    fi

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

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
