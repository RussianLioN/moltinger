#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

AUTH_CHECK_SCRIPT="$PROJECT_ROOT/scripts/clawdiy-auth-check.sh"
RUNTIME_CONFIG="$PROJECT_ROOT/config/clawdiy/openclaw.json"
GOOD_PROFILE='{"provider":"openai-codex","auth_type":"oauth","granted_scopes":["api.responses.write"],"allowed_models":["gpt-5.4"]}'
BAD_SCOPE_PROFILE='{"provider":"openai-codex","auth_type":"oauth","granted_scopes":["profile.read"],"allowed_models":["gpt-5.4"]}'

run_auth_check() {
    local provider="$1"
    local env_file="$2"
    local output_file="$3"
    shift 3

    set +e
    "$@" "$AUTH_CHECK_SCRIPT" --provider "$provider" --env-file "$env_file" --json >"$output_file"
    local exit_code=$?
    set -e
    return "$exit_code"
}

write_env_file() {
    local path="$1"
    local telegram_token="$2"
    local profile="$3"

    {
        printf '%s\n' 'CLAWDIY_PASSWORD=test-human-password'
        printf '%s\n' 'CLAWDIY_SERVICE_TOKEN=test-service-token'
        if [[ -n "$telegram_token" ]]; then
            printf 'CLAWDIY_TELEGRAM_BOT_TOKEN=%s\n' "$telegram_token"
        fi
        printf '%s\n' 'CLAWDIY_TELEGRAM_ALLOWED_USERS=user42,user99'
        if [[ -n "$profile" ]]; then
            printf 'CLAWDIY_OPENAI_CODEX_AUTH_PROFILE=%s\n' "$profile"
        fi
    } >"$path"
}

run_clawdiy_auth_boundary_tests() {
    start_timer

    test_start "security_api_clawdiy_auth_check_script_exists"
    if [[ -f "$AUTH_CHECK_SCRIPT" ]] && bash -n "$AUTH_CHECK_SCRIPT"; then
        test_pass
    else
        test_fail "scripts/clawdiy-auth-check.sh must exist and parse cleanly"
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    local pass_env="$tmpdir/pass.env"
    local missing_telegram_env="$tmpdir/missing-telegram.env"
    local bad_scope_env="$tmpdir/bad-scope.env"
    local bad_runtime_config="$tmpdir/openclaw-reused-service.json"

    write_env_file "$pass_env" "test-clawdiy-telegram-token" "$GOOD_PROFILE"
    write_env_file "$missing_telegram_env" "" "$GOOD_PROFILE"
    write_env_file "$bad_scope_env" "test-clawdiy-telegram-token" "$BAD_SCOPE_PROFILE"
    sed 's/github-secret:CLAWDIY_SERVICE_TOKEN/github-secret:MOLTINGER_SERVICE_TOKEN/' "$RUNTIME_CONFIG" >"$bad_runtime_config"

    test_start "security_api_clawdiy_valid_auth_profile_passes"
    if run_auth_check openai-codex "$pass_env" "$tmpdir/pass.json" env; then
        if jq -e '.status == "pass" and any(.capabilities[]; .capability == "openai-codex" and .status == "pass")' "$tmpdir/pass.json" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Valid Clawdiy provider auth profile should produce a passing capability result"
        fi
    else
        test_fail "Valid Clawdiy provider auth profile should pass auth-check"
    fi

    test_start "security_api_clawdiy_missing_telegram_token_fails_closed"
    if run_auth_check telegram "$missing_telegram_env" "$tmpdir/missing-telegram.json" env; then
        test_fail "Missing Telegram token must fail closed"
    elif jq -e '.status == "fail" and ([.errors[] | test("repeat-auth"; "i")] | any)' "$tmpdir/missing-telegram.json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Missing Telegram token should emit explicit repeat-auth guidance"
    fi

    test_start "security_api_clawdiy_bad_provider_scope_fails_closed"
    if run_auth_check openai-codex "$bad_scope_env" "$tmpdir/bad-scope.json" env; then
        test_fail "Bad provider scope must fail closed"
    elif jq -e '.status == "fail" and ([.errors[] | test("quarantined|quarantine|repeat-auth"; "i")] | any)' "$tmpdir/bad-scope.json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Bad provider scope should quarantine the capability with repeat-auth guidance"
    fi

    test_start "security_api_clawdiy_cross_agent_secret_reuse_rejected"
    if run_auth_check telegram "$pass_env" "$tmpdir/reused-service.json" env CLAWDIY_CONFIG_FILE="$bad_runtime_config"; then
        test_fail "Cross-agent service secret reuse must be rejected"
    elif jq -e '.status == "fail" and ([.errors[] | test("isolated|Moltinger"; "i")] | any)' "$tmpdir/reused-service.json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Cross-agent secret reuse should surface an isolation error"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_clawdiy_auth_boundary_tests
fi
