#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

REGISTRY_FILE="$PROJECT_ROOT/config/fleet/agents-registry.json"
POLICY_FILE="$PROJECT_ROOT/config/fleet/policy.json"
CLAWDIY_CONFIG_FILE="$PROJECT_ROOT/config/clawdiy/openclaw.json"
SMOKE_OUTPUT="$(secure_temp_file clawdiy-extraction-smoke)"

run_integration_local_clawdiy_extraction_readiness_tests() {
    start_timer

    require_commands_or_skip bash jq || {
        test_start "integration_local_clawdiy_extraction_readiness_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "integration_local_clawdiy_extraction_readiness_inputs"
    if [[ -f "$REGISTRY_FILE" && -f "$POLICY_FILE" && -f "$CLAWDIY_CONFIG_FILE" ]]; then
        test_pass
    else
        test_fail "Registry, policy, and Clawdiy runtime config must exist"
    fi

    test_start "integration_local_clawdiy_extraction_readiness_smoke"
    if "$PROJECT_ROOT/scripts/clawdiy-smoke.sh" --json --stage extraction-readiness >"$SMOKE_OUTPUT"; then
        if jq -e '
            .status == "pass"
            and any(.checks[]; .name == "extraction_topology_profiles" and .status == "pass")
            and any(.checks[]; .name == "extraction_runtime_alignment" and .status == "pass")
            and any(.checks[]; .name == "extraction_handoff_invariants" and .status == "pass")
            and any(.checks[]; .name == "extraction_policy_contract" and .status == "pass")
          ' "$SMOKE_OUTPUT" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Extraction-readiness smoke must pass all topology and policy contract checks"
        fi
    else
        test_fail "Extraction-readiness smoke command failed"
    fi

    test_start "integration_local_clawdiy_extraction_future_roles"
    if jq -e --slurpfile policy "$POLICY_FILE" '
        [.future_role_examples[].role] as $roles
        | ($roles | index("architect")) != null
        and ($roles | index("tester")) != null
        and ($roles | index("researcher")) != null
        and all($policy[0].future_role_defaults[]; (.supported_topology_profiles | index("same_host")) != null and (.supported_topology_profiles | index("remote_node")) != null and .transport == "http-json")
      ' "$REGISTRY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Future permanent-role examples must stay aligned between registry and policy"
    fi

    test_start "integration_local_clawdiy_extraction_logical_address"
    if jq -e '
        .agents[] | select(.agent_id == "clawdiy")
        | .logical_address == "agent://clawdiy"
      ' "$REGISTRY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Clawdiy logical address must stay stable between registry and runtime config"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_clawdiy_extraction_readiness_tests
fi
