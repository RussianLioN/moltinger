#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

INTAKE_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-intake.py"
ARTIFACT_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-artifacts.py"
FIXTURE_FILE="$PROJECT_ROOT/tests/fixtures/agent-factory/concept-intake.json"

run_integration_local_agent_factory_intake_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_intake_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_intake_ready_for_pack_with_complete_fixture"
    if python3 "$INTAKE_SCRIPT" --source "$FIXTURE_FILE" --output "$tmpdir/intake.json" >/dev/null
    then
        assert_eq "ready_for_pack" "$(jq -r '.status' "$tmpdir/intake.json")" "Fixture intake should be ready_for_pack"
        assert_eq "generate_artifacts" "$(jq -r '.next_action' "$tmpdir/intake.json")" "Ready intake should point to artifact generation"
        assert_eq "telegram" "$(jq -r '.concept_request.request_channel' "$tmpdir/intake.json")" "Request channel should remain telegram"
        assert_eq "draft" "$(jq -r '.concept_record.decision_state' "$tmpdir/intake.json")" "New concept should start in draft"
        assert_eq "4" "$(jq -r '.concept_record.applied_factory_patterns | length' "$tmpdir/intake.json" 2>/dev/null || true)" "Factory patterns should be seeded from the baseline"
        assert_gt "$(jq -r '.concept_record.success_metrics | length' "$tmpdir/intake.json")" "0" "Success metrics should be captured"
        test_pass
    else
        test_fail "Complete fixture intake should succeed"
    fi

    test_start "integration_local_agent_factory_intake_generates_downloadable_concept_pack"
    if python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/intake.json" --output-dir "$tmpdir/pack" --output "$tmpdir/generate.json" >/dev/null
    then
        assert_eq "telegram" "$(jq -r '.delivery_channel' "$tmpdir/generate.json")" "Concept pack should target Telegram delivery"
        assert_file_exists "$tmpdir/pack/downloads/one-page-summary.md" "One-page summary download should exist"
        assert_file_exists "$tmpdir/pack/downloads/project-doc.md" "Project doc download should exist"
        assert_file_exists "$tmpdir/pack/downloads/agent-spec.md" "Agent spec download should exist"
        assert_file_exists "$tmpdir/pack/downloads/presentation.md" "Presentation download should exist"
        test_pass
    else
        test_fail "Artifact generation should succeed from intake output"
    fi

    test_start "integration_local_agent_factory_intake_enters_clarifying_when_critical_fields_missing"
    cat > "$tmpdir/incomplete.json" <<'JSON'
{
  "concept_request_id": "concept-request-incomplete-001",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "262872984",
    "display_name": "Сергей"
  },
  "request_language": "ru",
  "raw_problem_statement": "Нужен агент для автоматизации согласования счетов.",
  "captured_answers": {
    "target_business_problem": "",
    "target_users": [],
    "current_workflow_summary": "",
    "constraints_or_exclusions": [],
    "measurable_success_expectation": []
  }
}
JSON
    if python3 "$INTAKE_SCRIPT" --source "$tmpdir/incomplete.json" --output "$tmpdir/incomplete-out.json" >/dev/null
    then
        assert_eq "clarifying" "$(jq -r '.status' "$tmpdir/incomplete-out.json")" "Incomplete intake should remain in clarifying state"
        assert_gt "$(jq -r '.follow_up_questions | length' "$tmpdir/incomplete-out.json")" "0" "Clarifying state should return follow-up questions"
        assert_eq "ask_followup_questions" "$(jq -r '.next_action' "$tmpdir/incomplete-out.json")" "Clarifying intake should request follow-up questions"
        test_pass
    else
        test_fail "Incomplete intake should still return a structured clarifying response"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_intake_tests
fi
