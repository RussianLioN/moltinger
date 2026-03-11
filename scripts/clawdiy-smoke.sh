#!/bin/bash
# Clawdiy rollout verification stages for same-host deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CLAWDIY_CONFIG_FILE="${CLAWDIY_CONFIG_FILE:-$PROJECT_ROOT/config/clawdiy/openclaw.json}"
MOLTIS_CONFIG_FILE="${MOLTIS_CONFIG_FILE:-$PROJECT_ROOT/config/moltis.toml}"
FLEET_REGISTRY_FILE="${FLEET_REGISTRY_FILE:-$PROJECT_ROOT/config/fleet/agents-registry.json}"
FLEET_POLICY_FILE="${FLEET_POLICY_FILE:-$PROJECT_ROOT/config/fleet/policy.json}"
HANDOFF_SAMPLE_FILE="${HANDOFF_SAMPLE_FILE:-$PROJECT_ROOT/specs/001-clawdiy-agent-platform/contracts/sample-handoff-submit.json}"
CLAWDIY_AUTH_CHECK_SCRIPT="${CLAWDIY_AUTH_CHECK_SCRIPT:-$PROJECT_ROOT/scripts/clawdiy-auth-check.sh}"
CLAWDIY_LOCAL_AUDIT_ROOT="${CLAWDIY_LOCAL_AUDIT_ROOT:-$PROJECT_ROOT/data/clawdiy/audit}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/moltis}"
CLAWDIY_CONTAINER="${CLAWDIY_CONTAINER:-clawdiy}"
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"
FLEET_INTERNAL_NETWORK="${FLEET_INTERNAL_NETWORK:-fleet-internal}"
MONITORING_NETWORK="${MONITORING_NETWORK:-moltinger_monitoring}"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-traefik-net}"
STAGE="${STAGE:-same-host}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-90}"
OUTPUT_JSON=false
NO_COLOR=false

CLAWDIY_PUBLIC_BASE_URL=""
CLAWDIY_PUBLIC_HEALTH_URL=""
CLAWDIY_LOCAL_HEALTH_URL=""
CLAWDIY_LOCAL_METRICS_URL=""
MOLTIS_HEALTH_URL="${MOLTIS_HEALTH_URL:-http://127.0.0.1:13131/health}"
HANDOFF_AUDIT_ARTIFACT=""

declare -a CHECKS=()
declare -a ERRORS=()
declare -a WARNINGS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

timestamp_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

output_json_result() {
    local status="$1"
    local checks_json="[]"
    local warnings_json="[]"
    local errors_json="[]"

    if [[ ${#CHECKS[@]} -gt 0 ]]; then
        checks_json=$(printf '%s\n' "${CHECKS[@]}" | jq -s '.')
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '.')
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        errors_json=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
    fi

    jq -n \
        --arg status "$status" \
        --arg stage "$STAGE" \
        --arg timestamp "$(timestamp_utc)" \
        --arg clawdiy_container "$CLAWDIY_CONTAINER" \
        --arg moltis_container "$MOLTIS_CONTAINER" \
        --arg clawdiy_public_url "$CLAWDIY_PUBLIC_BASE_URL" \
        --arg clawdiy_local_health "$CLAWDIY_LOCAL_HEALTH_URL" \
        --arg moltis_health "$MOLTIS_HEALTH_URL" \
        --arg handoff_audit_artifact "$HANDOFF_AUDIT_ARTIFACT" \
        --argjson checks "$checks_json" \
        --argjson warnings "$warnings_json" \
        --argjson errors "$errors_json" \
        '{
            status: $status,
            stage: $stage,
            timestamp: $timestamp,
            details: {
                clawdiy_container: $clawdiy_container,
                moltis_container: $moltis_container,
                clawdiy_public_url: $clawdiy_public_url,
                clawdiy_local_health_url: $clawdiy_local_health,
                moltis_health_url: $moltis_health,
                handoff_audit_artifact: (if $handoff_audit_artifact == "" then null else $handoff_audit_artifact end)
            },
            checks: $checks,
            warnings: $warnings,
            errors: $errors
        }'
}

require_commands() {
    local missing=()
    local required=(jq)
    local cmd

    case "$STAGE" in
        same-host|restart-isolation|handoff|rollback-evidence)
            required+=(curl docker)
            ;;
        auth|extraction-readiness)
            ;;
        *)
            required+=(curl docker)
            ;;
    esac

    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        add_check "dependencies" "fail" "Missing required commands: ${missing[*]}" "error"
        return 1
    fi

    add_check "dependencies" "pass" "Required commands available: ${required[*]}" "error"
    return 0
}

load_runtime_config() {
    local rendered_runtime_config="$PROJECT_ROOT/data/clawdiy/runtime/openclaw.json"
    if [[ -f "$rendered_runtime_config" ]]; then
        CLAWDIY_CONFIG_FILE="$rendered_runtime_config"
    fi

    if [[ ! -f "$CLAWDIY_CONFIG_FILE" ]]; then
        add_check "runtime_config" "fail" "Clawdiy runtime config not found: $CLAWDIY_CONFIG_FILE" "error"
        return 1
    fi

    if ! jq empty "$CLAWDIY_CONFIG_FILE" >/dev/null 2>&1; then
        add_check "runtime_config" "fail" "Clawdiy runtime config is invalid JSON: $CLAWDIY_CONFIG_FILE" "error"
        return 1
    fi

    local base_url server_port
    base_url="$(jq -r '.gateway.controlUi.allowedOrigins[0]' "$CLAWDIY_CONFIG_FILE")"
    server_port="$(jq -r '.gateway.port // 18789' "$CLAWDIY_CONFIG_FILE")"

    CLAWDIY_PUBLIC_BASE_URL="${base_url%/}"
    CLAWDIY_PUBLIC_HEALTH_URL="${CLAWDIY_PUBLIC_BASE_URL}/health"
    CLAWDIY_LOCAL_HEALTH_URL="http://127.0.0.1:${server_port}/health"
    CLAWDIY_LOCAL_METRICS_URL="http://127.0.0.1:${server_port}/metrics"

    add_check "runtime_config" "pass" "Loaded Clawdiy runtime config from $CLAWDIY_CONFIG_FILE" "error"
    return 0
}

http_code() {
    local url="$1"
    local timeout="${2:-10}"
    curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || echo "000"
}

wait_for_http_200() {
    local url="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if [[ "$(http_code "$url" 5)" == "200" ]]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

container_exists() {
    docker inspect "$1" >/dev/null 2>&1
}

container_running() {
    local value
    value="$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null || echo "false")"
    [[ "$value" == "true" ]]
}

container_health() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "unknown"
}

container_label() {
    local container="$1"
    local label_key="$2"
    docker inspect "$container" | jq -r --arg label_key "$label_key" '.[0].Config.Labels[$label_key] // empty'
}

container_mount_source() {
    local container="$1"
    local destination="$2"
    docker inspect "$container" | jq -r --arg destination "$destination" '
        .[0].Mounts[]
        | select(.Destination == $destination)
        | .Source
    ' | head -1
}

container_network_present() {
    local container="$1"
    local network_name="$2"
    docker inspect "$container" | jq -e --arg network_name "$network_name" '.[0].NetworkSettings.Networks | has($network_name)' >/dev/null 2>&1
}

latest_file_under() {
    local root="$1"

    if [[ ! -d "$root" ]]; then
        return 0
    fi

    find "$root" -type f | sort | tail -1
}

toml_contains_line() {
    local file_path="$1"
    local pattern="$2"
    grep -Eq "$pattern" "$file_path"
}

append_handoff_event() {
    local artifact_file="$1"
    local event_id="$2"
    local correlation_id="$3"
    local severity="$4"
    local handoff_state="$5"
    local status_summary="$6"
    local idempotency_key="$7"
    local duplicate_of="${8:-}"

    jq -nc \
        --arg event_id "$event_id" \
        --arg correlation_id "$correlation_id" \
        --arg severity "$severity" \
        --arg occurred_at "$(timestamp_utc)" \
        --arg handoff_state "$handoff_state" \
        --arg status_summary "$status_summary" \
        --arg idempotency_key "$idempotency_key" \
        --arg duplicate_of "$duplicate_of" \
        '{
            event_id: $event_id,
            event_type: "handoff",
            severity: $severity,
            agent_id: "clawdiy",
            correlation_id: $correlation_id,
            occurred_at: $occurred_at,
            actor: "clawdiy-smoke",
            sender_agent_id: "moltinger",
            recipient_agent_id: "clawdiy",
            handoff_state: $handoff_state,
            status_summary: $status_summary,
            idempotency_key: $idempotency_key,
            duplicate_of: (if $duplicate_of == "" then null else $duplicate_of end),
            payload_ref: null
        }' >>"$artifact_file"
}

write_handoff_smoke_artifact() {
    local audit_root
    audit_root="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw-data/audit")"
    if [[ -z "$audit_root" ]]; then
        add_check "handoff_audit_root" "fail" "Could not resolve Clawdiy audit root from container mount" "error"
        return 1
    fi

    mkdir -p "$audit_root"
    HANDOFF_AUDIT_ARTIFACT="$audit_root/smoke-handoff-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
    : >"$HANDOFF_AUDIT_ARTIFACT"

    local complete_correlation reject_correlation timeout_correlation late_correlation duplicate_correlation
    complete_correlation="11111111-1111-4111-8111-111111111111"
    reject_correlation="22222222-2222-4222-8222-222222222222"
    timeout_correlation="33333333-3333-4333-8333-333333333333"
    duplicate_correlation="44444444-4444-4444-8444-444444444444"
    late_correlation="55555555-5555-4555-8555-555555555555"

    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-complete-submitted" "$complete_correlation" "info" "submitted" "sample handoff submitted" "moltinger-clawdiy-task-20260309-accept"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-complete-accepted" "$complete_correlation" "info" "accepted" "recipient accepted handoff" "moltinger-clawdiy-task-20260309-accept"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-complete-started" "$complete_correlation" "info" "started" "recipient started execution" "moltinger-clawdiy-task-20260309-accept"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-complete-terminal" "$complete_correlation" "info" "completed" "recipient emitted terminal completion" "moltinger-clawdiy-task-20260309-accept"

    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-reject-submitted" "$reject_correlation" "warning" "submitted" "unauthorized capability probe submitted" "moltinger-clawdiy-task-20260309-reject"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-reject-terminal" "$reject_correlation" "warning" "rejected" "recipient rejected unknown capability" "moltinger-clawdiy-task-20260309-reject"

    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-timeout-submitted" "$timeout_correlation" "warning" "submitted" "timeout probe submitted" "moltinger-clawdiy-task-20260309-timeout"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-timeout-terminal" "$timeout_correlation" "warning" "timed_out" "delivery acknowledgement deadline exceeded" "moltinger-clawdiy-task-20260309-timeout"

    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-duplicate-primary" "$duplicate_correlation" "warning" "submitted" "primary submission recorded" "moltinger-clawdiy-task-20260309-duplicate"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-duplicate-secondary" "$duplicate_correlation" "warning" "duplicate" "duplicate idempotency key resolved to prior state" "moltinger-clawdiy-task-20260309-duplicate" "$duplicate_correlation"

    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-late-timeout" "$late_correlation" "critical" "timed_out" "handoff timed out before completion" "moltinger-clawdiy-task-20260309-late"
    append_handoff_event "$HANDOFF_AUDIT_ARTIFACT" "smoke-late-completion" "$late_correlation" "critical" "late_completion" "late completion preserved after timeout for operator review" "moltinger-clawdiy-task-20260309-late"

    add_check "handoff_audit_artifact_written" "pass" "Wrote append-only handoff smoke artifact to $HANDOFF_AUDIT_ARTIFACT" "error"
    return 0
}

verify_handoff_stage() {
    if ! container_exists "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_exists" "fail" "Clawdiy container $CLAWDIY_CONTAINER is missing" "error"
        return 1
    fi

    if ! container_exists "$MOLTIS_CONTAINER"; then
        add_check "moltis_container_exists" "fail" "Moltis container $MOLTIS_CONTAINER is missing" "error"
        return 1
    fi

    if [[ "$(http_code "$CLAWDIY_LOCAL_HEALTH_URL" 10)" == "200" ]]; then
        add_check "clawdiy_local_health" "pass" "Clawdiy local health endpoint returned 200 before handoff probe" "error"
    else
        add_check "clawdiy_local_health" "fail" "Clawdiy local health endpoint did not return 200 before handoff probe" "error"
    fi

    if [[ "$(http_code "$MOLTIS_HEALTH_URL" 10)" == "200" ]]; then
        add_check "moltis_health" "pass" "Moltis health endpoint returned 200 before handoff probe" "error"
    else
        add_check "moltis_health" "fail" "Moltis health endpoint did not return 200 before handoff probe" "error"
    fi

    if [[ -f "$FLEET_REGISTRY_FILE" && -f "$FLEET_POLICY_FILE" && -f "$HANDOFF_SAMPLE_FILE" && -f "$MOLTIS_CONFIG_FILE" ]]; then
        add_check "handoff_contract_inputs" "pass" "Handoff contract inputs exist for registry, policy, sender config, and sample envelope" "error"
    else
        add_check "handoff_contract_inputs" "fail" "Missing registry, policy, sender config, or sample handoff artifact" "error"
        return 1
    fi

    if jq -e '
        .schema_version == "v1"
        and (.sender.agent_id == "moltinger")
        and (.recipient.agent_id == "clawdiy")
        and (.idempotency_key | length > 0)
        and (.correlation_id | length > 0)
      ' "$HANDOFF_SAMPLE_FILE" >/dev/null 2>&1; then
        add_check "handoff_sample_envelope" "pass" "Sample handoff envelope is valid for Moltinger -> Clawdiy contract smoke" "error"
    else
        add_check "handoff_sample_envelope" "fail" "Sample handoff envelope is invalid for Moltinger -> Clawdiy contract smoke" "error"
    fi

    if jq -e --slurpfile policy "$FLEET_POLICY_FILE" '
        ($policy[0].routes[] | select(.caller == "moltinger" and .recipient == "clawdiy")) as $route
        | .agents[] | select(.agent_id == "clawdiy")
        | .endpoint_paths.handoff_submit == $route.endpoint
        and .endpoint_paths.handoff_ack == $route.ack_endpoint
        and .endpoint_paths.handoff_status == $route.status_endpoint
        and .endpoint_paths.handoff_cancel == $route.cancel_endpoint
      ' "$FLEET_REGISTRY_FILE" >/dev/null 2>&1; then
        add_check "clawdiy_control_plane_contract" "pass" "Fleet registry and policy expose the authoritative Clawdiy handoff paths" "error"
    else
        add_check "clawdiy_control_plane_contract" "fail" "Fleet registry and policy diverge on the authoritative Clawdiy handoff paths" "error"
    fi

    if toml_contains_line "$MOLTIS_CONFIG_FILE" '^[[:space:]]*MOLTIS_FLEET_HANDOFF_SUBMIT_PATH[[:space:]]*=[[:space:]]*"/internal/v1/agent-handoffs"' \
        && toml_contains_line "$MOLTIS_CONFIG_FILE" '^[[:space:]]*MOLTIS_FLEET_HANDOFF_ACK_PATH_TEMPLATE[[:space:]]*=[[:space:]]*"/internal/v1/agent-handoffs/\{correlation_id\}/acks"' \
        && toml_contains_line "$MOLTIS_CONFIG_FILE" '^[[:space:]]*MOLTIS_FLEET_HANDOFF_STATUS_PATH_TEMPLATE[[:space:]]*=[[:space:]]*"/internal/v1/agent-handoffs/\{correlation_id\}"' \
        && toml_contains_line "$MOLTIS_CONFIG_FILE" '^[[:space:]]*MOLTIS_FLEET_REQUIRED_ACKS[[:space:]]*=[[:space:]]*"delivery,accept,start,terminal"'; then
        add_check "moltis_handoff_env_contract" "pass" "Moltis config exports sender-side handoff metadata through supported env keys" "error"
    else
        add_check "moltis_handoff_env_contract" "fail" "Moltis config is missing sender-side handoff env metadata" "error"
    fi

    if jq -e --slurpfile policy "$FLEET_POLICY_FILE" '
        ($policy[0].routes[] | select(.caller == "moltinger" and .recipient == "clawdiy")) as $route
        | .agents[] | select(.agent_id == "clawdiy")
        | .endpoint_paths.handoff_submit == $route.endpoint
        and .endpoint_paths.handoff_ack == $route.ack_endpoint
        and .endpoint_paths.handoff_status == $route.status_endpoint
        and .endpoint_paths.handoff_cancel == $route.cancel_endpoint
      ' "$FLEET_REGISTRY_FILE" >/dev/null 2>&1; then
        add_check "handoff_route_alignment" "pass" "Fleet registry and policy routes agree on authoritative handoff endpoints" "error"
    else
        add_check "handoff_route_alignment" "fail" "Fleet registry and policy routes diverge on handoff endpoints" "error"
    fi

    write_handoff_smoke_artifact || return 1

    if jq -s '
        any(.[]; .handoff_state == "completed")
        and any(.[]; .handoff_state == "rejected")
        and any(.[]; .handoff_state == "timed_out")
        and any(.[]; .handoff_state == "duplicate")
        and any(.[]; .handoff_state == "late_completion")
        and all(.[]; .sender_agent_id == "moltinger" and .recipient_agent_id == "clawdiy" and (.correlation_id | length > 0) and (.idempotency_key | length > 0))
      ' "$HANDOFF_AUDIT_ARTIFACT" >/dev/null 2>&1; then
        add_check "handoff_audit_artifact_shape" "pass" "Handoff audit artifact captures completed, rejected, timed-out, duplicate, and late-completion evidence" "error"
    else
        add_check "handoff_audit_artifact_shape" "fail" "Handoff audit artifact is missing required evidence states or correlation metadata" "error"
    fi
}

verify_auth_stage() {
    if [[ ! -f "$CLAWDIY_AUTH_CHECK_SCRIPT" ]]; then
        add_check "auth_check_script_exists" "fail" "Clawdiy auth-check script is missing: $CLAWDIY_AUTH_CHECK_SCRIPT" "error"
        return 1
    fi

    if bash -n "$CLAWDIY_AUTH_CHECK_SCRIPT"; then
        add_check "auth_check_script_syntax" "pass" "Clawdiy auth-check script parses cleanly" "error"
    else
        add_check "auth_check_script_syntax" "fail" "Clawdiy auth-check script has shell syntax errors" "error"
        return 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    local positive_env="$tmpdir/auth-pass.env"
    local missing_telegram_env="$tmpdir/auth-missing-telegram.env"
    local bad_scope_env="$tmpdir/auth-bad-scope.env"
    local positive_profile='{"provider":"codex-oauth","auth_type":"oauth","granted_scopes":["api.responses.write"],"allowed_models":["gpt-5.4"]}'
    local bad_scope_profile='{"provider":"codex-oauth","auth_type":"oauth","granted_scopes":["profile.read"],"allowed_models":["gpt-5.4"]}'

    {
        printf '%s\n' 'CLAWDIY_PASSWORD=test-human-password'
        printf '%s\n' 'CLAWDIY_SERVICE_TOKEN=test-service-token'
        printf '%s\n' 'CLAWDIY_TELEGRAM_BOT_TOKEN=test-clawdiy-telegram-token'
        printf '%s\n' 'CLAWDIY_TELEGRAM_ALLOWED_USERS=user42,user99'
        printf 'CLAWDIY_OPENAI_CODEX_AUTH_PROFILE=%s\n' "$positive_profile"
    } >"$positive_env"

    {
        printf '%s\n' 'CLAWDIY_PASSWORD=test-human-password'
        printf '%s\n' 'CLAWDIY_SERVICE_TOKEN=test-service-token'
        printf '%s\n' 'CLAWDIY_TELEGRAM_ALLOWED_USERS=user42,user99'
        printf 'CLAWDIY_OPENAI_CODEX_AUTH_PROFILE=%s\n' "$positive_profile"
    } >"$missing_telegram_env"

    {
        printf '%s\n' 'CLAWDIY_PASSWORD=test-human-password'
        printf '%s\n' 'CLAWDIY_SERVICE_TOKEN=test-service-token'
        printf '%s\n' 'CLAWDIY_TELEGRAM_BOT_TOKEN=test-clawdiy-telegram-token'
        printf '%s\n' 'CLAWDIY_TELEGRAM_ALLOWED_USERS=user42,user99'
        printf 'CLAWDIY_OPENAI_CODEX_AUTH_PROFILE=%s\n' "$bad_scope_profile"
    } >"$bad_scope_env"

    if "$CLAWDIY_AUTH_CHECK_SCRIPT" --provider telegram --env-file "$positive_env" --json >"$tmpdir/telegram-pass.json"; then
        if jq -e '.status == "pass" and any(.capabilities[]; .capability == "telegram" and .status == "pass")' "$tmpdir/telegram-pass.json" >/dev/null 2>&1; then
            add_check "auth_smoke_telegram_pass" "pass" "Telegram repeat-auth validation passes with isolated test credentials" "error"
        else
            add_check "auth_smoke_telegram_pass" "fail" "Telegram repeat-auth validation did not report a passing capability state" "error"
        fi
    else
        add_check "auth_smoke_telegram_pass" "fail" "Telegram repeat-auth validation should pass with isolated test credentials" "error"
    fi

    set +e
    "$CLAWDIY_AUTH_CHECK_SCRIPT" --provider telegram --env-file "$missing_telegram_env" --json >"$tmpdir/telegram-fail.json"
    local telegram_fail_code=$?
    set -e
    if [[ $telegram_fail_code -ne 0 ]] && jq -e '.status == "fail" and ([.errors[] | test("repeat-auth"; "i")] | any)' "$tmpdir/telegram-fail.json" >/dev/null 2>&1; then
        add_check "auth_smoke_telegram_fail_closed" "pass" "Missing Telegram token fails closed with repeat-auth guidance" "error"
    else
        add_check "auth_smoke_telegram_fail_closed" "fail" "Missing Telegram token must fail closed with repeat-auth guidance" "error"
    fi

    if "$CLAWDIY_AUTH_CHECK_SCRIPT" --provider codex-oauth --env-file "$positive_env" --json >"$tmpdir/provider-pass.json"; then
        if jq -e '.status == "pass" and any(.capabilities[]; .capability == "codex-oauth" and .status == "pass")' "$tmpdir/provider-pass.json" >/dev/null 2>&1; then
            add_check "auth_smoke_provider_pass" "pass" "OpenAI Codex auth validation passes with required scope and model authorization" "error"
        else
            add_check "auth_smoke_provider_pass" "fail" "OpenAI Codex auth validation did not report a passing capability state" "error"
        fi
    else
        add_check "auth_smoke_provider_pass" "fail" "OpenAI Codex auth validation should pass with required scope and model authorization" "error"
    fi

    set +e
    "$CLAWDIY_AUTH_CHECK_SCRIPT" --provider codex-oauth --env-file "$bad_scope_env" --json >"$tmpdir/provider-fail.json"
    local provider_fail_code=$?
    set -e
    if [[ $provider_fail_code -ne 0 ]] && jq -e '.status == "fail" and ([.errors[] | test("quarantined|quarantine|repeat-auth"; "i")] | any)' "$tmpdir/provider-fail.json" >/dev/null 2>&1; then
        add_check "auth_smoke_provider_fail_closed" "pass" "Bad provider scopes fail closed and keep the capability quarantined" "error"
    else
        add_check "auth_smoke_provider_fail_closed" "fail" "Bad provider scopes must fail closed and quarantine the capability" "error"
    fi
}

verify_rollback_evidence_stage() {
    local audit_root="$CLAWDIY_LOCAL_AUDIT_ROOT"
    local rollback_manifest=""
    local backup_reference=""

    if [[ -d "$audit_root" ]]; then
        add_check "rollback_audit_root_exists" "pass" "Clawdiy audit root exists for rollback evidence review: $audit_root" "error"
    else
        add_check "rollback_audit_root_exists" "fail" "Clawdiy audit root is missing: $audit_root" "error"
        return 1
    fi

    rollback_manifest="$(latest_file_under "$audit_root/rollback-evidence")"
    if [[ -n "$rollback_manifest" && -f "$rollback_manifest" ]]; then
        add_check "rollback_manifest_exists" "pass" "Found latest Clawdiy rollback evidence manifest: $rollback_manifest" "error"
    else
        add_check "rollback_manifest_exists" "fail" "No Clawdiy rollback evidence manifest found under $audit_root/rollback-evidence" "error"
        return 1
    fi

    if jq -e '
        .schema_version == "v1"
        and .target == "clawdiy"
        and (.rollback_reason | type == "string" and length > 0)
        and (.pre_rollback_image | type == "string")
        and (.audit_root | type == "string" and length > 0)
        and (.audit_file_count_before | type == "number")
        and (.audit_file_count_after | type == "number")
        and (.moltis_health_http_code == 200)
        and (.resulting_mode == "rolled_back" or .resulting_mode == "disabled")
        and (.status == "completed")
      ' "$rollback_manifest" >/dev/null 2>&1; then
        add_check "rollback_manifest_shape" "pass" "Clawdiy rollback evidence manifest includes reason, audit counts, Moltis health, and resulting mode" "error"
    else
        add_check "rollback_manifest_shape" "fail" "Clawdiy rollback evidence manifest is missing required rollback metadata" "error"
    fi

    backup_reference="$(jq -r '.backup_reference // empty' "$rollback_manifest")"
    if [[ -n "$backup_reference" && -f "$backup_reference" ]]; then
        add_check "rollback_backup_reference" "pass" "Rollback evidence references an existing backup archive: $backup_reference" "error"
    else
        add_check "rollback_backup_reference" "fail" "Rollback evidence must reference an existing backup archive for restore readiness" "error"
    fi

    if [[ "$(http_code "$MOLTIS_HEALTH_URL" 10)" == "200" ]]; then
        add_check "rollback_moltis_health" "pass" "Moltis health endpoint remained 200 during rollback evidence review" "error"
    else
        add_check "rollback_moltis_health" "fail" "Moltis health endpoint did not return 200 during rollback evidence review" "error"
    fi
}

verify_extraction_readiness_stage() {
    if [[ -f "$FLEET_REGISTRY_FILE" && -f "$FLEET_POLICY_FILE" && -f "$CLAWDIY_CONFIG_FILE" ]]; then
        add_check "extraction_contract_inputs" "pass" "Registry, policy, and Clawdiy runtime config exist for extraction-readiness checks" "error"
    else
        add_check "extraction_contract_inputs" "fail" "Missing registry, policy, or Clawdiy runtime config for extraction-readiness checks" "error"
        return 1
    fi

    if jq -e '
        def host:
            tostring
            | sub("^https?://"; "")
            | split("/")[0]
            | ascii_downcase;
        (.agents[] | select(.agent_id == "clawdiy")) as $cl
        | .topology_profiles.same_host.transport == "http-json"
        and .topology_profiles.remote_node.transport == "http-json"
        and .topology_profiles.same_host.network_plane == "fleet-internal"
        and .topology_profiles.remote_node.network_plane == "private-overlay"
        and $cl.logical_address == "agent://clawdiy"
        and $cl.topology.active_profile == "same_host"
        and (($cl.topology.supported_profiles | index("same_host")) != null)
        and (($cl.topology.supported_profiles | index("remote_node")) != null)
        and $cl.topology.placement_profiles.same_host.internal_endpoint == $cl.internal_endpoint
        and ($cl.topology.placement_profiles.same_host.internal_endpoint | host) != ($cl.topology.placement_profiles.remote_node.internal_endpoint | host)
        and ($cl.topology.placement_profiles.remote_node.internal_endpoint | endswith("/internal/v1"))
        and ($cl.topology.placement_profiles.remote_node.health_endpoint | endswith("/health"))
        and ($cl.topology.placement_profiles.remote_node.metrics_endpoint | endswith("/metrics"))
      ' "$FLEET_REGISTRY_FILE" >/dev/null 2>&1; then
        add_check "extraction_topology_profiles" "pass" "Clawdiy registry preserves logical address and route placement invariants across same_host and remote_node profiles" "error"
    else
        add_check "extraction_topology_profiles" "fail" "Clawdiy registry is missing a stable same_host/remote_node extraction contract" "error"
    fi

    if jq -e --slurpfile runtime "$CLAWDIY_CONFIG_FILE" --slurpfile registry "$FLEET_REGISTRY_FILE" '
        ($runtime[0]) as $rt
        | ($registry[0].agents[] | select(.agent_id == "clawdiy")) as $cl
        | .gateway.controlUi.allowedOrigins[0] == $cl.public_endpoints.web
        and (.agents.list | any(.id == "main" and .identity.name == $cl.display_name))
      ' "$CLAWDIY_CONFIG_FILE" >/dev/null 2>&1; then
        add_check "extraction_runtime_alignment" "pass" "Clawdiy runtime control UI origin and main agent identity stay aligned with the fleet registry" "error"
    else
        add_check "extraction_runtime_alignment" "fail" "Clawdiy runtime control UI origin or main agent identity diverges from the fleet registry" "error"
    fi

    if jq -e --slurpfile policy "$FLEET_POLICY_FILE" '
        ($policy[0].routes[] | select(.caller == "moltinger" and .recipient == "clawdiy")) as $route
        | (.agents[] | select(.agent_id == "clawdiy")) as $cl
        | ($cl.endpoint_paths.handoff_submit == $cl.topology.route_invariants.handoff_submit_path)
        and ($cl.endpoint_paths.handoff_ack == $cl.topology.route_invariants.handoff_ack_path)
        and ($cl.endpoint_paths.handoff_status == $cl.topology.route_invariants.handoff_status_path)
        and ($cl.endpoint_paths.handoff_cancel == $cl.topology.route_invariants.handoff_cancel_path)
        and ($cl.topology.route_invariants.handoff_submit_path == $route.endpoint)
        and ($cl.topology.route_invariants.handoff_ack_path == $route.ack_endpoint)
        and ($cl.topology.route_invariants.handoff_status_path == $route.status_endpoint)
        and ($cl.topology.route_invariants.handoff_cancel_path == $route.cancel_endpoint)
      ' "$FLEET_REGISTRY_FILE" >/dev/null 2>&1; then
        add_check "extraction_handoff_invariants" "pass" "Clawdiy handoff submit, ack, status, and cancel paths remain stable for future-node extraction" "error"
    else
        add_check "extraction_handoff_invariants" "fail" "Clawdiy handoff path invariants are not stable across the extraction contract" "error"
    fi

    if jq -e --slurpfile registry "$FLEET_REGISTRY_FILE" '
        [.future_role_examples[].role] as $roles
        | ($roles | index("architect")) != null
        and ($roles | index("tester")) != null
        and ($roles | index("researcher")) != null
        and all(.future_role_examples[]; .logical_address_template == "agent://{agent_id}" and (.supported_topology_profiles | index("same_host")) != null and (.supported_topology_profiles | index("remote_node")) != null and .private_machine_transport_only == true)
      ' "$FLEET_REGISTRY_FILE" >/dev/null 2>&1; then
        add_check "extraction_future_roles" "pass" "Fleet registry includes architect, tester, and researcher examples using the same logical-address and topology contract" "error"
    else
        add_check "extraction_future_roles" "fail" "Fleet registry is missing future permanent-role examples for architect, tester, and researcher" "error"
    fi

    if jq -e '
        .topology_profiles.same_host.transport == "http-json"
        and .topology_profiles.remote_node.transport == "http-json"
        and .topology_profiles.same_host.allow_public_machine_handoffs == false
        and .topology_profiles.remote_node.allow_public_machine_handoffs == false
        and .topology_profiles.remote_node.requires_private_connectivity == true
        and any(.routes[]; .caller == "moltinger" and .recipient == "clawdiy" and (.supported_topology_profiles | index("remote_node")) != null)
        and any(.routes[]; .caller == "clawdiy" and .recipient == "moltinger" and (.supported_topology_profiles | index("remote_node")) != null)
        and all(.future_role_defaults[]; (.supported_topology_profiles | index("same_host")) != null and (.supported_topology_profiles | index("remote_node")) != null and .transport == "http-json" and .private_machine_handoffs_only == true)
      ' "$FLEET_POLICY_FILE" >/dev/null 2>&1; then
        add_check "extraction_policy_contract" "pass" "Fleet policy keeps remote-node handoffs private, fail-closed, and reusable for future permanent roles" "error"
    else
        add_check "extraction_policy_contract" "fail" "Fleet policy does not preserve the private remote-node contract for Clawdiy extraction and future roles" "error"
    fi
}

verify_same_host_stage() {
    if container_exists "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_exists" "pass" "Clawdiy container $CLAWDIY_CONTAINER exists" "error"
    else
        add_check "clawdiy_container_exists" "fail" "Clawdiy container $CLAWDIY_CONTAINER is missing" "error"
        return 1
    fi

    if container_running "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_running" "pass" "Clawdiy container $CLAWDIY_CONTAINER is running" "error"
    else
        add_check "clawdiy_container_running" "fail" "Clawdiy container $CLAWDIY_CONTAINER is not running" "error"
    fi

    local clawdiy_health
    clawdiy_health="$(container_health "$CLAWDIY_CONTAINER")"
    if [[ "$clawdiy_health" == "healthy" || "$clawdiy_health" == "none" ]]; then
        add_check "clawdiy_container_health" "pass" "Clawdiy container health is $clawdiy_health" "error"
    else
        add_check "clawdiy_container_health" "fail" "Clawdiy container health is $clawdiy_health" "error"
    fi

    if wait_for_http_200 "$CLAWDIY_LOCAL_HEALTH_URL" "$TIMEOUT_SECONDS"; then
        add_check "clawdiy_local_health" "pass" "Clawdiy local health endpoint returned 200: $CLAWDIY_LOCAL_HEALTH_URL" "error"
    else
        add_check "clawdiy_local_health" "fail" "Clawdiy local health endpoint did not return 200: $CLAWDIY_LOCAL_HEALTH_URL" "error"
    fi

    if [[ "$(http_code "$CLAWDIY_LOCAL_METRICS_URL" 10)" == "200" ]]; then
        add_check "clawdiy_local_metrics" "pass" "Clawdiy local metrics endpoint returned 200: $CLAWDIY_LOCAL_METRICS_URL" "error"
    else
        add_check "clawdiy_local_metrics" "fail" "Clawdiy local metrics endpoint did not return 200: $CLAWDIY_LOCAL_METRICS_URL" "error"
    fi

    if [[ "$(http_code "$CLAWDIY_PUBLIC_HEALTH_URL" 15)" == "200" ]]; then
        add_check "clawdiy_public_health" "pass" "Clawdiy public health endpoint returned 200: $CLAWDIY_PUBLIC_HEALTH_URL" "error"
    else
        add_check "clawdiy_public_health" "fail" "Clawdiy public health endpoint did not return 200: $CLAWDIY_PUBLIC_HEALTH_URL" "error"
    fi

    if [[ "$(http_code "$MOLTIS_HEALTH_URL" 10)" == "200" ]]; then
        add_check "moltis_health_unchanged" "pass" "Moltis health endpoint remained 200: $MOLTIS_HEALTH_URL" "error"
    else
        add_check "moltis_health_unchanged" "fail" "Moltis health endpoint did not return 200: $MOLTIS_HEALTH_URL" "error"
    fi

    local config_source registry_source state_source audit_source
    config_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw/openclaw.json")"
    registry_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw/registry")"
    state_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw-data/state")"
    audit_source="$(container_mount_source "$CLAWDIY_CONTAINER" "/home/node/.openclaw-data/audit")"

    if [[ "$config_source" == */data/clawdiy/runtime/openclaw.json && "$registry_source" == */config/fleet && "$state_source" == */data/clawdiy/state && "$audit_source" == */data/clawdiy/audit ]]; then
        add_check "clawdiy_mounts" "pass" "Clawdiy mounts are isolated for config, registry, state, and audit roots" "error"
    else
        add_check "clawdiy_mounts" "fail" "Clawdiy mounts are not wired to the expected isolated roots" "error"
    fi

    if [[ "$state_source" != "$audit_source" && "$config_source" != "$registry_source" ]]; then
        add_check "clawdiy_mounts_distinct" "pass" "Clawdiy persistent and control-plane mounts remain distinct" "error"
    else
        add_check "clawdiy_mounts_distinct" "fail" "Clawdiy mounts unexpectedly collapse onto shared paths" "error"
    fi

    local missing_networks=()
    local network_name
    for network_name in "$TRAEFIK_NETWORK" "$FLEET_INTERNAL_NETWORK" "$MONITORING_NETWORK"; do
        if ! container_network_present "$CLAWDIY_CONTAINER" "$network_name"; then
            missing_networks+=("$network_name")
        fi
    done

    if [[ ${#missing_networks[@]} -eq 0 ]]; then
        add_check "clawdiy_networks" "pass" "Clawdiy is attached to $TRAEFIK_NETWORK, $FLEET_INTERNAL_NETWORK, and $MONITORING_NETWORK" "error"
    else
        add_check "clawdiy_networks" "fail" "Clawdiy is missing expected networks: ${missing_networks[*]}" "error"
    fi

    local traefik_rule
    traefik_rule="$(container_label "$CLAWDIY_CONTAINER" "traefik.http.routers.clawdiy.rule")"
    if [[ "$traefik_rule" == *"clawdiy.ainetic.tech"* ]]; then
        add_check "clawdiy_traefik_rule" "pass" "Clawdiy Traefik router label targets clawdiy.ainetic.tech" "error"
    else
        add_check "clawdiy_traefik_rule" "fail" "Clawdiy Traefik router label is missing or misconfigured" "error"
    fi
}

verify_restart_isolation_stage() {
    if ! container_exists "$CLAWDIY_CONTAINER"; then
        add_check "clawdiy_container_exists" "fail" "Clawdiy container $CLAWDIY_CONTAINER is missing" "error"
        return 1
    fi

    if ! container_exists "$MOLTIS_CONTAINER"; then
        add_check "moltis_container_exists" "fail" "Moltis container $MOLTIS_CONTAINER is missing" "error"
        return 1
    fi

    local moltis_id_before moltis_started_before
    moltis_id_before="$(docker inspect --format '{{.Id}}' "$MOLTIS_CONTAINER")"
    moltis_started_before="$(docker inspect --format '{{.State.StartedAt}}' "$MOLTIS_CONTAINER")"
    add_check "restart_capture_baseline" "pass" "Captured Moltis baseline before Clawdiy restart" "error"

    docker restart "$CLAWDIY_CONTAINER" >/dev/null
    add_check "clawdiy_restart_invoked" "pass" "Restarted Clawdiy container $CLAWDIY_CONTAINER" "error"

    if wait_for_http_200 "$CLAWDIY_LOCAL_HEALTH_URL" "$TIMEOUT_SECONDS"; then
        add_check "clawdiy_restart_health" "pass" "Clawdiy returned healthy after restart" "error"
    else
        add_check "clawdiy_restart_health" "fail" "Clawdiy did not become healthy after restart" "error"
    fi

    local moltis_id_after moltis_started_after
    moltis_id_after="$(docker inspect --format '{{.Id}}' "$MOLTIS_CONTAINER")"
    moltis_started_after="$(docker inspect --format '{{.State.StartedAt}}' "$MOLTIS_CONTAINER")"

    if [[ "$moltis_id_before" == "$moltis_id_after" && "$moltis_started_before" == "$moltis_started_after" ]]; then
        add_check "moltis_restart_isolation" "pass" "Moltis container identity and start time did not change during Clawdiy restart" "error"
    else
        add_check "moltis_restart_isolation" "fail" "Moltis container changed during Clawdiy restart" "error"
    fi

    if [[ "$(http_code "$MOLTIS_HEALTH_URL" 10)" == "200" ]]; then
        add_check "moltis_health_after_restart" "pass" "Moltis health endpoint remained 200 after Clawdiy restart" "error"
    else
        add_check "moltis_health_after_restart" "fail" "Moltis health endpoint did not return 200 after Clawdiy restart" "error"
    fi
}

show_help() {
    cat <<EOF
Usage: $0 [--stage same-host|restart-isolation|handoff|auth|rollback-evidence|extraction-readiness] [--json] [--timeout seconds]

Options:
  --stage <name>      Verification stage to run (default: same-host). Supported: same-host, restart-isolation, handoff, auth, rollback-evidence, extraction-readiness
  --json              Emit JSON instead of human-readable logs
  --timeout <sec>     Wait timeout for health checks (default: ${TIMEOUT_SECONDS})
  --no-color          Disable colorized logs
  -h, --help          Show this help text
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stage)
                STAGE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
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

main() {
    parse_args "$@"
    disable_colors

    require_commands || {
        output_json_result "fail"
        exit 1
    }

    load_runtime_config || {
        output_json_result "fail"
        exit 1
    }

    case "$STAGE" in
        same-host)
            verify_same_host_stage
            ;;
        restart-isolation)
            verify_restart_isolation_stage
            ;;
        handoff)
            verify_handoff_stage
            ;;
        auth)
            verify_auth_stage
            ;;
        rollback-evidence)
            verify_rollback_evidence_stage
            ;;
        extraction-readiness)
            verify_extraction_readiness_stage
            ;;
        *)
            add_check "stage" "fail" "Unsupported Clawdiy smoke stage: $STAGE" "error"
            ;;
    esac

    local final_status="pass"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        final_status="fail"
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        final_status="warning"
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json_result "$final_status"
    fi

    [[ "$final_status" == "fail" ]] && exit 1
    exit 0
}

main "$@"
