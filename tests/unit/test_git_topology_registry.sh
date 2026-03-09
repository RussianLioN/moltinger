#!/bin/bash
# Unit tests for git topology registry discovery and deterministic rendering.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

REGISTRY_SCRIPT="$PROJECT_ROOT/scripts/git-topology-registry.sh"

hash_file() {
    local target="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print $1}'
    else
        shasum -a 256 "$target" | awk '{print $1}'
    fi
}

write_demo_intent() {
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

test_registry_refresh_is_deterministic_and_sanitized() {
    test_start "git_topology_registry_refresh_is_deterministic_and_sanitized"

    local fixture_root repo_dir worktree_path first_hash second_hash doc
    fixture_root="$(mktemp -d /tmp/git-topology-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    git_topology_fixture_add_branch "$repo_dir" "007-demo-feature"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"
    worktree_path="$fixture_root/repo-007-worktree"
    git_topology_fixture_add_worktree "$repo_dir" "$worktree_path" "007-demo-feature"

    (
        cd "$repo_dir"
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
    )
    first_hash="$(hash_file "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"

    (
        cd "$repo_dir"
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
    )
    second_hash="$(hash_file "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"

    assert_eq "$first_hash" "$second_hash" "Repeated refresh should render identical registry content"
    assert_contains "$doc" '`primary-feature-007`' "Registry should include generated worktree row"
    assert_contains "$doc" 'Demo feature worktree.' "Legacy feature-worktree intent should normalize onto the canonical row"
    assert_contains "$doc" '`origin/007-demo-feature`' "Registry should include unmerged remote branch row"

    if [[ "$doc" == *"$fixture_root"* ]] || [[ "$doc" == *"$repo_dir"* ]] || [[ "$doc" == *"$worktree_path"* ]]; then
        test_fail "Registry leaked absolute fixture paths"
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
        echo "  Git Topology Registry Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$REGISTRY_SCRIPT" ]]; then
        test_fail "Registry script missing or not executable: $REGISTRY_SCRIPT"
        generate_report
        return 1
    fi

    test_registry_refresh_is_deterministic_and_sanitized
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
