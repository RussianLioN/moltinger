#!/usr/bin/env bash
# Prove that the live Moltis container still matches the tracked runtime provenance.

set -euo pipefail

OUTPUT_JSON=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_PATH="$(pwd)"
ACTIVE_PATH="/opt/moltinger-active"
MOLTIS_CONTAINER="moltis"
MOLTIS_URL="http://localhost:13131"
EXPECTED_GIT_SHA=""
EXPECTED_GIT_REF=""
EXPECTED_VERSION=""
EXPECTED_RUNTIME_CONFIG_DIR=""
EXPECTED_AUTH_PROVIDER=""
CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR="${CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}"
MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="${MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"
AUTH_PROVIDER_CANARY_PROMPT="${AUTH_PROVIDER_CANARY_PROMPT:-Reply with exactly OK and nothing else.}"
AUTH_PROVIDER_CANARY_WAIT_MS="${AUTH_PROVIDER_CANARY_WAIT_MS:-3000}"
AUTH_PROVIDER_CANARY_TIMEOUT_SECONDS="${AUTH_PROVIDER_CANARY_TIMEOUT_SECONDS:-25}"
BROWSER_ENABLED=""
BROWSER_SANDBOX_IMAGE=""
BROWSER_CONTAINER_HOST=""
BROWSER_MAX_INSTANCES=""
BROWSER_PROFILE_DIR=""
BROWSER_PERSIST_PROFILE=""
BROWSER_PROFILE_ROOT=""
BROWSER_PROFILE_SOURCE=""
BROWSER_PROFILE_RW=""
BROWSER_PROFILE_ROOT_WRITABLE=""
BROWSER_PROFILE_DIR_WRITABLE=""
DOCKER_SOCKET_SOURCE=""
DOCKER_SOCKET_GID=""
DOCKER_SOCKET_MODE=""
CONTAINER_GROUP_IDS=""
HOST_DOCKER_INTERNAL_MAPPED=""

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

usage() {
    cat <<'EOF'
Usage: moltis-runtime-attestation.sh [--json] [--deploy-path <path>] [--active-path <path>] \
  [--container <name>] [--base-url <url>] [--expected-git-sha <sha>] [--expected-git-ref <ref>] \
  [--expected-version <version>] [--expected-runtime-config-dir <path>] [--expected-auth-provider <provider>]

Verify the live Moltis runtime provenance against the tracked deploy contract:
  - active deploy root resolves to the live /server mount
  - recorded deployed SHA/version still match the active root and live binary
  - runtime config and runtime home mounts stay attached to the expected durable state
EOF
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
    local candidate normalized_candidate allowlist_entry normalized_allowlist old_ifs
    candidate="$1"
    normalized_candidate="$(normalize_runtime_config_path "$candidate" || true)"
    [[ -n "$normalized_candidate" ]] || return 1

    old_ifs="$IFS"
    IFS=':'
    for allowlist_entry in $MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST; do
        normalized_allowlist="$(normalize_runtime_config_path "$allowlist_entry" || true)"
        if [[ -n "$normalized_allowlist" && "$normalized_candidate" == "$normalized_allowlist" ]]; then
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"

    return 1
}

canonicalize_existing_path() {
    local path="$1"

    if [[ -z "$path" || ! -e "$path" ]]; then
        return 1
    fi

    if [[ -d "$path" ]]; then
        (
            cd "$path"
            pwd -P
        )
    else
        (
            cd "$(dirname "$path")"
            printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")"
        )
    fi
}

read_toml_key() {
    local toml_file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$toml_file" ]] || return 1

    awk -v section="$section" -v key="$key" '
        BEGIN { in_section = 0 }
        /^[[:space:]]*\[/ {
            in_section = ($0 == section)
            next
        }
        in_section && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*#.*$/, "", line)
            sub("^[^=]+=[[:space:]]*", "", line)
            gsub(/^"/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$toml_file"
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

read_env_file_value() {
    local env_file="$1"
    local key="$2"
    local value

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    value="$(grep -E "^${key}=" "$env_file" | tail -1 | cut -d'=' -f2- || true)"
    value="${value%\"}"
    value="${value#\"}"

    if [[ -z "$value" ]]; then
        return 1
    fi

    printf '%s' "$value"
}

auth_status_provider_line() {
    local raw="$1"
    local provider="$2"

    if [[ -z "$raw" || -z "$provider" ]]; then
        return 1
    fi

    printf '%s\n' "$raw" | grep -F "$provider" | head -n 1 || true
}

auth_status_provider_is_valid() {
    local provider_line="${1:-}"
    [[ -n "$provider_line" ]] || return 1
    grep -F '[valid' >/dev/null 2>&1 <<<"$provider_line"
}

auth_status_provider_is_expired() {
    local provider_line="${1:-}"
    [[ -n "$provider_line" ]] || return 1
    grep -F '[expired' >/dev/null 2>&1 <<<"$provider_line"
}

oauth_tokens_have_refresh_token() {
    local runtime_config_dir="$1"
    local provider="$2"
    local oauth_tokens_file="$runtime_config_dir/oauth_tokens.json"

    [[ -f "$oauth_tokens_file" ]] || return 1

    jq -e \
        --arg provider "$provider" \
        '((.[$provider].refresh_token // "") | type == "string") and ((.[$provider].refresh_token // "") | length > 0)' \
        "$oauth_tokens_file" >/dev/null 2>&1
}

run_auth_provider_canary() {
    local base_url="$1"
    local password="$2"
    local ws_rpc_cli script_ws_rpc_cli active_ws_rpc_cli deploy_ws_rpc_cli params_json

    [[ -n "$password" ]] || return 1
    command -v node >/dev/null 2>&1 || return 1

    script_ws_rpc_cli="$SCRIPT_DIR/../tests/lib/ws_rpc_cli.mjs"
    active_ws_rpc_cli="$ACTIVE_TARGET/tests/lib/ws_rpc_cli.mjs"
    deploy_ws_rpc_cli="$DEPLOY_PATH/tests/lib/ws_rpc_cli.mjs"
    if [[ -f "$script_ws_rpc_cli" ]]; then
        ws_rpc_cli="$script_ws_rpc_cli"
    elif [[ -f "$active_ws_rpc_cli" ]]; then
        ws_rpc_cli="$active_ws_rpc_cli"
    elif [[ -f "$deploy_ws_rpc_cli" ]]; then
        ws_rpc_cli="$deploy_ws_rpc_cli"
    else
        return 1
    fi

    params_json="$(jq -nc --arg text "$AUTH_PROVIDER_CANARY_PROMPT" '{text: $text}')"
    AUTH_CANARY_OUTPUT="$(
        TEST_BASE_URL="$base_url" \
        MOLTIS_PASSWORD="$password" \
        TEST_TIMEOUT="$AUTH_PROVIDER_CANARY_TIMEOUT_SECONDS" \
        node "$ws_rpc_cli" \
            request \
            --method chat.send \
            --params "$params_json" \
            --wait-ms "$AUTH_PROVIDER_CANARY_WAIT_MS" \
            --subscribe chat 2>/dev/null || true
    )"

    if ! jq -e '
        .ok == true and
        .result.ok == true and
        .result.payload.ok == true and
        ([.events[]? | select(.event == "chat" and .payload.state == "final")] | length) >= 1
    ' >/dev/null 2>&1 <<<"$AUTH_CANARY_OUTPUT"; then
        return 1
    fi

    return 0
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

container_exec_shell() {
    local command="$1"
    docker exec "$MOLTIS_CONTAINER" sh -lc "$command" 2>/dev/null || true
}

container_exec_ok() {
    local command="$1"
    docker exec "$MOLTIS_CONTAINER" sh -lc "$command" >/dev/null 2>&1
}

browser_contract_required() {
    [[ "$BROWSER_ENABLED" == "true" && -n "$BROWSER_SANDBOX_IMAGE" ]]
}

container_group_has_gid() {
    local groups="$1"
    local gid="$2"
    local group_id

    for group_id in $groups; do
        if [[ "$group_id" == "$gid" ]]; then
            return 0
        fi
    done

    return 1
}

container_state() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "not_found"
}

container_working_dir() {
    docker inspect --format '{{.Config.WorkingDir}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo ""
}

health_status_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${MOLTIS_URL%/}/health" 2>/dev/null || echo "000"
}

read_deployment_info_field() {
    local info_file="$1"
    local key="$2"
    local value

    if [[ ! -f "$info_file" ]]; then
        return 1
    fi

    value="$(grep -E "^${key}=" "$info_file" | tail -1 | cut -d'=' -f2- || true)"
    [[ -n "$value" ]] || return 1
    printf '%s' "$value"
}

emit_failure_json() {
    local code="$1"
    local message="$2"
    local deploy_path="$3"
    local active_path="$4"
    local active_target="${5:-}"
    local release_root_mode="${6:-unknown}"
    local container_state_value="${7:-unknown}"
    local http_code="${8:-000}"
    local recorded_git_sha="${9:-}"
    local live_git_sha="${10:-}"

    jq -n \
        --arg status "failure" \
        --arg target "moltis" \
        --arg action "runtime-attestation" \
        --arg timestamp "$(timestamp)" \
        --arg code "$code" \
        --arg message "$message" \
        --arg deploy_path "$deploy_path" \
        --arg active_path "$active_path" \
        --arg active_target "$active_target" \
        --arg release_root_mode "$release_root_mode" \
        --arg container_state "$container_state_value" \
        --arg http_code "$http_code" \
        --arg recorded_git_sha "$recorded_git_sha" \
        --arg live_git_sha "$live_git_sha" \
        --arg expected_auth_provider "${EXPECTED_AUTH_PROVIDER:-}" \
        --arg auth_status_raw "${AUTH_STATUS_RAW:-}" \
        --arg auth_status_post_canary "${AUTH_STATUS_POST_CANARY:-}" \
        --arg auth_status_valid "${AUTH_STATUS_VALID:-}" \
        --arg auth_validation_path "${AUTH_VALIDATION_PATH:-}" \
        --arg auth_canary_attempted "${AUTH_CANARY_ATTEMPTED:-}" \
        --arg auth_canary_succeeded "${AUTH_CANARY_SUCCEEDED:-}" \
        '{
          status: $status,
          target: $target,
          action: $action,
          timestamp: $timestamp,
          details: {
            deploy_path: $deploy_path,
            active_path: $active_path,
            active_target: (if $active_target == "" then null else $active_target end),
            release_root_mode: $release_root_mode,
            container_state: $container_state,
            http_code: $http_code,
            recorded_git_sha: (if $recorded_git_sha == "" then null else $recorded_git_sha end),
            live_git_sha: (if $live_git_sha == "" then null else $live_git_sha end),
            expected_auth_provider: (if $expected_auth_provider == "" then null else $expected_auth_provider end),
            auth_status_raw: (if $auth_status_raw == "" then null else $auth_status_raw end),
            auth_status_post_canary: (if $auth_status_post_canary == "" then null else $auth_status_post_canary end),
            auth_status_valid: (if $auth_status_valid == "" then null else ($auth_status_valid == "true") end),
            auth_validation_path: (if $auth_validation_path == "" then null else $auth_validation_path end),
            auth_canary_attempted: (if $auth_canary_attempted == "" then null else ($auth_canary_attempted == "true") end),
            auth_canary_succeeded: (if $auth_canary_succeeded == "" then null else ($auth_canary_succeeded == "true") end)
          },
          errors: [{code: $code, message: $message}]
        }'
}

fail_with() {
    local code="$1"
    local message="$2"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        emit_failure_json \
            "$code" \
            "$message" \
            "$DEPLOY_PATH" \
            "$ACTIVE_PATH" \
            "${ACTIVE_TARGET:-}" \
            "${RELEASE_ROOT_MODE:-unknown}" \
            "${CONTAINER_STATE_VALUE:-unknown}" \
            "${HTTP_CODE:-000}" \
            "${RECORDED_GIT_SHA:-}" \
            "${LIVE_GIT_SHA:-}"
    else
        echo "moltis-runtime-attestation.sh: [$code] $message" >&2
    fi
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --deploy-path)
            DEPLOY_PATH="${2:-}"
            shift 2
            ;;
        --active-path)
            ACTIVE_PATH="${2:-}"
            shift 2
            ;;
        --container)
            MOLTIS_CONTAINER="${2:-}"
            shift 2
            ;;
        --base-url)
            MOLTIS_URL="${2:-}"
            shift 2
            ;;
        --expected-git-sha)
            EXPECTED_GIT_SHA="${2:-}"
            shift 2
            ;;
        --expected-git-ref)
            EXPECTED_GIT_REF="${2:-}"
            shift 2
            ;;
        --expected-version)
            EXPECTED_VERSION="${2:-}"
            shift 2
            ;;
        --expected-runtime-config-dir)
            EXPECTED_RUNTIME_CONFIG_DIR="${2:-}"
            shift 2
            ;;
        --expected-auth-provider)
            EXPECTED_AUTH_PROVIDER="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "moltis-runtime-attestation.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

DEPLOY_PATH="$(cd "$DEPLOY_PATH" && pwd)"
ENV_FILE="$DEPLOY_PATH/.env"
ACTIVE_CANONICAL="$(canonicalize_existing_path "$ACTIVE_PATH" || true)"
ACTIVE_TARGET="${ACTIVE_CANONICAL:-}"
RELEASE_ROOT_MODE="unknown"
CONTAINER_STATE_VALUE="unknown"
HTTP_CODE="000"
RECORDED_GIT_SHA=""
RECORDED_GIT_REF=""
RECORDED_VERSION=""
RECORDED_WORKFLOW_RUN=""
RECORDED_DEPLOY_PATH=""
RECORDED_RUNTIME_CONFIG_DIR=""
LIVE_GIT_SHA=""
LIVE_GIT_REF=""
LIVE_VERSION=""
RUNTIME_CONFIG_RW=""
AUTH_STATUS_RAW=""
AUTH_STATUS_POST_CANARY=""
AUTH_STATUS_VALID=""
AUTH_VALIDATION_PATH=""
AUTH_CANARY_ATTEMPTED=""
AUTH_CANARY_SUCCEEDED=""
AUTH_CANARY_OUTPUT=""
TRACKED_RUNTIME_TOML=""
RUNTIME_RUNTIME_TOML=""

if [[ ! -L "$ACTIVE_PATH" ]]; then
    fail_with "ACTIVE_ROOT_NOT_SYMLINK" "Active deploy root is not a symlink: $ACTIVE_PATH"
fi

if [[ -z "$ACTIVE_TARGET" || ! -d "$ACTIVE_TARGET" ]]; then
    fail_with "ACTIVE_ROOT_TARGET_MISSING" "Active deploy root does not resolve to an existing directory: $ACTIVE_PATH"
fi

if [[ "$ACTIVE_TARGET" == "$DEPLOY_PATH" ]]; then
    RELEASE_ROOT_MODE="mutable-root"
else
    RELEASE_ROOT_MODE="active-symlink"
fi

DEPLOY_INFO_FILE="$ACTIVE_TARGET/data/.deployment-info"
DEPLOY_SHA_FILE="$ACTIVE_TARGET/data/.deployed-sha"
if [[ ! -f "$DEPLOY_INFO_FILE" && -f "$DEPLOY_PATH/data/.deployment-info" ]]; then
    DEPLOY_INFO_FILE="$DEPLOY_PATH/data/.deployment-info"
fi
if [[ ! -f "$DEPLOY_SHA_FILE" && -f "$DEPLOY_PATH/data/.deployed-sha" ]]; then
    DEPLOY_SHA_FILE="$DEPLOY_PATH/data/.deployed-sha"
fi

if [[ ! -f "$DEPLOY_SHA_FILE" ]]; then
    fail_with "DEPLOYED_SHA_MISSING" "Recorded deployed SHA file is missing: $DEPLOY_SHA_FILE"
fi
if [[ ! -f "$DEPLOY_INFO_FILE" ]]; then
    fail_with "DEPLOYMENT_INFO_MISSING" "Recorded deployment info file is missing: $DEPLOY_INFO_FILE"
fi

RECORDED_GIT_SHA="$(cat "$DEPLOY_SHA_FILE" 2>/dev/null || true)"
[[ -n "$RECORDED_GIT_SHA" ]] || fail_with "DEPLOYED_SHA_EMPTY" "Recorded deployed SHA is empty: $DEPLOY_SHA_FILE"

RECORDED_GIT_REF="$(read_deployment_info_field "$DEPLOY_INFO_FILE" "git_ref" || true)"
RECORDED_VERSION="$(read_deployment_info_field "$DEPLOY_INFO_FILE" "version" || true)"
RECORDED_WORKFLOW_RUN="$(read_deployment_info_field "$DEPLOY_INFO_FILE" "workflow_run" || true)"
RECORDED_DEPLOY_PATH="$(read_deployment_info_field "$DEPLOY_INFO_FILE" "deploy_path" || true)"
RECORDED_RUNTIME_CONFIG_DIR="$(read_deployment_info_field "$DEPLOY_INFO_FILE" "runtime_config_dir" || true)"

if [[ -n "$EXPECTED_GIT_REF" && -n "$RECORDED_GIT_REF" && "$EXPECTED_GIT_REF" != "$RECORDED_GIT_REF" ]]; then
    fail_with "RECORDED_GIT_REF_MISMATCH" "Recorded git ref '$RECORDED_GIT_REF' does not match expected '$EXPECTED_GIT_REF'"
fi

if [[ -n "$EXPECTED_VERSION" && -n "$RECORDED_VERSION" && "$EXPECTED_VERSION" != "$RECORDED_VERSION" ]]; then
    fail_with "RECORDED_VERSION_MISMATCH" "Recorded version '$RECORDED_VERSION' does not match expected '$EXPECTED_VERSION'"
fi

INFO_GIT_SHA="$(read_deployment_info_field "$DEPLOY_INFO_FILE" "git_sha" || true)"
if [[ -n "$INFO_GIT_SHA" && "$INFO_GIT_SHA" != "$RECORDED_GIT_SHA" ]]; then
    fail_with "DEPLOY_METADATA_MISMATCH" "Recorded deployment info git_sha '$INFO_GIT_SHA' does not match $DEPLOY_SHA_FILE value '$RECORDED_GIT_SHA'"
fi

if [[ -n "$EXPECTED_GIT_SHA" && "$RECORDED_GIT_SHA" != "$EXPECTED_GIT_SHA" ]]; then
    fail_with "RECORDED_GIT_SHA_MISMATCH" "Recorded deployed SHA '$RECORDED_GIT_SHA' does not match expected '$EXPECTED_GIT_SHA'"
fi

CONTAINER_STATE_VALUE="$(container_state)"
HTTP_CODE="$(health_status_code)"

if [[ "$CONTAINER_STATE_VALUE" != "healthy" && "$CONTAINER_STATE_VALUE" != "running" ]]; then
    fail_with "CONTAINER_NOT_READY" "Moltis container state is not ready: $CONTAINER_STATE_VALUE"
fi

if [[ "$HTTP_CODE" != "200" ]]; then
    fail_with "HEALTHCHECK_HTTP_MISMATCH" "Moltis /health returned HTTP $HTTP_CODE"
fi

WORKING_DIR="$(container_working_dir)"
if [[ "$WORKING_DIR" != "/server" ]]; then
    fail_with "WORKING_DIR_MISMATCH" "Moltis working_dir is '$WORKING_DIR', expected '/server'"
fi

WORKSPACE_SOURCE="$(container_mount_source "$MOLTIS_CONTAINER" "/server")"
if [[ -z "$WORKSPACE_SOURCE" ]]; then
    fail_with "WORKSPACE_MOUNT_MISSING" "Moltis container does not expose /server mount"
fi
WORKSPACE_SOURCE="$(canonicalize_existing_path "$WORKSPACE_SOURCE" || printf '%s\n' "$WORKSPACE_SOURCE")"
if [[ "$WORKSPACE_SOURCE" != "$ACTIVE_TARGET" ]]; then
    fail_with "WORKSPACE_PROVENANCE_MISMATCH" "Live /server mount source '$WORKSPACE_SOURCE' does not match active deploy target '$ACTIVE_TARGET'"
fi

if [[ -f "$ACTIVE_TARGET/.env" ]]; then
    ENV_FILE="$ACTIVE_TARGET/.env"
fi

EXPECTED_RUNTIME_CONFIG="${EXPECTED_RUNTIME_CONFIG_DIR:-}"
if [[ -z "$EXPECTED_RUNTIME_CONFIG" ]]; then
    EXPECTED_RUNTIME_CONFIG="$(read_env_file_value "$ENV_FILE" "MOLTIS_RUNTIME_CONFIG_DIR" || true)"
fi
EXPECTED_RUNTIME_CONFIG="${EXPECTED_RUNTIME_CONFIG:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"
EXPECTED_RUNTIME_CONFIG="$(normalize_runtime_config_path "$EXPECTED_RUNTIME_CONFIG")"
if ! runtime_config_dir_allowed "$EXPECTED_RUNTIME_CONFIG"; then
    fail_with "RUNTIME_CONFIG_ALLOWLIST_MISMATCH" "Runtime config dir '$EXPECTED_RUNTIME_CONFIG' is outside allowlist '$MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST'"
fi
if [[ ! -d "$EXPECTED_RUNTIME_CONFIG" ]]; then
    fail_with "RUNTIME_CONFIG_DIR_MISSING" "Expected runtime config dir is missing: $EXPECTED_RUNTIME_CONFIG"
fi
EXPECTED_RUNTIME_CONFIG="$(canonicalize_existing_path "$EXPECTED_RUNTIME_CONFIG" || printf '%s\n' "$EXPECTED_RUNTIME_CONFIG")"

RUNTIME_CONFIG_SOURCE="$(container_mount_source "$MOLTIS_CONTAINER" "/home/moltis/.config/moltis")"
if [[ -z "$RUNTIME_CONFIG_SOURCE" ]]; then
    fail_with "RUNTIME_CONFIG_MOUNT_MISSING" "Moltis runtime config mount is missing"
fi
RUNTIME_CONFIG_SOURCE="$(canonicalize_existing_path "$RUNTIME_CONFIG_SOURCE" || printf '%s\n' "$RUNTIME_CONFIG_SOURCE")"
if [[ "$RUNTIME_CONFIG_SOURCE" != "$EXPECTED_RUNTIME_CONFIG" ]]; then
    fail_with "RUNTIME_CONFIG_SOURCE_MISMATCH" "Runtime config source '$RUNTIME_CONFIG_SOURCE' does not match expected '$EXPECTED_RUNTIME_CONFIG'"
fi

RUNTIME_CONFIG_RW="$(container_mount_rw "$MOLTIS_CONTAINER" "/home/moltis/.config/moltis")"
if [[ "$RUNTIME_CONFIG_RW" != "true" ]]; then
    fail_with "RUNTIME_CONFIG_NOT_WRITABLE" "Runtime config mount for /home/moltis/.config/moltis must be writable"
fi

TRACKED_RUNTIME_TOML="$ACTIVE_TARGET/config/moltis.toml"
RUNTIME_RUNTIME_TOML="$EXPECTED_RUNTIME_CONFIG/moltis.toml"
if [[ ! -f "$TRACKED_RUNTIME_TOML" || ! -f "$RUNTIME_RUNTIME_TOML" ]]; then
    fail_with "RUNTIME_CONFIG_FILE_MISSING" "Tracked or runtime moltis.toml is missing; expected '$TRACKED_RUNTIME_TOML' and '$RUNTIME_RUNTIME_TOML'"
fi
if ! cmp -s "$TRACKED_RUNTIME_TOML" "$RUNTIME_RUNTIME_TOML"; then
    fail_with "RUNTIME_CONFIG_FILE_MISMATCH" "Runtime moltis.toml diverges from tracked config/moltis.toml"
fi

BROWSER_ENABLED="$(read_toml_key "$RUNTIME_RUNTIME_TOML" "[tools.browser]" "enabled" || true)"
BROWSER_SANDBOX_IMAGE="$(read_toml_key "$RUNTIME_RUNTIME_TOML" "[tools.browser]" "sandbox_image" || true)"
BROWSER_CONTAINER_HOST="$(read_toml_key "$RUNTIME_RUNTIME_TOML" "[tools.browser]" "container_host" || true)"
BROWSER_MAX_INSTANCES="$(read_toml_key "$RUNTIME_RUNTIME_TOML" "[tools.browser]" "max_instances" || true)"
BROWSER_PROFILE_DIR="$(read_toml_key "$RUNTIME_RUNTIME_TOML" "[tools.browser]" "profile_dir" || true)"
BROWSER_PERSIST_PROFILE="$(read_toml_key "$RUNTIME_RUNTIME_TOML" "[tools.browser]" "persist_profile" || true)"

if browser_contract_required; then
    if [[ -z "$BROWSER_SANDBOX_IMAGE" ]]; then
        fail_with "BROWSER_SANDBOX_IMAGE_MISSING" "Browser sandbox requires a tracked tools.browser.sandbox_image value"
    fi
    if ! docker image inspect "$BROWSER_SANDBOX_IMAGE" >/dev/null 2>&1; then
        fail_with "BROWSER_SANDBOX_IMAGE_UNAVAILABLE" "Tracked browser sandbox image is not available on the host: $BROWSER_SANDBOX_IMAGE"
    fi

    DOCKER_SOCKET_SOURCE="$(container_mount_source "$MOLTIS_CONTAINER" "/var/run/docker.sock")"
    if [[ -z "$DOCKER_SOCKET_SOURCE" ]]; then
        fail_with "BROWSER_DOCKER_SOCKET_MOUNT_MISSING" "Browser sandbox requires /var/run/docker.sock to be mounted into the Moltis container"
    fi

    if [[ -z "$BROWSER_CONTAINER_HOST" || "$BROWSER_CONTAINER_HOST" == "127.0.0.1" || "$BROWSER_CONTAINER_HOST" == "localhost" ]]; then
        fail_with "BROWSER_CONTAINER_HOST_INVALID" "Browser sandbox requires tools.browser.container_host to point to the host gateway when Moltis itself runs in Docker"
    fi

    CONTAINER_GROUP_IDS="$(container_exec_shell 'id -G')"
    DOCKER_SOCKET_GID="$(container_exec_shell 'stat -c "%g" /var/run/docker.sock')"
    DOCKER_SOCKET_MODE="$(container_exec_shell 'stat -c "%a" /var/run/docker.sock')"

    if [[ -z "$CONTAINER_GROUP_IDS" || -z "$DOCKER_SOCKET_GID" ]]; then
        fail_with "BROWSER_DOCKER_SOCKET_METADATA_MISSING" "Browser sandbox contract could not read docker socket ownership metadata from the live container"
    fi

    if ! container_group_has_gid "$CONTAINER_GROUP_IDS" "$DOCKER_SOCKET_GID"; then
        fail_with "BROWSER_DOCKER_SOCKET_GID_MISMATCH" "Browser sandbox docker.sock gid '$DOCKER_SOCKET_GID' is not present in the live Moltis process groups '$CONTAINER_GROUP_IDS'"
    fi

    if [[ "$BROWSER_CONTAINER_HOST" == "host.docker.internal" ]]; then
        if ! container_exec_ok 'grep -Eq "(^|[[:space:]])host\.docker\.internal([[:space:]]|$)" /etc/hosts'; then
            fail_with "BROWSER_CONTAINER_HOST_MAPPING_MISSING" "tools.browser.container_host points to host.docker.internal but the hostname is not mapped inside the live Moltis container"
        fi
        HOST_DOCKER_INTERNAL_MAPPED="true"
    fi

    if [[ -n "$BROWSER_PROFILE_DIR" ]]; then
        local_browser_profile_root="$(dirname "$BROWSER_PROFILE_DIR")"
        expected_browser_profile_root="$(canonicalize_existing_path "$local_browser_profile_root" || printf '%s\n' "$local_browser_profile_root")"
        expected_browser_profile_dir="$(canonicalize_existing_path "$BROWSER_PROFILE_DIR" || printf '%s\n' "$BROWSER_PROFILE_DIR")"

        BROWSER_PROFILE_SOURCE="$(container_mount_source "$MOLTIS_CONTAINER" "$local_browser_profile_root")"
        if [[ -z "$BROWSER_PROFILE_SOURCE" ]]; then
            fail_with "BROWSER_PROFILE_MOUNT_MISSING" "Moltis browser profile root '$local_browser_profile_root' is not mounted into the live container"
        fi
        BROWSER_PROFILE_SOURCE="$(canonicalize_existing_path "$BROWSER_PROFILE_SOURCE" || printf '%s\n' "$BROWSER_PROFILE_SOURCE")"
        if [[ "$BROWSER_PROFILE_SOURCE" != "$expected_browser_profile_root" ]]; then
            fail_with "BROWSER_PROFILE_SOURCE_MISMATCH" "Live browser profile source '$BROWSER_PROFILE_SOURCE' does not match tracked root '$expected_browser_profile_root'"
        fi

        BROWSER_PROFILE_RW="$(container_mount_rw "$MOLTIS_CONTAINER" "$local_browser_profile_root")"
        if [[ "$BROWSER_PROFILE_RW" != "true" ]]; then
            fail_with "BROWSER_PROFILE_MOUNT_NOT_WRITABLE" "Browser profile mount '$local_browser_profile_root' must be writable"
        fi

        if [[ ! -d "$expected_browser_profile_root" ]]; then
            fail_with "BROWSER_PROFILE_ROOT_MISSING" "Tracked browser profile root is missing on the host: $expected_browser_profile_root"
        fi
        if [[ ! -d "$expected_browser_profile_dir" ]]; then
            fail_with "BROWSER_PROFILE_DIR_MISSING" "Tracked browser profile dir is missing on the host: $expected_browser_profile_dir"
        fi
        if ! dir_mode_allows_other_write_exec "$expected_browser_profile_root"; then
            fail_with "BROWSER_PROFILE_ROOT_PERMISSION_MISMATCH" "Browser profile root '$expected_browser_profile_root' is not writable/traversable for arbitrary non-root users"
        fi
        if ! dir_mode_allows_other_write_exec "$expected_browser_profile_dir"; then
            fail_with "BROWSER_PROFILE_DIR_PERMISSION_MISMATCH" "Browser profile dir '$expected_browser_profile_dir' is not writable/traversable for arbitrary non-root users"
        fi
        if [[ "$expected_browser_profile_dir" == "$expected_browser_profile_root" ]]; then
            fail_with "BROWSER_PROFILE_DIR_ROOT_COLLISION" "Browser profile_dir must be a dedicated child path, not the mounted root itself"
        fi
        if [[ "$BROWSER_PERSIST_PROFILE" == "false" && "$BROWSER_MAX_INSTANCES" != "1" ]]; then
            fail_with "BROWSER_PROFILE_CONCURRENCY_MISMATCH" "Browser non-persistent profile contract requires max_instances=1 to avoid shared Chrome SingletonLock contention"
        fi

        BROWSER_PROFILE_ROOT="$expected_browser_profile_root"
        BROWSER_PROFILE_DIR="$expected_browser_profile_dir"
        BROWSER_PROFILE_ROOT_WRITABLE="true"
        BROWSER_PROFILE_DIR_WRITABLE="true"
    fi
fi

RUNTIME_HOME_SOURCE="$(container_mount_source "$MOLTIS_CONTAINER" "/home/moltis/.moltis")"
if [[ -z "$RUNTIME_HOME_SOURCE" ]]; then
    fail_with "RUNTIME_HOME_MOUNT_MISSING" "Moltis runtime home mount /home/moltis/.moltis is missing"
fi
RUNTIME_HOME_SOURCE="$(canonicalize_existing_path "$RUNTIME_HOME_SOURCE" || printf '%s\n' "$RUNTIME_HOME_SOURCE")"

LIVE_GIT_SHA="$(git -C "$ACTIVE_TARGET" rev-parse HEAD 2>/dev/null || true)"
LIVE_GIT_REF="$(git -C "$ACTIVE_TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -n "$RECORDED_GIT_SHA" && -n "$LIVE_GIT_SHA" && "$RECORDED_GIT_SHA" != "$LIVE_GIT_SHA" ]]; then
    fail_with "DEPLOYED_SHA_MISMATCH" "Recorded deployed SHA '$RECORDED_GIT_SHA' does not match active root HEAD '$LIVE_GIT_SHA'"
fi

LIVE_VERSION_RAW="$(docker exec "$MOLTIS_CONTAINER" moltis --version 2>/dev/null || true)"
LIVE_VERSION="${LIVE_VERSION_RAW##* }"
if [[ -n "$EXPECTED_VERSION" && -n "$LIVE_VERSION" && "$EXPECTED_VERSION" != "$LIVE_VERSION" ]]; then
    fail_with "LIVE_VERSION_MISMATCH" "Expected version '$EXPECTED_VERSION' does not match live Moltis version '$LIVE_VERSION'"
fi
if [[ -n "$RECORDED_VERSION" && -n "$LIVE_VERSION" && "$RECORDED_VERSION" != "$LIVE_VERSION" ]]; then
    fail_with "LIVE_VERSION_MISMATCH" "Recorded version '$RECORDED_VERSION' does not match live Moltis version '$LIVE_VERSION'"
fi

if [[ -n "$EXPECTED_AUTH_PROVIDER" ]]; then
    AUTH_STATUS_RAW="$(docker exec "$MOLTIS_CONTAINER" moltis auth status 2>/dev/null || true)"
    AUTH_PROVIDER_STATUS_LINE="$(auth_status_provider_line "$AUTH_STATUS_RAW" "$EXPECTED_AUTH_PROVIDER" || true)"

    if auth_status_provider_is_valid "$AUTH_PROVIDER_STATUS_LINE"; then
        AUTH_STATUS_VALID="true"
        AUTH_VALIDATION_PATH="status"
    elif auth_status_provider_is_expired "$AUTH_PROVIDER_STATUS_LINE" && oauth_tokens_have_refresh_token "$EXPECTED_RUNTIME_CONFIG" "$EXPECTED_AUTH_PROVIDER"; then
        AUTH_CANARY_ATTEMPTED="true"
        AUTH_CANARY_PASSWORD="$(read_env_file_value "$ENV_FILE" "MOLTIS_PASSWORD" || true)"

        if run_auth_provider_canary "$MOLTIS_URL" "$AUTH_CANARY_PASSWORD"; then
            AUTH_CANARY_SUCCEEDED="true"
            AUTH_STATUS_POST_CANARY="$(docker exec "$MOLTIS_CONTAINER" moltis auth status 2>/dev/null || true)"
            AUTH_PROVIDER_STATUS_LINE="$(auth_status_provider_line "$AUTH_STATUS_POST_CANARY" "$EXPECTED_AUTH_PROVIDER" || true)"
            if auth_status_provider_is_valid "$AUTH_PROVIDER_STATUS_LINE"; then
                AUTH_STATUS_VALID="true"
                AUTH_VALIDATION_PATH="refreshable-canary"
            else
                fail_with "AUTH_PROVIDER_INVALID_AFTER_CANARY" "Expected auth provider '$EXPECTED_AUTH_PROVIDER' remained non-valid after successful refresh canary"
            fi
        else
            fail_with "AUTH_PROVIDER_CANARY_FAILED" "Expected auth provider '$EXPECTED_AUTH_PROVIDER' was refreshable-but-expired and the runtime canary did not recover it"
        fi
    else
        fail_with "AUTH_PROVIDER_INVALID" "Expected valid auth provider '$EXPECTED_AUTH_PROVIDER' was not found in live Moltis auth status"
    fi
fi

if [[ "$OUTPUT_JSON" == "true" ]]; then
    jq -n \
        --arg status "success" \
        --arg target "moltis" \
        --arg action "runtime-attestation" \
        --arg timestamp "$(timestamp)" \
        --arg deploy_path "$DEPLOY_PATH" \
        --arg active_path "$ACTIVE_PATH" \
        --arg active_target "$ACTIVE_TARGET" \
        --arg release_root_mode "$RELEASE_ROOT_MODE" \
        --arg container "$MOLTIS_CONTAINER" \
        --arg container_state "$CONTAINER_STATE_VALUE" \
        --arg http_code "$HTTP_CODE" \
        --arg workspace_source "$WORKSPACE_SOURCE" \
        --arg runtime_config_source "$RUNTIME_CONFIG_SOURCE" \
        --arg runtime_home_source "$RUNTIME_HOME_SOURCE" \
        --arg recorded_git_sha "$RECORDED_GIT_SHA" \
        --arg recorded_git_ref "$RECORDED_GIT_REF" \
        --arg recorded_version "$RECORDED_VERSION" \
        --arg recorded_workflow_run "$RECORDED_WORKFLOW_RUN" \
        --arg recorded_deploy_path "$RECORDED_DEPLOY_PATH" \
        --arg recorded_runtime_config_dir "$RECORDED_RUNTIME_CONFIG_DIR" \
        --arg live_git_sha "$LIVE_GIT_SHA" \
        --arg live_git_ref "$LIVE_GIT_REF" \
        --arg live_version "$LIVE_VERSION" \
        --arg runtime_config_rw "$RUNTIME_CONFIG_RW" \
        --arg tracked_runtime_toml "$TRACKED_RUNTIME_TOML" \
        --arg runtime_runtime_toml "$RUNTIME_RUNTIME_TOML" \
        --arg browser_enabled "$BROWSER_ENABLED" \
        --arg browser_sandbox_image "$BROWSER_SANDBOX_IMAGE" \
        --arg browser_container_host "$BROWSER_CONTAINER_HOST" \
        --arg browser_max_instances "$BROWSER_MAX_INSTANCES" \
        --arg browser_profile_dir "$BROWSER_PROFILE_DIR" \
        --arg browser_profile_root "$BROWSER_PROFILE_ROOT" \
        --arg browser_profile_source "$BROWSER_PROFILE_SOURCE" \
        --arg browser_profile_rw "$BROWSER_PROFILE_RW" \
        --arg browser_persist_profile "$BROWSER_PERSIST_PROFILE" \
        --arg browser_profile_root_writable "$BROWSER_PROFILE_ROOT_WRITABLE" \
        --arg browser_profile_dir_writable "$BROWSER_PROFILE_DIR_WRITABLE" \
        --arg docker_socket_source "$DOCKER_SOCKET_SOURCE" \
        --arg docker_socket_gid "$DOCKER_SOCKET_GID" \
        --arg docker_socket_mode "$DOCKER_SOCKET_MODE" \
        --arg container_group_ids "$CONTAINER_GROUP_IDS" \
        --arg host_docker_internal_mapped "$HOST_DOCKER_INTERNAL_MAPPED" \
        --arg expected_auth_provider "$EXPECTED_AUTH_PROVIDER" \
        --arg auth_status_raw "$AUTH_STATUS_RAW" \
        --arg auth_status_post_canary "$AUTH_STATUS_POST_CANARY" \
        --arg auth_status_valid "$AUTH_STATUS_VALID" \
        --arg auth_validation_path "$AUTH_VALIDATION_PATH" \
        --arg auth_canary_attempted "$AUTH_CANARY_ATTEMPTED" \
        --arg auth_canary_succeeded "$AUTH_CANARY_SUCCEEDED" \
        '{
          status: $status,
          target: $target,
          action: $action,
          timestamp: $timestamp,
          details: {
            deploy_path: $deploy_path,
            active_path: $active_path,
            active_target: $active_target,
            release_root_mode: $release_root_mode,
            container: $container,
            container_state: $container_state,
            http_code: $http_code,
            workspace_source: $workspace_source,
            runtime_config_source: $runtime_config_source,
            runtime_home_source: $runtime_home_source,
            recorded_git_sha: (if $recorded_git_sha == "" then null else $recorded_git_sha end),
            recorded_git_ref: (if $recorded_git_ref == "" then null else $recorded_git_ref end),
            recorded_version: (if $recorded_version == "" then null else $recorded_version end),
            recorded_workflow_run: (if $recorded_workflow_run == "" then null else $recorded_workflow_run end),
            recorded_deploy_path: (if $recorded_deploy_path == "" then null else $recorded_deploy_path end),
            recorded_runtime_config_dir: (if $recorded_runtime_config_dir == "" then null else $recorded_runtime_config_dir end),
            live_git_sha: (if $live_git_sha == "" then null else $live_git_sha end),
            live_git_ref: (if $live_git_ref == "" then null else $live_git_ref end),
            live_version: (if $live_version == "" then null else $live_version end),
            runtime_config_rw: (if $runtime_config_rw == "" then null else $runtime_config_rw end),
            tracked_runtime_toml: (if $tracked_runtime_toml == "" then null else $tracked_runtime_toml end),
            runtime_runtime_toml: (if $runtime_runtime_toml == "" then null else $runtime_runtime_toml end),
            browser_enabled: (if $browser_enabled == "" then null else ($browser_enabled == "true") end),
            browser_sandbox_image: (if $browser_sandbox_image == "" then null else $browser_sandbox_image end),
            browser_container_host: (if $browser_container_host == "" then null else $browser_container_host end),
            browser_max_instances: (if $browser_max_instances == "" then null else ($browser_max_instances | tonumber) end),
            browser_profile_dir: (if $browser_profile_dir == "" then null else $browser_profile_dir end),
            browser_profile_root: (if $browser_profile_root == "" then null else $browser_profile_root end),
            browser_profile_source: (if $browser_profile_source == "" then null else $browser_profile_source end),
            browser_profile_rw: (if $browser_profile_rw == "" then null else $browser_profile_rw end),
            browser_persist_profile: (if $browser_persist_profile == "" then null else $browser_persist_profile end),
            browser_profile_root_writable: (if $browser_profile_root_writable == "" then null else ($browser_profile_root_writable == "true") end),
            browser_profile_dir_writable: (if $browser_profile_dir_writable == "" then null else ($browser_profile_dir_writable == "true") end),
            docker_socket_source: (if $docker_socket_source == "" then null else $docker_socket_source end),
            docker_socket_gid: (if $docker_socket_gid == "" then null else $docker_socket_gid end),
            docker_socket_mode: (if $docker_socket_mode == "" then null else $docker_socket_mode end),
            container_group_ids: (if $container_group_ids == "" then null else ($container_group_ids | split(" ")) end),
            host_docker_internal_mapped: (if $host_docker_internal_mapped == "" then null else ($host_docker_internal_mapped == "true") end),
            expected_auth_provider: (if $expected_auth_provider == "" then null else $expected_auth_provider end),
            auth_status_raw: (if $auth_status_raw == "" then null else $auth_status_raw end),
            auth_status_post_canary: (if $auth_status_post_canary == "" then null else $auth_status_post_canary end),
            auth_status_valid: (if $auth_status_valid == "" then null else ($auth_status_valid == "true") end),
            auth_validation_path: (if $auth_validation_path == "" then null else $auth_validation_path end),
            auth_canary_attempted: (if $auth_canary_attempted == "" then null else ($auth_canary_attempted == "true") end),
            auth_canary_succeeded: (if $auth_canary_succeeded == "" then null else ($auth_canary_succeeded == "true") end)
          },
          errors: []
        }'
else
    cat <<EOF
[OK] Moltis runtime attestation passed
deploy_path=$DEPLOY_PATH
active_path=$ACTIVE_PATH
active_target=$ACTIVE_TARGET
release_root_mode=$RELEASE_ROOT_MODE
workspace_source=$WORKSPACE_SOURCE
runtime_config_source=$RUNTIME_CONFIG_SOURCE
runtime_home_source=$RUNTIME_HOME_SOURCE
recorded_git_sha=${RECORDED_GIT_SHA:-unknown}
live_git_sha=${LIVE_GIT_SHA:-unknown}
recorded_version=${RECORDED_VERSION:-unknown}
live_version=${LIVE_VERSION:-unknown}
runtime_config_rw=${RUNTIME_CONFIG_RW:-unknown}
tracked_runtime_toml=${TRACKED_RUNTIME_TOML:-unknown}
runtime_runtime_toml=${RUNTIME_RUNTIME_TOML:-unknown}
browser_enabled=${BROWSER_ENABLED:-unknown}
browser_sandbox_image=${BROWSER_SANDBOX_IMAGE:-none}
browser_container_host=${BROWSER_CONTAINER_HOST:-none}
browser_max_instances=${BROWSER_MAX_INSTANCES:-unknown}
browser_profile_dir=${BROWSER_PROFILE_DIR:-none}
browser_profile_root=${BROWSER_PROFILE_ROOT:-none}
browser_profile_source=${BROWSER_PROFILE_SOURCE:-none}
browser_profile_rw=${BROWSER_PROFILE_RW:-unknown}
browser_persist_profile=${BROWSER_PERSIST_PROFILE:-unknown}
browser_profile_root_writable=${BROWSER_PROFILE_ROOT_WRITABLE:-skipped}
browser_profile_dir_writable=${BROWSER_PROFILE_DIR_WRITABLE:-skipped}
docker_socket_source=${DOCKER_SOCKET_SOURCE:-none}
docker_socket_gid=${DOCKER_SOCKET_GID:-none}
docker_socket_mode=${DOCKER_SOCKET_MODE:-none}
container_group_ids=${CONTAINER_GROUP_IDS:-none}
host_docker_internal_mapped=${HOST_DOCKER_INTERNAL_MAPPED:-false}
expected_auth_provider=${EXPECTED_AUTH_PROVIDER:-none}
auth_status_raw=${AUTH_STATUS_RAW:-none}
auth_status_post_canary=${AUTH_STATUS_POST_CANARY:-none}
auth_status_valid=${AUTH_STATUS_VALID:-skipped}
auth_validation_path=${AUTH_VALIDATION_PATH:-skipped}
auth_canary_attempted=${AUTH_CANARY_ATTEMPTED:-false}
auth_canary_succeeded=${AUTH_CANARY_SUCCEEDED:-false}
EOF
fi
