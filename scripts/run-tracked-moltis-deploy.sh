#!/bin/bash
# Shared remote entrypoint for tracked Moltis deploy orchestration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
ACTIVE_DEPLOY_PATH="${ACTIVE_DEPLOY_PATH:-/opt/moltinger-active}"
CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR="${CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}"
MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="${MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"

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
  [--active-path <path>] --git-sha <sha> --git-ref <ref> --workflow-run <run-id> [--version <version>]

Runs the tracked Moltis deploy control plane on the remote host:
  1. prepare writable runtime config
  2. validate tracked deploy contract
  3. call scripts/deploy.sh --json moltis deploy
  4. record deployed git SHA + deployment metadata
  5. align the server checkout to the deployed commit
  6. attest the live runtime provenance against the tracked intent
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
    local candidate normalized_candidate allowlist_entry normalized_allowlist
    candidate="$1"
    normalized_candidate="$(normalize_runtime_config_path "$candidate" || true)"
    [[ -n "$normalized_candidate" ]] || return 1

    OLD_IFS="$IFS"
    IFS=':'
    for allowlist_entry in $MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST; do
        normalized_allowlist="$(normalize_runtime_config_path "$allowlist_entry" || true)"
        if [[ -n "$normalized_allowlist" && "$normalized_candidate" == "$normalized_allowlist" ]]; then
            IFS="$OLD_IFS"
            return 0
        fi
    done
    IFS="$OLD_IFS"

    return 1
}

validate_runtime_config_dir_policy() {
    local candidate="$1"
    local message

    if runtime_config_dir_allowed "$candidate"; then
        return 0
    fi

    message="Moltis runtime config dir '$candidate' is outside the production allowlist '$MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST'"
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        emit_failure_json "$message"
    else
        echo "$message" >&2
    fi
    exit 1
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
    RUNTIME_CONFIG_DIR="$(normalize_runtime_config_path "$RUNTIME_CONFIG_DIR")"
    validate_runtime_config_dir_policy "$RUNTIME_CONFIG_DIR"

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
    local target_root="$1"

    mkdir -p "$target_root/data"
    printf '%s\n' "$GIT_SHA" > "$target_root/data/.deployed-sha"

    cat > "$target_root/data/.deployment-info" <<EOF
deployed_at=$(timestamp)
git_sha=$GIT_SHA
git_ref=$GIT_REF
workflow_run=$WORKFLOW_RUN
version=${TRACKED_VERSION:-$EXPECTED_VERSION}
deploy_path=$DEPLOY_PATH
active_path=$ACTIVE_DEPLOY_PATH
runtime_config_dir=$RUNTIME_CONFIG_DIR
audit_root=$target_root
EOF
}

resolve_active_target() {
    if [[ -d "$ACTIVE_DEPLOY_PATH" ]]; then
        (
            cd "$ACTIVE_DEPLOY_PATH"
            pwd -P
        )
    fi
}

record_deployment_markers() {
    local active_target=""

    record_deployment_state "$DEPLOY_PATH"

    active_target="$(resolve_active_target || true)"
    if [[ -n "$active_target" && "$active_target" != "$DEPLOY_PATH" ]]; then
        record_deployment_state "$active_target"
    fi
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
        --active-path)
            ACTIVE_DEPLOY_PATH="${2:-}"
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
require_file "$DEPLOY_PATH/scripts/moltis-runtime-attestation.sh"
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
              "align-server-checkout",
              "attest-live-runtime"
            ]
          },
          errors: []
        }'
    exit 0
fi

bash "$SCRIPT_DIR/prod-mutation-guard.sh" \
    --action "run-tracked-moltis-deploy" \
    --target-path "$DEPLOY_PATH" \
    --expected-ref "$GIT_REF" \
    --expected-sha "$GIT_SHA"

log_info "Preparing writable Moltis runtime config"
if ! prepare_runtime_config; then
    emit_failure_json "Failed to prepare writable Moltis runtime config"
    exit 1
fi

log_info "Validating tracked Moltis deploy contract"
validate_tracked_contract

log_info "Running tracked Moltis deploy via scripts/deploy.sh"
set +e
DEPLOY_OUTPUT="$(
    env \
        GITHUB_ACTIONS="${GITHUB_ACTIONS:-true}" \
        GITHUB_RUN_ID="${GITHUB_RUN_ID:-$WORKFLOW_RUN}" \
        GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}" \
        GITOPS_CONFIRM_SKIP=true \
        "$DEPLOY_PATH/scripts/deploy.sh" --json moltis deploy
)"
DEPLOY_EXIT=$?
set -e

if ! jq empty >/dev/null 2>&1 <<<"$DEPLOY_OUTPUT"; then
    if [[ "$DEPLOY_EXIT" -ne 0 ]]; then
        emit_failure_json "deploy.sh exited with code $DEPLOY_EXIT before returning JSON; inspect workflow stderr for root cause"
    else
        emit_failure_json "deploy.sh returned non-JSON output despite --json contract"
    fi
    exit 1
fi

DEPLOY_STATUS="$(jq -r '.status // empty' <<<"$DEPLOY_OUTPUT" 2>/dev/null || true)"
DEPLOY_HEALTH="$(jq -r '.details.health // empty' <<<"$DEPLOY_OUTPUT" 2>/dev/null || true)"
ROLLBACK_VERIFIED=false

if [[ "$DEPLOY_EXIT" -eq 0 && "$DEPLOY_STATUS" == "success" ]]; then
    log_info "Recording deployed git SHA and deployment metadata"
    if ! record_deployment_markers; then
        emit_failure_json "Deploy succeeded but recording deployment metadata failed" "healthy"
        exit 1
    fi

    log_info "Aligning server git checkout to deployed commit"
    if ! align_checkout; then
        emit_failure_json "Deploy succeeded but aligning the server checkout failed" "healthy"
        exit 1
    fi

    log_info "Attesting live Moltis runtime provenance"
    set +e
    ATTESTATION_OUTPUT="$(
        "$DEPLOY_PATH/scripts/moltis-runtime-attestation.sh" \
            --json \
            --deploy-path "$DEPLOY_PATH" \
            --active-path "$ACTIVE_DEPLOY_PATH" \
            --container "moltis" \
            --base-url "http://localhost:13131" \
            --expected-git-sha "$GIT_SHA" \
            --expected-git-ref "$GIT_REF" \
            --expected-version "${TRACKED_VERSION:-$EXPECTED_VERSION}" \
            --expected-runtime-config-dir "$RUNTIME_CONFIG_DIR" \
            --expected-auth-provider "openai-codex"
    )"
    ATTESTATION_EXIT=$?
    set -e

    if ! jq empty >/dev/null 2>&1 <<<"$ATTESTATION_OUTPUT"; then
        emit_failure_json "Deploy succeeded but runtime attestation returned non-JSON output" "healthy"
        exit 1
    fi

    if [[ "$ATTESTATION_EXIT" -ne 0 || "$(jq -r '.status // empty' <<<"$ATTESTATION_OUTPUT")" != "success" ]]; then
        ATTESTATION_MESSAGE="$(jq -r '.errors[0].message // empty' <<<"$ATTESTATION_OUTPUT" 2>/dev/null || true)"
        ATTESTATION_MESSAGE="${ATTESTATION_MESSAGE:-Deploy succeeded but live runtime attestation failed}"
        RESULT_JSON="$(append_result_context "$DEPLOY_OUTPUT" "failure" "$ROLLBACK_VERIFIED" "$ATTESTATION_MESSAGE")"
        RESULT_JSON="$(jq \
            --argjson attestation "$ATTESTATION_OUTPUT" \
            '.details = ((.details // {}) + {
                runtime_attestation: {
                    status: ($attestation.status // null),
                    details: ($attestation.details // {}),
                    errors: ($attestation.errors // [])
                }
            })' <<<"$RESULT_JSON")"
        printf '%s\n' "$RESULT_JSON"
        exit 1
    fi

    RESULT_JSON="$(append_result_context "$DEPLOY_OUTPUT" "success" "$ROLLBACK_VERIFIED")"
    RESULT_JSON="$(jq \
        --argjson attestation "$ATTESTATION_OUTPUT" \
        '.details = ((.details // {}) + {
            runtime_attestation: {
                status: ($attestation.status // null),
                details: ($attestation.details // {}),
                errors: ($attestation.errors // [])
            }
        })' <<<"$RESULT_JSON")"

    printf '%s\n' "$RESULT_JSON"
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
