#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STANDALONE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$STANDALONE_ROOT/tests/lib/core.sh"
source "$STANDALONE_ROOT/tests/lib/git_topology_fixture.sh"

REGISTRY_SCRIPT="$STANDALONE_ROOT/core/scripts/git-topology-registry.sh"

hash_file() {
    local target="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$target" | awk '{print $1}'
    else
        shasum -a 256 "$target" | awk '{print $1}'
    fi
}

write_custom_intent() {
    local intent_path="$1"
    mkdir -p "$(dirname "$intent_path")"
    cat > "$intent_path" <<'EOF'
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

test_portable_registry_respects_custom_doc_and_intent_paths() {
    test_start "portable_registry_respects_custom_doc_and_intent_paths"

    local fixture_root repo_dir worktree_path custom_doc custom_intent first_hash second_hash doc
    fixture_root="$(mktemp -d /tmp/worktree-skill-topology.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    git_topology_fixture_add_branch "$repo_dir" "007-demo-feature"
    worktree_path="$fixture_root/repo-007-worktree"
    git_topology_fixture_add_worktree "$repo_dir" "$worktree_path" "007-demo-feature"

    custom_doc="docs/custom/topology.md"
    custom_intent="docs/custom/intent.yaml"
    write_custom_intent "$repo_dir/$custom_intent"

    (
        cd "$repo_dir"
        WORKTREE_SKILL_TOPOLOGY_DOC="$custom_doc" \
        WORKTREE_SKILL_TOPOLOGY_INTENT="$custom_intent" \
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
    )
    first_hash="$(hash_file "$repo_dir/$custom_doc")"
    doc="$(cat "$repo_dir/$custom_doc")"

    (
        cd "$repo_dir"
        WORKTREE_SKILL_TOPOLOGY_DOC="$custom_doc" \
        WORKTREE_SKILL_TOPOLOGY_INTENT="$custom_intent" \
        "$REGISTRY_SCRIPT" refresh --write-doc >/dev/null
    )
    second_hash="$(hash_file "$repo_dir/$custom_doc")"

    assert_eq "$first_hash" "$second_hash" "Portable registry should render deterministically with custom paths"
    assert_contains "$doc" '`primary-feature-007`' "Portable registry should include canonical feature worktree row"
    assert_contains "$doc" 'Demo feature worktree.' "Portable registry should preserve reviewed worktree note"
    assert_contains "$doc" '`origin/007-demo-feature`' "Portable registry should include the remote feature row"

    if [[ -e "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md" ]]; then
        test_fail "Portable registry should not write the default topology doc when custom path is configured"
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
        echo "  Portable Topology Registry Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$REGISTRY_SCRIPT" ]]; then
        test_fail "Portable registry script missing or not executable: $REGISTRY_SCRIPT"
        generate_report
        return 1
    fi

    test_portable_registry_respects_custom_doc_and_intent_paths
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
