#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

INTAKE_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-intake.py"
ARTIFACT_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-artifacts.py"
REVIEW_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-review.py"
INTAKE_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/concept-intake.json"
REWORK_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/defense-feedback.json"
CONCEPT_ID="concept-invoice-approval-factory-demo"

prepare_baseline_pack() {
    local root="$1"
    python3 "$INTAKE_SCRIPT" --source "$INTAKE_FIXTURE" --concept-id "$CONCEPT_ID" --output "$root/intake.json" >/dev/null
    python3 "$ARTIFACT_SCRIPT" generate --input "$root/intake.json" --output-dir "$root/pack" --output "$root/generate.json" >/dev/null
}

write_review_fixture() {
    local filepath="$1"
    local review_id="$2"
    local outcome="$3"
    local next_step_summary="$4"

    cat > "$filepath" <<JSON
{
  "defense_review": {
    "review_id": "$review_id",
    "concept_id": "$CONCEPT_ID",
    "concept_version": "0.1.0",
    "outcome": "$outcome",
    "reviewers": ["factory_board"],
    "feedback_summary": "Решение по защите для сценария $outcome.",
    "decision_notes": "Сценарий $outcome зафиксирован в integration test.",
    "reviewed_at": "2026-03-12T20:40:00Z"
  },
  "feedback_items": [],
  "expected_next_step_summary": "$next_step_summary"
}
JSON
}

run_integration_local_agent_factory_review_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_review_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_review_rework_requested_preserves_history"
    mkdir -p "$tmpdir/rework"
    if prepare_baseline_pack "$tmpdir/rework" \
        && python3 "$REVIEW_SCRIPT" --manifest "$tmpdir/rework/pack/concept-pack.json" --feedback "$REWORK_FIXTURE" --output "$tmpdir/rework/review.json" >/dev/null \
        && python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/rework/review.json" --output-dir "$tmpdir/rework/pack" --output "$tmpdir/rework/regenerate.json" >/dev/null
    then
        assert_eq "review_recorded" "$(jq -r '.status' "$tmpdir/rework/review.json")" "Review status should be recorded"
        assert_eq "regenerate_artifacts" "$(jq -r '.next_action' "$tmpdir/rework/review.json")" "Rework should request artifact regeneration"
        assert_eq "0.2.0" "$(jq -r '.concept_record.current_version' "$tmpdir/rework/review.json")" "Rework should bump concept version"
        assert_eq "0.2.0" "$(jq -r '.concept_version' "$tmpdir/rework/regenerate.json")" "Regenerated manifest should use the bumped concept version"
        assert_eq "blocked" "$(jq -r '.approval_gate.status' "$tmpdir/rework/regenerate.json")" "Rework should keep approval gate blocked"
        assert_eq "1" "$(jq -r '.history | length' "$tmpdir/rework/regenerate.json")" "Previous pack should be archived into history"
        assert_eq "0.1.0" "$(jq -r '.history[0].concept_version' "$tmpdir/rework/regenerate.json")" "History should preserve the reviewed concept version"
        assert_eq "2" "$(jq -r '.current_feedback_items | length' "$tmpdir/rework/regenerate.json")" "Current feedback items should stay attached after rework"
        assert_dir_exists "$(jq -r '.history[0].archive_ref' "$tmpdir/rework/regenerate.json")" "Archived pack directory should exist"
        test_pass
    else
        test_fail "Rework flow should preserve history and regenerate the concept pack"
    fi

    test_start "integration_local_agent_factory_review_approved_unlocks_production_gate"
    mkdir -p "$tmpdir/approved"
    write_review_fixture "$tmpdir/approved/review-input.json" "defense-review-approved-001" "approved" "Запустить production swarm для версии 0.1.0."
    if prepare_baseline_pack "$tmpdir/approved" \
        && python3 "$REVIEW_SCRIPT" --manifest "$tmpdir/approved/pack/concept-pack.json" --feedback "$tmpdir/approved/review-input.json" --output "$tmpdir/approved/review.json" >/dev/null \
        && python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/approved/review.json" --output-dir "$tmpdir/approved/pack" --output "$tmpdir/approved/regenerate.json" >/dev/null
    then
        assert_eq "ready_for_production" "$(jq -r '.next_action' "$tmpdir/approved/review.json")" "Approved review should point to production"
        assert_eq "active" "$(jq -r '.production_approval.status' "$tmpdir/approved/review.json")" "Approved review should create an active approval"
        assert_eq "r2" "$(jq -r '.artifact_revision' "$tmpdir/approved/regenerate.json")" "Same-version review update should bump artifact revision"
        assert_eq "unlocked" "$(jq -r '.approval_gate.status' "$tmpdir/approved/regenerate.json")" "Approved concept should unlock the production gate"
        assert_eq "true" "$(jq -r '.production_ready' "$tmpdir/approved/regenerate.json")" "Approved concept should be marked production-ready"
        assert_eq "0.1.0" "$(jq -r '.production_approval.approved_version' "$tmpdir/approved/regenerate.json")" "Approval should remain tied to the reviewed concept version"
        test_pass
    else
        test_fail "Approved review should unlock the production gate"
    fi

    test_start "integration_local_agent_factory_review_rejected_stays_blocked"
    mkdir -p "$tmpdir/rejected"
    write_review_fixture "$tmpdir/rejected/review-input.json" "defense-review-rejected-001" "rejected" "Остановить инициативу и не запускать production swarm."
    if prepare_baseline_pack "$tmpdir/rejected" \
        && python3 "$REVIEW_SCRIPT" --manifest "$tmpdir/rejected/pack/concept-pack.json" --feedback "$tmpdir/rejected/review-input.json" --output "$tmpdir/rejected/review.json" >/dev/null \
        && python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/rejected/review.json" --output-dir "$tmpdir/rejected/pack" --output "$tmpdir/rejected/regenerate.json" >/dev/null
    then
        assert_eq "concept_rejected" "$(jq -r '.next_action' "$tmpdir/rejected/review.json")" "Rejected review should stop the concept"
        assert_eq "rejected" "$(jq -r '.concept_record.decision_state' "$tmpdir/rejected/review.json")" "Decision state should be rejected"
        assert_eq "null" "$(jq -r '.production_approval' "$tmpdir/rejected/review.json")" "Rejected review must not create approval"
        assert_eq "blocked" "$(jq -r '.approval_gate.status' "$tmpdir/rejected/regenerate.json")" "Rejected concept must remain blocked"
        assert_eq "false" "$(jq -r '.production_ready' "$tmpdir/rejected/regenerate.json")" "Rejected concept must not be production-ready"
        test_pass
    else
        test_fail "Rejected review should keep the concept blocked"
    fi

    test_start "integration_local_agent_factory_review_pending_decision_stays_blocked"
    mkdir -p "$tmpdir/pending"
    write_review_fixture "$tmpdir/pending/review-input.json" "defense-review-pending-001" "pending_decision" "Ожидается итоговое решение по защите."
    if prepare_baseline_pack "$tmpdir/pending" \
        && python3 "$REVIEW_SCRIPT" --manifest "$tmpdir/pending/pack/concept-pack.json" --feedback "$tmpdir/pending/review-input.json" --output "$tmpdir/pending/review.json" >/dev/null \
        && python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/pending/review.json" --output-dir "$tmpdir/pending/pack" --output "$tmpdir/pending/regenerate.json" >/dev/null
    then
        assert_eq "wait_for_decision" "$(jq -r '.next_action' "$tmpdir/pending/review.json")" "Pending decision should wait for explicit resolution"
        assert_eq "pending_decision" "$(jq -r '.concept_record.decision_state' "$tmpdir/pending/review.json")" "Decision state should remain pending_decision"
        assert_eq "blocked" "$(jq -r '.approval_gate.status' "$tmpdir/pending/regenerate.json")" "Pending decision must keep the production gate blocked"
        assert_eq "false" "$(jq -r '.production_ready' "$tmpdir/pending/regenerate.json")" "Pending decision must not be production-ready"
        test_pass
    else
        test_fail "Pending decision should remain blocked"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_review_tests
fi
