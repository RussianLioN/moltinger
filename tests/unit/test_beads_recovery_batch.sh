#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

BATCH_SCRIPT="$PROJECT_ROOT/scripts/beads-recovery-batch.sh"

bootstrap_local_beads_db() {
    local worktree_dir="$1"

    (
        cd "$worktree_dir"
        BEADS_DB="$worktree_dir/.beads/beads.db" bd --no-daemon list >/dev/null 2>&1
    )
}

seed_repo_beads_state() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"demo-1","title":"seed"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track beads state" >/dev/null
    )
}

create_owner_worktree() {
    local repo_dir="$1"
    local branch_name="$2"
    local worktree_dir="$3"

    (
        cd "${repo_dir}"
        git branch "${branch_name}" >/dev/null
        git worktree add "${worktree_dir}" "${branch_name}" >/dev/null
    )
}

test_batch_audit_reports_safe_and_blocked_candidates() {
    test_start "beads_recovery_batch_audit_reports_safe_and_blocked_candidates"

    local fixture_root repo_dir worktree_dir source_jsonl ownership_map plan_path
    local safe_count blocked_count requires_localization missing_blocker plan_schema source_state
    fixture_root="$(mktemp -d /tmp/beads-recovery-batch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_dir="${fixture_root}/moltinger-demo-ejy-owner"
    source_jsonl="${fixture_root}/source.jsonl"
    ownership_map="${fixture_root}/ownership.json"
    plan_path="${fixture_root}/plan.json"

    seed_repo_beads_state "${repo_dir}"
    create_owner_worktree "${repo_dir}" "feat/demo-ejy-owner" "${worktree_dir}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_dir}/.beads/redirect"

    (
        cd "${repo_dir}"
        git branch "feat/demo-missing-owner" >/dev/null
    )

    cat > "${source_jsonl}" <<'EOF'
{"id":"demo-ejy","title":"recoverable"}
{"id":"demo-miss","title":"missing worktree"}
EOF

    cat > "${ownership_map}" <<'EOF'
{"version":1,"entries":[{"issue_id":"demo-miss","branch":"feat/demo-missing-owner","reason":"fixture missing worktree"}]}
EOF

    (
        cd "${repo_dir}"
        "$BATCH_SCRIPT" audit \
            --output "${plan_path}" \
            --source-jsonl "${source_jsonl}" \
            --ownership-map "${ownership_map}" >/dev/null
    )

    safe_count="$(jq -r '.safe_count' "${plan_path}")"
    blocked_count="$(jq -r '.blocked_count' "${plan_path}")"
    requires_localization="$(jq -r '.candidates[] | select(.issue_id == "demo-ejy") | .requires_localization' "${plan_path}")"
    missing_blocker="$(jq -r '.candidates[] | select(.issue_id == "demo-miss") | .blockers[0]' "${plan_path}")"
    plan_schema="$(jq -r '.schema' "${plan_path}")"
    source_state="$(jq -r '.candidates[] | select(.issue_id == "demo-ejy") | .validation_contract.source_issue.state' "${plan_path}")"

    assert_eq "1" "${safe_count}" "Audit should report one safe candidate"
    assert_eq "1" "${blocked_count}" "Audit should report one blocked candidate"
    assert_eq "true" "${requires_localization}" "Audit should mark redirected owner worktrees for localization"
    assert_eq "missing_worktree" "${missing_blocker}" "Audit should block candidates whose owner branch has no attached worktree"
    assert_eq "beads-recovery-plan/v2" "${plan_schema}" "Audit should emit the candidate-scoped plan schema"
    assert_eq "present" "${source_state}" "Audit should persist source issue validation state for safe candidates"

    rm -rf "${fixture_root}"
    test_pass
}

test_batch_apply_localizes_and_recovers_safe_candidates() {
    test_start "beads_recovery_batch_apply_localizes_and_recovers_safe_candidates"

    local fixture_root repo_dir worktree_dir source_jsonl plan_path journal_root journal_path backup_path
    fixture_root="$(mktemp -d /tmp/beads-recovery-batch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_dir="${fixture_root}/moltinger-demo-ejy-owner"
    source_jsonl="${fixture_root}/source.jsonl"
    plan_path="${fixture_root}/plan.json"
    journal_root="${fixture_root}/journals"

    seed_repo_beads_state "${repo_dir}"
    create_owner_worktree "${repo_dir}" "feat/demo-ejy-owner" "${worktree_dir}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_dir}/.beads/redirect"

    cat > "${source_jsonl}" <<'EOF'
{"id":"demo-ejy","title":"recoverable","status":"in_progress","priority":2,"issue_type":"bug"}
EOF

    (
        cd "${repo_dir}"
        "$BATCH_SCRIPT" audit \
            --output "${plan_path}" \
            --source-jsonl "${source_jsonl}" >/dev/null
        "$BATCH_SCRIPT" apply \
            --plan "${plan_path}" \
            --journal-dir "${journal_root}" >/dev/null
    )

    if [[ -f "${worktree_dir}/.beads/redirect" ]]; then
        test_fail "Apply should localize redirected worktrees before recovery"
    fi
    if ! rg -q '"id":"demo-ejy"' "${worktree_dir}/.beads/issues.jsonl"; then
        test_fail "Apply should recover the leaked issue into the target worktree"
    fi

    journal_path="$(find "${journal_root}" -name journal.json | head -1)"
    backup_path="$(find "${journal_root}" -name issues.jsonl.bak | head -1)"

    if [[ -z "${journal_path}" || ! -f "${journal_path}" ]]; then
        test_fail "Apply should create one journal artifact"
    fi
    if [[ -z "${backup_path}" || ! -f "${backup_path}" ]]; then
        test_fail "Apply should create a backup before mutating the target worktree"
    fi
    if [[ "$(jq -r '.actions[0].result' "${journal_path}")" != "imported" ]]; then
        test_fail "Apply journal should record a successful import"
    fi
    if ! rg -q '"id":"demo-ejy"' "${source_jsonl}"; then
        test_fail "Apply must not delete the issue from the source snapshot"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

test_batch_apply_allows_unrelated_topology_drift() {
    test_start "beads_recovery_batch_apply_allows_unrelated_topology_drift"

    local fixture_root repo_dir worktree_dir source_jsonl plan_path journal_root output rc journal_path
    fixture_root="$(mktemp -d /tmp/beads-recovery-batch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_dir="${fixture_root}/moltinger-demo-ejy-owner"
    source_jsonl="${fixture_root}/source.jsonl"
    plan_path="${fixture_root}/plan.json"
    journal_root="${fixture_root}/journals"

    seed_repo_beads_state "${repo_dir}"
    create_owner_worktree "${repo_dir}" "feat/demo-ejy-owner" "${worktree_dir}"

    cat > "${source_jsonl}" <<'EOF'
{"id":"demo-ejy","title":"recoverable","status":"in_progress","priority":2,"issue_type":"bug"}
EOF

    (
        cd "${repo_dir}"
        "$BATCH_SCRIPT" audit \
            --output "${plan_path}" \
            --source-jsonl "${source_jsonl}" >/dev/null
        git branch "feat/demo-drift" >/dev/null
        git worktree add "${fixture_root}/moltinger-demo-drift" "feat/demo-drift" >/dev/null
    )

    output="$(
        set +e
        cd "${repo_dir}"
        "$BATCH_SCRIPT" apply --plan "${plan_path}" --journal-dir "${journal_root}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${rc}" "Apply should tolerate unrelated topology drift under plan v2"
    if ! rg -q '"id":"demo-ejy"' "${worktree_dir}/.beads/issues.jsonl"; then
        test_fail "Apply should still recover the safe candidate when unrelated worktrees changed"
    fi
    journal_path="$(find "${journal_root}" -name journal.json | head -1)"
    assert_eq "true" "$(jq -r '.topology_drift_detected' "${journal_path}")" "Journal should record advisory topology drift"

    rm -rf "${fixture_root}"
    test_pass
}

test_batch_apply_blocks_candidate_worktree_change() {
    test_start "beads_recovery_batch_apply_blocks_candidate_worktree_change"

    local fixture_root repo_dir worktree_dir moved_worktree source_jsonl plan_path output rc
    fixture_root="$(mktemp -d /tmp/beads-recovery-batch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_dir="${fixture_root}/moltinger-demo-ejy-owner"
    moved_worktree="${fixture_root}/moltinger-demo-ejy-owner-moved"
    source_jsonl="${fixture_root}/source.jsonl"
    plan_path="${fixture_root}/plan.json"

    seed_repo_beads_state "${repo_dir}"
    create_owner_worktree "${repo_dir}" "feat/demo-ejy-owner" "${worktree_dir}"

    cat > "${source_jsonl}" <<'EOF'
{"id":"demo-ejy","title":"recoverable","status":"in_progress","priority":2,"issue_type":"bug"}
EOF

    (
        cd "${repo_dir}"
        "$BATCH_SCRIPT" audit \
            --output "${plan_path}" \
            --source-jsonl "${source_jsonl}" >/dev/null
        git worktree remove "${worktree_dir}" --force >/dev/null
        git worktree add "${moved_worktree}" "feat/demo-ejy-owner" >/dev/null
    )

    output="$(
        set +e
        cd "${repo_dir}"
        "$BATCH_SCRIPT" apply --plan "${plan_path}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "4" "${rc}" "Apply should fail closed when the planned owner worktree path changed"
    assert_contains "${output}" "Canonical Root Cleanup: still blocked" "Apply should record the blocked candidate in the summary"
    if rg -q '"id":"demo-ejy"' "${moved_worktree}/.beads/issues.jsonl"; then
        test_fail "Apply must not recover into a moved owner worktree from a stale contract"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Beads Recovery Batch Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$BATCH_SCRIPT" ]]; then
        test_fail "Batch recovery script missing or not executable: $BATCH_SCRIPT"
        generate_report
        return 1
    fi

    test_batch_audit_reports_safe_and_blocked_candidates
    test_batch_apply_localizes_and_recovers_safe_candidates
    test_batch_apply_allows_unrelated_topology_drift
    test_batch_apply_blocks_candidate_worktree_change
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
