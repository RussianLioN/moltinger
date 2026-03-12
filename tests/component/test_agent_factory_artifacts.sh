#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

INTAKE_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-intake.py"
ARTIFACT_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-artifacts.py"
FIXTURE_FILE="$PROJECT_ROOT/tests/fixtures/agent-factory/concept-intake.json"

run_component_agent_factory_artifacts_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_artifacts_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_artifacts_generate_synchronized_pack"
    if python3 "$INTAKE_SCRIPT" --source "$FIXTURE_FILE" --output "$tmpdir/intake.json" >/dev/null \
        && python3 "$ARTIFACT_SCRIPT" generate --input "$tmpdir/intake.json" --output-dir "$tmpdir/pack" --output "$tmpdir/generate.json" >/dev/null
    then
        assert_file_exists "$tmpdir/pack/concept-pack.json" "Concept pack manifest should exist"
        assert_file_exists "$tmpdir/pack/working/project-doc.md" "Working project doc should exist"
        assert_file_exists "$tmpdir/pack/working/agent-spec.md" "Working agent spec should exist"
        assert_file_exists "$tmpdir/pack/working/presentation.md" "Working presentation should exist"
        assert_file_exists "$tmpdir/pack/downloads/project-doc.md" "Download project doc should exist"
        assert_file_exists "$tmpdir/pack/downloads/agent-spec.md" "Download agent spec should exist"
        assert_file_exists "$tmpdir/pack/downloads/presentation.md" "Download presentation should exist"
        assert_eq "generated" "$(jq -r '.status' "$tmpdir/generate.json")" "Generation status should be generated"
        assert_eq "aligned" "$(jq -r '.sync_status' "$tmpdir/generate.json")" "Generation should start aligned"
        assert_eq "3" "$(jq -r '.artifacts | length' "$tmpdir/generate.json")" "Manifest should contain three artifacts"
        test_pass
    else
        test_fail "Concept pack generation should succeed for the fixture intake"
    fi

    test_start "component_agent_factory_artifacts_alignment_check_passes_for_fresh_outputs"
    if python3 "$ARTIFACT_SCRIPT" check-alignment --manifest "$tmpdir/pack/concept-pack.json" --output "$tmpdir/alignment-ok.json" >/dev/null
    then
        assert_eq "aligned" "$(jq -r '.status' "$tmpdir/alignment-ok.json")" "Fresh concept pack should be aligned"
        test_pass
    else
        test_fail "Alignment check should pass for fresh outputs"
    fi

    test_start "component_agent_factory_artifacts_alignment_detects_manual_drift"
    printf '\nDRIFT DETECTED\n' >> "$tmpdir/pack/downloads/project-doc.md"
    if python3 "$ARTIFACT_SCRIPT" check-alignment --manifest "$tmpdir/pack/concept-pack.json" --output "$tmpdir/alignment-drift.json" >/dev/null 2>&1
    then
        test_fail "Alignment check should fail after download artifact drift"
    else
        assert_eq "drift_detected" "$(jq -r '.status' "$tmpdir/alignment-drift.json")" "Drift report should mark drift_detected"
        assert_contains "$(jq -r '.issues | join(" | ")' "$tmpdir/alignment-drift.json")" "diverged" "Drift report should explain the divergence"
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_artifacts_tests
fi
