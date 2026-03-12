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
    "review_id": "defense-review-approved-us3",
    "concept_id": "$CONCEPT_ID",
    "concept_version": "0.1.0",
    "outcome": "approved",
    "reviewers": ["factory_board"],
    "feedback_summary": "Концепция одобрена для запуска swarm.",
    "decision_notes": "Разрешить запуск production swarm на approved concept version.",
    "reviewed_at": "2026-03-12T21:00:00Z"
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

run_integration_local_agent_factory_swarm_tests() {
    start_timer
    require_commands_or_skip python3 jq tar || {
        test_start "integration_local_agent_factory_swarm_prereqs"
        test_skip "python3, jq, and tar are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_swarm_runs_approved_concept_to_playground"
    mkdir -p "$tmpdir/swarm"
    if prepare_approved_pack "$tmpdir/swarm" \
        && python3 "$SWARM_SCRIPT" run --manifest "$tmpdir/swarm/pack/concept-pack.json" --output-dir "$tmpdir/swarm/run" --output "$tmpdir/swarm/swarm-output.json" >/dev/null
    then
        assert_eq "completed" "$(jq -r '.status' "$tmpdir/swarm/swarm-output.json")" "Swarm output status should be completed"
        assert_eq "completed" "$(jq -r '.swarm_run.run_status' "$tmpdir/swarm/swarm-output.json")" "Swarm run should complete"
        assert_eq "5" "$(jq -r '.stage_executions | length' "$tmpdir/swarm/swarm-output.json")" "All five swarm stages should execute"
        assert_eq "coding,testing,validation,audit,assembly" "$(jq -r '[.stage_executions[].stage_name] | join(",")' "$tmpdir/swarm/swarm-output.json")" "Stages should remain ordered and traceable"
        assert_eq "ready_for_demo" "$(jq -r '.playground_package.review_status' "$tmpdir/swarm/swarm-output.json")" "Playground package should be ready for demo"
        assert_eq "synthetic" "$(jq -r '.playground_package.data_profile' "$tmpdir/swarm/swarm-output.json")" "Playground must stay synthetic"
        assert_file_exists "$(jq -r '.playground_package.bundle_archive_ref' "$tmpdir/swarm/swarm-output.json")" "Playground archive should exist"
        assert_file_exists "$(jq -r '.evidence_bundle.archive_ref' "$tmpdir/swarm/swarm-output.json")" "Evidence bundle archive should exist"
        assert_file_exists "$tmpdir/swarm/run/swarm-run.json" "Swarm manifest should exist"
        test_pass
    else
        test_fail "Approved concept should complete the prototype swarm and produce a playground bundle"
    fi

    test_start "integration_local_agent_factory_swarm_evidence_bundle_is_readable"
    if tar -tzf "$(jq -r '.playground_package.bundle_archive_ref' "$tmpdir/swarm/swarm-output.json")" >/dev/null 2>&1 \
        && python3 - <<'PY' "$(jq -r '.evidence_bundle.archive_ref' "$tmpdir/swarm/swarm-output.json")"
import sys, zipfile
archive = sys.argv[1]
with zipfile.ZipFile(archive) as fh:
    names = fh.namelist()
    assert "bundle-manifest.json" in names
PY
    then
        assert_contains "$(jq -r '.stage_executions[0].evidence_refs[0]' "$tmpdir/swarm/swarm-output.json")" "artifacts/coding/output-summary.md" "Coding stage should publish output summary"
        test_pass
    else
        test_fail "Playground archive and evidence bundle should be readable"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_swarm_tests
fi
