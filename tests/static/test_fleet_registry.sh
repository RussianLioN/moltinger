#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

REGISTRY_FILE="$PROJECT_ROOT/config/fleet/agents-registry.json"
POLICY_FILE="$PROJECT_ROOT/config/fleet/policy.json"
CLAWDIY_CONFIG_FILE="$PROJECT_ROOT/config/clawdiy/openclaw.json"

run_fleet_registry_tests() {
    start_timer

    test_start "fleet_registry_file_exists"
    if [[ -f "$REGISTRY_FILE" ]]; then
        test_pass
    else
        test_fail "Missing config/fleet/agents-registry.json"
    fi

    test_start "fleet_policy_file_exists"
    if [[ -f "$POLICY_FILE" ]]; then
        test_pass
    else
        test_fail "Missing config/fleet/policy.json"
    fi

    test_start "fleet_registry_valid_json"
    if jq -e '.schema_version == "v1" and (.agents | type == "array" and length >= 2)' "$REGISTRY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet registry JSON is invalid or missing required top-level structure"
    fi

    test_start "fleet_policy_valid_json"
    if jq -e '.schema_version == "v1" and (.routes | type == "array" and length >= 2)' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy JSON is invalid or missing required top-level structure"
    fi

    test_start "fleet_registry_contains_moltinger_and_clawdiy"
    if jq -e '
        [.agents[].agent_id] as $ids
        | ($ids | index("moltinger")) != null
        and ($ids | index("clawdiy")) != null
      ' "$REGISTRY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet registry must contain canonical moltinger and clawdiy agent ids"
    fi

    test_start "fleet_registry_identities_are_unique"
    if jq -e '
        def normweb:
            tostring
            | sub("^https?://"; "")
            | sub("/+$"; "")
            | split("/")[0]
            | ascii_downcase;
        def normtg:
            tostring | ascii_downcase;
        .agents as $agents
        | (($agents | map(.agent_id) | length) == ($agents | map(.agent_id) | unique | length))
        and (([$agents[] | .public_endpoints.web? | select(type == "string" and length > 0) | normweb] | length) == ([$agents[] | .public_endpoints.web? | select(type == "string" and length > 0) | normweb] | unique | length))
        and (([$agents[] | .public_endpoints.telegram? | select(type == "string" and length > 0) | normtg] | length) == ([$agents[] | .public_endpoints.telegram? | select(type == "string" and length > 0) | normtg] | unique | length))
      ' "$REGISTRY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet registry contains duplicate agent_id, web, or Telegram identities"
    fi

    test_start "fleet_registry_clawdiy_matches_runtime_config"
    if jq -e --slurpfile runtime "$CLAWDIY_CONFIG_FILE" '
        ($runtime[0]) as $rt
        | .agents[] | select(.agent_id == "clawdiy")
        | (.internal_endpoint == $rt.identity.internal_endpoint)
        and (.public_endpoints.web == $rt.server.base_url)
        and (.public_endpoints.telegram == $rt.identity.telegram_bot)
      ' "$REGISTRY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Clawdiy registry entry must match runtime config endpoint, web URL, and Telegram identity"
    fi

    test_start "fleet_policy_defaults_fail_closed"
    if jq -e '
        .defaults.allow_unknown_agents == false
        and .defaults.allow_unknown_capabilities == false
        and .defaults.allow_public_machine_handoffs == false
        and .defaults.fail_closed_on_auth_error == true
        and .service_auth.mode == "bearer"
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy must remain fail-closed with bearer service auth"
    fi

    test_start "fleet_policy_routes_cover_bidirectional_handoff"
    if jq -e '
        any(.routes[]; .caller == "moltinger" and .recipient == "clawdiy" and .transport == "http-json")
        and any(.routes[]; .caller == "clawdiy" and .recipient == "moltinger" and .transport == "http-json")
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy must define moltinger<->clawdiy HTTP JSON routes"
    fi

    test_start "fleet_policy_capabilities_align_with_registry"
    if jq -e --slurpfile registry "$REGISTRY_FILE" '
        ($registry[0].agents | map({key: .agent_id, value: .capabilities}) | from_entries) as $capabilities
        | all(.routes[]; . as $route | all($route.capabilities[]; ($capabilities[$route.recipient] // []) | index(.) != null))
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy route capabilities must be declared by the recipient registry entry"
    fi

    test_start "fleet_service_auth_refs_are_distinct"
    if jq -e '
        .secret_refs.moltinger_service_auth != .secret_refs.clawdiy_service_auth
        and (.secret_refs.moltinger_service_auth | startswith("github-secret:"))
        and (.secret_refs.clawdiy_service_auth | startswith("github-secret:"))
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy service auth refs must be distinct GitHub secret refs"
    fi

    test_start "fleet_telegram_auth_boundary_isolated"
    if jq -e '
        .telegram_auth.clawdiy.mode == "polling"
        and .telegram_auth.clawdiy.fail_closed_on_token_error == true
        and .telegram_auth.clawdiy.secret_ref == .secret_refs.clawdiy_telegram_auth
        and .telegram_auth.clawdiy.allowlist_secret_ref == .secret_refs.clawdiy_telegram_allowlist
        and .secret_refs.clawdiy_telegram_auth != .secret_refs.moltinger_telegram_auth
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy must keep Clawdiy Telegram auth isolated and fail-closed"
    fi

    test_start "fleet_provider_auth_gate_defined"
    if jq -e '
        .provider_auth.clawdiy["openai-codex"].secret_ref == .secret_refs.clawdiy_openai_codex_auth_profile
        and .provider_auth.clawdiy["openai-codex"].profile_format == "json"
        and .provider_auth.clawdiy["openai-codex"].auth_type == "oauth"
        and (.provider_auth.clawdiy["openai-codex"].required_scopes | index("api.responses.write") != null)
        and (.provider_auth.clawdiy["openai-codex"].allowed_models | index("gpt-5.4") != null)
        and .provider_auth.clawdiy["openai-codex"].fail_closed_on_scope_error == true
      ' "$POLICY_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy must define the fail-closed openai-codex rollout gate for Clawdiy"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_fleet_registry_tests
fi
