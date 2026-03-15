#!/usr/bin/env bash
# Validate Clawdiy auth boundaries and repeat-auth readiness.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="${SECRETS_DIR:-$PROJECT_ROOT/secrets}"
CLAWDIY_CONFIG_FILE="${CLAWDIY_CONFIG_FILE:-$PROJECT_ROOT/config/clawdiy/openclaw.json}"
FLEET_POLICY_FILE="${FLEET_POLICY_FILE:-$PROJECT_ROOT/config/fleet/policy.json}"
ENV_FILE="${ENV_FILE:-}"
PROVIDER="${PROVIDER:-all}"
OUTPUT_JSON=false
STRICT_MODE=false
NO_COLOR=false

declare -a CHECKS=()
declare -a ERRORS=()
declare -a WARNINGS=()
declare -a CAPABILITIES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GATEWAY_AUTH_MODE=""
TELEGRAM_ENABLED=""
TELEGRAM_DM_POLICY=""
TELEGRAM_ALLOW_FROM_COUNT="0"
PROVIDER_SECRET_REF=""
PROVIDER_PROFILE_FORMAT=""
PROVIDER_AUTH_TYPE=""
PROVIDER_ROLLOUT_GATE=""
PROVIDER_ENABLED=""
POLICY_CLAWDIY_HUMAN_REF=""
POLICY_CLAWDIY_SERVICE_REF=""
POLICY_CLAWDIY_TELEGRAM_REF=""
POLICY_CLAWDIY_ALLOWLIST_REF=""
POLICY_CLAWDIY_PROVIDER_REF=""
POLICY_MOLTINGER_SERVICE_REF=""
POLICY_MOLTINGER_TELEGRAM_REF=""

disable_colors() {
    if [[ "$NO_COLOR" == "true" || "$OUTPUT_JSON" == "true" || ! -t 1 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        NC=''
    fi
}

log() {
    local level="$1"
    shift
    local message="$*"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        return
    fi

    case "$level" in
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; WARNINGS+=("$1"); }
log_error() { log ERROR "$@"; ERRORS+=("$1"); }
log_success() { log SUCCESS "$@"; }

add_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    local severity="${4:-error}"

    CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"message\":\"$message\",\"severity\":\"$severity\"}")

    case "$status" in
        pass) log_success "$message" ;;
        warning) log_warn "$message" ;;
        fail)
            if [[ "$severity" == "warning" ]]; then
                log_warn "$message"
            else
                log_error "$message"
            fi
            ;;
    esac
}

add_capability_result() {
    local capability="$1"
    local status="$2"
    local next_action="$3"
    CAPABILITIES+=("{\"capability\":\"$capability\",\"status\":\"$status\",\"next_action\":\"$next_action\"}")
}

timestamp_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

to_secret_file_stem() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

secret_ref_name() {
    local ref="$1"
    printf '%s' "${ref#github-secret:}"
}

read_env_file() {
    local file_path="$1"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" != *=* ]]; then
            continue
        fi

        local key="${line%%=*}"
        local value="${line#*=}"
        key="$(printf '%s' "$key" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

        export "$key=$value"
    done <"$file_path"
}

lookup_secret_value() {
    local name="$1"
    local stem
    stem="$(to_secret_file_stem "$name")"
    local lowercase_file="$SECRETS_DIR/${stem}.txt"
    local exact_file="$SECRETS_DIR/${name}.txt"

    if [[ -n "${!name:-}" ]]; then
        printf '%s' "${!name}"
        return 0
    fi

    if [[ -f "$exact_file" ]]; then
        cat "$exact_file"
        return 0
    fi

    if [[ -f "$lowercase_file" ]]; then
        cat "$lowercase_file"
        return 0
    fi

    return 1
}

is_clawdiy_telegram_shadow() {
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${CLAWDIY_TELEGRAM_BOT_TOKEN:-}" && "${TELEGRAM_BOT_TOKEN}" == "${CLAWDIY_TELEGRAM_BOT_TOKEN}" ]]
}

require_commands() {
    local missing=()
    local cmd
    for cmd in jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        add_check "dependencies" "fail" "Missing required commands: ${missing[*]}" "error"
        return 1
    fi

    add_check "dependencies" "pass" "Required commands available: jq" "error"
    return 0
}

parse_runtime_config() {
    local rendered_runtime_config="$PROJECT_ROOT/data/clawdiy/runtime/openclaw.json"
    if [[ -f "$rendered_runtime_config" ]]; then
        CLAWDIY_CONFIG_FILE="$rendered_runtime_config"
    fi

    if [[ ! -f "$CLAWDIY_CONFIG_FILE" ]]; then
        add_check "runtime_config_exists" "fail" "Clawdiy runtime config is missing: $CLAWDIY_CONFIG_FILE" "error"
        return 1
    fi

    if ! jq empty "$CLAWDIY_CONFIG_FILE" >/dev/null 2>&1; then
        add_check "runtime_config_valid" "fail" "Clawdiy runtime config is not valid JSON: $CLAWDIY_CONFIG_FILE" "error"
        return 1
    fi

    if ! jq -e '
        .gateway.mode == "local"
        and .gateway.auth.mode == "token"
        and .gateway.auth.token.source == "env"
        and .gateway.auth.token.provider == "default"
        and .gateway.auth.token.id == "OPENCLAW_GATEWAY_TOKEN"
        and (.channels.telegram.enabled == true)
        and (.channels.telegram.dmPolicy == "allowlist")
        and (.channels.telegram.allowFrom | type == "array")
        and .channels.telegram.botToken.source == "env"
        and .channels.telegram.botToken.provider == "default"
        and .channels.telegram.botToken.id == "TELEGRAM_BOT_TOKEN"
    ' "$CLAWDIY_CONFIG_FILE" >/dev/null 2>&1; then
        add_check "runtime_auth_shape" "fail" "Clawdiy runtime config is missing required official gateway or Telegram auth fields" "error"
        return 1
    fi

    GATEWAY_AUTH_MODE="$(jq -r '.gateway.auth.mode' "$CLAWDIY_CONFIG_FILE")"
    TELEGRAM_ENABLED="$(jq -r '.channels.telegram.enabled' "$CLAWDIY_CONFIG_FILE")"
    TELEGRAM_DM_POLICY="$(jq -r '.channels.telegram.dmPolicy' "$CLAWDIY_CONFIG_FILE")"
    TELEGRAM_ALLOW_FROM_COUNT="$(jq -r '.channels.telegram.allowFrom | length' "$CLAWDIY_CONFIG_FILE")"

    add_check "runtime_auth_shape" "pass" "Clawdiy runtime auth boundary fields parsed successfully" "error"
    return 0
}

parse_policy_config() {
    if [[ ! -f "$FLEET_POLICY_FILE" ]]; then
        add_check "policy_exists" "fail" "Fleet policy is missing: $FLEET_POLICY_FILE" "error"
        return 1
    fi

    if ! jq empty "$FLEET_POLICY_FILE" >/dev/null 2>&1; then
        add_check "policy_valid" "fail" "Fleet policy is not valid JSON: $FLEET_POLICY_FILE" "error"
        return 1
    fi

    if ! jq -e '
        .defaults.fail_closed_on_auth_error == true
        and .service_auth.mode == "bearer"
        and .service_auth.authorization_header == "Authorization"
        and (.secret_refs.clawdiy_human_auth | type == "string" and length > 0)
        and (.secret_refs.clawdiy_service_auth | type == "string" and length > 0)
        and (.secret_refs.clawdiy_telegram_auth | type == "string" and length > 0)
        and (.secret_refs.clawdiy_telegram_allowlist | type == "string" and length > 0)
        and (.secret_refs.clawdiy_openai_codex_auth_profile | type == "string" and length > 0)
        and (.telegram_auth.clawdiy.secret_ref == .secret_refs.clawdiy_telegram_auth)
        and (.telegram_auth.clawdiy.allowlist_secret_ref == .secret_refs.clawdiy_telegram_allowlist)
        and (.telegram_auth.clawdiy.mode == "polling")
        and (.telegram_auth.clawdiy.fail_closed_on_token_error == true)
        and (.provider_auth.clawdiy["codex-oauth"].secret_ref == .secret_refs.clawdiy_openai_codex_auth_profile)
        and (.provider_auth.clawdiy["codex-oauth"].auth_type == "oauth")
        and (.provider_auth.clawdiy["codex-oauth"].profile_format == "json")
        and (.provider_auth.clawdiy["codex-oauth"].required_scopes | index("api.responses.write") != null)
        and (.provider_auth.clawdiy["codex-oauth"].allowed_models | index("gpt-5.4") != null)
        and (.provider_auth.clawdiy["codex-oauth"].fail_closed_on_scope_error == true)
    ' "$FLEET_POLICY_FILE" >/dev/null 2>&1; then
        add_check "policy_auth_shape" "fail" "Fleet policy is missing fail-closed service, Telegram, or provider auth metadata for Clawdiy" "error"
        return 1
    fi

    POLICY_CLAWDIY_HUMAN_REF="$(jq -r '.secret_refs.clawdiy_human_auth' "$FLEET_POLICY_FILE")"
    POLICY_CLAWDIY_SERVICE_REF="$(jq -r '.secret_refs.clawdiy_service_auth' "$FLEET_POLICY_FILE")"
    POLICY_CLAWDIY_TELEGRAM_REF="$(jq -r '.secret_refs.clawdiy_telegram_auth' "$FLEET_POLICY_FILE")"
    POLICY_CLAWDIY_ALLOWLIST_REF="$(jq -r '.secret_refs.clawdiy_telegram_allowlist' "$FLEET_POLICY_FILE")"
    POLICY_CLAWDIY_PROVIDER_REF="$(jq -r '.secret_refs.clawdiy_openai_codex_auth_profile' "$FLEET_POLICY_FILE")"
    POLICY_MOLTINGER_SERVICE_REF="$(jq -r '.secret_refs.moltinger_service_auth' "$FLEET_POLICY_FILE")"
    POLICY_MOLTINGER_TELEGRAM_REF="$(jq -r '.secret_refs.moltinger_telegram_auth' "$FLEET_POLICY_FILE")"
    PROVIDER_SECRET_REF="$(jq -r '.provider_auth.clawdiy["codex-oauth"].secret_ref' "$FLEET_POLICY_FILE")"
    PROVIDER_PROFILE_FORMAT="$(jq -r '.provider_auth.clawdiy["codex-oauth"].profile_format' "$FLEET_POLICY_FILE")"
    PROVIDER_AUTH_TYPE="$(jq -r '.provider_auth.clawdiy["codex-oauth"].auth_type' "$FLEET_POLICY_FILE")"
    PROVIDER_ROLLOUT_GATE="$(jq -r '.provider_auth.clawdiy["codex-oauth"].rollout_gate' "$FLEET_POLICY_FILE")"
    PROVIDER_ENABLED="${CLAWDIY_OPENAI_CODEX_AUTH_ENABLED:-false}"

    add_check "policy_auth_shape" "pass" "Fleet policy auth metadata parsed successfully for Clawdiy" "error"
    return 0
}

check_common_auth_boundary() {
    if [[ "$GATEWAY_AUTH_MODE" != "token" ]]; then
        add_check "gateway_auth_contract" "fail" "Clawdiy gateway auth must stay on token mode for the hosted Control UI" "error"
    else
        add_check "gateway_auth_contract" "pass" "Clawdiy gateway auth stays on token mode for the hosted Control UI" "error"
    fi

    if [[ "$(jq -r '.service_auth.mode' "$FLEET_POLICY_FILE")" != "bearer" || "$(jq -r '.service_auth.authorization_header' "$FLEET_POLICY_FILE")" != "Authorization" || "$(jq -r '.service_auth.bind_token_to_agent_header' "$FLEET_POLICY_FILE")" != "true" ]]; then
        add_check "service_auth_contract" "fail" "Clawdiy service auth must stay on bearer mode with Authorization and X-Agent-Id binding" "error"
    else
        add_check "service_auth_contract" "pass" "Clawdiy service auth stays on bearer mode with explicit caller binding" "error"
    fi

    if [[ "$POLICY_CLAWDIY_HUMAN_REF" == "github-secret:MOLTIS_PASSWORD" || "$POLICY_CLAWDIY_SERVICE_REF" == "github-secret:MOLTINGER_SERVICE_TOKEN" || "$POLICY_CLAWDIY_TELEGRAM_REF" == "github-secret:TELEGRAM_BOT_TOKEN" || "$POLICY_CLAWDIY_ALLOWLIST_REF" == "github-secret:TELEGRAM_ALLOWED_USERS" || "$PROVIDER_SECRET_REF" == "github-secret:MOLTINGER_SERVICE_TOKEN" ]]; then
        add_check "auth_ref_isolation" "fail" "Clawdiy gateway, service, and Telegram auth refs must stay isolated from Moltinger refs" "error"
        return 1
    fi

    local gateway_secret_value=""
    gateway_secret_value="$(lookup_secret_value "$(secret_ref_name "$POLICY_CLAWDIY_HUMAN_REF")" || true)"
    if [[ -z "$gateway_secret_value" && -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        gateway_secret_value="${OPENCLAW_GATEWAY_TOKEN}"
    fi
    if [[ -z "$gateway_secret_value" && -n "${CLAWDIY_PASSWORD:-}" ]]; then
        gateway_secret_value="${CLAWDIY_PASSWORD}"
        add_check "gateway_auth_secret_source" "warning" "Clawdiy gateway auth is using legacy CLAWDIY_PASSWORD fallback; rotate to CLAWDIY_GATEWAY_TOKEN when practical" "warning"
    elif [[ -n "$gateway_secret_value" ]]; then
        add_check "gateway_auth_secret_source" "pass" "Clawdiy gateway token material is present for the hosted Control UI" "error"
    else
        add_check "gateway_auth_secret_source" "fail" "Clawdiy gateway token material is missing; hosted Control UI auth cannot succeed" "error"
        return 1
    fi

    local clawdiy_service_value=""
    local moltinger_service_value=""
    local clawdiy_telegram_value=""
    local moltinger_telegram_value=""
    clawdiy_service_value="$(lookup_secret_value "$(secret_ref_name "$POLICY_CLAWDIY_SERVICE_REF")" || true)"
    moltinger_service_value="$(lookup_secret_value "$(secret_ref_name "$POLICY_MOLTINGER_SERVICE_REF")" || true)"
    clawdiy_telegram_value="$(lookup_secret_value "$(secret_ref_name "$POLICY_CLAWDIY_TELEGRAM_REF")" || true)"
    moltinger_telegram_value="$(lookup_secret_value "$(secret_ref_name "$POLICY_MOLTINGER_TELEGRAM_REF")" || true)"

    if is_clawdiy_telegram_shadow && [[ "$moltinger_telegram_value" == "${TELEGRAM_BOT_TOKEN}" ]]; then
        moltinger_telegram_value=""
    fi

    if [[ -n "$clawdiy_service_value" && -n "$moltinger_service_value" && "$clawdiy_service_value" == "$moltinger_service_value" ]]; then
        add_check "auth_value_isolation" "fail" "Clawdiy service token value must not equal Moltinger service token value" "error"
        return 1
    fi

    if [[ -n "$clawdiy_telegram_value" && -n "$moltinger_telegram_value" && "$clawdiy_telegram_value" == "$moltinger_telegram_value" ]]; then
        add_check "auth_value_isolation" "fail" "Clawdiy Telegram token value must not equal Moltinger Telegram token value" "error"
        return 1
    fi

    add_check "auth_ref_alignment" "pass" "Clawdiy auth refs are sourced from the fleet policy catalog" "error"
    add_check "auth_ref_isolation" "pass" "Clawdiy auth refs stay isolated from Moltinger auth refs" "error"
    add_check "auth_value_isolation" "pass" "Clawdiy auth values do not collide with Moltinger values when both are available" "error"
    return 0
}

run_telegram_check() {
    local token_secret
    local allowlist_secret
    local token_value=""
    local allowlist_value=""

    token_secret="$(secret_ref_name "$POLICY_CLAWDIY_TELEGRAM_REF")"
    allowlist_secret="$(secret_ref_name "$POLICY_CLAWDIY_ALLOWLIST_REF")"
    token_value="$(lookup_secret_value "$token_secret" || true)"
    allowlist_value="$(lookup_secret_value "$allowlist_secret" || true)"

    if [[ "$TELEGRAM_ENABLED" != "true" || "$TELEGRAM_DM_POLICY" != "allowlist" ]]; then
        add_check "telegram_contract" "fail" "Clawdiy Telegram auth must stay enabled with allowlist DM policy" "error"
        add_capability_result "telegram" "fail" "Fix runtime config before repeating Telegram auth"
        return 1
    fi

    add_check "telegram_contract" "pass" "Clawdiy Telegram runtime stays enabled with allowlist DM policy" "error"

    if [[ -z "$token_value" ]]; then
        add_check "telegram_token_present" "fail" "Clawdiy Telegram token is missing; keep Telegram ingress quarantined and run repeat-auth" "error"
        add_capability_result "telegram" "fail" "Repeat-auth the Telegram bot token and redeploy Clawdiy"
        return 1
    fi

    add_check "telegram_token_present" "pass" "Clawdiy Telegram token is present for repeat-auth validation" "error"

    local moltinger_runtime_telegram_token=""
    moltinger_runtime_telegram_token="$(lookup_secret_value "$(secret_ref_name "$POLICY_MOLTINGER_TELEGRAM_REF")" || true)"

    if is_clawdiy_telegram_shadow && [[ "$moltinger_runtime_telegram_token" == "${TELEGRAM_BOT_TOKEN}" ]]; then
        moltinger_runtime_telegram_token=""
    fi

    if [[ -n "$moltinger_runtime_telegram_token" && "$token_value" == "$moltinger_runtime_telegram_token" ]]; then
        add_check "telegram_token_isolation" "fail" "Clawdiy Telegram token must not reuse Moltinger TELEGRAM_BOT_TOKEN" "error"
        add_capability_result "telegram" "fail" "Rotate Clawdiy Telegram token so it is isolated from Moltinger"
        return 1
    fi

    add_check "telegram_token_isolation" "pass" "Clawdiy Telegram token stays isolated from Moltinger bot identity" "error"

    if [[ -n "$allowlist_value" ]]; then
        if printf '%s' "$allowlist_value" | grep -Eq '^[^[:space:],]+(,[^[:space:],]+)*$'; then
            add_check "telegram_allowlist_format" "pass" "Clawdiy Telegram allowlist is present and formatted as a comma-separated list" "warning"
        else
            add_check "telegram_allowlist_format" "fail" "Clawdiy Telegram allowlist is malformed; keep Telegram ingress fail-closed until corrected" "error"
            add_capability_result "telegram" "fail" "Fix CLAWDIY_TELEGRAM_ALLOWED_USERS formatting and redeploy"
            return 1
        fi
    else
        add_check "telegram_allowlist_format" "warning" "Clawdiy Telegram allowlist is empty; operator-side filtering still required until the allowlist secret is set" "warning"
    fi

    if [[ "$TELEGRAM_ALLOW_FROM_COUNT" == "0" && -n "$allowlist_value" ]]; then
        add_check "telegram_runtime_allowlist_render" "warning" "Rendered Clawdiy runtime allowFrom list is still empty; rerender runtime config before relying on Telegram ingress" "warning"
    else
        add_check "telegram_runtime_allowlist_render" "pass" "Clawdiy runtime allowFrom list is ready for Telegram ingress" "warning"
    fi

    add_capability_result "telegram" "pass" "Telegram auth boundary is ready; keep monitoring duplicate delivery separately"
    return 0
}

run_openai_codex_check() {
    local profile_secret
    local profile_value=""

    profile_secret="$(secret_ref_name "$PROVIDER_SECRET_REF")"
    profile_value="$(lookup_secret_value "$profile_secret" || true)"

    if [[ "$PROVIDER_PROFILE_FORMAT" != "json" || "$PROVIDER_AUTH_TYPE" != "oauth" || "$PROVIDER_ROLLOUT_GATE" != "post-auth-verify" ]]; then
        add_check "openai_codex_contract" "fail" "Clawdiy codex-oauth auth must stay JSON/OAuth with the post-auth-verify rollout gate" "error"
        add_capability_result "codex-oauth" "fail" "Fix runtime provider auth metadata before repeating OAuth verification"
        return 1
    fi

    if [[ "$PROVIDER_ENABLED" == "true" ]]; then
        add_check "openai_codex_gate" "warning" "Clawdiy codex-oauth capability is already enabled; verify the rollout gate before promoting it again" "warning"
    else
        add_check "openai_codex_gate" "pass" "Clawdiy codex-oauth capability remains rollout-gated until post-auth verification passes" "error"
    fi

    add_check "openai_codex_contract" "pass" "Clawdiy codex-oauth runtime metadata stays JSON/OAuth with an explicit rollout gate" "error"

    if [[ -z "$profile_value" ]]; then
        add_check "openai_codex_profile_present" "fail" "Clawdiy codex-oauth auth profile is missing; keep the capability quarantined and run repeat-auth" "error"
        add_capability_result "codex-oauth" "fail" "Refresh CLAWDIY_OPENAI_CODEX_AUTH_PROFILE before enabling Codex-backed capability"
        return 1
    fi

    if ! printf '%s' "$profile_value" | jq -e '
        .provider == "codex-oauth"
        and .auth_type == "oauth"
        and (.granted_scopes | type == "array")
        and (.allowed_models | type == "array")
    ' >/dev/null 2>&1; then
        add_check "openai_codex_profile_json" "fail" "Clawdiy codex-oauth auth profile must be compact JSON with provider/auth/scopes/models fields" "error"
        add_capability_result "codex-oauth" "fail" "Rewrite CLAWDIY_OPENAI_CODEX_AUTH_PROFILE as valid compact JSON"
        return 1
    fi

    add_check "openai_codex_profile_json" "pass" "Clawdiy codex-oauth auth profile is valid JSON" "error"

    if ! jq -e --argjson required_scopes "$(jq -c '.provider_auth.clawdiy["codex-oauth"].required_scopes' "$FLEET_POLICY_FILE")" --argjson allowed_models "$(jq -c '.provider_auth.clawdiy["codex-oauth"].allowed_models' "$FLEET_POLICY_FILE")" '
        (($required_scopes - (.granted_scopes // [])) | length == 0)
        and (($allowed_models - (.allowed_models // [])) | length == 0)
    ' <(printf '%s' "$profile_value") >/dev/null 2>&1; then
        add_check "openai_codex_scope_gate" "fail" "Clawdiy codex-oauth profile is missing required scopes or gpt-5.4 authorization; capability stays quarantined and repeat-auth is required" "error"
        add_capability_result "codex-oauth" "fail" "Repeat OAuth until api.responses.write and gpt-5.4 authorization are present"
        return 1
    fi

    add_check "openai_codex_scope_gate" "pass" "Clawdiy codex-oauth profile grants api.responses.write and gpt-5.4 authorization" "error"
    add_capability_result "codex-oauth" "pass" "Provider auth profile is valid; capability may be promoted only after the post-auth verification gate"
    return 0
}

show_help() {
    cat <<EOF
Usage: $0 [--provider telegram|codex-oauth|all] [--env-file path] [--json] [--strict] [--no-color]

Options:
  --provider <name>   Capability to validate (default: all)
  --env-file <path>   Optional env file to load before checks
  --json              Emit JSON output
  --strict            Treat warnings as failures
  --no-color          Disable colorized logs
  -h, --help          Show help text
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                PROVIDER="$2"
                shift 2
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --strict)
                STRICT_MODE=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 2
                ;;
        esac
    done
}

output_json_result() {
    local status="$1"
    local checks_json="[]"
    local warnings_json="[]"
    local errors_json="[]"
    local capabilities_json="[]"

    if [[ ${#CHECKS[@]} -gt 0 ]]; then
        checks_json=$(printf '%s\n' "${CHECKS[@]}" | jq -s '.')
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '.')
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        errors_json=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
    fi

    if [[ ${#CAPABILITIES[@]} -gt 0 ]]; then
        capabilities_json=$(printf '%s\n' "${CAPABILITIES[@]}" | jq -s '.')
    fi

    jq -n \
        --arg status "$status" \
        --arg provider "$PROVIDER" \
        --arg timestamp "$(timestamp_utc)" \
        --arg config "$CLAWDIY_CONFIG_FILE" \
        --arg policy "$FLEET_POLICY_FILE" \
        --arg env_file "${ENV_FILE:-}" \
        --argjson checks "$checks_json" \
        --argjson warnings "$warnings_json" \
        --argjson errors "$errors_json" \
        --argjson capabilities "$capabilities_json" \
        '{
            status: $status,
            provider: $provider,
            timestamp: $timestamp,
            details: {
                config: $config,
                policy: $policy,
                env_file: (if $env_file == "" then null else $env_file end)
            },
            checks: $checks,
            capabilities: $capabilities,
            warnings: $warnings,
            errors: $errors
        }'
}

main() {
    parse_args "$@"
    disable_colors

    if [[ -n "$ENV_FILE" ]]; then
        if [[ ! -f "$ENV_FILE" ]]; then
            add_check "env_file_exists" "fail" "Env file not found: $ENV_FILE" "error"
            output_json_result "fail"
            exit 1
        fi
        read_env_file "$ENV_FILE"
        add_check "env_file_exists" "pass" "Loaded auth input env file: $ENV_FILE" "error"
    fi

    require_commands || {
        output_json_result "fail"
        exit 1
    }

    parse_runtime_config || {
        output_json_result "fail"
        exit 1
    }

    parse_policy_config || {
        output_json_result "fail"
        exit 1
    }

    check_common_auth_boundary || {
        output_json_result "fail"
        exit 1
    }

    case "$PROVIDER" in
        telegram)
            run_telegram_check || true
            ;;
        codex-oauth)
            run_openai_codex_check || true
            ;;
        all)
            run_telegram_check || true
            run_openai_codex_check || true
            ;;
        *)
            add_check "provider" "fail" "Unsupported provider: $PROVIDER" "error"
            ;;
    esac

    local final_status="pass"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        final_status="fail"
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        if [[ "$STRICT_MODE" == "true" ]]; then
            final_status="fail"
        else
            final_status="warning"
        fi
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json_result "$final_status"
    fi

    [[ "$final_status" == "fail" ]] && exit 1
    exit 0
}

main "$@"
