#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

RECOVER_SCRIPT="$PROJECT_ROOT/scripts/beads-recover-issue.sh"

bootstrap_local_beads_db() {
    local worktree_dir="$1"

    (
        cd "$worktree_dir"
        BEADS_DB="$worktree_dir/.beads/beads.db" bd --no-daemon list >/dev/null 2>&1
    )
}

test_recover_issue_dry_run_keeps_target_clean() {
    test_start "beads_recover_issue_dry_run_keeps_target_clean"

    local fixture_root repo_dir worktree_dir source_jsonl output
    fixture_root="$(mktemp -d /tmp/beads-recover-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_dir="${fixture_root}/moltinger-safe-owner"
    source_jsonl="${fixture_root}/source.jsonl"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"demo-1","title":"seed"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track beads state" >/dev/null
        git branch feat/demo-owner >/dev/null
        git worktree add "${worktree_dir}" feat/demo-owner >/dev/null
    )

    bootstrap_local_beads_db "${worktree_dir}"
    printf '{"id":"demo-ejy","title":"recovered issue","status":"in_progress","priority":2,"issue_type":"bug"}\n' > "${source_jsonl}"

    output="$("$RECOVER_SCRIPT" --issue demo-ejy --source-jsonl "${source_jsonl}" --target-worktree "${worktree_dir}")"

    assert_contains "$output" 'Result: ready_to_apply' "Dry-run recovery should report that the issue is ready to import"
    if rg -q '"id":"demo-ejy"' "${worktree_dir}/.beads/issues.jsonl"; then
        test_fail "Dry-run recovery must not modify the target issues.jsonl"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

test_recover_issue_apply_imports_into_target_worktree() {
    test_start "beads_recover_issue_apply_imports_into_target_worktree"

    local fixture_root repo_dir worktree_dir source_jsonl output
    fixture_root="$(mktemp -d /tmp/beads-recover-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_dir="${fixture_root}/moltinger-safe-owner"
    source_jsonl="${fixture_root}/source.jsonl"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"demo-1","title":"seed"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track beads state" >/dev/null
        git branch feat/demo-owner >/dev/null
        git worktree add "${worktree_dir}" feat/demo-owner >/dev/null
    )

    bootstrap_local_beads_db "${worktree_dir}"
    printf '{"id":"demo-ejy","title":"recovered issue","status":"in_progress","priority":2,"issue_type":"bug"}\n' > "${source_jsonl}"

    output="$("$RECOVER_SCRIPT" --issue demo-ejy --source-jsonl "${source_jsonl}" --target-worktree "${worktree_dir}" --apply)"

    assert_contains "$output" 'Result: imported' "Apply recovery should report a successful import"
    if ! rg -q '"id":"demo-ejy"' "${worktree_dir}/.beads/issues.jsonl"; then
        test_fail "Apply recovery must import the issue into the target issues.jsonl"
    fi
    if ! (cd "${worktree_dir}" && bd --no-daemon --db "${worktree_dir}/.beads/beads.db" show demo-ejy >/dev/null 2>&1); then
        test_fail "Apply recovery must import the issue into the target local DB"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Beads Recover Issue Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$RECOVER_SCRIPT" ]]; then
        test_fail "Recover script missing or not executable: $RECOVER_SCRIPT"
        generate_report
        return 1
    fi

    test_recover_issue_dry_run_keeps_target_clean
    test_recover_issue_apply_imports_into_target_worktree
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
