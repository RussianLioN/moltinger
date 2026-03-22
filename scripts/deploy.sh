#!/bin/bash
# Multi-target deployment script for Moltinger platform agents
# Version: 2.3
# Features: target-aware deploy, health checks, rollback, notifications, GitOps guards
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# ========================================================================
# GITOPS GUARDS
# ========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/gitops-guards.sh" ]]; then
    source "$SCRIPT_DIR/gitops-guards.sh"
fi

# ========================================================================
# GLOBAL CONFIGURATION
# ========================================================================
DEFAULT_TARGET="moltis"
TARGET="$DEFAULT_TARGET"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-traefik-net}"
FLEET_INTERNAL_NETWORK="${FLEET_INTERNAL_NETWORK:-fleet-internal}"
MONITORING_NETWORK="${MONITORING_NETWORK:-moltinger_monitoring}"
CLAWDIY_RUNTIME_UID="${CLAWDIY_RUNTIME_UID:-1000}"
CLAWDIY_RUNTIME_GID="${CLAWDIY_RUNTIME_GID:-1000}"
MOLTIS_SERVICE_UID="${MOLTIS_SERVICE_UID:-1000}"
MOLTIS_SERVICE_GID="${MOLTIS_SERVICE_GID:-1000}"
CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR="${CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}"
MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="${MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"

HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
ROLLBACK_ENABLED="${ROLLBACK_ENABLED:-true}"

OUTPUT_JSON=false
NO_COLOR=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -a JSON_ERRORS=()
declare -a JSON_SERVICES=()

DEPLOY_START_TIME=0
DEPLOY_ACTION=""
DEPLOY_IMAGE=""
DEPLOY_RESTORE_CHECK_FILE=""

# Target-specific state
TARGET_DISPLAY=""
COMPOSE_FILE=""
ENV_FILE=""
TARGET_CONTAINER=""
TARGET_SERVICE=""
TARGET_HEALTH_URL=""
TARGET_METRICS_URL=""
TARGET_LAST_IMAGE_FILE=""
TARGET_LAST_BACKUP_FILE=""
TARGET_LAST_RESTORE_CHECK_FILE=""
TARGET_NOTIFICATION_NAME=""
TARGET_REQUIRED_NETWORKS=()
TARGET_AUXILIARY_SERVICES=()
TARGET_HEALTH_TIMEOUT="$HEALTH_CHECK_TIMEOUT"
CLAWDIY_CONFIG_FILE="$PROJECT_ROOT/config/clawdiy/openclaw.json"
CLAWDIY_RENDERED_CONFIG_FILE="$PROJECT_ROOT/data/clawdiy/runtime/openclaw.json"
CLAWDIY_RUNTIME_RENDER_SCRIPT="$PROJECT_ROOT/scripts/render-clawdiy-runtime-config.sh"
MOLTIS_KNOWLEDGE_SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-moltis-project-knowledge.sh"
DEFAULT_CLAWDIY_IMAGE="ghcr.io/openclaw/openclaw:2026.3.11"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh"
MOLTIS_VERSION_HELPER="$PROJECT_ROOT/scripts/moltis-version.sh"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/moltis}"
DEPLOY_EVIDENCE_FILE=""
ROLLBACK_REASON="${ROLLBACK_REASON:-unspecified}"
CLAWDIY_HEALTH_CHECK_TIMEOUT="${CLAWDIY_HEALTH_CHECK_TIMEOUT:-420}"
DEPLOY_MUTEX_ENABLED="${DEPLOY_MUTEX_ENABLED:-true}"
DEPLOY_MUTEX_PATH="${DEPLOY_MUTEX_PATH:-/var/lock/moltinger/deploy.lock}"
DEPLOY_MUTEX_WAIT_SECONDS="${DEPLOY_MUTEX_WAIT_SECONDS:-3600}"
DEPLOY_MUTEX_TTL_SECONDS="${DEPLOY_MUTEX_TTL_SECONDS:-5400}"
DEPLOY_MUTEX_POLL_SECONDS="${DEPLOY_MUTEX_POLL_SECONDS:-5}"
DEPLOY_MUTEX_OWNER="${DEPLOY_MUTEX_OWNER:-}"

DEPLOY_LOCK_MODE=""
DEPLOY_LOCK_FD=""
DEPLOY_LOCK_DIR=""
DEPLOY_LOCK_META_PATH=""
DEPLOY_LOCK_OWNER=""

# ========================================================================
# UTILITY FUNCTIONS
# ========================================================================

lock_command_mutates_state() {
    local command="$1"
    case "$command" in
        deploy|rollback|start|stop|restart)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

lock_meta_value() {
    local file="$1"
    local key="$2"

    if [[ ! -r "$file" ]]; then
        return 1
    fi

    awk -F= -v key="$key" '$1 == key { sub($1 FS, ""); print; exit }' "$file"
}

write_deploy_lock_metadata() {
    local metadata_path="$1"
    local lock_command="$2"
    local now_epoch="$3"
    local lock_host

    lock_host="$(hostname 2>/dev/null || uname -n)"
    cat > "$metadata_path" <<EOF
owner=$DEPLOY_LOCK_OWNER
target=$TARGET
command=$lock_command
host=$lock_host
pid=$$
created_at=$now_epoch
expires_at=$((now_epoch + DEPLOY_MUTEX_TTL_SECONDS))
EOF
}

acquire_deploy_mutex() {
    local lock_command="$1"
    local lock_parent start_epoch now_epoch waited_seconds expires_at current_owner

    if [[ "$DEPLOY_MUTEX_ENABLED" != "true" ]]; then
        return 0
    fi

    lock_parent="$(dirname "$DEPLOY_MUTEX_PATH")"
    mkdir -p "$lock_parent"

    DEPLOY_LOCK_OWNER="${DEPLOY_MUTEX_OWNER:-gha:${GITHUB_REPOSITORY:-local}:${GITHUB_RUN_ID:-manual}:${GITHUB_RUN_ATTEMPT:-0}:${TARGET}:${lock_command}:pid-$$}"

    if command -v flock >/dev/null 2>&1; then
        exec {DEPLOY_LOCK_FD}>"$DEPLOY_MUTEX_PATH"
        if ! flock -w "$DEPLOY_MUTEX_WAIT_SECONDS" "$DEPLOY_LOCK_FD"; then
            log_error "Timed out waiting for deploy mutex: $DEPLOY_MUTEX_PATH"
            exit 1
        fi

        DEPLOY_LOCK_MODE="flock"
        DEPLOY_LOCK_META_PATH="${DEPLOY_MUTEX_PATH}.meta"
        now_epoch="$(date +%s)"
        write_deploy_lock_metadata "$DEPLOY_LOCK_META_PATH" "$lock_command" "$now_epoch"
        log_info "Acquired deploy mutex ($DEPLOY_LOCK_MODE): $DEPLOY_MUTEX_PATH owner=$DEPLOY_LOCK_OWNER"
        return 0
    fi

    DEPLOY_LOCK_MODE="mkdir"
    DEPLOY_LOCK_DIR="${DEPLOY_MUTEX_PATH}.d"
    DEPLOY_LOCK_META_PATH="${DEPLOY_LOCK_DIR}/meta"

    start_epoch="$(date +%s)"
    while true; do
        now_epoch="$(date +%s)"

        if mkdir "$DEPLOY_LOCK_DIR" 2>/dev/null; then
            write_deploy_lock_metadata "$DEPLOY_LOCK_META_PATH" "$lock_command" "$now_epoch"
            log_info "Acquired deploy mutex ($DEPLOY_LOCK_MODE): $DEPLOY_LOCK_DIR owner=$DEPLOY_LOCK_OWNER"
            return 0
        fi

        expires_at="$(lock_meta_value "$DEPLOY_LOCK_META_PATH" "expires_at" || true)"
        if [[ "$expires_at" =~ ^[0-9]+$ ]] && (( now_epoch >= expires_at )); then
            current_owner="$(lock_meta_value "$DEPLOY_LOCK_META_PATH" "owner" || true)"
            log_warn "Removing stale deploy mutex owned by ${current_owner:-unknown}: $DEPLOY_LOCK_DIR"
            rm -rf "$DEPLOY_LOCK_DIR" 2>/dev/null || true
            continue
        fi

        waited_seconds=$((now_epoch - start_epoch))
        if (( waited_seconds >= DEPLOY_MUTEX_WAIT_SECONDS )); then
            current_owner="$(lock_meta_value "$DEPLOY_LOCK_META_PATH" "owner" || true)"
            log_error "Timed out waiting for deploy mutex owner=${current_owner:-unknown}: $DEPLOY_LOCK_DIR"
            exit 1
        fi

        sleep "$DEPLOY_MUTEX_POLL_SECONDS"
    done
}

release_deploy_mutex() {
    local current_owner

    if [[ "$DEPLOY_MUTEX_ENABLED" != "true" ]]; then
        return 0
    fi

    case "$DEPLOY_LOCK_MODE" in
        flock)
            rm -f "$DEPLOY_LOCK_META_PATH" 2>/dev/null || true
            if [[ -n "$DEPLOY_LOCK_FD" ]]; then
                flock -u "$DEPLOY_LOCK_FD" 2>/dev/null || true
                eval "exec ${DEPLOY_LOCK_FD}>&-"
                DEPLOY_LOCK_FD=""
            fi
            ;;
        mkdir)
            if [[ -n "$DEPLOY_LOCK_DIR" ]]; then
                current_owner="$(lock_meta_value "$DEPLOY_LOCK_META_PATH" "owner" || true)"
                if [[ -z "$current_owner" || "$current_owner" == "$DEPLOY_LOCK_OWNER" ]]; then
                    rm -rf "$DEPLOY_LOCK_DIR" 2>/dev/null || true
                else
                    log_warn "Skipping deploy mutex release; ownership changed to ${current_owner}"
                fi
            fi
            ;;
        *)
            ;;
    esac

    DEPLOY_LOCK_MODE=""
    DEPLOY_LOCK_DIR=""
    DEPLOY_LOCK_META_PATH=""
    DEPLOY_LOCK_OWNER=""
}

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
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        return
    fi

    case "$level" in
        INFO) echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" ;;
    esac
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; JSON_ERRORS+=("$1"); }
log_success() { log "SUCCESS" "$@"; }

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

output_json_result() {
    local status="$1"
    local action="$2"
    local health="$3"
    local duration_ms=0
    local services_json="[]"
    local errors_json="[]"
    local details="{}"
    local evidence_file_json="null"

    if [[ $DEPLOY_START_TIME -gt 0 ]]; then
        duration_ms=$(( ($(date +%s) - DEPLOY_START_TIME) * 1000 ))
    fi

    if [[ ${#JSON_SERVICES[@]} -gt 0 ]]; then
        services_json=$(printf '%s\n' "${JSON_SERVICES[@]}" | jq -s '.')
    fi

    if [[ ${#JSON_ERRORS[@]} -gt 0 ]]; then
        errors_json=$(printf '%s\n' "${JSON_ERRORS[@]}" | jq -R '{code: "DEPLOY_ERROR", message: .}' | jq -s '.')
    fi

    if [[ -n "$DEPLOY_IMAGE" ]]; then
        details=$(jq -n \
            --arg image "$DEPLOY_IMAGE" \
            --argjson duration "$duration_ms" \
            --arg health "$health" \
            --arg evidence_file "$DEPLOY_EVIDENCE_FILE" \
            --arg restore_check_file "$DEPLOY_RESTORE_CHECK_FILE" \
            --argjson services "$services_json" \
            '{image: $image, duration_ms: $duration, health: $health, services: $services, rollback_evidence_file: (if $evidence_file == "" then null else $evidence_file end), restore_check_file: (if $restore_check_file == "" then null else $restore_check_file end)}')
    fi

    jq -n \
        --arg status "$status" \
        --arg timestamp "$(get_timestamp)" \
        --arg action "$action" \
        --arg target "$TARGET" \
        --argjson details "$details" \
        --argjson errors "$errors_json" \
        '{
            status: $status,
            target: $target,
            timestamp: $timestamp,
            action: $action,
            details: $details,
            errors: $errors
        }'
}

read_env_file_value() {
    local key="$1"

    if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
        return 1
    fi

    local value
    value=$(grep -E "^${key}=" "$ENV_FILE" | tail -1 | cut -d'=' -f2- || true)
    value="${value%\"}"
    value="${value#\"}"

    if [[ -z "$value" ]]; then
        return 1
    fi

    printf '%s' "$value"
}

canonicalize_existing_path() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi

    if [[ -d "$path" ]]; then
        (cd "$path" && pwd -P)
        return 0
    fi

    if [[ -e "$path" ]]; then
        local parent base
        parent="$(dirname "$path")"
        base="$(basename "$path")"
        printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
        return 0
    fi

    return 1
}

normalize_runtime_config_path() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi

    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done

    printf '%s' "$path"
}

runtime_config_dir_allowed() {
    local candidate="$1"
    local normalized_candidate normalized_allowlist entry
    normalized_candidate="$(normalize_runtime_config_path "$candidate" || true)"
    [[ -n "$normalized_candidate" ]] || return 1

    local old_ifs="$IFS"
    IFS=':'
    for entry in $MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST; do
        normalized_allowlist="$(normalize_runtime_config_path "$entry" || true)"
        if [[ -n "$normalized_allowlist" && "$normalized_candidate" == "$normalized_allowlist" ]]; then
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"

    return 1
}

container_mount_source() {
    local container="$1"
    local destination="$2"

    docker inspect "$container" 2>/dev/null | \
        jq -r --arg destination "$destination" '.[0].Mounts[]? | select(.Destination == $destination) | .Source' | \
        head -n 1
}

container_mount_rw() {
    local container="$1"
    local destination="$2"

    docker inspect "$container" 2>/dev/null | \
        jq -r --arg destination "$destination" '.[0].Mounts[]? | select(.Destination == $destination) | .RW' | \
        head -n 1
}

tracked_moltis_version() {
    if [[ ! -x "$MOLTIS_VERSION_HELPER" ]]; then
        log_error "Moltis version helper is missing or not executable: $MOLTIS_VERSION_HELPER"
        exit 2
    fi

    "$MOLTIS_VERSION_HELPER" version
}

tracked_moltis_image_ref() {
    if [[ ! -x "$MOLTIS_VERSION_HELPER" ]]; then
        log_error "Moltis version helper is missing or not executable: $MOLTIS_VERSION_HELPER"
        exit 2
    fi

    "$MOLTIS_VERSION_HELPER" image
}

assert_tracked_moltis_contract() {
    if [[ ! -x "$MOLTIS_VERSION_HELPER" ]]; then
        log_error "Moltis version helper is missing or not executable: $MOLTIS_VERSION_HELPER"
        exit 2
    fi

    "$MOLTIS_VERSION_HELPER" assert-tracked >/dev/null
}

enforce_moltis_git_tracked_version() {
    local action="$1"
    local tracked_version env_file_version=""

    if [[ "$TARGET" != "moltis" ]]; then
        return 0
    fi

    assert_tracked_moltis_contract
    tracked_version="$(tracked_moltis_version)"

    if read_env_file_value "MOLTIS_VERSION" >/dev/null 2>&1; then
        env_file_version="$(read_env_file_value "MOLTIS_VERSION")"
        if [[ "${ALLOW_MOLTIS_VERSION_OVERRIDE:-false}" != "true" && "$env_file_version" != "$tracked_version" ]]; then
            log_error "MOLTIS_VERSION in $ENV_FILE ($env_file_version) does not match tracked git version $tracked_version"
            exit 2
        fi
    fi

    if [[ -n "${MOLTIS_VERSION:-}" && "${ALLOW_MOLTIS_VERSION_OVERRIDE:-false}" != "true" && "$MOLTIS_VERSION" != "$tracked_version" ]]; then
        log_error "Ad-hoc MOLTIS_VERSION override is forbidden for Moltis $action; update tracked compose files in git instead"
        exit 2
    fi
}

extract_moltis_version_tag() {
    local image_ref="$1"
    if [[ "$image_ref" == ghcr.io/moltis-org/moltis:* ]]; then
        printf '%s' "${image_ref##*:}"
    else
        printf '%s' "$image_ref"
    fi
}

resolve_clawdiy_image_ref() {
    if [[ -n "${CLAWDIY_IMAGE:-}" ]]; then
        printf '%s' "$CLAWDIY_IMAGE"
        return 0
    fi

    if read_env_file_value "CLAWDIY_IMAGE" >/dev/null 2>&1; then
        read_env_file_value "CLAWDIY_IMAGE"
        return 0
    fi

    if [[ -f "$TARGET_LAST_IMAGE_FILE" && -s "$TARGET_LAST_IMAGE_FILE" ]]; then
        cat "$TARGET_LAST_IMAGE_FILE"
        return 0
    fi

    return 1
}

require_clawdiy_image_ref() {
    if resolve_clawdiy_image_ref >/dev/null 2>&1; then
        return 0
    fi

    log_error "CLAWDIY_IMAGE must be provided via environment, env file, or previous deployment state before Clawdiy deploy/start"
    exit 2
}

compose_cmd() {
    local mode="${1:-normal}"
    shift

    local args=("$@")
    local -a compose_args=()
    local docker_socket_gid=""
    local redirect_stdout=false

    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        compose_args+=(--env-file "$ENV_FILE")
    fi

    compose_args+=(-f "$COMPOSE_FILE")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        redirect_stdout=true
    fi

    if [[ "$TARGET" == "moltis" ]]; then
        if [[ -S /var/run/docker.sock ]]; then
            docker_socket_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
        fi
        (
            if [[ -n "$docker_socket_gid" ]]; then
                export DOCKER_SOCKET_GID="$docker_socket_gid"
            fi

            if [[ "${ALLOW_MOLTIS_VERSION_OVERRIDE:-false}" == "true" && -n "${MOLTIS_VERSION:-}" ]]; then
                export MOLTIS_VERSION="$MOLTIS_VERSION"
            else
                unset MOLTIS_VERSION
            fi

            if [[ "$redirect_stdout" == "true" ]]; then
                docker compose "${compose_args[@]}" "${args[@]}" 1>&2
            else
                docker compose "${compose_args[@]}" "${args[@]}"
            fi
        )
        return
    fi

    if [[ "$TARGET" == "clawdiy" ]]; then
        local clawdiy_image=""

        if resolve_clawdiy_image_ref >/dev/null 2>&1; then
            clawdiy_image="$(resolve_clawdiy_image_ref)"
        elif [[ "$mode" == "allow-placeholder" ]]; then
            clawdiy_image="$DEFAULT_CLAWDIY_IMAGE"
        fi

        if [[ -n "$clawdiy_image" ]]; then
            if [[ "$redirect_stdout" == "true" ]]; then
                CLAWDIY_IMAGE="$clawdiy_image" docker compose "${compose_args[@]}" "${args[@]}" 1>&2
            else
                CLAWDIY_IMAGE="$clawdiy_image" docker compose "${compose_args[@]}" "${args[@]}"
            fi
            return
        fi
    fi

    if [[ "$redirect_stdout" == "true" ]]; then
        docker compose "${compose_args[@]}" "${args[@]}" 1>&2
    else
        docker compose "${compose_args[@]}" "${args[@]}"
    fi
}

add_json_services() {
    JSON_SERVICES=()
    JSON_SERVICES+=("\"$TARGET_SERVICE\"")

    for service in "${TARGET_AUXILIARY_SERVICES[@]}"; do
        JSON_SERVICES+=("\"$service\"")
    done
}

configure_target() {
    case "$TARGET" in
        moltis)
            TARGET_DISPLAY="Moltis"
            COMPOSE_FILE="$PROJECT_ROOT/docker-compose.prod.yml"
            ENV_FILE="$PROJECT_ROOT/.env"
            TARGET_CONTAINER="moltis"
            TARGET_SERVICE="moltis"
            TARGET_HEALTH_URL="http://localhost:13131/health"
            TARGET_METRICS_URL="http://localhost:13131/metrics"
            TARGET_LAST_IMAGE_FILE="$PROJECT_ROOT/data/moltis/.last-deployed-image"
            TARGET_LAST_BACKUP_FILE="$PROJECT_ROOT/data/moltis/.last-moltis-backup"
            TARGET_LAST_RESTORE_CHECK_FILE="$PROJECT_ROOT/data/moltis/.last-moltis-restore-check"
            TARGET_NOTIFICATION_NAME="Moltis"
            TARGET_HEALTH_TIMEOUT="$HEALTH_CHECK_TIMEOUT"
            TARGET_REQUIRED_NETWORKS=("$TRAEFIK_NETWORK")
            # Scope managed rollout to Moltis core + required sidecars only.
            # Monitoring services must not block Moltis deploys due host-level port conflicts.
            TARGET_AUXILIARY_SERVICES=("watchtower" "ollama")
            ;;
        clawdiy)
            TARGET_DISPLAY="Clawdiy"
            COMPOSE_FILE="$PROJECT_ROOT/docker-compose.clawdiy.yml"
            ENV_FILE="${CLAWDIY_ENV_FILE:-$PROJECT_ROOT/.env.clawdiy}"
            TARGET_CONTAINER="clawdiy"
            TARGET_SERVICE="clawdiy"
            TARGET_LAST_IMAGE_FILE="$PROJECT_ROOT/data/clawdiy/.last-deployed-image"
            TARGET_LAST_BACKUP_FILE="$PROJECT_ROOT/data/clawdiy/.last-backup"
            TARGET_NOTIFICATION_NAME="Clawdiy"
            TARGET_HEALTH_TIMEOUT="$CLAWDIY_HEALTH_CHECK_TIMEOUT"
            TARGET_REQUIRED_NETWORKS=(
                "$TRAEFIK_NETWORK"
                "$FLEET_INTERNAL_NETWORK"
                "$MONITORING_NETWORK"
            )
            TARGET_AUXILIARY_SERVICES=()

            local server_port
            server_port="$(read_env_file_value "CLAWDIY_INTERNAL_PORT" || true)"
            server_port="${server_port:-18789}"
            TARGET_HEALTH_URL="http://localhost:${server_port}/health"
            TARGET_METRICS_URL="http://localhost:${server_port}/metrics"
            TARGET_LAST_RESTORE_CHECK_FILE=""
            ;;
        *)
            echo "Unsupported target: $TARGET" >&2
            exit 2
            ;;
    esac
}

ensure_required_networks() {
    for network_name in "${TARGET_REQUIRED_NETWORKS[@]}"; do
        if ! docker network ls --format '{{.Name}}' | grep -qx "$network_name"; then
            log_warn "Network $network_name not found for target $TARGET, creating it"
            docker network create "$network_name" >/dev/null
        fi
    done
}

managed_container_names_for_target() {
    case "$TARGET" in
        moltis)
            echo "moltis"
            echo "watchtower"
            echo "ollama-fallback"
            ;;
        clawdiy)
            echo "clawdiy"
            ;;
        *)
            ;;
    esac
}

log_json_stderr() {
    local level="$1"
    shift

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "[$level] $*" >&2
    else
        case "$level" in
            INFO) log_info "$@" ;;
            WARN) log_warn "$@" ;;
            ERROR) log_error "$@" ;;
            *) log_info "$@" ;;
        esac
    fi
}

resolve_container_name_conflicts() {
    local expected_project="${COMPOSE_PROJECT_NAME:-}"
    local container_name container_id container_project container_service

    if [[ -z "$expected_project" ]]; then
        expected_project="$(basename "$PROJECT_ROOT")"
    fi

    while IFS= read -r container_name; do
        [[ -n "$container_name" ]] || continue

        container_id="$(docker ps -aq --filter "name=^/${container_name}$" | head -1 || true)"
        [[ -n "$container_id" ]] || continue

        container_project="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$container_id" 2>/dev/null || true)"
        container_service="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$container_id" 2>/dev/null || true)"

        if [[ -n "$container_project" && "$container_project" == "$expected_project" ]]; then
            continue
        fi

        log_json_stderr WARN "Removing legacy/conflicting container '$container_name' (id=$container_id project=${container_project:-none} service=${container_service:-none}) before deploy"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            if ! docker rm -f "$container_id" 1>&2; then
                log_error "Failed to remove conflicting container: $container_name ($container_id)"
                exit 1
            fi
        else
            if ! docker rm -f "$container_id"; then
                log_error "Failed to remove conflicting container: $container_name ($container_id)"
                exit 1
            fi
        fi
    done < <(managed_container_names_for_target)
}

ensure_clawdiy_runtime_paths() {
    local required_paths=(
        "$PROJECT_ROOT/data/clawdiy"
        "$PROJECT_ROOT/config/clawdiy"
        "$PROJECT_ROOT/config/fleet"
        "$PROJECT_ROOT/data/clawdiy/runtime"
        "$PROJECT_ROOT/data/clawdiy/workspace"
        "$PROJECT_ROOT/data/clawdiy/state"
        "$PROJECT_ROOT/data/clawdiy/audit"
        "$PROJECT_ROOT/data/clawdiy/audit/rollback-evidence"
    )

    for path in "${required_paths[@]}"; do
        mkdir -p "$path"
    done

    if [[ "$EUID" -ne 0 ]]; then
        log_warn "Skipping Clawdiy runtime ownership normalization because deploy.sh is not running as root"
        return 0
    fi

    local runtime_paths=(
        "$PROJECT_ROOT/data/clawdiy/runtime"
        "$PROJECT_ROOT/data/clawdiy/workspace"
        "$PROJECT_ROOT/data/clawdiy/state"
        "$PROJECT_ROOT/data/clawdiy/audit"
    )

    for path in "${runtime_paths[@]}"; do
        chown -R "${CLAWDIY_RUNTIME_UID}:${CLAWDIY_RUNTIME_GID}" "$path"
    done
}

render_clawdiy_runtime_config() {
    if [[ "$TARGET" != "clawdiy" ]]; then
        return 0
    fi

    if [[ ! -x "$CLAWDIY_RUNTIME_RENDER_SCRIPT" ]]; then
        log_error "Clawdiy runtime render script is missing or not executable: $CLAWDIY_RUNTIME_RENDER_SCRIPT"
        exit 2
    fi

    local -a args=(
        --template "$CLAWDIY_CONFIG_FILE"
        --output "$CLAWDIY_RENDERED_CONFIG_FILE"
    )

    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        args+=(--env-file "$ENV_FILE")
    fi

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        "$CLAWDIY_RUNTIME_RENDER_SCRIPT" "${args[@]}" --json >/dev/null
    else
        "$CLAWDIY_RUNTIME_RENDER_SCRIPT" "${args[@]}"
    fi
}

count_files_under() {
    local root="$1"

    if [[ ! -d "$root" ]]; then
        echo "0"
        return
    fi

    find "$root" -type f | wc -l | tr -d ' '
}

latest_file_under() {
    local root="$1"

    if [[ ! -d "$root" ]]; then
        return 0
    fi

    find "$root" -type f | sort | tail -1
}

latest_backup_path() {
    if [[ -n "$TARGET_LAST_BACKUP_FILE" && -f "$TARGET_LAST_BACKUP_FILE" && -s "$TARGET_LAST_BACKUP_FILE" ]]; then
        cat "$TARGET_LAST_BACKUP_FILE"
        return 0
    fi

    ls -t \
        "$BACKUP_DIR"/pre_deploy_*.tar.gz \
        "$BACKUP_DIR"/daily/moltis_* \
        "$BACKUP_DIR"/weekly/moltis_* \
        "$BACKUP_DIR"/monthly/moltis_* 2>/dev/null | head -1 || true
}

latest_restore_check_path() {
    if [[ -n "$TARGET_LAST_RESTORE_CHECK_FILE" && -f "$TARGET_LAST_RESTORE_CHECK_FILE" && -s "$TARGET_LAST_RESTORE_CHECK_FILE" ]]; then
        cat "$TARGET_LAST_RESTORE_CHECK_FILE"
        return 0
    fi

    latest_file_under "$PROJECT_ROOT/data/moltis/audit/restore-checks"
    return 0
}

ensure_moltis_audit_paths() {
    mkdir -p \
        "$PROJECT_ROOT/data/moltis" \
        "$PROJECT_ROOT/data/moltis/audit/restore-checks" \
        "$PROJECT_ROOT/data/moltis/audit/rollback-evidence"
}

write_moltis_restore_check_evidence() {
    local backup_ref="$1"
    local evidence_root="$PROJECT_ROOT/data/moltis/audit/restore-checks"
    local evidence_file="$evidence_root/restore-check-$(date -u +%Y%m%dT%H%M%SZ).json"
    local current_image current_health

    ensure_moltis_audit_paths
    current_image="$(get_current_version)"
    current_health="$(curl -s -o /dev/null -w '%{http_code}' "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")"

    cat > "$evidence_file" <<EOF
{
  "schema_version": "v1",
  "target": "moltis",
  "checked_at": "$(get_timestamp)",
  "backup_reference": $(printf '%s' "$backup_ref" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "restore_check_command": "./scripts/backup-moltis-enhanced.sh restore-check <backup>",
  "pre_update_image": "$current_image",
  "moltis_health_http_code_before_update": $current_health,
  "status": "passed"
}
EOF

    if [[ -n "$TARGET_LAST_RESTORE_CHECK_FILE" ]]; then
        echo "$evidence_file" > "$TARGET_LAST_RESTORE_CHECK_FILE"
    fi

    DEPLOY_RESTORE_CHECK_FILE="$evidence_file"
    printf '%s' "$evidence_file"
}

capture_moltis_rollback_evidence() {
    local reason="$1"
    local evidence_root="$PROJECT_ROOT/data/moltis/audit/rollback-evidence"
    local evidence_file="$evidence_root/rollback-$(date -u +%Y%m%dT%H%M%SZ).json"
    local current_image current_health backup_ref restore_check_ref

    ensure_moltis_audit_paths
    current_image="$(get_current_version)"
    current_health="$(curl -s -o /dev/null -w '%{http_code}' "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")"
    backup_ref="$(latest_backup_path)"
    restore_check_ref="$(latest_restore_check_path)"

    cat > "$evidence_file" <<EOF
{
  "schema_version": "v1",
  "target": "moltis",
  "captured_at": "$(get_timestamp)",
  "rollback_reason": "$reason",
  "backup_reference": $(printf '%s' "$backup_ref" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "restore_check_reference": $(printf '%s' "$restore_check_ref" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "pre_rollback_image": "$current_image",
  "pre_rollback_health_http_code": $current_health,
  "resulting_mode": null,
  "post_rollback_image": null,
  "post_rollback_health_http_code": null,
  "status": "captured"
}
EOF

    DEPLOY_EVIDENCE_FILE="$evidence_file"
    printf '%s' "$evidence_file"
}

update_moltis_rollback_evidence() {
    local evidence_file="$1"
    local resulting_mode="$2"

    if [[ -z "$evidence_file" || ! -f "$evidence_file" ]]; then
        return 0
    fi

    local post_image post_health tmp_file
    post_image="$(get_current_version)"
    post_health="$(curl -s -o /dev/null -w '%{http_code}' "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")"
    tmp_file="$(mktemp)"

    jq \
        --arg resulting_mode "$resulting_mode" \
        --arg post_image "$post_image" \
        --arg completed_at "$(get_timestamp)" \
        --argjson post_health "$post_health" \
        '.resulting_mode = $resulting_mode
        | .post_rollback_image = (if $post_image == "" then null else $post_image end)
        | .post_rollback_health_http_code = $post_health
        | .completed_at = $completed_at
        | .status = "completed"' \
        "$evidence_file" > "$tmp_file"

    mv "$tmp_file" "$evidence_file"
}

capture_clawdiy_rollback_evidence() {
    local reason="$1"
    local evidence_root="$PROJECT_ROOT/data/clawdiy/audit/rollback-evidence"
    local evidence_file="$evidence_root/rollback-$(date -u +%Y%m%dT%H%M%SZ).json"
    local current_image current_health backup_ref latest_audit artifact_count moltis_health_code

    mkdir -p "$evidence_root" "$PROJECT_ROOT/data/clawdiy/audit" 2>/dev/null || true

    current_image="$(get_current_version)"
    current_health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$TARGET_CONTAINER" 2>/dev/null || echo "not_found")"
    backup_ref="$(latest_backup_path)"
    latest_audit="$(latest_file_under "$PROJECT_ROOT/data/clawdiy/audit")"
    artifact_count="$(count_files_under "$PROJECT_ROOT/data/clawdiy/audit")"
    moltis_health_code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:13131/health 2>/dev/null || echo "000")"

    cat > "$evidence_file" <<EOF
{
  "schema_version": "v1",
  "target": "clawdiy",
  "captured_at": "$(get_timestamp)",
  "rollback_reason": "$reason",
  "pre_rollback_image": "$current_image",
  "pre_rollback_health": "$current_health",
  "audit_root": "$PROJECT_ROOT/data/clawdiy/audit",
  "audit_file_count_before": $artifact_count,
  "latest_audit_artifact_before": $(printf '%s' "$latest_audit" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "backup_reference": $(printf '%s' "$backup_ref" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
  "moltis_health_http_code": $moltis_health_code,
  "resulting_mode": null,
  "post_rollback_image": null,
  "post_rollback_health": null,
  "audit_file_count_after": null,
  "latest_audit_artifact_after": null,
  "status": "captured"
}
EOF

    DEPLOY_EVIDENCE_FILE="$evidence_file"
    printf '%s' "$evidence_file"
}

update_clawdiy_rollback_evidence() {
    local evidence_file="$1"
    local resulting_mode="$2"

    if [[ -z "$evidence_file" || ! -f "$evidence_file" ]]; then
        return 0
    fi

    local post_image post_health latest_audit artifact_count tmp_file
    post_image="$(get_current_version)"
    post_health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$TARGET_CONTAINER" 2>/dev/null || echo "not_found")"
    latest_audit="$(latest_file_under "$PROJECT_ROOT/data/clawdiy/audit")"
    artifact_count="$(count_files_under "$PROJECT_ROOT/data/clawdiy/audit")"
    tmp_file="$(mktemp)"

    jq \
        --arg resulting_mode "$resulting_mode" \
        --arg post_image "$post_image" \
        --arg post_health "$post_health" \
        --arg completed_at "$(get_timestamp)" \
        --arg latest_audit "$latest_audit" \
        --argjson artifact_count "$artifact_count" \
        '.resulting_mode = $resulting_mode
        | .post_rollback_image = (if $post_image == "" then null else $post_image end)
        | .post_rollback_health = $post_health
        | .completed_at = $completed_at
        | .audit_file_count_after = $artifact_count
        | .latest_audit_artifact_after = (if $latest_audit == "" then null else $latest_audit end)
        | .status = "completed"' \
        "$evidence_file" > "$tmp_file"

    mv "$tmp_file" "$evidence_file"
}

check_prerequisites() {
    local action="$1"

    log_info "Checking prerequisites for target $TARGET..."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Compose file not found: $COMPOSE_FILE"
        exit 2
    fi

    if [[ "$TARGET" == "moltis" ]]; then
        enforce_moltis_git_tracked_version "$action"

        if [[ "$action" == "deploy" || "$action" == "rollback" ]]; then
            ensure_moltis_audit_paths
        fi

        if [[ ! -f "$PROJECT_ROOT/secrets/moltis_password.txt" ]]; then
            log_warn "Secrets file not found, creating from .env"
            mkdir -p "$PROJECT_ROOT/secrets"
            if [[ -f "$ENV_FILE" ]]; then
                grep "MOLTIS_PASSWORD" "$ENV_FILE" | cut -d'=' -f2 > "$PROJECT_ROOT/secrets/moltis_password.txt"
            else
                log_error "No MOLTIS_PASSWORD found in .env"
                exit 2
            fi
        fi
    fi

    if [[ "$TARGET" == "clawdiy" && ("$action" == "deploy" || "$action" == "rollback" || "$action" == "start" || "$action" == "restart") ]]; then
        require_clawdiy_image_ref
        ensure_clawdiy_runtime_paths
        render_clawdiy_runtime_config
    fi

    if ! compose_cmd allow-placeholder config --quiet >/dev/null 2>&1; then
        log_error "Compose configuration failed to render for target $TARGET"
        exit 2
    fi

    ensure_required_networks
    resolve_container_name_conflicts
    log_success "Prerequisites check passed for target $TARGET"
}

wait_for_healthy() {
    local container="$1"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"
    local elapsed=0
    local warned_unhealthy=false

    log_info "Waiting for $container to become healthy (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        local health
        local state
        local http_code="000"
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
        state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")

        if [[ -n "${TARGET_HEALTH_URL:-}" && "$state" == "running" ]]; then
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")
        fi

        case "$health" in
            healthy)
                log_success "$container is healthy"
                return 0
                ;;
            unhealthy)
                if [[ "$http_code" == "200" ]]; then
                    log_success "$container health endpoint is already serving HTTP 200 while Docker health is still catching up"
                    return 0
                fi

                if [[ "$state" == "exited" || "$state" == "dead" ]]; then
                    log_error "$container is unhealthy and no longer running"
                    docker logs "$container" --tail 80 >&2 || true
                    return 1
                fi

                if [[ "$warned_unhealthy" == "false" ]]; then
                    log_warn "$container is temporarily unhealthy during startup; continuing to wait until timeout"
                    docker inspect --format='{{json .State.Health}}' "$container" 2>/dev/null | jq . >&2 || true
                    docker logs "$container" --tail 80 >&2 || true
                    warned_unhealthy=true
                fi
                ;;
            starting)
                if [[ "$http_code" == "200" ]]; then
                    log_success "$container health endpoint is already serving HTTP 200 while Docker health is still starting"
                    return 0
                fi
                ;;
        esac

        sleep "$HEALTH_CHECK_INTERVAL"
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        if [[ "$OUTPUT_JSON" != "true" ]]; then
            echo -n "."
        fi
    done

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
    fi
    log_error "Timeout waiting for $container to become healthy"
    return 1
}

get_current_version() {
    docker inspect "$TARGET_CONTAINER" --format='{{.Config.Image}}' 2>/dev/null || echo "none"
}

backup_current_state() {
    local backup_name="pre-deploy-${TARGET}-$(date +%Y%m%d_%H%M%S)"
    local current_image
    local backup_json=""
    local backup_path=""

    log_info "Creating pre-deployment backup marker: $backup_name"
    current_image="$(get_current_version)"

    if [[ -x "$BACKUP_SCRIPT" ]]; then
        backup_json="$("$BACKUP_SCRIPT" --json backup)"
        backup_path="$(printf '%s' "$backup_json" | jq -r '.details.local_path // empty')"
        if [[ -n "$backup_path" && -n "$TARGET_LAST_BACKUP_FILE" ]]; then
            echo "$backup_path" > "$TARGET_LAST_BACKUP_FILE"
            log_info "Stored latest backup reference for target $TARGET: $backup_path"
        fi

        if [[ "$TARGET" == "moltis" ]]; then
            if [[ -z "$backup_path" || ! -f "$backup_path" ]]; then
                log_error "Pre-deployment backup did not produce a valid archive for Moltis"
                exit 1
            fi

            log_info "Running restore-readiness check for Moltis backup..."
            if [[ "$OUTPUT_JSON" == "true" ]]; then
                "$BACKUP_SCRIPT" restore-check "$backup_path" 1>&2
            else
                "$BACKUP_SCRIPT" restore-check "$backup_path"
            fi
            write_moltis_restore_check_evidence "$backup_path" >/dev/null
            log_success "Restore-readiness evidence recorded: $DEPLOY_RESTORE_CHECK_FILE"
        fi
    else
        if [[ "$TARGET" == "moltis" ]]; then
            log_error "Backup script is required for Moltis pre-deployment backup and restore-readiness checks"
            exit 1
        fi

        log_warn "Backup script not executable, skipping pre-deployment backup archive"
    fi

    if [[ "$current_image" != "none" ]]; then
        echo "$current_image" > "$TARGET_LAST_IMAGE_FILE"
        log_info "Stored last image reference for target $TARGET"
    fi

    log_success "Pre-deployment backup step completed for target $TARGET"
}

pull_images() {
    log_info "Pulling images for target $TARGET..."

    if [[ "$TARGET" == "moltis" ]]; then
        log_info "Using tracked Moltis image from git: $(tracked_moltis_image_ref)"
    fi

    compose_cmd normal pull
    log_success "Images pulled successfully for target $TARGET"
}

deploy_containers() {
    log_info "Deploying containers for target $TARGET..."
    local -a deploy_services=("$TARGET_SERVICE")
    local -a deploy_args=(up -d --remove-orphans)
    local service

    for service in "${TARGET_AUXILIARY_SERVICES[@]}"; do
        [[ -n "$service" ]] || continue
        deploy_services+=("$service")
    done

    if [[ "$TARGET" == "moltis" ]]; then
        # Moltis loads runtime config at process start, so bind-mounted config
        # changes must force a recreate to avoid stale live state.
        deploy_args+=(--force-recreate)
    fi

    compose_cmd normal "${deploy_args[@]}" "${deploy_services[@]}"
    log_success "Containers deployed for target $TARGET"
}

rollback() {
    log_warn "Initiating rollback for target $TARGET..."

    local last_image=""
    local evidence_file=""
    local resulting_mode="rolled_back"
    if [[ -f "$TARGET_LAST_IMAGE_FILE" ]]; then
        last_image="$(cat "$TARGET_LAST_IMAGE_FILE")"
    fi

    if [[ "$TARGET" == "clawdiy" ]]; then
        evidence_file="$(capture_clawdiy_rollback_evidence "$ROLLBACK_REASON")"
    elif [[ "$TARGET" == "moltis" ]]; then
        evidence_file="$(capture_moltis_rollback_evidence "$ROLLBACK_REASON")"
    fi

    if [[ -n "$last_image" && "$last_image" != "none" ]]; then
        log_info "Rolling back target $TARGET to $last_image"

        if [[ "$TARGET" == "moltis" ]]; then
            ALLOW_MOLTIS_VERSION_OVERRIDE=true \
                MOLTIS_VERSION="$(extract_moltis_version_tag "$last_image")" \
                compose_cmd normal up -d --force-recreate "$TARGET_SERVICE"
        else
            CLAWDIY_IMAGE="$last_image" compose_cmd normal up -d --force-recreate "$TARGET_SERVICE"
        fi
    elif [[ "$TARGET" == "moltis" ]]; then
        log_error "No previous image found for rollback"

        local latest_backup
        latest_backup="$(latest_backup_path)"
        if [[ -n "$latest_backup" ]]; then
            log_info "Attempting restore from backup: $latest_backup"
            "$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh" restore "$latest_backup"
            resulting_mode="restored_from_backup"
        else
            resulting_mode="failed"
        fi
    else
        log_warn "No previous Clawdiy image found, disabling Clawdiy stack instead"
        compose_cmd allow-placeholder down --remove-orphans
        resulting_mode="disabled"
    fi

    if [[ "$TARGET" == "clawdiy" ]]; then
        update_clawdiy_rollback_evidence "$evidence_file" "$resulting_mode"
    elif [[ "$TARGET" == "moltis" ]]; then
        update_moltis_rollback_evidence "$evidence_file" "$resulting_mode"
    fi

    log_success "Rollback complete for target $TARGET"
}

verify_deployment() {
    log_info "Verifying deployment for target $TARGET..."

    if ! wait_for_healthy "$TARGET_CONTAINER" "$TARGET_HEALTH_TIMEOUT"; then
        return 1
    fi

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")
    if [[ "$http_code" != "200" ]]; then
        log_error "Health endpoint returned HTTP $http_code for target $TARGET"
        return 1
    fi

    if [[ -n "$TARGET_METRICS_URL" ]]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_METRICS_URL" 2>/dev/null || echo "000")
        if [[ "$http_code" != "200" ]]; then
            log_warn "Metrics endpoint returned HTTP $http_code for target $TARGET (non-critical)"
        fi
    fi

    if [[ "$TARGET" == "moltis" ]]; then
        local expected_workspace expected_runtime_config
        local actual_workspace_source actual_runtime_config_source
        local actual_runtime_config_rw working_dir

        working_dir="$(docker inspect --format '{{.Config.WorkingDir}}' "$TARGET_CONTAINER" 2>/dev/null || echo "")"
        if [[ "$working_dir" != "/server" ]]; then
            log_error "Moltis runtime contract mismatch: working_dir is '$working_dir', expected '/server'"
            return 1
        fi

        expected_workspace="$(canonicalize_existing_path "$PROJECT_ROOT" || printf '%s\n' "$PROJECT_ROOT")"
        actual_workspace_source="$(container_mount_source "$TARGET_CONTAINER" "/server")"
        if [[ -z "$actual_workspace_source" ]]; then
            log_error "Moltis runtime contract mismatch: /server mount is missing in container $TARGET_CONTAINER"
            return 1
        fi
        actual_workspace_source="$(canonicalize_existing_path "$actual_workspace_source" || printf '%s\n' "$actual_workspace_source")"
        if [[ "$actual_workspace_source" != "$expected_workspace" ]]; then
            log_error "Moltis runtime contract mismatch: /server source is '$actual_workspace_source', expected '$expected_workspace'"
            return 1
        fi

        expected_runtime_config="$(read_env_file_value "MOLTIS_RUNTIME_CONFIG_DIR" || true)"
        expected_runtime_config="${expected_runtime_config:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"
        expected_runtime_config="$(normalize_runtime_config_path "$expected_runtime_config")"
        if ! runtime_config_dir_allowed "$expected_runtime_config"; then
            log_error "Moltis runtime contract mismatch: runtime config dir '$expected_runtime_config' is outside the production allowlist '$MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST'"
            return 1
        fi
        expected_runtime_config="$(canonicalize_existing_path "$expected_runtime_config" || printf '%s\n' "$expected_runtime_config")"
        actual_runtime_config_source="$(container_mount_source "$TARGET_CONTAINER" "/home/moltis/.config/moltis")"
        if [[ -z "$actual_runtime_config_source" ]]; then
            log_error "Moltis runtime contract mismatch: runtime config mount is missing for /home/moltis/.config/moltis"
            return 1
        fi
        actual_runtime_config_source="$(canonicalize_existing_path "$actual_runtime_config_source" || printf '%s\n' "$actual_runtime_config_source")"
        if [[ "$actual_runtime_config_source" != "$expected_runtime_config" ]]; then
            log_error "Moltis runtime contract mismatch: runtime config source is '$actual_runtime_config_source', expected '$expected_runtime_config'"
            return 1
        fi

        actual_runtime_config_rw="$(container_mount_rw "$TARGET_CONTAINER" "/home/moltis/.config/moltis")"
        if [[ "$actual_runtime_config_rw" != "true" ]]; then
            log_error "Moltis runtime contract mismatch: runtime config mount must be writable for runtime-managed auth/key files"
            return 1
        fi

        if ! docker exec "$TARGET_CONTAINER" sh -lc '
            test -d /server &&
            test -d /server/skills &&
            test -f /home/moltis/.config/moltis/moltis.toml &&
            tmp_path="/home/moltis/.config/moltis/provider_keys.json.tmp.contract-check.$$" &&
            : > "$tmp_path" &&
            rm -f "$tmp_path"
        ' >/dev/null 2>&1; then
            log_error "Moltis runtime contract mismatch: repo skills are not visible or runtime config is not writable inside the container"
            return 1
        fi
    fi

    log_success "Deployment verification passed for target $TARGET"
    return 0
}

sync_moltis_project_knowledge() {
    local runtime_home_source canonical_runtime_home

    if [[ "$TARGET" != "moltis" ]]; then
        return 0
    fi

    if [[ ! -d "$PROJECT_ROOT/knowledge" ]]; then
        log_info "Tracked knowledge/ directory not present; skipping project knowledge sync"
        return 0
    fi

    if [[ ! -x "$MOLTIS_KNOWLEDGE_SYNC_SCRIPT" ]]; then
        log_error "Moltis knowledge sync script is missing or not executable: $MOLTIS_KNOWLEDGE_SYNC_SCRIPT"
        return 1
    fi

    runtime_home_source="$(container_mount_source "$TARGET_CONTAINER" "/home/moltis/.moltis")"
    if [[ -z "$runtime_home_source" ]]; then
        log_error "Moltis runtime contract mismatch: /home/moltis/.moltis mount source is missing"
        return 1
    fi
    canonical_runtime_home="$(canonicalize_existing_path "$runtime_home_source" || printf '%s\n' "$runtime_home_source")"

    if ! MOLTIS_SERVICE_UID="$MOLTIS_SERVICE_UID" \
         MOLTIS_SERVICE_GID="$MOLTIS_SERVICE_GID" \
         bash "$MOLTIS_KNOWLEDGE_SYNC_SCRIPT" \
            --knowledge-root "$PROJECT_ROOT/knowledge" \
            --runtime-home "$canonical_runtime_home"; then
        log_error "Failed to sync tracked project knowledge into Moltis runtime memory"
        return 1
    fi

    if ! docker exec "$TARGET_CONTAINER" sh -lc 'test -f /home/moltis/.moltis/memory/project-knowledge.md' >/dev/null 2>&1; then
        log_error "Moltis knowledge sync did not materialize /home/moltis/.moltis/memory/project-knowledge.md"
        return 1
    fi

    log_success "Tracked project knowledge synced into Moltis runtime memory"
    return 0
}

prepull_moltis_browser_sandbox_image() {
    if [[ "$TARGET" != "moltis" ]]; then
        return 0
    fi

    local browser_contract browser_enabled sandbox_image
    browser_contract="$(awk '
        BEGIN {
            in_section = 0
            enabled = "true"
            image = "browserless/chrome"
        }
        /^\[tools\.browser\][[:space:]]*$/ {
            in_section = 1
            next
        }
        /^\[/ {
            if (in_section) {
                exit
            }
        }
        in_section {
            if ($0 ~ /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*(true|false)/) {
                gsub(/#.*/, "", $0)
                sub(/^[[:space:]]*enabled[[:space:]]*=[[:space:]]*/, "", $0)
                gsub(/[[:space:]]+$/, "", $0)
                enabled = $0
            }
            if ($0 ~ /^[[:space:]]*sandbox_image[[:space:]]*=[[:space:]]*"/) {
                gsub(/#.*/, "", $0)
                sub(/^[[:space:]]*sandbox_image[[:space:]]*=[[:space:]]*"/, "", $0)
                sub(/".*$/, "", $0)
                image = $0
            }
        }
        END {
            print enabled "|" image
        }
    ' "$PROJECT_ROOT/config/moltis.toml")"
    browser_enabled="${browser_contract%%|*}"
    sandbox_image="${browser_contract#*|}"

    if [[ "$browser_enabled" != "true" ]]; then
        log_info "Tracked Moltis browser tool is disabled; skipping sandbox image pre-pull"
        return 0
    fi

    if [[ -z "$sandbox_image" || "$sandbox_image" == "null" ]]; then
        sandbox_image="browserless/chrome"
    fi

    log_info "Pre-pulling Moltis browser sandbox image: $sandbox_image"
    docker pull "$sandbox_image" >/dev/null
    log_success "Moltis browser sandbox image ready: $sandbox_image"
    return 0
}

send_notification() {
    local status="$1"
    local message="$2"

    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        local color
        case "$status" in
            success) color="good" ;;
            failure) color="danger" ;;
            *) color="warning" ;;
        esac

        curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"title\": \"${TARGET_NOTIFICATION_NAME} Deployment - $status\",
                    \"text\": \"$message\",
                    \"footer\": \"Host: $(hostname)\",
                    \"ts\": $(date +%s)
                }]
            }" >/dev/null 2>&1 || true
    fi
}

# ========================================================================
# DEPLOYMENT COMMANDS
# ========================================================================

cmd_deploy() {
    local environment="${1:-production}"
    DEPLOY_ACTION="deploy"
    DEPLOY_START_TIME=$(date +%s)

    if type gitops_guard_deploy >/dev/null 2>&1; then
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            gitops_guard_deploy "deploy.sh $TARGET" 1>&2
        else
            gitops_guard_deploy "deploy.sh $TARGET"
        fi
    fi

    log_info "=========================================="
    log_info "Starting ${TARGET_DISPLAY} Deployment"
    log_info "Environment: $environment"
    log_info "Target: $TARGET"
    log_info "=========================================="

    check_prerequisites "deploy"
    backup_current_state
    pull_images
    prepull_moltis_browser_sandbox_image
    deploy_containers

    if verify_deployment; then
        if ! sync_moltis_project_knowledge; then
            log_error "${TARGET_DISPLAY} post-deploy knowledge sync failed"
            if [[ "$OUTPUT_JSON" == "true" ]]; then
                output_json_result "failure" "deploy" "unhealthy"
            fi
            exit 1
        fi

        DEPLOY_IMAGE="$(get_current_version)"
        add_json_services

        log_success "=========================================="
        log_success "${TARGET_DISPLAY} deployment completed successfully"
        log_success "=========================================="
        send_notification "success" "${TARGET_DISPLAY} deployment completed successfully"

        if [[ "$OUTPUT_JSON" == "true" ]]; then
            output_json_result "success" "deploy" "healthy"
        fi
    else
        log_error "${TARGET_DISPLAY} deployment verification failed"
        local health_status="unhealthy"

        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            ROLLBACK_REASON="deployment-verification-failed"
            rollback
            if [[ "$TARGET" == "clawdiy" ]] && ! docker ps --format '{{.Names}}' | grep -qx "$TARGET_CONTAINER"; then
                health_status="disabled"
            else
                health_status="rolled_back"
            fi
            send_notification "failure" "${TARGET_DISPLAY} deployment failed and rollback was triggered"
        fi

        if [[ "$OUTPUT_JSON" == "true" ]]; then
            output_json_result "failure" "deploy" "$health_status"
        fi
        exit 1
    fi
}

cmd_rollback() {
    DEPLOY_ACTION="rollback"
    DEPLOY_START_TIME=$(date +%s)
    local container_present=false
    ROLLBACK_REASON="operator-requested"

    log_info "=========================================="
    log_info "Starting ${TARGET_DISPLAY} Rollback"
    log_info "=========================================="

    check_prerequisites "rollback"
    rollback

    if docker ps --format '{{.Names}}' | grep -qx "$TARGET_CONTAINER"; then
        container_present=true
    fi

    if [[ "$TARGET" == "clawdiy" && "$container_present" == "false" ]]; then
        DEPLOY_IMAGE="disabled"
        add_json_services
        log_success "Rollback completed by disabling Clawdiy"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            output_json_result "success" "rollback" "disabled"
        fi
        return
    fi

    if verify_deployment; then
        DEPLOY_IMAGE="$(get_current_version)"
        add_json_services

        log_success "Rollback completed successfully for target $TARGET"
        send_notification "warning" "${TARGET_DISPLAY} deployment rolled back"

        if [[ "$OUTPUT_JSON" == "true" ]]; then
            output_json_result "success" "rollback" "healthy"
        fi
    else
        log_error "Rollback verification failed for target $TARGET"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            output_json_result "failure" "rollback" "unhealthy"
        fi
        exit 1
    fi
}

cmd_status() {
    DEPLOY_ACTION="status"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        local health
        local image
        local uptime=0
        local started_at
        local services_json

        health=$(docker inspect --format='{{.State.Health.Status}}' "$TARGET_CONTAINER" 2>/dev/null | tr -d '\n' || echo "not_found")
        image=$(docker inspect --format='{{.Config.Image}}' "$TARGET_CONTAINER" 2>/dev/null | tr -d '\n' || echo "")
        started_at=$(docker inspect --format='{{.State.StartedAt}}' "$TARGET_CONTAINER" 2>/dev/null | tr -d '\n' || echo "")

        if [[ -n "$started_at" ]]; then
            local started_epoch
            started_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%%.*}" +%s 2>/dev/null || echo "0")
            uptime=$(( $(date +%s) - started_epoch ))
        fi

        services_json=$(jq -n \
            --arg name "$TARGET_SERVICE" \
            --arg status "$health" \
            --argjson uptime "$uptime" \
            '[{name: $name, status: $status, uptime_seconds: $uptime}]')

        jq -n \
            --arg status "$health" \
            --arg target "$TARGET" \
            --arg timestamp "$(get_timestamp)" \
            --argjson services "$services_json" \
            --arg image "$image" \
            '{status: $status, target: $target, timestamp: $timestamp, services: $services, image: $image}'
    else
        log_info "Deployment Status for target $TARGET"
        echo ""
        echo "Container Status:"
        docker ps -a --filter "name=$TARGET_CONTAINER" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "Health Status:"
        docker inspect "$TARGET_CONTAINER" --format='Health: {{.State.Health.Status}}' 2>/dev/null || echo "Not available"
        echo ""
        echo "Image:"
        echo "  Current: $(get_current_version)"
        if [[ "$TARGET" == "moltis" ]]; then
            echo "  Tracked: $(tracked_moltis_image_ref)"
        fi
        if [[ -f "$TARGET_LAST_IMAGE_FILE" ]]; then
            echo "  Previous: $(cat "$TARGET_LAST_IMAGE_FILE")"
        fi

        if [[ "$TARGET" == "moltis" ]]; then
            echo ""
            echo "Recent Deploys:"
            ls -lt /var/backups/moltis/daily/*.tar.gz* 2>/dev/null | head -5 || echo "  No backups found"
        fi
    fi
}

cmd_stop() {
    log_info "Stopping target $TARGET..."
    compose_cmd allow-placeholder down
    log_success "Target $TARGET stopped"
}

cmd_start() {
    log_info "Starting target $TARGET..."
    check_prerequisites "start"
    compose_cmd normal up -d
    wait_for_healthy "$TARGET_CONTAINER" "$TARGET_HEALTH_TIMEOUT"
    log_success "Target $TARGET started"
}

cmd_restart() {
    check_prerequisites "restart"
    cmd_stop
    sleep 5
    cmd_start
}

cmd_logs() {
    local follow="${1:-}"

    if [[ "$follow" == "-f" ]]; then
        compose_cmd allow-placeholder logs -f --tail=100
    else
        compose_cmd allow-placeholder logs --tail=200
    fi
}

# ========================================================================
# MAIN
# ========================================================================

show_usage() {
    echo "Multi-target Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [TARGET] COMMAND [ARGS]"
    echo ""
    echo "Options:"
    echo "  --json          Output in JSON format (for CI/AI parsing)"
    echo "  --no-color      Disable colored output"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Targets:"
    echo "  moltis         Default target"
    echo "  clawdiy        OpenClaw sidecar stack"
    echo ""
    echo "Commands:"
    echo "  deploy [env]   Deploy the target stack (default env: production)"
    echo "  rollback       Roll back the target stack"
    echo "  status         Show target deployment status"
    echo "  start          Start target services"
    echo "  stop           Stop target services"
    echo "  restart        Restart target services"
    echo "  logs [-f]      Show target logs (follow with -f)"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 clawdiy deploy"
    echo "  $0 --json clawdiy status"
    echo ""
    echo "Exit Codes:"
    echo "  0 - Success"
    echo "  1 - General error"
    echo "  2 - Configuration error"
    echo "  3 - Health check failed"
    echo "  4 - Pre-flight validation failed"
    echo "  5 - Rollback triggered"
    echo ""
    echo "Environment Variables:"
    echo "  SLACK_WEBHOOK        - Slack webhook for notifications"
    echo "  HEALTH_CHECK_TIMEOUT - Health check timeout in seconds"
    echo "  CLAWDIY_HEALTH_CHECK_TIMEOUT - Clawdiy-specific health timeout in seconds"
    echo "  ROLLBACK_ENABLED     - Enable automatic rollback (true/false)"
    echo "  CLAWDIY_IMAGE        - OpenClaw image for target=clawdiy deploys"
    echo "  CLAWDIY_ENV_FILE     - Optional env file for target=clawdiy"
    echo ""
    echo "Contract: specs/001-docker-deploy-improvements/contracts/scripts.md"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                OUTPUT_JSON=true
                NO_COLOR=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ "${1:-}" == "moltis" || "${1:-}" == "clawdiy" ]]; then
        TARGET="$1"
        shift
    fi

    configure_target
    disable_colors

    local command="${1:-help}"
    shift || true

    if lock_command_mutates_state "$command"; then
        acquire_deploy_mutex "$command"
        trap 'release_deploy_mutex' EXIT
    fi

    case "$command" in
        deploy)
            cmd_deploy "$@"
            ;;
        rollback)
            cmd_rollback
            ;;
        status)
            cmd_status
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        logs)
            cmd_logs "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
