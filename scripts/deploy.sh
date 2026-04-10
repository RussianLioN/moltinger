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
CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR="${CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}"
MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="${MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"
MOLTIS_RUNTIME_DATA_DIR="${MOLTIS_RUNTIME_DATA_DIR:-/home/moltis/.moltis}"
MOLTIS_REPO_SKILLS_SOURCE_ROOT="${MOLTIS_REPO_SKILLS_SOURCE_ROOT:-/server/skills}"
MOLTIS_RUNTIME_SKILLS_ROOT="${MOLTIS_RUNTIME_SKILLS_ROOT:-$MOLTIS_RUNTIME_DATA_DIR/skills}"
MOLTIS_RUNTIME_SKILLS_MANIFEST="${MOLTIS_RUNTIME_SKILLS_MANIFEST:-$MOLTIS_RUNTIME_DATA_DIR/.repo-managed-skills.txt}"
MOLTIS_REPO_HOOKS_SOURCE_ROOT="${MOLTIS_REPO_HOOKS_SOURCE_ROOT:-/server/.moltis/hooks}"
MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT="${MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT:-$MOLTIS_RUNTIME_DATA_DIR/.moltis/hooks}"
MOLTIS_RUNTIME_PROJECT_HOOKS_MANIFEST="${MOLTIS_RUNTIME_PROJECT_HOOKS_MANIFEST:-$MOLTIS_RUNTIME_DATA_DIR/.moltis/.repo-managed-hooks.txt}"
MOLTIS_STOP_TIMEOUT_SECONDS="${MOLTIS_STOP_TIMEOUT_SECONDS:-45}"
CANONICAL_MOLTIS_BROWSER_PROFILE_DIR="${CANONICAL_MOLTIS_BROWSER_PROFILE_DIR:-/tmp/moltis-browser-profile}"

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
DEFAULT_CLAWDIY_IMAGE="ghcr.io/openclaw/openclaw@sha256:d7e8c5c206b107c2e65b610f57f97408e8c07fe9d0ee5cc9193939e48ffb3006"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh"
MOLTIS_VERSION_HELPER="$PROJECT_ROOT/scripts/moltis-version.sh"
STORAGE_MAINTENANCE_SCRIPT="$PROJECT_ROOT/scripts/moltis-storage-maintenance.sh"
CLAWDIY_RUNTIME_ATTESTATION_SCRIPT="$PROJECT_ROOT/scripts/clawdiy-runtime-attestation.sh"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/moltis}"
DEPLOY_EVIDENCE_FILE=""
ROLLBACK_REASON="${ROLLBACK_REASON:-unspecified}"
VERIFY_FAILURE_REASON=""
CLAWDIY_HEALTH_CHECK_TIMEOUT="${CLAWDIY_HEALTH_CHECK_TIMEOUT:-420}"
DEPLOY_MUTEX_ENABLED="${DEPLOY_MUTEX_ENABLED:-true}"
DEPLOY_MUTEX_PATH="${DEPLOY_MUTEX_PATH:-/var/lock/moltinger/deploy.lock}"
DEPLOY_MUTEX_WAIT_SECONDS="${DEPLOY_MUTEX_WAIT_SECONDS:-3600}"
DEPLOY_MUTEX_TTL_SECONDS="${DEPLOY_MUTEX_TTL_SECONDS:-5400}"
DEPLOY_MUTEX_POLL_SECONDS="${DEPLOY_MUTEX_POLL_SECONDS:-5}"
DEPLOY_MUTEX_OWNER="${DEPLOY_MUTEX_OWNER:-}"
POST_DEPLOY_STORAGE_RECLAIM="${POST_DEPLOY_STORAGE_RECLAIM:-true}"
POST_DEPLOY_STORAGE_KEEP_PREDEPLOY_BACKUPS="${POST_DEPLOY_STORAGE_KEEP_PREDEPLOY_BACKUPS:-10}"
BROWSER_SANDBOX_SPEC_LABEL="io.moltinger.browser-sandbox.spec-sha"

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

record_verification_failure() {
    local message="$1"

    if [[ -z "$VERIFY_FAILURE_REASON" ]]; then
        VERIFY_FAILURE_REASON="$message"
    fi
    log_error "$message"
    return 0
}

verification_failure_recorded() {
    [[ -n "$VERIFY_FAILURE_REASON" ]]
}

output_json_result() {
    local status="$1"
    local action="$2"
    local health="$3"
    local duration_ms=0
    local services_json="[]"
    local errors_json="[]"
    local details="{}"

    if [[ $DEPLOY_START_TIME -gt 0 ]]; then
        duration_ms=$(( ($(date +%s) - DEPLOY_START_TIME) * 1000 ))
    fi

    if [[ ${#JSON_SERVICES[@]} -gt 0 ]]; then
        services_json=$(printf '%s\n' "${JSON_SERVICES[@]}" | jq -s '.')
    fi

    if [[ ${#JSON_ERRORS[@]} -gt 0 ]]; then
        errors_json=$(printf '%s\n' "${JSON_ERRORS[@]}" | jq -R '{code: "DEPLOY_ERROR", message: .}' | jq -s '.')
    fi

    details=$(jq -n \
        --arg image "$DEPLOY_IMAGE" \
        --argjson duration "$duration_ms" \
        --arg health "$health" \
        --arg evidence_file "$DEPLOY_EVIDENCE_FILE" \
        --arg restore_check_file "$DEPLOY_RESTORE_CHECK_FILE" \
        --arg verify_failure_reason "$VERIFY_FAILURE_REASON" \
        --argjson services "$services_json" \
        '{
            image: (if $image == "" then null else $image end),
            duration_ms: $duration,
            health: $health,
            services: $services,
            rollback_evidence_file: (if $evidence_file == "" then null else $evidence_file end),
            restore_check_file: (if $restore_check_file == "" then null else $restore_check_file end),
            verify_failure_reason: (if $verify_failure_reason == "" then null else $verify_failure_reason end)
        }')

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

dir_mode_allows_other_write_exec() {
    local path="$1"
    local mode last_digit

    mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
    if [[ -z "$mode" ]]; then
        mode="$(stat -f '%Mp%Lp' "$path" 2>/dev/null || true)"
    fi
    [[ -n "$mode" ]] || return 1

    last_digit="${mode: -1}"
    [[ -n "$last_digit" ]] || return 1

    (( (10#$last_digit & 2) == 2 && (10#$last_digit & 1) == 1 ))
}

read_toml_key() {
    local file_path="$1"
    local section="$2"
    local key="$3"

    awk -v section="$section" -v key="$key" '
        BEGIN { in_section = 0 }
        $0 ~ "^[[:space:]]*\\[.*\\][[:space:]]*$" {
            in_section = ($0 == section)
            next
        }
        in_section {
            line = $0
            sub(/[[:space:]]*#.*/, "", line)
            if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
                sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
                gsub(/^[[:space:]]*"/, "", line)
                gsub(/"[[:space:]]*$/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print line
                exit
            }
        }
    ' "$file_path"
}

extract_json_payload() {
    local raw_output="$1"

    awk '
        BEGIN { capture = 0 }
        /^[[:space:]]*[\[{]/ { capture = 1 }
        capture { print }
    ' <<<"$raw_output"
}

list_repo_skill_names() {
    local skills_dir="$PROJECT_ROOT/skills"
    local skill_dir
    shopt -s nullglob
    for skill_dir in "$skills_dir"/*; do
        [[ -d "$skill_dir" ]] || continue
        [[ -f "$skill_dir/SKILL.md" ]] || continue
        basename "$skill_dir"
    done | LC_ALL=C sort
    shopt -u nullglob
}

list_repo_hook_names() {
    local hooks_dir="$PROJECT_ROOT/.moltis/hooks"
    local hook_dir
    shopt -s nullglob
    for hook_dir in "$hooks_dir"/*; do
        [[ -d "$hook_dir" ]] || continue
        [[ -f "$hook_dir/HOOK.md" ]] || continue
        basename "$hook_dir"
    done | LC_ALL=C sort
    shopt -u nullglob
}

sync_moltis_repo_skills_into_runtime() {
    local sync_script="/server/scripts/moltis-repo-skills-sync.sh"

    if ! docker exec "$TARGET_CONTAINER" sh -lc "
        test -x '$sync_script' &&
        export MOLTIS_RUNTIME_SKILLS_PRUNE_UNMANAGED=1 &&
        '$sync_script' \
          --source-root '$MOLTIS_REPO_SKILLS_SOURCE_ROOT' \
          --target-root '$MOLTIS_RUNTIME_SKILLS_ROOT' \
          --manifest '$MOLTIS_RUNTIME_SKILLS_MANIFEST'
    " >/dev/null 2>&1; then
        record_verification_failure "Moltis runtime contract mismatch: failed to sync repo-managed skills into runtime discovery path"
        return 1
    fi

    return 0
}

sync_moltis_repo_hooks_into_runtime() {
    local sync_script="/server/scripts/moltis-repo-hooks-sync.sh"

    if ! docker exec "$TARGET_CONTAINER" sh -lc "
        test -x '$sync_script' &&
        '$sync_script' \
          --source-root '$MOLTIS_REPO_HOOKS_SOURCE_ROOT' \
          --target-root '$MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT' \
          --manifest '$MOLTIS_RUNTIME_PROJECT_HOOKS_MANIFEST'
    " >/dev/null 2>&1; then
        record_verification_failure "Moltis runtime contract mismatch: failed to sync repo-managed hooks into the runtime project hook discovery path"
        return 1
    fi

    return 0
}

prestage_moltis_repo_hooks_into_runtime() {
    local container_id hook_name
    local -a repo_hook_names=()

    while IFS= read -r hook_name; do
        [[ -n "$hook_name" ]] || continue
        repo_hook_names+=("$hook_name")
    done < <(list_repo_hook_names)

    if [[ ${#repo_hook_names[@]} -eq 0 ]]; then
        return 0
    fi

    container_id="$(docker ps -q --filter "name=^/${TARGET_CONTAINER}$" | head -1 || true)"
    [[ -n "$container_id" ]] || return 0

    sync_moltis_repo_hooks_into_runtime || return 1
    return 0
}

read_moltis_auth_password() {
    local password_file="$PROJECT_ROOT/secrets/moltis_password.txt"
    local password=""

    if [[ -f "$password_file" ]]; then
        password="$(tr -d '\r\n' < "$password_file")"
    elif read_env_file_value "MOLTIS_PASSWORD" >/dev/null 2>&1; then
        password="$(read_env_file_value "MOLTIS_PASSWORD")"
    fi

    [[ -n "$password" ]] || return 1
    printf '%s\n' "$password"
}

moltis_login_session() {
    local cookie_file="$1"
    local login_url="${TARGET_HEALTH_URL%/health}/api/auth/login"
    local password login_payload login_code

    password="$(read_moltis_auth_password 2>/dev/null || true)"
    if [[ -z "$password" ]]; then
        record_verification_failure "Moltis runtime contract mismatch: cannot authenticate live /api/skills verification because MOLTIS_PASSWORD is unavailable"
        return 1
    fi

    login_payload="$(jq -nc --arg password "$password" '{password:$password}')"
    login_code="$(
        curl -sS -o /dev/null -w '%{http_code}' \
            -c "$cookie_file" -b "$cookie_file" \
            -X POST "$login_url" \
            -H 'Content-Type: application/json' \
            -d "$login_payload" \
            --max-time 10 2>/dev/null || echo "000"
    )"

    if [[ "$login_code" != "200" ]]; then
        record_verification_failure "Moltis runtime contract mismatch: live /api/auth/login failed before /api/skills verification (HTTP $login_code)"
        return 1
    fi

    return 0
}

verify_moltis_repo_skills_discovery() {
    local skills_api_url repo_skill_name skills_json attempt cookie_file
    local -a repo_skill_names=()

    while IFS= read -r repo_skill_name; do
        [[ -n "$repo_skill_name" ]] || continue
        repo_skill_names+=("$repo_skill_name")
    done < <(list_repo_skill_names)

    if [[ ${#repo_skill_names[@]} -eq 0 ]]; then
        return 0
    fi

    sync_moltis_repo_skills_into_runtime || return 1

    for repo_skill_name in "${repo_skill_names[@]}"; do
        if ! docker exec "$TARGET_CONTAINER" sh -lc "
            test -f '$MOLTIS_RUNTIME_SKILLS_ROOT/$repo_skill_name/SKILL.md'
        " >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: synced runtime skill is missing SKILL.md for $repo_skill_name"
        fi
    done

    skills_api_url="${TARGET_HEALTH_URL%/health}/api/skills"
    cookie_file="$(mktemp)"
    if ! moltis_login_session "$cookie_file"; then
        rm -f "$cookie_file"
        return 1
    fi

    for attempt in {1..10}; do
        skills_json="$(curl -fsS -b "$cookie_file" -c "$cookie_file" "$skills_api_url" --max-time 10 2>/dev/null || true)"
        if [[ -n "$skills_json" ]]; then
            local missing_skill=0
            for repo_skill_name in "${repo_skill_names[@]}"; do
                if ! jq -e --arg skill_name "$repo_skill_name" '
                    .skills[]? | select(.name == $skill_name)
                ' <<<"$skills_json" >/dev/null; then
                    missing_skill=1
                    break
                fi
            done
            if [[ $missing_skill -eq 0 ]]; then
                rm -f "$cookie_file"
                return 0
            fi
        fi
        sleep 2
    done
    rm -f "$cookie_file"

    if [[ -z "$skills_json" ]]; then
        record_verification_failure "Moltis runtime contract mismatch: failed to query authenticated live /api/skills after repo skill sync"
    else
        for repo_skill_name in "${repo_skill_names[@]}"; do
            if ! jq -e --arg skill_name "$repo_skill_name" '
                .skills[]? | select(.name == $skill_name)
            ' <<<"$skills_json" >/dev/null; then
                record_verification_failure "Moltis runtime contract mismatch: authenticated live /api/skills does not expose repo-managed skill '$repo_skill_name'"
            fi
        done
    fi

    if verification_failure_recorded; then
        return 1
    fi

    return 0
}

verify_moltis_repo_hook_discovery() {
    local hook_name hooks_json hooks_output
    local -a repo_hook_names=()

    while IFS= read -r hook_name; do
        [[ -n "$hook_name" ]] || continue
        repo_hook_names+=("$hook_name")
    done < <(list_repo_hook_names)

    if [[ ${#repo_hook_names[@]} -eq 0 ]]; then
        return 0
    fi

    sync_moltis_repo_hooks_into_runtime || return 1

    for hook_name in "${repo_hook_names[@]}"; do
        if ! docker exec "$TARGET_CONTAINER" sh -lc "
            test -f '$MOLTIS_REPO_HOOKS_SOURCE_ROOT/$hook_name/HOOK.md'
        " >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: tracked repo hook bundle is missing HOOK.md for $hook_name under $MOLTIS_REPO_HOOKS_SOURCE_ROOT"
        fi
        if ! docker exec "$TARGET_CONTAINER" sh -lc "
            test -f '$MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT/$hook_name/HOOK.md'
        " >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: synced runtime hook is missing HOOK.md for $hook_name under $MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT"
        fi
    done

    hooks_output="$(docker exec "$TARGET_CONTAINER" moltis hooks list --json 2>/dev/null || true)"
    hooks_json="$(extract_json_payload "$hooks_output")"
    if [[ -z "$hooks_json" ]]; then
        record_verification_failure "Moltis runtime contract mismatch: failed to query live hook registration via 'moltis hooks list --json'"
        return 1
    fi

    for hook_name in "${repo_hook_names[@]}"; do
        if ! jq -e --arg hook_name "$hook_name" '
            .[] | select(
                .name == $hook_name and
                .source == "project" and
                .eligible == true and
                .path == ($runtime_root + "/" + $hook_name)
            )
        ' --arg runtime_root "$MOLTIS_RUNTIME_PROJECT_HOOKS_ROOT" <<<"$hooks_json" >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: repo-managed hook '$hook_name' is not registered from the active runtime project hook discovery path"
        fi
    done

    return 0
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
    local -a env_prefix=(env)
    local redirect_stdout=false

    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        compose_args+=(--env-file "$ENV_FILE")
    fi

    compose_args+=(-f "$COMPOSE_FILE")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        redirect_stdout=true
    fi

    if [[ "$TARGET" == "moltis" ]]; then
        local docker_socket_gid="${DOCKER_SOCKET_GID:-}"
        if [[ -z "$docker_socket_gid" && -S /var/run/docker.sock ]]; then
            docker_socket_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
        fi
        if [[ -z "$docker_socket_gid" ]]; then
            log_error "Moltis browser sandbox contract requires a detectable DOCKER_SOCKET_GID for /var/run/docker.sock"
            exit 2
        fi
        if [[ ! "$docker_socket_gid" =~ ^[0-9]+$ ]]; then
            log_error "DOCKER_SOCKET_GID must be numeric; got '$docker_socket_gid'"
            exit 2
        fi

        if [[ "${ALLOW_MOLTIS_VERSION_OVERRIDE:-false}" == "true" && -n "${MOLTIS_VERSION:-}" ]]; then
            env_prefix=(env "DOCKER_SOCKET_GID=$docker_socket_gid" "MOLTIS_VERSION=$MOLTIS_VERSION")
            if [[ "$redirect_stdout" == "true" ]]; then
                "${env_prefix[@]}" docker compose "${compose_args[@]}" "${args[@]}" 1>&2
            else
                "${env_prefix[@]}" docker compose "${compose_args[@]}" "${args[@]}"
            fi
        else
            env_prefix=(env -u MOLTIS_VERSION "DOCKER_SOCKET_GID=$docker_socket_gid")
            if [[ "$redirect_stdout" == "true" ]]; then
                "${env_prefix[@]}" docker compose "${compose_args[@]}" "${args[@]}" 1>&2
            else
                "${env_prefix[@]}" docker compose "${compose_args[@]}" "${args[@]}"
            fi
        fi
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

prepare_moltis_container_for_rollout() {
    local stop_timeout="${MOLTIS_STOP_TIMEOUT_SECONDS:-45}"
    local container_id=""

    if [[ "$TARGET" != "moltis" ]]; then
        return 0
    fi

    if [[ ! "$stop_timeout" =~ ^[0-9]+$ ]] || (( stop_timeout < 1 )); then
        log_error "MOLTIS_STOP_TIMEOUT_SECONDS must be a positive integer; got '$stop_timeout'"
        exit 2
    fi

    container_id="$(docker ps -aq --filter "name=^/${TARGET_CONTAINER}$" | head -1 || true)"
    [[ -n "$container_id" ]] || return 0

    if docker ps -q --filter "id=$container_id" | grep -q .; then
        log_json_stderr INFO "Stopping existing Moltis container '$TARGET_CONTAINER' with ${stop_timeout}s grace before rollout"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            if ! docker stop --timeout "$stop_timeout" "$TARGET_CONTAINER" 1>&2; then
                log_error "Failed to stop existing Moltis container: $TARGET_CONTAINER"
                exit 1
            fi
        else
            if ! docker stop --timeout "$stop_timeout" "$TARGET_CONTAINER"; then
                log_error "Failed to stop existing Moltis container: $TARGET_CONTAINER"
                exit 1
            fi
        fi
    fi

    container_id="$(docker ps -aq --filter "name=^/${TARGET_CONTAINER}$" | head -1 || true)"
    [[ -n "$container_id" ]] || return 0

    log_json_stderr INFO "Removing existing Moltis container '$TARGET_CONTAINER' before rollout"
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        if ! docker rm -f "$TARGET_CONTAINER" 1>&2; then
            log_error "Failed to remove existing Moltis container: $TARGET_CONTAINER"
            exit 1
        fi
    else
        if ! docker rm -f "$TARGET_CONTAINER"; then
            log_error "Failed to remove existing Moltis container: $TARGET_CONTAINER"
            exit 1
        fi
    fi
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
  "rollback_reason": $(printf '%s' "$reason" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
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
  "rollback_reason": $(printf '%s' "$reason" | jq -Rsc 'if . == "" then null else rtrimstr("\n") end'),
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
    local -a auxiliary_services=()
    local -a deploy_args=(up -d --remove-orphans)
    local service

    for service in "${TARGET_AUXILIARY_SERVICES[@]}"; do
        [[ -n "$service" ]] || continue
        deploy_services+=("$service")
        auxiliary_services+=("$service")
    done

    if [[ "$TARGET" == "moltis" ]]; then
        # Moltis loads runtime config at process start, so bind-mounted config
        # changes must force a recreate to avoid stale live state. Prestage the
        # repo-managed hook bundles into the runtime data-dir hook path before
        # recreate, because Moltis 0.10.18 discovers project hooks relative to
        # the active data_dir instead of the bind-mounted /server workspace.
        # Keep sidecars converged without forcing a second Moltis recreate in the
        # same compose transaction. Then pre-stop/remove the fixed-name Moltis
        # container and recreate only the Moltis service with --no-deps.
        if [[ ${#auxiliary_services[@]} -gt 0 ]]; then
            compose_cmd normal up -d --remove-orphans "${auxiliary_services[@]}"
        fi
        prestage_moltis_repo_hooks_into_runtime
        prepare_moltis_container_for_rollout
        compose_cmd normal up -d --no-deps --force-recreate "$TARGET_SERVICE"
        log_success "Containers deployed for target $TARGET"
        return 0
    fi

    compose_cmd normal "${deploy_args[@]}" "${deploy_services[@]}"
    log_success "Containers deployed for target $TARGET"
}

run_post_deploy_storage_reclaim() {
    if [[ "$TARGET" != "moltis" || "$POST_DEPLOY_STORAGE_RECLAIM" != "true" ]]; then
        return 0
    fi

    if [[ ! -x "$STORAGE_MAINTENANCE_SCRIPT" ]]; then
        log_warn "Skipping post-deploy storage reclaim because the maintenance script is not executable: $STORAGE_MAINTENANCE_SCRIPT"
        return 0
    fi

    log_info "Running post-deploy storage reclaim for Moltis"
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        if ! MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS="$POST_DEPLOY_STORAGE_KEEP_PREDEPLOY_BACKUPS" \
            "$STORAGE_MAINTENANCE_SCRIPT" reclaim \
                --ignore-deploy-mutex \
                --skip-journal-vacuum 1>&2; then
            log_warn "Post-deploy storage reclaim reported warnings; continuing because rollout is already healthy"
            return 0
        fi
    elif ! MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS="$POST_DEPLOY_STORAGE_KEEP_PREDEPLOY_BACKUPS" \
        "$STORAGE_MAINTENANCE_SCRIPT" reclaim \
            --ignore-deploy-mutex \
            --skip-journal-vacuum; then
        log_warn "Post-deploy storage reclaim reported warnings; continuing because rollout is already healthy"
        return 0
    fi

    log_success "Post-deploy storage reclaim completed"
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
            local rollback_version
            rollback_version="$(extract_moltis_version_tag "$last_image")"
            prepare_moltis_container_for_rollout
            ALLOW_MOLTIS_VERSION_OVERRIDE=true \
                MOLTIS_VERSION="$rollback_version" \
                compose_cmd normal up -d --no-deps --force-recreate "$TARGET_SERVICE"
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
    VERIFY_FAILURE_REASON=""

    if ! wait_for_healthy "$TARGET_CONTAINER" "$TARGET_HEALTH_TIMEOUT"; then
        record_verification_failure "Health wait timed out for target $TARGET"
    fi

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")
    if [[ "$http_code" != "200" ]]; then
        record_verification_failure "Health endpoint returned HTTP $http_code for target $TARGET"
    fi

    if [[ -n "$TARGET_METRICS_URL" ]]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_METRICS_URL" 2>/dev/null || echo "000")
        if [[ "$http_code" != "200" ]]; then
            log_warn "Metrics endpoint returned HTTP $http_code for target $TARGET (non-critical)"
        fi
    fi

    if [[ "$TARGET" == "clawdiy" ]]; then
        local attestation_config_file expected_default_model expected_version expected_image attestation_output attestation_message
        attestation_config_file="$CLAWDIY_CONFIG_FILE"
        if [[ -f "$CLAWDIY_RENDERED_CONFIG_FILE" ]]; then
            attestation_config_file="$CLAWDIY_RENDERED_CONFIG_FILE"
        fi

        if [[ ! -x "$CLAWDIY_RUNTIME_ATTESTATION_SCRIPT" ]]; then
            record_verification_failure "Clawdiy runtime attestation script is missing or not executable: $CLAWDIY_RUNTIME_ATTESTATION_SCRIPT"
        else
            expected_default_model="$(jq -r '.agents.defaults.model.primary // empty' "$attestation_config_file" 2>/dev/null || true)"
            expected_version="$(jq -r '.meta.lastTouchedVersion // empty' "$attestation_config_file" 2>/dev/null || true)"
            expected_image="$(resolve_clawdiy_image_ref || true)"

            if ! attestation_output="$("$CLAWDIY_RUNTIME_ATTESTATION_SCRIPT" \
                --json \
                --container "$TARGET_CONTAINER" \
                --base-url "$TARGET_HEALTH_URL" \
                --expected-image "$expected_image" \
                --expected-default-model "$expected_default_model" \
                --expected-version "$expected_version")"; then
                attestation_message="$(printf '%s' "$attestation_output" | jq -r '.errors[0].message // empty' 2>/dev/null || true)"
                record_verification_failure "${attestation_message:-Clawdiy runtime attestation failed}"
            elif [[ "$OUTPUT_JSON" != "true" ]]; then
                printf '%s\n' "$attestation_output" | jq . >&2 || true
            fi
        fi
    fi

    if [[ "$TARGET" == "moltis" ]]; then
        local expected_workspace expected_runtime_config
        local actual_workspace_source actual_runtime_config_source
        local actual_runtime_config_rw working_dir
        local browser_profile_dir browser_profile_root browser_persist_profile browser_max_instances actual_browser_profile_source actual_browser_profile_rw
        local tracked_runtime_toml runtime_runtime_toml

        working_dir="$(docker inspect --format '{{.Config.WorkingDir}}' "$TARGET_CONTAINER" 2>/dev/null || echo "")"
        if [[ "$working_dir" != "/server" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: working_dir is '$working_dir', expected '/server'"
        fi

        expected_workspace="$(canonicalize_existing_path "$PROJECT_ROOT" || printf '%s\n' "$PROJECT_ROOT")"
        actual_workspace_source="$(container_mount_source "$TARGET_CONTAINER" "/server")"
        if [[ -z "$actual_workspace_source" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: /server mount is missing in container $TARGET_CONTAINER"
        fi
        actual_workspace_source="$(canonicalize_existing_path "$actual_workspace_source" || printf '%s\n' "$actual_workspace_source")"
        if [[ "$actual_workspace_source" != "$expected_workspace" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: /server source is '$actual_workspace_source', expected '$expected_workspace'"
        fi

        expected_runtime_config="$(read_env_file_value "MOLTIS_RUNTIME_CONFIG_DIR" || true)"
        expected_runtime_config="${expected_runtime_config:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"
        expected_runtime_config="$(normalize_runtime_config_path "$expected_runtime_config")"
        if ! runtime_config_dir_allowed "$expected_runtime_config"; then
            record_verification_failure "Moltis runtime contract mismatch: runtime config dir '$expected_runtime_config' is outside the production allowlist '$MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST'"
        fi
        expected_runtime_config="$(canonicalize_existing_path "$expected_runtime_config" || printf '%s\n' "$expected_runtime_config")"
        actual_runtime_config_source="$(container_mount_source "$TARGET_CONTAINER" "/home/moltis/.config/moltis")"
        if [[ -z "$actual_runtime_config_source" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: runtime config mount is missing for /home/moltis/.config/moltis"
        fi
        actual_runtime_config_source="$(canonicalize_existing_path "$actual_runtime_config_source" || printf '%s\n' "$actual_runtime_config_source")"
        if [[ "$actual_runtime_config_source" != "$expected_runtime_config" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: runtime config source is '$actual_runtime_config_source', expected '$expected_runtime_config'"
        fi

        actual_runtime_config_rw="$(container_mount_rw "$TARGET_CONTAINER" "/home/moltis/.config/moltis")"
        if [[ "$actual_runtime_config_rw" != "true" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: runtime config mount must be writable for runtime-managed auth/key files"
        fi

        tracked_runtime_toml="$PROJECT_ROOT/config/moltis.toml"
        runtime_runtime_toml="$expected_runtime_config/moltis.toml"
        if [[ ! -f "$tracked_runtime_toml" || ! -f "$runtime_runtime_toml" ]]; then
            record_verification_failure "Moltis runtime contract mismatch: tracked or runtime moltis.toml is missing"
        fi
        if ! cmp -s "$tracked_runtime_toml" "$runtime_runtime_toml"; then
            record_verification_failure "Moltis runtime contract mismatch: runtime moltis.toml diverges from tracked config/moltis.toml"
        fi

        if ! docker exec "$TARGET_CONTAINER" sh -lc '
            test -d /server &&
            test -d /server/skills &&
            test -x /server/scripts/telegram-safe-llm-guard.sh &&
            test -f /server/.moltis/hooks/telegram-safe-llm-guard/HOOK.md &&
            test -x /server/.moltis/hooks/telegram-safe-llm-guard/handler.sh &&
            test -f /home/moltis/.config/moltis/moltis.toml &&
            tmp_path="/home/moltis/.config/moltis/provider_keys.json.tmp.contract-check.$$" &&
            : > "$tmp_path" &&
            rm -f "$tmp_path"
        ' >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: repo skills are not visible or runtime config is not writable inside the container"
        fi

        verify_moltis_repo_skills_discovery || true
        verify_moltis_repo_hook_discovery || true

        if ! docker exec "$TARGET_CONTAINER" sh -lc '
            sock_gid="$(stat -c %g /var/run/docker.sock)" &&
            id -G | tr " " "\n" | grep -qx "$sock_gid"
        ' >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: mounted docker.sock gid is not present in the live Moltis process groups"
        fi

        if ! docker exec "$TARGET_CONTAINER" sh -lc '
            grep -Eq "(^|[[:space:]])host\.docker\.internal([[:space:]]|$)" /etc/hosts
        ' >/dev/null 2>&1; then
            record_verification_failure "Moltis runtime contract mismatch: host.docker.internal is not mapped inside the live container for sibling browser connectivity"
        fi

        browser_profile_dir="$(read_toml_key "$tracked_runtime_toml" "[tools.browser]" "profile_dir" || true)"
        browser_persist_profile="$(read_toml_key "$tracked_runtime_toml" "[tools.browser]" "persist_profile" || true)"
        browser_max_instances="$(read_toml_key "$tracked_runtime_toml" "[tools.browser]" "max_instances" || true)"
        if [[ -n "$browser_profile_dir" ]]; then
            browser_profile_root="$(dirname "$browser_profile_dir")"
            actual_browser_profile_source="$(container_mount_source "$TARGET_CONTAINER" "$browser_profile_root")"
            if [[ -z "$actual_browser_profile_source" ]]; then
                log_error "Moltis browser contract mismatch: browser profile root mount '$browser_profile_root' is missing"
                return 1
            fi
            actual_browser_profile_source="$(canonicalize_existing_path "$actual_browser_profile_source" || printf '%s\n' "$actual_browser_profile_source")"
            browser_profile_root="$(canonicalize_existing_path "$browser_profile_root" || printf '%s\n' "$browser_profile_root")"
            browser_profile_dir="$(canonicalize_existing_path "$browser_profile_dir" || printf '%s\n' "$browser_profile_dir")"
            if [[ "$actual_browser_profile_source" != "$browser_profile_root" ]]; then
                log_error "Moltis browser contract mismatch: browser profile source is '$actual_browser_profile_source', expected '$browser_profile_root'"
                return 1
            fi

            actual_browser_profile_rw="$(container_mount_rw "$TARGET_CONTAINER" "$browser_profile_root")"
            if [[ "$actual_browser_profile_rw" != "true" ]]; then
                log_error "Moltis browser contract mismatch: browser profile mount '$browser_profile_root' must be writable"
                return 1
            fi

            if [[ ! -d "$browser_profile_root" || ! -d "$browser_profile_dir" ]]; then
                log_error "Moltis browser contract mismatch: browser profile root or configured dir is missing on host"
                return 1
            fi

            if ! dir_mode_allows_other_write_exec "$browser_profile_root" || ! dir_mode_allows_other_write_exec "$browser_profile_dir"; then
                log_error "Moltis browser contract mismatch: browser profile root/configured dir must be writable for arbitrary non-root browser users"
                return 1
            fi

            if [[ "$browser_profile_dir" == "$browser_profile_root" ]]; then
                log_error "Moltis browser contract mismatch: browser profile_dir must be a dedicated child path, not the mounted root itself"
                return 1
            fi

            if [[ "$browser_persist_profile" == "false" && "${browser_max_instances:-}" != "1" ]]; then
                log_error "Moltis browser contract mismatch: persist_profile=false requires max_instances=1 to avoid shared Chrome profile lock contention"
                return 1
            fi
        fi
    fi

    if verification_failure_recorded; then
        return 1
    fi

    log_success "Deployment verification passed for target $TARGET"
    return 0
}

prepare_moltis_browser_profile_dir() {
    local tracked_runtime_toml browser_profile_dir browser_profile_root browser_persist_profile browser_max_instances

    if [[ "$TARGET" != "moltis" ]]; then
        return 0
    fi

    tracked_runtime_toml="$PROJECT_ROOT/config/moltis.toml"
    browser_profile_dir="$(read_toml_key "$tracked_runtime_toml" "[tools.browser]" "profile_dir" || true)"
    browser_persist_profile="$(read_toml_key "$tracked_runtime_toml" "[tools.browser]" "persist_profile" || true)"
    browser_max_instances="$(read_toml_key "$tracked_runtime_toml" "[tools.browser]" "max_instances" || true)"
    if [[ -z "$browser_profile_dir" ]]; then
        log_error "Missing tools.browser.profile_dir in tracked config: $tracked_runtime_toml"
        return 1
    fi

    browser_profile_root="$(dirname "$browser_profile_dir")"
    if [[ "$browser_profile_root" != "$CANONICAL_MOLTIS_BROWSER_PROFILE_DIR" ]]; then
        log_error "Tracked browser profile root '$browser_profile_root' must stay under canonical mount root '$CANONICAL_MOLTIS_BROWSER_PROFILE_DIR'"
        return 1
    fi

    if [[ "$browser_profile_dir" == "$browser_profile_root" ]]; then
        log_error "Tracked browser profile_dir must be a dedicated child path under '$browser_profile_root'"
        return 1
    fi

    if [[ "$browser_persist_profile" == "false" && "${browser_max_instances:-}" != "1" ]]; then
        log_error "Tracked browser contract must pin max_instances=1 when persist_profile=false"
        return 1
    fi

    mkdir -p "$browser_profile_root"
    chmod 0777 "$browser_profile_root"
    rm -rf "$browser_profile_dir"
    mkdir -p "$browser_profile_dir"
    chmod 0777 "$browser_profile_dir"
    log_success "Prepared dedicated Moltis browser profile dir: $browser_profile_dir"
    return 0
}

browser_sandbox_spec_sha() {
    local sandbox_dockerfile="$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile"
    local sandbox_entrypoint="$PROJECT_ROOT/scripts/moltis-browser-sandbox/entrypoint.sh"

    if command -v sha256sum >/dev/null 2>&1; then
        {
            cat "$sandbox_dockerfile"
            printf '\0'
            cat "$sandbox_entrypoint"
        } | sha256sum | awk '{print $1}'
        return 0
    fi

    {
        cat "$sandbox_dockerfile"
        printf '\0'
        cat "$sandbox_entrypoint"
    } | shasum -a 256 | awk '{print $1}'
}

browser_sandbox_image_spec_sha() {
    local image_ref="$1"
    local label_value

    label_value="$(docker image inspect --format "{{ index .Config.Labels \"$BROWSER_SANDBOX_SPEC_LABEL\" }}" "$image_ref" 2>/dev/null || true)"
    if [[ "$label_value" == "<no value>" ]]; then
        label_value=""
    fi

    printf '%s\n' "$label_value"
}

prepare_moltis_browser_sandbox_image() {
    if [[ "$TARGET" != "moltis" ]]; then
        return 0
    fi

    local browser_contract browser_enabled sandbox_image sandbox_build_context sandbox_dockerfile desired_spec_sha existing_spec_sha
    browser_contract="$(awk '
        BEGIN {
            in_section = 0
            enabled = "true"
            image = "moltis-browserless-chrome:tracked"
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
        log_info "Tracked Moltis browser tool is disabled; skipping sandbox image preparation"
        return 0
    fi

    if [[ -z "$sandbox_image" || "$sandbox_image" == "null" ]]; then
        sandbox_image="moltis-browserless-chrome:tracked"
    fi

    if [[ "$sandbox_image" == "moltis-browserless-chrome:tracked" ]]; then
        sandbox_build_context="$PROJECT_ROOT/scripts/moltis-browser-sandbox"
        sandbox_dockerfile="$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile"
        if [[ ! -f "$sandbox_dockerfile" ]]; then
            log_error "Tracked Moltis browser sandbox Dockerfile is missing: $sandbox_dockerfile"
            return 1
        fi

        desired_spec_sha="$(browser_sandbox_spec_sha)"
        existing_spec_sha="$(browser_sandbox_image_spec_sha "$sandbox_image")"
        if [[ -n "$existing_spec_sha" && "$existing_spec_sha" == "$desired_spec_sha" ]]; then
            log_info "Tracked Moltis browser sandbox image is already current: $sandbox_image ($desired_spec_sha)"
            return 0
        fi

        log_info "Building tracked Moltis browser sandbox image: $sandbox_image"
        docker build \
            --build-arg BASE_IMAGE=browserless/chrome \
            --build-arg SANDBOX_SPEC_SHA="$desired_spec_sha" \
            -t "$sandbox_image" \
            -f "$sandbox_dockerfile" \
            "$sandbox_build_context" >/dev/null
        log_success "Tracked Moltis browser sandbox image built: $sandbox_image ($desired_spec_sha)"
        return 0
    fi

    log_info "Pulling Moltis browser sandbox image: $sandbox_image"
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
    prepare_moltis_browser_profile_dir
    prepare_moltis_browser_sandbox_image
    deploy_containers

    if verify_deployment; then
        DEPLOY_IMAGE="$(get_current_version)"
        add_json_services
        run_post_deploy_storage_reclaim

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
            if [[ -n "$VERIFY_FAILURE_REASON" ]]; then
                log_error "Auto rollback trigger reason: $VERIFY_FAILURE_REASON"
                ROLLBACK_REASON="deployment-verification-failed: $VERIFY_FAILURE_REASON"
            else
                ROLLBACK_REASON="deployment-verification-failed"
            fi
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
