#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STANDALONE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$STANDALONE_ROOT/tests/lib/core.sh"
source "$STANDALONE_ROOT/tests/lib/git_topology_fixture.sh"

WORKTREE_PHASE_A_SCRIPT="$STANDALONE_ROOT/core/scripts/worktree-phase-a.sh"

create_fake_bd_worktree_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "worktree" && "${2:-}" == "create" ]]; then
  if [[ $# -ne 5 || "${4:-}" != "--branch" ]]; then
    printf 'unsupported fake bd worktree create invocation\n' >&2
    exit 1
  fi
  path="$3"
  branch="$5"
  git -C "$PWD" worktree add "$path" "$branch" >/dev/null
  exit 0
fi

printf 'unsupported fake bd invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

run_phase_a_create() {
    local fake_bin="$1"
    shift
    PATH="${fake_bin}:$PATH" "$WORKTREE_PHASE_A_SCRIPT" create-from-base "$@"
}

assert_path_missing() {
    local path="$1"
    local message="$2"
    if [[ -e "$path" ]]; then
        test_fail "$message (unexpected path: $path)"
    fi
}

test_portable_phase_a_create_from_base_anchors_new_branch() {
    test_start "portable_phase_a_create_from_base_anchors_new_branch"

    local fixture_root repo_dir fake_bin target_path base_sha branch_sha worktree_sha output
    fixture_root="$(mktemp -d /tmp/worktree-skill-phase-a.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "portable-skill")"
    fake_bin="$(create_fake_bd_worktree_bin "$fixture_root")"
    target_path="${fixture_root}/portable-skill-clean-start"

    (
        cd "${repo_dir}"
        git switch -c topic/source-line >/dev/null
        printf 'source\n' > source.txt
        git add source.txt
        git commit -m "fixture: source line" >/dev/null
        git switch main >/dev/null
    )

    output="$(run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/clean-start \
        --path "$target_path" \
        --format env)"

    base_sha="$(git -C "$repo_dir" rev-parse main)"
    branch_sha="$(git -C "$repo_dir" rev-parse feat/clean-start)"
    worktree_sha="$(git -C "$target_path" rev-parse HEAD)"

    assert_contains "$output" 'schema=worktree-phase-a/v1' "Portable Phase A should expose env schema"
    assert_contains "$output" 'result=created_from_base' "Portable Phase A should report successful creation"
    assert_eq "$base_sha" "$branch_sha" "Portable branch should be created at canonical base"
    assert_eq "$base_sha" "$worktree_sha" "Portable worktree HEAD should match canonical base"

    rm -rf "$fixture_root"
    test_pass
}

test_portable_phase_a_blocks_existing_branch_on_wrong_base() {
    test_start "portable_phase_a_blocks_existing_branch_on_wrong_base"

    local fixture_root repo_dir fake_bin target_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-skill-phase-a.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "portable-skill")"
    fake_bin="$(create_fake_bd_worktree_bin "$fixture_root")"
    target_path="${fixture_root}/portable-skill-drifted-start"

    (
        cd "${repo_dir}"
        git switch -c feat/drifted >/dev/null
        printf 'drift\n' > drift.txt
        git add drift.txt
        git commit -m "fixture: drifted branch" >/dev/null
        git switch main >/dev/null
    )

    output="$(
        set +e
        run_phase_a_create "$fake_bin" \
            --canonical-root "$repo_dir" \
            --base-ref main \
            --branch feat/drifted \
            --path "$target_path" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Portable Phase A should block drifted branch creation"
    assert_contains "$output" "Existing branch 'feat/drifted' is not aligned to main" "Portable Phase A should explain the base mismatch"
    assert_path_missing "$target_path" "Portable Phase A should not create a worktree when blocked"

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Portable Worktree Phase A Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$WORKTREE_PHASE_A_SCRIPT" ]]; then
        test_fail "Portable Phase A script missing or not executable: $WORKTREE_PHASE_A_SCRIPT"
        generate_report
        return 1
    fi

    test_portable_phase_a_create_from_base_anchors_new_branch
    test_portable_phase_a_blocks_existing_branch_on_wrong_base
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
