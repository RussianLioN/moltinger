#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"
INTAKE_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-intake.py"
BRIEF_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/brief-awaiting-confirmation.json"

run_component_agent_factory_handoff_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_handoff_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_handoff_generates_ready_record_only_after_confirmed_brief_is_replayed"
    if jq '. + {
      "confirmation_reply": {
        "confirmed": true,
        "confirmation_text": "Да, это верное описание требований для первого прототипа.",
        "confirmed_by": "demo-business-user"
      }
    }' "$BRIEF_FIXTURE" >"$tmpdir/confirmation-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/confirmation-source.json" --output "$tmpdir/confirmed-brief.json" >/dev/null &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/confirmed-brief.json" --output "$tmpdir/handoff-ready.json" >/dev/null; then
        assert_eq "false" "$(jq -r 'has("factory_handoff_record")' "$tmpdir/confirmed-brief.json")" "Initial confirmation should still stop before live handoff generation"
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/handoff-ready.json")" "Replay of a confirmed brief should keep the brief status confirmed"
        assert_eq "run_factory_intake" "$(jq -r '.next_action' "$tmpdir/handoff-ready.json")" "Ready handoff should point to the downstream intake bridge"
        assert_eq "ready" "$(jq -r '.factory_handoff_record.handoff_status' "$tmpdir/handoff-ready.json")" "Confirmed replay should emit a ready handoff record"
        assert_eq "specs/020-agent-factory-prototype" "$(jq -r '.factory_handoff_record.downstream_target' "$tmpdir/handoff-ready.json")" "Handoff should target the existing concept-pack pipeline"
        assert_eq "1.0" "$(jq -r '.factory_handoff_record.brief_version' "$tmpdir/handoff-ready.json")" "Handoff must bind to the exact confirmed brief version"
        test_pass
    else
        test_fail "Discovery runtime should generate one canonical ready handoff from a confirmed brief replay"
    fi

    test_start "component_agent_factory_handoff_bridge_maps_provenance_into_intake"
    if python3 "$INTAKE_SCRIPT" --source "$tmpdir/handoff-ready.json" --output "$tmpdir/intake-from-handoff.json" >/dev/null; then
        assert_eq "ready_for_pack" "$(jq -r '.status' "$tmpdir/intake-from-handoff.json")" "Ready handoff should bridge into a ready-for-pack concept request"
        assert_eq "confirmed_discovery_handoff" "$(jq -r '.concept_request.source_kind' "$tmpdir/intake-from-handoff.json")" "Intake should preserve discovery handoff source kind"
        assert_eq "$(jq -r '.factory_handoff_record.factory_handoff_id' "$tmpdir/handoff-ready.json")" "$(jq -r '.concept_record.source_request_id' "$tmpdir/intake-from-handoff.json")" "Concept record should keep the exact upstream handoff id"
        assert_eq "$(jq -r '.confirmation_snapshot.confirmed_by' "$tmpdir/handoff-ready.json")" "$(jq -r '.concept_record.confirmed_by' "$tmpdir/intake-from-handoff.json")" "Confirmed-by provenance should survive the bridge"
        assert_eq "$(jq -r '.requirement_brief.version' "$tmpdir/handoff-ready.json")" "$(jq -r '.concept_record.brief_version' "$tmpdir/intake-from-handoff.json")" "Concept record should keep the exact confirmed brief version"
        test_pass
    else
        test_fail "Intake bridge should consume a ready discovery handoff and emit downstream concept-pack input"
    fi

    test_start "component_agent_factory_handoff_blocks_downstream_before_ready_record_exists"
    if python3 "$INTAKE_SCRIPT" --source "$tmpdir/confirmed-brief.json" --output "$tmpdir/blocked-intake.json" >/dev/null; then
        assert_eq "blocked" "$(jq -r '.status' "$tmpdir/blocked-intake.json")" "Confirmed brief without ready handoff should stay blocked"
        assert_eq "return_to_discovery_handoff" "$(jq -r '.next_action' "$tmpdir/blocked-intake.json")" "Blocked bridge should send the caller back to the handoff stage"
        assert_contains "$(jq -r '.block_reason' "$tmpdir/blocked-intake.json")" "Factory handoff record не готов" "Block reason should explain the missing ready handoff"
        test_pass
    else
        test_fail "Intake bridge should block discovery payloads that have not produced a ready handoff record yet"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_handoff_tests
fi
