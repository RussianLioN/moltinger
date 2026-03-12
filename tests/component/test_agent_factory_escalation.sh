#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

INTAKE_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-intake.py"
ARTIFACT_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-artifacts.py"
REVIEW_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-review.py"
SWARM_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-swarm.py"
INTAKE_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/concept-intake.json"
CONCEPT_ID="concept-invoice-approval-factory-demo"

prepare_approved_pack() {
    local root="$1"

    cat > "$root/approved-review.json" <<JSON
{
  "defense_review": {
    "review_id": "defense-review-approved-us4",
    "concept_id": "$CONCEPT_ID",
    "concept_version": "0.1.0",
    "outcome": "approved",
    "reviewers": ["factory_board"],
    "feedback_summary": "Концепция одобрена для запуска swarm.",
    "decision_notes": "Разрешить запуск production swarm на approved concept version.",
    "reviewed_at": "2026-03-12T22:00:00Z"
  },
  "feedback_items": [],
  "expected_next_step_summary": "Запустить production swarm для approved concept version."
}
JSON

    python3 "$INTAKE_SCRIPT" --source "$INTAKE_FIXTURE" --concept-id "$CONCEPT_ID" --output "$root/intake.json" >/dev/null
    python3 "$ARTIFACT_SCRIPT" generate --input "$root/intake.json" --output-dir "$root/pack" --output "$root/generate.json" >/dev/null
    python3 "$REVIEW_SCRIPT" --manifest "$root/pack/concept-pack.json" --feedback "$root/approved-review.json" --output "$root/review.json" >/dev/null
    python3 "$ARTIFACT_SCRIPT" generate --input "$root/review.json" --output-dir "$root/pack" --output "$root/approved-pack.json" >/dev/null
}

run_component_agent_factory_escalation_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_escalation_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    mkdir -p "$tmpdir/base"
    prepare_approved_pack "$tmpdir/base"

    test_start "component_agent_factory_escalation_publish_status_reports_production_before_swarm"
    if python3 "$ARTIFACT_SCRIPT" publish-status --manifest "$tmpdir/base/pack/concept-pack.json" --output "$tmpdir/production-status.json" >/dev/null
    then
        assert_eq "production" "$(jq -r '.user_visible_status' "$tmpdir/production-status.json")" "Approved concept should publish production status before swarm start"
        assert_eq "0" "$(jq -r '.active_escalation_count' "$tmpdir/production-status.json")" "Approved concept should not report active escalations"
        assert_eq "unlocked" "$(jq -r '.approval_gate_status' "$tmpdir/production-status.json")" "Approval gate should stay unlocked"
        test_pass
    else
        test_fail "Status publication should work for an approved concept pack"
    fi

    test_start "component_agent_factory_escalation_failed_swarm_creates_admin_packet"
    if python3 "$SWARM_SCRIPT" run \
        --manifest "$tmpdir/base/pack/concept-pack.json" \
        --output-dir "$tmpdir/failure-run" \
        --fail-stage validation \
        --failure-summary "Validation drift detected between approved scope and produced prototype." \
        --failure-class "scope_drift" \
        --output "$tmpdir/failure-run.json" >/dev/null 2>&1
    then
        test_fail "Forced stage failure should return a terminal non-zero status"
    else
        assert_eq "needs_admin_attention" "$(jq -r '.status' "$tmpdir/failure-run.json")" "Failure run should request admin attention"
        assert_eq "failed" "$(jq -r '.swarm_run.run_status' "$tmpdir/failure-run.json")" "Swarm run should fail on forced blocker"
        assert_eq "validation" "$(jq -r '.swarm_run.current_stage' "$tmpdir/failure-run.json")" "Current stage should point to the blocker stage"
        assert_eq "1" "$(jq -r '.escalation_packets | length' "$tmpdir/failure-run.json")" "One escalation packet should be created"
        assert_eq "validation" "$(jq -r '.escalation_packets[0].stage_name' "$tmpdir/failure-run.json")" "Escalation should point to the failed stage"
        assert_eq "open" "$(jq -r '.escalation_packets[0].status' "$tmpdir/failure-run.json")" "Escalation should remain open for admin review"
        assert_file_exists "$(jq -r '.escalation_packets[0].packet_ref' "$tmpdir/failure-run.json")" "Escalation packet file should exist"
        assert_file_exists "$(jq -r '.evidence_bundle.archive_ref' "$tmpdir/failure-run.json")" "Failure evidence bundle should exist"
        assert_contains "$(jq -r '[.audit_trail[].event_type] | join(",")' "$tmpdir/failure-run.json")" "stage_failed" "Audit trail should record the failed stage"
        assert_contains "$(jq -r '[.audit_trail[].event_type] | join(",")' "$tmpdir/failure-run.json")" "escalation_created" "Audit trail should record escalation creation"
        python3 - <<'PY' "$(jq -r '.evidence_bundle.archive_ref' "$tmpdir/failure-run.json")"
import sys, zipfile
archive = sys.argv[1]
with zipfile.ZipFile(archive) as fh:
    names = fh.namelist()
    assert "bundle-manifest.json" in names
PY
        python3 "$ARTIFACT_SCRIPT" publish-status \
            --manifest "$tmpdir/base/pack/concept-pack.json" \
            --swarm-run "$tmpdir/failure-run/swarm-run.json" \
            --output "$tmpdir/failure-status.json" >/dev/null
        assert_eq "needs_admin_attention" "$(jq -r '.user_visible_status' "$tmpdir/failure-status.json")" "Published status should expose admin attention state"
        assert_eq "validation" "$(jq -r '.current_stage' "$tmpdir/failure-status.json")" "Published status should expose the failed stage"
        assert_eq "1" "$(jq -r '.active_escalation_count' "$tmpdir/failure-status.json")" "Published status should expose one active escalation"
        test_pass
    fi

    test_start "component_agent_factory_escalation_happy_path_stays_silent"
    if python3 "$SWARM_SCRIPT" run --manifest "$tmpdir/base/pack/concept-pack.json" --output-dir "$tmpdir/happy-run" --output "$tmpdir/happy-run.json" >/dev/null \
        && python3 "$ARTIFACT_SCRIPT" publish-status --manifest "$tmpdir/base/pack/concept-pack.json" --swarm-run "$tmpdir/happy-run/swarm-run.json" --output "$tmpdir/happy-status.json" >/dev/null
    then
        assert_eq "0" "$(jq -r '.escalation_packets | length' "$tmpdir/happy-run.json")" "Happy path should not create escalation packets"
        assert_eq "playground_ready" "$(jq -r '.user_visible_status' "$tmpdir/happy-status.json")" "Published status should expose playground_ready after success"
        assert_eq "0" "$(jq -r '.active_escalation_count' "$tmpdir/happy-status.json")" "Happy path should stay silent for escalations"
        test_pass
    else
        test_fail "Happy-path swarm run should complete without escalation"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_escalation_tests
fi
