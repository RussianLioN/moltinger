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

create_fake_gh_bin() {
    local fixture_root="$1"
    local fake_bin="$fixture_root/bin"

    mkdir -p "$fake_bin"
    cat > "$fake_bin/gh" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_GH_LOG}"

if [[ "${1:-}" == "workflow" && "${2:-}" == "run" ]]; then
    echo "workflow dispatched"
    exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
    chmod +x "$fake_bin/gh"

    printf '%s\n' "$fake_bin"
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

assert_publish_refusal() {
    local output="$1"
    local rc="$2"
    local branch_display="$3"

    assert_eq "1" "$rc" "Publish should refuse non-canonical publish lanes"
    assert_contains "$output" "Refusing to publish docs/GIT-TOPOLOGY-REGISTRY.md from ${branch_display}." "Publish refusal should report the current branch"
    assert_contains "$output" "Switch to the dedicated non-main topology publish branch 'chore/topology-registry-publish'" "Publish refusal should point to the exact dedicated branch"
}

test_registry_refresh_requires_dedicated_publish_branch() {
    test_start "git_topology_registry_refresh_requires_dedicated_publish_branch"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/git-topology-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"

    output="$(
        cd "$repo_dir" &&
        set +e &&
        "$REGISTRY_SCRIPT" refresh --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "$rc" "Refresh publish should refuse ordinary branches"
    assert_contains "$output" 'Refusing to publish docs/GIT-TOPOLOGY-REGISTRY.md from main.' "Refresh refusal should report the current branch"
    assert_contains "$output" 'Canonical main is not an allowed topology publish lane.' "Refresh refusal should explain why main is rejected"
    assert_contains "$output" "Switch to the dedicated non-main topology publish branch 'chore/topology-registry-publish'" "Refresh refusal should point to the exact dedicated branch"

    rm -rf "$fixture_root"
    test_pass
}

test_registry_refresh_rejects_ordinary_and_alias_branches() {
    test_start "git_topology_registry_refresh_rejects_ordinary_and_alias_branches"

    local fixture_root repo_dir branch output rc
    fixture_root="$(mktemp -d /tmp/git-topology-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"

    for branch in "feat/demo-topology" "uat/demo-topology" "chore/topology-registry-publish-demo"; do
        (
            cd "$repo_dir"
            git switch -C "$branch" main >/dev/null
        )
        output="$(
            cd "$repo_dir" &&
            set +e &&
            "$REGISTRY_SCRIPT" refresh --write-doc 2>&1
            printf '\n__RC__=%s\n' "$?"
        )"
        rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"
        assert_publish_refusal "$output" "$rc" "$branch"
    done

    rm -rf "$fixture_root"
    test_pass
}

test_registry_refresh_rejects_detached_head() {
    test_start "git_topology_registry_refresh_rejects_detached_head"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/git-topology-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"
    git_topology_fixture_detach_head "$repo_dir" main

    output="$(
        cd "$repo_dir" &&
        set +e &&
        "$REGISTRY_SCRIPT" refresh --write-doc 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_publish_refusal "$output" "$rc" "detached HEAD"

    rm -rf "$fixture_root"
    test_pass
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

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"
    first_hash="$(hash_file "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"
    doc="$(cat "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"

    git_topology_fixture_refresh_registry_from_publish_branch "$repo_dir" "$REGISTRY_SCRIPT"
    second_hash="$(hash_file "$repo_dir/docs/GIT-TOPOLOGY-REGISTRY.md")"

    assert_eq "$first_hash" "$second_hash" "Repeated refresh should render identical registry content"
    assert_contains "$doc" '**Scope**: Shared remote governance snapshot' "Registry should render the shared remote-governance scope"
    assert_contains "$doc" '`origin/007-demo-feature`' "Registry should include unmerged remote branch row"
    assert_not_contains_literal "$doc" '## Current Worktrees' "Tracked registry should no longer publish local worktree inventory"
    assert_not_contains_literal "$doc" '## Active Local Branches' "Tracked registry should no longer publish local branch inventory"
    assert_not_contains_literal "$doc" 'Demo feature worktree.' "Tracked registry should keep worktree-only intent out of the shared snapshot"

    if [[ "$doc" == *"$fixture_root"* ]] || [[ "$doc" == *"$repo_dir"* ]] || [[ "$doc" == *"$worktree_path"* ]]; then
        test_fail "Registry leaked absolute fixture paths"
        rm -rf "$fixture_root"
        return 1
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_registry_publish_dispatches_workflow() {
    test_start "git_topology_registry_publish_dispatches_workflow"

    local fixture_root repo_dir fake_bin gh_log output
    fixture_root="$(mktemp -d /tmp/git-topology-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"
    fake_bin="$(create_fake_gh_bin "$fixture_root")"
    gh_log="$fixture_root/gh.log"
    : > "$gh_log"

    output="$(
        cd "$repo_dir" &&
        PATH="$fake_bin:$PATH" \
        FAKE_GH_LOG="$gh_log" \
        "$REGISTRY_SCRIPT" publish 2>&1
    )"

    assert_contains "$output" 'Publish workflow dispatched.' "Publish wrapper should confirm workflow dispatch"
    assert_contains "$output" 'Workflow: topology-registry-publish.yml' "Publish wrapper should report the workflow file"
    assert_contains "$output" 'Ref: main' "Publish wrapper should report the dispatch ref"
    assert_contains "$output" 'workflow dispatched' "Publish wrapper should surface gh workflow output"
    assert_eq 'workflow run topology-registry-publish.yml --ref main' "$(tail -1 "$gh_log")" "Publish wrapper should dispatch the expected workflow and ref"

    rm -rf "$fixture_root"
    test_pass
}

test_registry_publish_requires_gh() {
    test_start "git_topology_registry_publish_requires_gh"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/git-topology-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_repo "$fixture_root")"
    mkdir -p "$repo_dir/docs"
    write_demo_intent "$repo_dir"

    output="$(
        cd "$repo_dir" &&
        set +e &&
        GIT_TOPOLOGY_REGISTRY_GH_BIN="gh-missing-for-test" "$REGISTRY_SCRIPT" publish 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "$rc" "Publish should fail closed when gh is unavailable"
    assert_contains "$output" "Cannot dispatch publish workflow because 'gh-missing-for-test' is unavailable." "Publish should name the missing binary"
    assert_contains "$output" "dispatch workflow 'topology-registry-publish.yml' manually from the Actions UI." "Publish should point to the manual workflow fallback"

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

    test_registry_refresh_requires_dedicated_publish_branch
    test_registry_refresh_rejects_ordinary_and_alias_branches
    test_registry_refresh_rejects_detached_head
    test_registry_refresh_is_deterministic_and_sanitized
    test_registry_publish_dispatches_workflow
    test_registry_publish_requires_gh
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
