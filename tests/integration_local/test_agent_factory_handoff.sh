#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"
INTAKE_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-intake.py"
ARTIFACT_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-artifacts.py"
BRIEF_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/brief-awaiting-confirmation.json"

run_integration_local_agent_factory_handoff_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_handoff_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_handoff_bridges_confirmed_discovery_into_concept_pack"
    if jq '. + {
      "confirmation_reply": {
        "confirmed": true,
        "confirmation_text": "Да, это верное описание требований для первого прототипа.",
        "confirmed_by": "demo-business-user"
      }
    }' "$BRIEF_FIXTURE" >"$tmpdir/confirmation-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/confirmation-source.json" --output "$tmpdir/confirmed-brief.json" >/dev/null &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/confirmed-brief.json" --output "$tmpdir/handoff-ready.json" >/dev/null &&
        python3 "$INTAKE_SCRIPT" --source "$tmpdir/handoff-ready.json" --output "$tmpdir/intake.json" >/dev/null &&
        python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/intake.json" --output-dir "$tmpdir/pack" --output "$tmpdir/generate.json" >/dev/null &&
        python3 "$ARTIFACT_SCRIPT" check-alignment --manifest "$tmpdir/pack/concept-pack.json" --output "$tmpdir/alignment.json" >/dev/null; then
        assert_eq "ready" "$(jq -r '.factory_handoff_record.handoff_status' "$tmpdir/handoff-ready.json")" "Discovery replay should produce a ready handoff"
        assert_eq "ready_for_pack" "$(jq -r '.status' "$tmpdir/intake.json")" "Ready handoff should bridge into a ready-for-pack intake payload"
        assert_eq "aligned" "$(jq -r '.status' "$tmpdir/alignment.json")" "Concept pack generated from discovery handoff should stay aligned"
        assert_file_exists "$tmpdir/pack/downloads/project-doc.md" "Project doc should be generated from the bridged handoff payload"
        assert_eq "$(jq -r '.factory_handoff_record.factory_handoff_id' "$tmpdir/handoff-ready.json")" "$(jq -r '.source_provenance.factory_handoff_id' "$tmpdir/pack/concept-pack.json")" "Manifest should preserve exact handoff provenance"
        assert_eq "$(jq -r '.requirement_brief.version' "$tmpdir/handoff-ready.json")" "$(jq -r '.source_provenance.brief_version' "$tmpdir/pack/concept-pack.json")" "Manifest should keep the confirmed brief version"
        assert_eq "$(jq -r '.source_provenance.factory_handoff_id' "$tmpdir/pack/concept-pack.json")" "$(jq -r '.artifacts.project_doc.generated_from.factory_handoff_id' "$tmpdir/pack/concept-pack.json")" "Per-artifact metadata should keep the same upstream handoff provenance"
        assert_eq "$(jq -r '.source_provenance.confirmation_snapshot_id' "$tmpdir/pack/concept-pack.json")" "$(jq -r '.artifacts.agent_spec.generated_from.confirmation_snapshot_id' "$tmpdir/pack/concept-pack.json")" "Per-artifact metadata should keep confirmation snapshot linkage"
        test_pass
    else
        test_fail "Confirmed discovery should bridge into the existing concept-pack pipeline without manual copy-paste"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_handoff_tests
fi
