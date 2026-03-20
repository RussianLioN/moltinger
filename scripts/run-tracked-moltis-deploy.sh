#!/bin/bash
# Shared remote entrypoint for tracked Moltis deploy orchestration.

set -euo pipefail

OUTPUT_JSON=false
DRY_RUN=false
DEPLOY_PATH="$(pwd)"
GIT_SHA=""
GIT_REF=""
WORKFLOW_RUN=""
EXPECTED_VERSION=""
TRACKED_VERSION=""
RUNTIME_CONFIG_DIR=""
MOLTIS_DOMAIN_VALUE="moltis.ainetic.tech"

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_info() {
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "[run-tracked-moltis-deploy] $*" >&2
    else
        echo "[run-tracked-moltis-deploy] $*"
    fi
}

usage() {
    cat <<'EOF'
Usage: run-tracked-moltis-deploy.sh [--json] [--dry-run] [--deploy-path <path>] \
  --git-sha <sha> --git-ref <ref> --workflow-run <run-id> [--version <version>]

Runs the tracked Moltis deploy control plane on the remote host:
  1. prepare writable runtime config
  2. validate tracked deploy contract
  3. call scripts/deploy.sh --json moltis deploy
  4. record deployed git SHA + deployment metadata
  5. align the server checkout to the deployed commit
EOF
}

emit_failure_json() {
    local message="$1"
    local health="${2:-failed}"
    local rollback_verified="${3:-false}"

    jq -n \
        --arg status "failure" \
        --arg target "moltis" \
        --arg action "tracked-deploy" \
        --arg timestamp "$(timestamp)" \
        --arg message "$message" \
        --arg git_sha "$GIT_SHA" \
        --arg git_ref "$GIT_REF" \
        --arg workflow_run "$WORKFLOW_RUN" \
        --arg runtime_config_dir "${RUNTIME_CONFIG_DIR:-}" \
        --arg tracked_version "${TRACKED_VERSION:-${EXPECTED_VERSION:-}}" \
        --arg health "$health" \
        --argjson rollback_verified "$rollback_verified" \
        '{
          status: $status,
          target: $target,
          timestamp: $timestamp,
          action: $action,
          details: {
            health: $health,
            git_sha: $git_sha,
            git_ref: $git_ref,
            workflow_run: $workflow_run,
            runtime_config_dir: (if $runtime_config_dir == "" then null else $runtime_config_dir end),
            tracked_version: (if $tracked_version == "" then null else $tracked_version end),
            rollback_verified: $rollback_verified
          },
          errors: [{code: "TRACKED_DEPLOY_ERROR", message: $message}]
        }'
}

append_result_context() {
    local base_json="$1"
    local final_status="$2"
    local rollback_verified="$3"
    local extra_error="${4:-}"

    if ! jq empty >/dev/null 2>&1 <<<"$base_json"; then
        emit_failure_json "run-tracked-moltis-deploy.sh received non-JSON output from deploy.sh" "failed" "$rollback_verified"
        return
    fi

    jq \
        --arg final_status "$final_status" \
        --arg action "tracked-deploy" \
        --arg git_sha "$GIT_SHA" \
        --arg git_ref "$GIT_REF" \
        --arg workflow_run "$WORKFLOW_RUN" \
        --arg runtime_config_dir "$RUNTIME_CONFIG_DIR" \
        --arg tracked_version "${TRACKED_VERSION:-$EXPECTED_VERSION}" \
        --arg extra_error "$extra_error" \
        --argjson rollback_verified "$rollback_verified" \
        '
        .status = $final_status
        | .action = $action
        | .details = ((.details // {}) + {
            git_sha: $git_sha,
            git_ref: $git_ref,
            workflow_run: $workflow_run,
            runtime_config_dir: $runtime_config_dir,
            tracked_version: $tracked_version,
            rollback_verified: $rollback_verified
          })
        | if $extra_error == "" then
            .
          else
            .errors = ((.errors // []) + [{code: "TRACKED_DEPLOY_ERROR", message: $extra_error}])
          end
        ' <<<"$base_json"
}

require_argument() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "run-tracked-moltis-deploy.sh: missing required argument: $key" >&2
        usage >&2
        exit 2
    fi
}

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        local message="Missing required file: $path"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            emit_failure_json "$message"
        else
            echo "$message" >&2
        fi
        exit 1
    fi
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

load_runtime_settings() {
    local env_file="$DEPLOY_PATH/.env"
    require_file "$env_file"

    RUNTIME_CONFIG_DIR="$(read_env_file_value "$env_file" "MOLTIS_RUNTIME_CONFIG_DIR" || true)"
    [[ -n "$RUNTIME_CONFIG_DIR" ]] || RUNTIME_CONFIG_DIR="/opt/moltinger-state/config-runtime"

    MOLTIS_DOMAIN_VALUE="$(read_env_file_value "$env_file" "MOLTIS_DOMAIN" || true)"
    [[ -n "$MOLTIS_DOMAIN_VALUE" ]] || MOLTIS_DOMAIN_VALUE="moltis.ainetic.tech"
}

prepare_runtime_config() {
    mkdir -p "$RUNTIME_CONFIG_DIR"
    bash "$DEPLOY_PATH/scripts/prepare-moltis-runtime-config.sh" \
        "$DEPLOY_PATH/config" \
        "$RUNTIME_CONFIG_DIR" >&2
    test -f "$RUNTIME_CONFIG_DIR/moltis.toml"
}

validate_tracked_contract() {
    if grep -q '^MOLTIS_VERSION=' "$DEPLOY_PATH/.env" 2>/dev/null; then
        local message="MOLTIS_VERSION override is forbidden in $DEPLOY_PATH/.env; track Moltis version in git compose files instead"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            emit_failure_json "$message"
        else
            echo "$message" >&2
        fi
        exit 1
    fi

    TRACKED_VERSION="$("$DEPLOY_PATH/scripts/moltis-version.sh" version)"
    if [[ -n "$EXPECTED_VERSION" && "$EXPECTED_VERSION" != "$TRACKED_VERSION" ]]; then
        local message="Workflow version $EXPECTED_VERSION does not match tracked git version $TRACKED_VERSION"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            emit_failure_json "$message"
        else
            echo "$message" >&2
        fi
        exit 1
    fi

    "$DEPLOY_PATH/scripts/moltis-version.sh" assert-tracked >/dev/null
    env -u MOLTIS_VERSION docker compose -f "$DEPLOY_PATH/docker-compose.prod.yml" config --quiet >/dev/null

    if ! grep -q "traefik.enable=true" "$DEPLOY_PATH/docker-compose.prod.yml"; then
        local message="Traefik labels missing in docker-compose.prod.yml"
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            emit_failure_json "$message"
        else
            echo "$message" >&2
        fi
        exit 1
    fi
}

record_deployment_state() {
    mkdir -p "$DEPLOY_PATH/data"
    printf '%s\n' "$GIT_SHA" > "$DEPLOY_PATH/data/.deployed-sha"

    cat > "$DEPLOY_PATH/data/.deployment-info" <<EOF
deployed_at=$(timestamp)
git_sha=$GIT_SHA
workflow_run=$WORKFLOW_RUN
version=${TRACKED_VERSION:-$EXPECTED_VERSION}
EOF
}

align_checkout() {
    (
        cd "$DEPLOY_PATH"
        git fetch --depth=1 origin "$GIT_REF" >&2
        git checkout --force "$GIT_REF" >&2
        git reset --hard "$GIT_SHA" >&2
        git status --short >&2 || true
    )
}

verify_rollback_health() {
    local container_health
    local local_http_code
    local external_http_code
    local domain

    container_health="$(docker inspect --format='{{.State.Health.Status}}' moltis 2>/dev/null || echo "not_found")"
    if [[ "$container_health" != "healthy" ]]; then
        log_info "Post-rollback container health is not healthy: $container_health"
        return 1
    fi

    local_http_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:13131/health 2>/dev/null || echo "000")"
    if [[ "$local_http_code" != "200" ]]; then
        log_info "Post-rollback localhost health returned HTTP $local_http_code"
        return 1
    fi

    domain="$MOLTIS_DOMAIN_VALUE"
    external_http_code="$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${domain}/health" 2>/dev/null || echo "000")"
    if [[ "$external_http_code" != "200" && "$external_http_code" != "401" ]]; then
        log_info "Post-rollback external health returned HTTP $external_http_code"
        return 1
    fi

    return 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --deploy-path)
            DEPLOY_PATH="${2:-}"
            shift 2
            ;;
        --git-sha)
            GIT_SHA="${2:-}"
            shift 2
            ;;
        --git-ref)
            GIT_REF="${2:-}"
            shift 2
            ;;
        --workflow-run)
            WORKFLOW_RUN="${2:-}"
            shift 2
            ;;
        --version)
            EXPECTED_VERSION="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "run-tracked-moltis-deploy.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_argument "--git-sha" "$GIT_SHA"
require_argument "--git-ref" "$GIT_REF"
require_argument "--workflow-run" "$WORKFLOW_RUN"

DEPLOY_PATH="$(cd "$DEPLOY_PATH" && pwd)"

require_file "$DEPLOY_PATH/scripts/prepare-moltis-runtime-config.sh"
require_file "$DEPLOY_PATH/scripts/moltis-version.sh"
require_file "$DEPLOY_PATH/scripts/deploy.sh"
require_file "$DEPLOY_PATH/docker-compose.prod.yml"
require_file "$DEPLOY_PATH/config/moltis.toml"

load_runtime_settings

if [[ "$DRY_RUN" == "true" ]]; then
    TRACKED_VERSION="${EXPECTED_VERSION:-dry-run}"
    jq -n \
        --arg status "dry-run" \
        --arg target "moltis" \
        --arg action "tracked-deploy" \
        --arg timestamp "$(timestamp)" \
        --arg deploy_path "$DEPLOY_PATH" \
        --arg git_sha "$GIT_SHA" \
        --arg git_ref "$GIT_REF" \
        --arg workflow_run "$WORKFLOW_RUN" \
        --arg runtime_config_dir "$RUNTIME_CONFIG_DIR" \
        --arg tracked_version "$TRACKED_VERSION" \
        '{
          status: $status,
          target: $target,
          timestamp: $timestamp,
          action: $action,
          details: {
            deploy_path: $deploy_path,
            git_sha: $git_sha,
            git_ref: $git_ref,
            workflow_run: $workflow_run,
            runtime_config_dir: $runtime_config_dir,
            tracked_version: $tracked_version,
            planned_steps: [
              "prepare-runtime-config",
              "validate-tracked-contract",
              "deploy-via-deploy-sh",
              "record-deployed-state",
              "align-server-checkout"
            ]
          },
          errors: []
        }'
    exit 0
fi

log_info "Preparing writable Moltis runtime config"
if ! prepare_runtime_config; then
    emit_failure_json "Failed to prepare writable Moltis runtime config"
    exit 1
fi

log_info "Validating tracked Moltis deploy contract"
validate_tracked_contract

log_info "Running tracked Moltis deploy via scripts/deploy.sh"
set +e
DEPLOY_OUTPUT="$("$DEPLOY_PATH/scripts/deploy.sh" --json moltis deploy)"
DEPLOY_EXIT=$?
set -e

DEPLOY_STATUS="$(jq -r '.status // empty' <<<"$DEPLOY_OUTPUT" 2>/dev/null || true)"
DEPLOY_HEALTH="$(jq -r '.details.health // empty' <<<"$DEPLOY_OUTPUT" 2>/dev/null || true)"
ROLLBACK_VERIFIED=false

if [[ "$DEPLOY_EXIT" -eq 0 && "$DEPLOY_STATUS" == "success" ]]; then
    log_info "Recording deployed git SHA and deployment metadata"
    if ! record_deployment_state; then
        emit_failure_json "Deploy succeeded but recording deployment metadata failed" "healthy"
        exit 1
    fi

    log_info "Aligning server git checkout to deployed commit"
    if ! align_checkout; then
        emit_failure_json "Deploy succeeded but aligning the server checkout failed" "healthy"
        exit 1
    fi

    append_result_context "$DEPLOY_OUTPUT" "success" "$ROLLBACK_VERIFIED"
    exit 0
fi

if [[ "$DEPLOY_HEALTH" == "rolled_back" ]]; then
    if verify_rollback_health; then
        ROLLBACK_VERIFIED=true
    fi
fi

append_result_context \
    "$DEPLOY_OUTPUT" \
    "failure" \
    "$ROLLBACK_VERIFIED" \
    "Tracked Moltis deploy failed before reaching a healthy deployed state"
exit 1
