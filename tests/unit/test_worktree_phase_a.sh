#!/bin/bash
# Unit tests for deterministic Phase A worktree creation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

WORKTREE_PHASE_A_SCRIPT="$PROJECT_ROOT/scripts/worktree-phase-a.sh"

create_fake_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--no-daemon" ]]; then
  shift
fi

if [[ "${1:-}" == "--db" ]]; then
  db_path="${2:-}"
  shift 2
  if [[ "${1:-}" == "info" ]]; then
    mkdir -p "$(dirname "${db_path}")"
    : > "${db_path}"
    exit 0
  fi
fi

if [[ "${1:-}" == "list" ]]; then
  if [[ -n "${BEADS_DB:-}" ]]; then
    mkdir -p "$(dirname "${BEADS_DB}")"
    : > "${BEADS_DB}"
  fi
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

assert_file_missing() {
    local path="$1"
    local message="$2"
    if [[ -e "$path" ]]; then
        test_fail "$message (unexpected path: $path)"
    fi
}

test_phase_a_create_from_base_anchors_new_branch_to_main() {
    test_start "worktree_phase_a_create_from_base_anchors_new_branch_to_main"

    local fixture_root repo_dir fake_bin target_path base_sha branch_sha worktree_sha output
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-clean-start"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track beads state" >/dev/null
    )

    (
        cd "${repo_dir}"
        git switch -c uat/source-line >/dev/null
        printf 'source\n' > source.txt
        git add source.txt
        git commit -m "fixture: source line" >/dev/null
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

    assert_contains "$output" 'schema=worktree-phase-a/v1' "Phase A create should expose its env schema"
    assert_contains "$output" 'result=created_from_base' "Phase A create should report successful base-anchored creation"
    assert_eq "$base_sha" "$branch_sha" "New branch should be created exactly at canonical main"
    assert_eq "$base_sha" "$worktree_sha" "New worktree HEAD should match canonical main"
    assert_file_missing "${target_path}/.beads/redirect" "Phase A create should not leave redirect metadata in the new worktree"
    if [[ ! -f "${target_path}/.beads/beads.db" ]]; then
        test_fail "Phase A create should bootstrap a local beads.db in the new worktree"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_blocks_existing_branch_on_wrong_base() {
    test_start "worktree_phase_a_create_blocks_existing_branch_on_wrong_base"

    local fixture_root repo_dir fake_bin target_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-drifted-start"

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

    assert_eq "23" "$rc" "Existing drifted branch should block Phase A create"
    assert_contains "$output" "Existing branch 'feat/drifted' is not aligned to main" "Blocked Phase A should explain the base mismatch"
    assert_file_missing "$target_path" "Blocked Phase A should not create a worktree"

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Worktree Phase A Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$WORKTREE_PHASE_A_SCRIPT" ]]; then
        test_fail "Worktree Phase A script missing or not executable: $WORKTREE_PHASE_A_SCRIPT"
        generate_report
        return 1
    fi

    test_phase_a_create_from_base_anchors_new_branch_to_main
    test_phase_a_create_blocks_existing_branch_on_wrong_base
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
