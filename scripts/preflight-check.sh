#!/bin/bash
#
# Pre-flight Validation Script for Docker Deployment
# Validates required secrets and configuration before deployment
#
# Usage:
#   ./scripts/preflight-check.sh [OPTIONS]
#
# Options:
#   --json             Output in JSON format
#   --strict           Fail on warnings (not just errors)
#   --ci               CI/CD mode (skip Docker daemon and runtime checks)
#   --target <name>    Validation target (moltis|clawdiy)
#   -h, --help         Show help message
#
# Exit Codes:
#   0 - All checks passed
#   1 - General error
#   4 - Pre-flight validation failed
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-traefik-net}"
FLEET_INTERNAL_NETWORK="${FLEET_INTERNAL_NETWORK:-fleet-internal}"
MONITORING_NETWORK="${MONITORING_NETWORK:-moltinger_monitoring}"
DEFAULT_CLAWDIY_IMAGE="ghcr.io/openclaw/openclaw:latest"

# Output format
OUTPUT_JSON=false
STRICT_MODE=false
CI_MODE="${CI:-false}"
TARGET="${TARGET:-moltis}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Results storage
CHECKS=()
ERRORS=()
WARNINGS=()
MISSING_SECRETS=()

# Target-specific state
REQUIRED_SECRETS=()
OPTIONAL_SECRETS=()
COMPOSE_FILES=()
REQUIRED_NETWORKS=()
BOOTSTRAP_NETWORKS=()
RUNTIME_CONFIG_PATH=""
REGISTRY_CONFIG_PATH=""
POLICY_CONFIG_PATH=""

# Clawdiy runtime cache
CLAWDIY_AGENT_ID=""
CLAWDIY_BASE_URL=""
CLAWDIY_RUNTIME_NAME=""
CLAWDIY_TELEGRAM_MODE=""
CLAWDIY_TELEGRAM_ALLOW_FROM_COUNT=""
CLAWDIY_LOGICAL_ADDRESS=""
CLAWDIY_REGISTRY_WEB=""
CLAWDIY_REGISTRY_TELEGRAM=""
CLAWDIY_POLICY_SERVICE_REF=""
CLAWDIY_POLICY_HUMAN_REF=""
CLAWDIY_POLICY_TELEGRAM_REF=""
CLAWDIY_POLICY_ALLOWLIST_REF=""
CLAWDIY_POLICY_PROVIDER_REF=""

# Helper functions
log_info() {
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
    WARNINGS+=("$1")
}

log_error() {
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
    ERRORS+=("$1")
}

add_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    local severity="${4:-error}"

    CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"message\":\"$message\",\"severity\":\"$severity\"}")

    if [[ "$status" == "fail" ]]; then
        if [[ "$severity" == "error" ]]; then
            log_error "$message"
        else
            log_warn "$message"
        fi
    else
        log_info "$message"
    fi
}

to_env_name() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

normalize_host() {
    printf '%s' "$1" \
        | sed -E 's#^[A-Za-z]+://##' \
        | sed -E 's#/.*$##' \
        | sed -E 's/:.*$//' \
        | tr '[:upper:]' '[:lower:]'
}

normalize_telegram() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

configure_target() {
    case "$TARGET" in
        moltis)
            REQUIRED_SECRETS=(
                "moltis_password"
                "telegram_bot_token"
                "tavily_api_key"
                "glm_api_key"
            )
            OPTIONAL_SECRETS=(
                "smtp_password"
                "ollama_api_key"
            )
            if [[ "$CI_MODE" == "true" ]]; then
                COMPOSE_FILES=("$PROJECT_ROOT/docker-compose.prod.yml")
            else
                COMPOSE_FILES=(
                    "$PROJECT_ROOT/docker-compose.yml"
                    "$PROJECT_ROOT/docker-compose.prod.yml"
                )
            fi
            REQUIRED_NETWORKS=("$TRAEFIK_NETWORK")
            BOOTSTRAP_NETWORKS=()
            ;;
        clawdiy)
            REQUIRED_SECRETS=(
                "clawdiy_service_token"
                "clawdiy_telegram_bot_token"
            )
            OPTIONAL_SECRETS=(
                "clawdiy_gateway_token"
                "clawdiy_password"
                "clawdiy_telegram_allowed_users"
                "clawdiy_openai_codex_auth_profile"
            )
            COMPOSE_FILES=("$PROJECT_ROOT/docker-compose.clawdiy.yml")
            REQUIRED_NETWORKS=(
                "$TRAEFIK_NETWORK"
                "$MONITORING_NETWORK"
            )
            BOOTSTRAP_NETWORKS=("$FLEET_INTERNAL_NETWORK")
            RUNTIME_CONFIG_PATH="$PROJECT_ROOT/config/clawdiy/openclaw.json"
            REGISTRY_CONFIG_PATH="$PROJECT_ROOT/config/fleet/agents-registry.json"
            POLICY_CONFIG_PATH="$PROJECT_ROOT/config/fleet/policy.json"
            ;;
        *)
            echo "Unsupported target: $TARGET" >&2
            exit 1
            ;;
    esac
}

secret_present() {
    local secret="$1"
    local secret_file="$SECRETS_DIR/${secret}.txt"
    local env_name
    env_name="$(to_env_name "$secret")"

    if [[ -f "$secret_file" && -s "$secret_file" ]]; then
        return 0
    fi

    if [[ -n "${!env_name:-}" ]]; then
        return 0
    fi

    return 1
}

validate_json_file() {
    local file_path="$1"
    local check_name="$2"
    local missing_message="$3"
    local invalid_message="$4"

    if [[ ! -f "$file_path" ]]; then
        add_check "$check_name" "fail" "$missing_message" "error"
        return 1
    fi

    if ! jq empty "$file_path" >/dev/null 2>&1; then
        add_check "$check_name" "fail" "$invalid_message" "error"
        return 1
    fi

    return 0
}

run_compose_config_check() {
    local compose_file="$1"

    if [[ "$TARGET" == "clawdiy" ]]; then
        CLAWDIY_IMAGE="${CLAWDIY_IMAGE:-$DEFAULT_CLAWDIY_IMAGE}" \
            docker compose -f "$compose_file" config --quiet >/dev/null 2>&1
    else
        docker compose -f "$compose_file" config --quiet >/dev/null 2>&1
    fi
}

run_yaml_fallback_check() {
    local compose_file="$1"

    if command -v yq >/dev/null 2>&1 && yq eval '.' "$compose_file" >/dev/null 2>&1; then
        return 0
    fi

    if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml; yaml.safe_load(open('$compose_file'))" 2>/dev/null; then
        return 0
    fi

    if command -v ruby >/dev/null 2>&1 && ruby -ryaml -e "YAML.load_file('$compose_file')" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Validation functions
check_secrets_exist() {
    local all_found=true

    if [[ "$TARGET" == "clawdiy" ]]; then
        if secret_present "clawdiy_gateway_token"; then
            add_check "clawdiy_gateway_secret_present" "pass" "Clawdiy gateway token secret is present" "error"
        elif secret_present "clawdiy_password"; then
            add_check "clawdiy_gateway_secret_present" "pass" "Clawdiy legacy password secret is present for gateway-token compatibility fallback" "warning"
        else
            MISSING_SECRETS+=("clawdiy_gateway_token|clawdiy_password")
            all_found=false
        fi
    fi

    for secret in "${REQUIRED_SECRETS[@]}"; do
        if ! secret_present "$secret"; then
            MISSING_SECRETS+=("$secret")
            all_found=false
        fi
    done

    if [[ "$all_found" == "true" ]]; then
        add_check "secrets_exist" "pass" "All ${#REQUIRED_SECRETS[@]} required secrets found for target $TARGET" "error"
    else
        add_check "secrets_exist" "fail" "Missing secrets for target $TARGET: ${MISSING_SECRETS[*]}" "error"
    fi

    for secret in "${OPTIONAL_SECRETS[@]}"; do
        if ! secret_present "$secret"; then
            log_warn "Optional secret '$secret' not found for target $TARGET"
        fi
    done
}

check_docker_available() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        add_check "docker_available" "pass" "Docker daemon is running" "error"
    else
        add_check "docker_available" "fail" "Docker daemon is not available" "error"
    fi
}

check_compose_valid() {
    local all_valid=true
    local checked_files=()

    for compose_file in "${COMPOSE_FILES[@]}"; do
        if [[ ! -f "$compose_file" ]]; then
            all_valid=false
            add_check "compose_valid" "fail" "$(basename "$compose_file") not found" "error"
            continue
        fi

        checked_files+=("$(basename "$compose_file")")

        if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
            if ! run_compose_config_check "$compose_file"; then
                all_valid=false
                add_check "compose_valid" "fail" "$(basename "$compose_file") has compose config errors" "error"
            fi
            continue
        fi

        if ! run_yaml_fallback_check "$compose_file"; then
            all_valid=false
            add_check "compose_valid" "fail" "$(basename "$compose_file") has syntax errors and no compose validator is available" "error"
        fi
    done

    if [[ "$all_valid" == "true" && ${#checked_files[@]} -gt 0 ]]; then
        add_check "compose_valid" "pass" "Compose files valid for target $TARGET: ${checked_files[*]}" "error"
    fi
}

check_network_exists() {
    local missing_networks=()

    if ! command -v docker >/dev/null 2>&1; then
        add_check "network_exists" "fail" "Docker CLI is required to validate external networks" "error"
        return
    fi

    for network_name in "${REQUIRED_NETWORKS[@]}"; do
        if ! docker network ls --format '{{.Name}}' | grep -qx "$network_name" 2>/dev/null; then
            missing_networks+=("$network_name")
        fi
    done

    if [[ ${#missing_networks[@]} -eq 0 ]]; then
        add_check "network_exists" "pass" "Required external networks exist for target $TARGET: ${REQUIRED_NETWORKS[*]}" "error"
    else
        add_check "network_exists" "fail" "Missing external networks for target $TARGET: ${missing_networks[*]}" "error"
    fi
}

check_bootstrap_networks() {
    local missing_bootstrap_networks=()

    if [[ ${#BOOTSTRAP_NETWORKS[@]} -eq 0 ]]; then
        return
    fi

    if ! command -v docker >/dev/null 2>&1; then
        add_check "network_bootstrap" "warning" "Docker CLI is required to validate bootstrap-capable networks for target $TARGET" "warning"
        return
    fi

    for network_name in "${BOOTSTRAP_NETWORKS[@]}"; do
        if ! docker network ls --format '{{.Name}}' | grep -qx "$network_name" 2>/dev/null; then
            missing_bootstrap_networks+=("$network_name")
        fi
    done

    if [[ ${#missing_bootstrap_networks[@]} -eq 0 ]]; then
        add_check "network_bootstrap" "pass" "Bootstrap-capable networks already exist for target $TARGET: ${BOOTSTRAP_NETWORKS[*]}" "warning"
    else
        add_check "network_bootstrap" "warning" "Bootstrap-capable networks missing for target $TARGET: ${missing_bootstrap_networks[*]}; they will be created during Clawdiy deploy via GitOps" "warning"
    fi
}

check_s3_credentials() {
    if command -v rclone >/dev/null 2>&1 && rclone config show backup-s3 >/dev/null 2>&1; then
        add_check "s3_credentials" "pass" "S3 credentials configured" "warning"
    else
        add_check "s3_credentials" "warning" "S3 credentials not configured, backup will be local only" "warning"
    fi
}

check_disk_space() {
    local backup_dir="/var/backups/moltis"
    local required_mb=1024

    if [[ -d "$backup_dir" ]]; then
        local available_kb
        available_kb=$(df -k "$backup_dir" | awk 'NR==2 {print $4}')
        local available_mb=$((available_kb / 1024))

        if [[ $available_mb -ge $required_mb ]]; then
            add_check "disk_space" "pass" "Sufficient disk space: ${available_mb}MB available" "warning"
        else
            add_check "disk_space" "fail" "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required" "warning"
        fi
    else
        add_check "disk_space" "pass" "Backup directory will be created on first backup" "warning"
    fi
}

check_ollama_config() {
    local moltis_config="$PROJECT_ROOT/config/moltis.toml"
    local ollama_enabled=false
    local ollama_base_url=""
    local ollama_model=""
    local failover_enabled=false

    if [[ ! -f "$moltis_config" ]]; then
        add_check "ollama_config" "fail" "moltis.toml not found" "error"
        return
    fi

    if grep -q '^\[providers\.ollama\]' "$moltis_config"; then
        ollama_enabled=$(grep -A5 '^\[providers\.ollama\]' "$moltis_config" | grep 'enabled' | sed 's/.*=.*\(true\|false\).*/\1/' | head -1)
        ollama_base_url=$(grep -A5 '^\[providers\.ollama\]' "$moltis_config" | grep 'base_url' | sed 's/.*=.*"\([^"]*\)".*/\1/' | head -1)
        ollama_model=$(grep -A5 '^\[providers\.ollama\]' "$moltis_config" | grep 'model' | sed 's/.*=.*"\([^"]*\)".*/\1/' | head -1)
    fi

    if grep -q '^\[failover\]' "$moltis_config"; then
        failover_enabled=$(grep -A5 '^\[failover\]' "$moltis_config" | grep 'enabled' | sed 's/.*=.*\(true\|false\).*/\1/' | head -1)
    fi

    if [[ "$ollama_enabled" == "true" ]]; then
        if [[ -n "$ollama_base_url" ]]; then
            add_check "ollama_base_url" "pass" "Ollama base URL configured: $ollama_base_url" "warning"
        else
            add_check "ollama_base_url" "fail" "Ollama enabled but base_url not set" "error"
        fi

        if [[ -n "$ollama_model" ]]; then
            add_check "ollama_model" "pass" "Ollama model configured: $ollama_model" "warning"
        else
            add_check "ollama_model" "fail" "Ollama enabled but model not set" "error"
        fi

        if [[ "$ollama_model" == *":cloud"* ]]; then
            local ollama_key_file="$SECRETS_DIR/ollama_api_key.txt"
            local ollama_key_env="${OLLAMA_API_KEY:-}"

            if [[ -n "$ollama_key_env" || (-f "$ollama_key_file" && -s "$ollama_key_file") ]]; then
                if [[ -f "$ollama_key_file" ]] && grep -q "PLACEHOLDER" "$ollama_key_file" 2>/dev/null; then
                    add_check "ollama_api_key" "fail" "Ollama API key is placeholder - replace with actual key" "warning"
                else
                    add_check "ollama_api_key" "pass" "Ollama API key configured for cloud model" "warning"
                fi
            else
                add_check "ollama_api_key" "fail" "Ollama cloud model requires ollama_api_key secret" "warning"
            fi
        fi

        if [[ "$failover_enabled" == "true" ]]; then
            add_check "failover_config" "pass" "Failover is enabled in moltis.toml" "warning"
        else
            add_check "failover_config" "warning" "Ollama configured but failover not enabled" "warning"
        fi
    else
        add_check "ollama_config" "pass" "Ollama provider not enabled (optional)" "warning"
    fi
}

check_ollama_secret() {
    local ollama_key_file="$SECRETS_DIR/ollama_api_key.txt"

    if [[ -n "${OLLAMA_API_KEY:-}" ]]; then
        add_check "ollama_secret_valid" "pass" "Ollama API key provided via environment" "warning"
        return
    fi

    if [[ -f "$ollama_key_file" ]]; then
        if [[ -s "$ollama_key_file" ]]; then
            local perms
            perms=$(stat -f "%Lp" "$ollama_key_file" 2>/dev/null || stat -c "%a" "$ollama_key_file" 2>/dev/null || echo "unknown")

            if [[ "$perms" == "600" ]]; then
                add_check "ollama_secret_perms" "pass" "Ollama API key file has correct permissions (600)" "warning"
            else
                add_check "ollama_secret_perms" "warning" "Ollama API key file should have 600 permissions (got: $perms)" "warning"
            fi

            if grep -q "PLACEHOLDER" "$ollama_key_file" 2>/dev/null; then
                add_check "ollama_secret_valid" "warning" "Ollama API key contains placeholder - replace before deployment" "warning"
            else
                add_check "ollama_secret_valid" "pass" "Ollama API key file exists and is not empty" "warning"
            fi
        else
            add_check "ollama_secret_valid" "warning" "Ollama API key file is empty" "warning"
        fi
    else
        add_check "ollama_secret_valid" "pass" "Ollama API key not configured (optional for local models)" "warning"
    fi
}

check_clawdiy_runtime_config() {
    local rendered_runtime_config="$PROJECT_ROOT/data/clawdiy/runtime/openclaw.json"
    if [[ -f "$rendered_runtime_config" ]]; then
        RUNTIME_CONFIG_PATH="$rendered_runtime_config"
    fi

    if ! validate_json_file \
        "$RUNTIME_CONFIG_PATH" \
        "runtime_config_valid" \
        "Clawdiy runtime config not found: $(basename "$RUNTIME_CONFIG_PATH")" \
        "Clawdiy runtime config is not valid JSON: $(basename "$RUNTIME_CONFIG_PATH")"; then
        return
    fi

    if ! jq -e '
        .gateway.mode == "local"
        and .gateway.bind == "custom"
        and .gateway.customBindHost == "0.0.0.0"
        and (.gateway.port | type == "number")
        and .gateway.auth.mode == "token"
        and .gateway.auth.token.source == "env"
        and .gateway.auth.token.provider == "default"
        and .gateway.auth.token.id == "OPENCLAW_GATEWAY_TOKEN"
        and .gateway.controlUi.enabled == true
        and (.gateway.controlUi.allowedOrigins | type == "array" and length > 0)
        and (.agents.list | type == "array" and any(.id == "main" and .identity.name == "Clawdiy"))
        and .channels.telegram.enabled == true
        and .channels.telegram.dmPolicy == "allowlist"
        and (.channels.telegram.allowFrom | type == "array")
        and .channels.telegram.botToken.source == "env"
        and .channels.telegram.botToken.provider == "default"
        and .channels.telegram.botToken.id == "TELEGRAM_BOT_TOKEN"
    ' "$RUNTIME_CONFIG_PATH" >/dev/null 2>&1; then
        add_check "runtime_config_shape" "fail" "Clawdiy runtime config is missing required official OpenClaw gateway, control UI, agent identity, or Telegram fields" "error"
        return
    fi

    CLAWDIY_AGENT_ID="$TARGET"
    CLAWDIY_BASE_URL="$(jq -r '.gateway.controlUi.allowedOrigins[0]' "$RUNTIME_CONFIG_PATH")"
    CLAWDIY_RUNTIME_NAME="$(jq -r '.agents.list[] | select(.id == "main") | .identity.name' "$RUNTIME_CONFIG_PATH")"
    CLAWDIY_TELEGRAM_MODE="$(jq -r '.channels.telegram.dmPolicy' "$RUNTIME_CONFIG_PATH")"
    CLAWDIY_TELEGRAM_ALLOW_FROM_COUNT="$(jq -r '.channels.telegram.allowFrom | length' "$RUNTIME_CONFIG_PATH")"

    add_check "runtime_config_shape" "pass" "Clawdiy runtime config fields parsed successfully" "error"
}

check_fleet_registry_config() {
    if ! validate_json_file \
        "$REGISTRY_CONFIG_PATH" \
        "fleet_registry_valid" \
        "Fleet registry config not found: $(basename "$REGISTRY_CONFIG_PATH")" \
        "Fleet registry config is not valid JSON: $(basename "$REGISTRY_CONFIG_PATH")"; then
        return
    fi

    if ! jq -e --arg target "$TARGET" '
        def normweb:
            tostring
            | sub("^https?://"; "")
            | sub("/+$"; "")
            | split("/")[0]
            | ascii_downcase;
        def normtg:
            tostring | ascii_downcase;
        .agents as $agents
        | ($agents | type == "array")
        and (($agents | length) > 0)
        and ($agents | any(.agent_id == $target))
        and (($agents | map(.agent_id) | length) == ($agents | map(.agent_id) | unique | length))
        and (([$agents[] | .public_endpoints.web? | select(type == "string" and length > 0) | normweb] | length) == ([$agents[] | .public_endpoints.web? | select(type == "string" and length > 0) | normweb] | unique | length))
        and (([$agents[] | .public_endpoints.telegram? | select(type == "string" and length > 0) | normtg] | length) == ([$agents[] | .public_endpoints.telegram? | select(type == "string" and length > 0) | normtg] | unique | length))
    ' "$REGISTRY_CONFIG_PATH" >/dev/null 2>&1; then
        add_check "fleet_registry_shape" "fail" "Fleet registry must contain target $TARGET with unique agent_id, web, and Telegram identities" "error"
        return
    fi

    if ! jq -e --arg target "$TARGET" '
        .agents[]
        | select(.agent_id == $target)
        | (.display_name | type == "string" and length > 0)
        and (.role | type == "string" and length > 0)
        and (.logical_address | type == "string" and length > 0)
        and (.runtime_engine | type == "string" and length > 0)
        and (.internal_endpoint | type == "string" and length > 0)
        and (.public_endpoints.web | type == "string" and length > 0)
        and (.public_endpoints.telegram | type == "string" and length > 0)
        and (.capabilities | type == "array" and length > 0)
        and (.allowed_callers | type == "array" and length > 0)
        and (.topology.active_profile == "same_host")
        and ((.topology.supported_profiles | index("same_host")) != null)
        and ((.topology.supported_profiles | index("remote_node")) != null)
        and (.policy_version | type == "string" and length > 0)
    ' "$REGISTRY_CONFIG_PATH" >/dev/null 2>&1; then
        add_check "fleet_registry_shape" "fail" "Fleet registry target entry is missing required fields for $TARGET" "error"
        return
    fi

    CLAWDIY_REGISTRY_WEB="$(jq -r --arg target "$TARGET" '.agents[] | select(.agent_id == $target) | .public_endpoints.web' "$REGISTRY_CONFIG_PATH")"
    CLAWDIY_REGISTRY_TELEGRAM="$(jq -r --arg target "$TARGET" '.agents[] | select(.agent_id == $target) | .public_endpoints.telegram' "$REGISTRY_CONFIG_PATH")"

    add_check "fleet_registry_shape" "pass" "Fleet registry parsed successfully for target $TARGET" "error"
}

check_fleet_policy_config() {
    if ! validate_json_file \
        "$POLICY_CONFIG_PATH" \
        "fleet_policy_valid" \
        "Fleet policy config not found: $(basename "$POLICY_CONFIG_PATH")" \
        "Fleet policy config is not valid JSON: $(basename "$POLICY_CONFIG_PATH")"; then
        return
    fi

    if ! jq -e '
        .defaults.allow_unknown_agents == false
        and .defaults.allow_unknown_capabilities == false
        and .defaults.allow_public_machine_handoffs == false
        and .defaults.fail_closed_on_auth_error == true
        and .defaults.require_topology_profile_alignment == true
        and .service_auth.mode == "bearer"
        and .service_auth.authorization_header == "Authorization"
        and (.service_auth.required_headers | type == "array" and length > 0)
        and .service_auth.reject_on_missing_required_headers == true
        and .service_auth.reject_on_agent_header_mismatch == true
        and .topology_profiles.same_host.transport == "http-json"
        and .topology_profiles.same_host.allow_public_machine_handoffs == false
        and .topology_profiles.remote_node.transport == "http-json"
        and .topology_profiles.remote_node.allow_public_machine_handoffs == false
        and (.secret_refs.clawdiy_human_auth | type == "string" and length > 0)
        and (.secret_refs.clawdiy_telegram_auth | type == "string" and length > 0)
        and (.secret_refs.clawdiy_telegram_allowlist | type == "string" and length > 0)
        and (.secret_refs.clawdiy_openai_codex_auth_profile | type == "string" and length > 0)
        and (.telegram_auth.clawdiy.secret_ref == .secret_refs.clawdiy_telegram_auth)
        and (.telegram_auth.clawdiy.allowlist_secret_ref == .secret_refs.clawdiy_telegram_allowlist)
        and (.telegram_auth.clawdiy.mode == "polling")
        and (.telegram_auth.clawdiy.fail_closed_on_token_error == true)
        and (.provider_auth.clawdiy["codex-oauth"].secret_ref == .secret_refs.clawdiy_openai_codex_auth_profile)
        and (.provider_auth.clawdiy["codex-oauth"].profile_format == "json")
        and (.provider_auth.clawdiy["codex-oauth"].auth_type == "oauth")
        and (.provider_auth.clawdiy["codex-oauth"].required_scopes | index("api.responses.write") != null)
        and (.provider_auth.clawdiy["codex-oauth"].allowed_models | index("gpt-5.4") != null)
        and (.provider_auth.clawdiy["codex-oauth"].fail_closed_on_scope_error == true)
    ' "$POLICY_CONFIG_PATH" >/dev/null 2>&1; then
        add_check "fleet_policy_shape" "fail" "Fleet policy must stay fail-closed with bearer service auth defaults" "error"
        return
    fi

    if ! jq -e --arg target "$TARGET" '
        (.routes | type == "array")
        and any(.routes[]; .caller == "moltinger" and .recipient == $target and .transport == "http-json")
        and (.secret_refs.clawdiy_service_auth | type == "string" and length > 0)
    ' "$POLICY_CONFIG_PATH" >/dev/null 2>&1; then
        add_check "fleet_policy_shape" "fail" "Fleet policy must define moltinger -> $TARGET HTTP JSON routing and service auth secret refs" "error"
        return
    fi

    CLAWDIY_POLICY_HUMAN_REF="$(jq -r '.secret_refs.clawdiy_human_auth' "$POLICY_CONFIG_PATH")"
    CLAWDIY_POLICY_SERVICE_REF="$(jq -r '.secret_refs.clawdiy_service_auth' "$POLICY_CONFIG_PATH")"
    CLAWDIY_POLICY_TELEGRAM_REF="$(jq -r '.secret_refs.clawdiy_telegram_auth' "$POLICY_CONFIG_PATH")"
    CLAWDIY_POLICY_ALLOWLIST_REF="$(jq -r '.secret_refs.clawdiy_telegram_allowlist' "$POLICY_CONFIG_PATH")"
    CLAWDIY_POLICY_PROVIDER_REF="$(jq -r '.secret_refs.clawdiy_openai_codex_auth_profile' "$POLICY_CONFIG_PATH")"
    add_check "fleet_policy_shape" "pass" "Fleet policy parsed successfully for target $TARGET" "error"
}

check_clawdiy_identity_alignment() {
    if [[ -z "$CLAWDIY_AGENT_ID" || -z "$CLAWDIY_BASE_URL" || -z "$CLAWDIY_REGISTRY_WEB" || -z "$CLAWDIY_RUNTIME_NAME" ]]; then
        add_check "fleet_identity_alignment" "fail" "Clawdiy identity alignment could not be evaluated because required config parsing did not complete" "error"
        return
    fi

    local runtime_host registry_host

    if [[ "$CLAWDIY_AGENT_ID" != "$TARGET" ]]; then
        add_check "fleet_identity_alignment" "fail" "Clawdiy runtime agent_id must match target $TARGET" "error"
        return
    fi

    runtime_host="$(normalize_host "$CLAWDIY_BASE_URL")"
    registry_host="$(normalize_host "$CLAWDIY_REGISTRY_WEB")"

    if [[ "$runtime_host" != "$registry_host" ]]; then
        add_check "fleet_identity_alignment" "fail" "Clawdiy runtime control UI origin and registry web endpoint must resolve to the same host" "error"
        return
    fi

    if [[ "$CLAWDIY_RUNTIME_NAME" != "Clawdiy" ]]; then
        add_check "fleet_identity_alignment" "fail" "Clawdiy runtime main agent identity must stay named Clawdiy" "error"
        return
    fi

    add_check "fleet_identity_alignment" "pass" "Clawdiy runtime control UI origin and agent identity align with the fleet registry" "error"
}

check_clawdiy_secret_isolation() {
    if [[ -z "$CLAWDIY_POLICY_HUMAN_REF" || -z "$CLAWDIY_POLICY_SERVICE_REF" || -z "$CLAWDIY_POLICY_TELEGRAM_REF" || -z "$CLAWDIY_POLICY_ALLOWLIST_REF" || -z "$CLAWDIY_POLICY_PROVIDER_REF" ]]; then
        add_check "fleet_secret_isolation" "fail" "Clawdiy secret isolation could not be evaluated because fleet policy parsing did not complete" "error"
        return
    fi

    if [[ "$CLAWDIY_POLICY_HUMAN_REF" == "github-secret:MOLTIS_PASSWORD" ]]; then
        add_check "fleet_secret_isolation" "fail" "Clawdiy gateway auth secret must not reuse MOLTIS_PASSWORD" "error"
        return
    fi

    if [[ "$CLAWDIY_POLICY_SERVICE_REF" == "github-secret:MOLTINGER_SERVICE_TOKEN" ]]; then
        add_check "fleet_secret_isolation" "fail" "Clawdiy service auth secret must not reuse MOLTINGER_SERVICE_TOKEN" "error"
        return
    fi

    if [[ "$CLAWDIY_POLICY_TELEGRAM_REF" == "github-secret:TELEGRAM_BOT_TOKEN" ]]; then
        add_check "fleet_secret_isolation" "fail" "Clawdiy Telegram token ref must not reuse TELEGRAM_BOT_TOKEN" "error"
        return
    fi

    if [[ "$CLAWDIY_POLICY_ALLOWLIST_REF" == "github-secret:TELEGRAM_ALLOWED_USERS" ]]; then
        add_check "fleet_secret_isolation" "fail" "Clawdiy Telegram allowlist ref must not reuse TELEGRAM_ALLOWED_USERS" "error"
        return
    fi

    if [[ "$CLAWDIY_POLICY_PROVIDER_REF" == "github-secret:MOLTINGER_SERVICE_TOKEN" || "$CLAWDIY_POLICY_PROVIDER_REF" == "github-secret:TELEGRAM_BOT_TOKEN" ]]; then
        add_check "fleet_secret_isolation" "fail" "Clawdiy provider auth profile ref must stay isolated from Moltinger auth secrets" "error"
        return
    fi

    add_check "fleet_secret_isolation" "pass" "Clawdiy auth, Telegram, and provider auth refs are isolated from Moltinger in the fleet policy catalog" "error"
}

check_clawdiy_topology_alignment() {
    if ! jq -e --slurpfile registry "$REGISTRY_CONFIG_PATH" --slurpfile policy "$POLICY_CONFIG_PATH" '
        ($registry[0].agents[] | select(.agent_id == "clawdiy")) as $cl
        | ($policy[0].routes[] | select(.caller == "moltinger" and .recipient == "clawdiy")) as $to_clawdiy
        | ($policy[0].routes[] | select(.caller == "clawdiy" and .recipient == "moltinger")) as $to_moltinger
        | $cl.logical_address == "agent://clawdiy"
        and $cl.topology.active_profile == "same_host"
        and ($cl.topology.supported_profiles | index("same_host")) != null
        and ($cl.topology.supported_profiles | index("remote_node")) != null
        and ($cl.topology.placement_profiles.same_host.internal_endpoint | endswith("/internal/v1"))
        and ($cl.topology.placement_profiles.remote_node.internal_endpoint | endswith("/internal/v1"))
        and ($to_clawdiy.supported_topology_profiles | index("same_host")) != null
        and ($to_clawdiy.supported_topology_profiles | index("remote_node")) != null
        and ($to_moltinger.supported_topology_profiles | index("same_host")) != null
        and ($to_moltinger.supported_topology_profiles | index("remote_node")) != null
        and $policy[0].defaults.require_topology_profile_alignment == true
      ' "$POLICY_CONFIG_PATH" >/dev/null 2>&1; then
        add_check "fleet_topology_alignment" "fail" "Clawdiy registry and policy must keep topology-profile and logical-address alignment fail-closed" "error"
        return
    fi

    add_check "fleet_topology_alignment" "pass" "Clawdiy registry and policy stay aligned on same_host/remote_node topology profiles" "error"
}

check_target_specific_config() {
    case "$TARGET" in
        clawdiy)
            check_clawdiy_runtime_config
            check_fleet_registry_config
            check_fleet_policy_config
            check_clawdiy_identity_alignment
            check_clawdiy_secret_isolation
            check_clawdiy_topology_alignment
            ;;
    esac
}

# Output functions
output_json() {
    local status="pass"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local error_count=0
    local warning_count=0
    local check_count=0
    local missing_count=0

    error_count=${#ERRORS[@]}
    warning_count=${#WARNINGS[@]}
    check_count=${#CHECKS[@]}
    missing_count=${#MISSING_SECRETS[@]}

    if [[ $error_count -gt 0 ]]; then
        status="fail"
    elif [[ $warning_count -gt 0 && "$STRICT_MODE" == "true" ]]; then
        status="fail"
    elif [[ $warning_count -gt 0 ]]; then
        status="warning"
    fi

    local checks_json="[]"
    local missing_json="[]"
    local errors_json="[]"
    local warnings_json="[]"

    if [[ $check_count -gt 0 ]]; then
        checks_json=$(printf '%s\n' "${CHECKS[@]}" | jq -s '.')
    fi

    if [[ $missing_count -gt 0 ]]; then
        missing_json=$(printf '%s\n' "${MISSING_SECRETS[@]}" | jq -R . | jq -s .)
    fi

    if [[ $error_count -gt 0 ]]; then
        errors_json=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s .)
    fi

    if [[ $warning_count -gt 0 ]]; then
        warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --arg target "$TARGET" \
        --argjson checks "$checks_json" \
        --argjson missing_secrets "$missing_json" \
        --argjson errors "$errors_json" \
        --argjson warnings "$warnings_json" \
        '{
            status: $status,
            target: $target,
            timestamp: $timestamp,
            checks: $checks,
            missing_secrets: $missing_secrets,
            errors: $errors,
            warnings: $warnings
        }'
}

output_text() {
    echo ""
    echo "========================================="
    echo "  Pre-flight Validation Results ($TARGET)"
    echo "========================================="
    echo ""

    if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
        echo -e "${GREEN}✓ All checks passed${NC}"
    elif [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠ All critical checks passed, ${#WARNINGS[@]} warnings${NC}"
    else
        echo -e "${RED}✗ ${#ERRORS[@]} checks failed${NC}"
    fi

    echo ""
    echo "Checks performed: ${#CHECKS[@]}"
    echo "Errors: ${#ERRORS[@]}"
    echo "Warnings: ${#WARNINGS[@]}"

    if [[ ${#MISSING_SECRETS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Missing secrets:${NC}"
        for secret in "${MISSING_SECRETS[@]}"; do
            echo "  - $secret"
        done
    fi

    echo ""
}

# Help function
show_help() {
    cat << EOF
Pre-flight Validation Script for Docker Deployment

Usage:
    $0 [OPTIONS]

Options:
    --json             Output in JSON format for AI parsing
    --strict           Fail on warnings (not just errors)
    --ci               CI mode (skip Docker daemon and runtime checks)
    --target <name>    Validation target: moltis or clawdiy
    -h, --help         Show help message

Exit Codes:
    0 - All checks passed
    1 - General error
    4 - Pre-flight validation failed

Examples:
    $0
    $0 --json
    $0 --ci --json
    $0 --target clawdiy --json
    $0 --json --strict

Contract: specs/001-docker-deploy-improvements/contracts/scripts.md
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        --target)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --target" >&2
                exit 1
            fi
            TARGET="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    configure_target

    if [[ "$CI_MODE" == "true" && "$OUTPUT_JSON" == "false" ]]; then
        echo "Running in CI mode - skipping Docker daemon and runtime checks" >&2
    fi

    check_compose_valid
    check_target_specific_config

    if [[ "$CI_MODE" == "true" ]]; then
        if [[ "$TARGET" == "moltis" ]]; then
            check_ollama_config
        fi
    else
        check_secrets_exist
        check_docker_available
        check_network_exists
        check_bootstrap_networks
        check_s3_credentials
        check_disk_space

        if [[ "$TARGET" == "moltis" ]]; then
            check_ollama_config
            check_ollama_secret
        fi
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json
    else
        output_text
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        exit 4
    elif [[ ${#WARNINGS[@]} -gt 0 && "$STRICT_MODE" == "true" ]]; then
        exit 4
    else
        exit 0
    fi
}

main
