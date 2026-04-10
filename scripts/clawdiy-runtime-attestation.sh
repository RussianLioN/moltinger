#!/usr/bin/env bash
# Prove that the live Clawdiy runtime still matches the tracked image and auth baseline.

set -euo pipefail

OUTPUT_JSON=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONTAINER="${CONTAINER:-clawdiy}"
BASE_URL="${BASE_URL:-http://127.0.0.1:18789}"
EXPECTED_IMAGE="${EXPECTED_IMAGE:-}"
EXPECTED_DEFAULT_MODEL="${EXPECTED_DEFAULT_MODEL:-}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_PROVIDER="${EXPECTED_PROVIDER:-openai-codex}"
TRACKED_CONFIG_FILE="${TRACKED_CONFIG_FILE:-$PROJECT_ROOT/config/clawdiy/openclaw.json}"
RUNTIME_CONFIG_FILE="${RUNTIME_CONFIG_FILE:-$PROJECT_ROOT/data/clawdiy/runtime/openclaw.json}"
MODELS_STATUS_TIMEOUT="${MODELS_STATUS_TIMEOUT:-20}"

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

usage() {
    cat <<'EOF'
Usage: clawdiy-runtime-attestation.sh [--json] [--container <name>] [--base-url <url>]
  [--expected-image <image-ref-or-digest>] [--expected-default-model <model>]
  [--expected-version <version>] [--expected-provider <provider>]
  [--tracked-config-file <path>] [--runtime-config-file <path>]

Verify the live Clawdiy runtime provenance against the tracked deploy contract:
  - container is healthy and serves /health
  - live image matches the expected pinned baseline
  - live OpenClaw runtime still resolves the tracked default model
  - live runtime auth store exists and the expected provider is ready
EOF
}

container_state() {
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || echo "not_found"
}

container_config_image() {
    docker inspect --format '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || echo ""
}

container_image_id() {
    docker inspect --format '{{.Image}}' "$CONTAINER" 2>/dev/null || echo ""
}

container_version_label() {
    docker inspect --format '{{json .Config.Labels}}' "$CONTAINER" 2>/dev/null | jq -r '."org.opencontainers.image.version" // empty'
}

container_repo_digests_json() {
    local image_id="$1"

    if [[ -z "$image_id" ]]; then
        printf '[]\n'
        return 0
    fi

    docker image inspect "$image_id" --format '{{json .RepoDigests}}' 2>/dev/null || printf '[]\n'
}

health_status_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL%/}/health" 2>/dev/null || echo "000"
}

resolve_expected_default_model() {
    if [[ -n "$EXPECTED_DEFAULT_MODEL" ]]; then
        printf '%s\n' "$EXPECTED_DEFAULT_MODEL"
        return 0
    fi

    local config_file="$TRACKED_CONFIG_FILE"
    if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
        config_file="$RUNTIME_CONFIG_FILE"
    fi

    if [[ -f "$config_file" ]]; then
        jq -r '.agents.defaults.model.primary // empty' "$config_file"
        return 0
    fi

    printf '\n'
}

resolve_expected_version() {
    if [[ -n "$EXPECTED_VERSION" ]]; then
        printf '%s\n' "$EXPECTED_VERSION"
        return 0
    fi

    local config_file="$TRACKED_CONFIG_FILE"
    if [[ -f "$RUNTIME_CONFIG_FILE" ]]; then
        config_file="$RUNTIME_CONFIG_FILE"
    fi

    if [[ -f "$config_file" ]]; then
        jq -r '.meta.lastTouchedVersion // empty' "$config_file"
        return 0
    fi

    printf '\n'
}

emit_failure_json() {
    local code="$1"
    local message="$2"
    local container_state_value="$3"
    local http_code="$4"
    local config_image="$5"
    local version_label="$6"
    local repo_digests_json="$7"
    local default_model="$8"
    local store_path="$9"
    local provider_status="${10}"
    local models_status_json="${11}"

    jq -n \
        --arg status "failure" \
        --arg target "clawdiy" \
        --arg action "runtime-attestation" \
        --arg timestamp "$(timestamp)" \
        --arg code "$code" \
        --arg message "$message" \
        --arg container "$CONTAINER" \
        --arg base_url "$BASE_URL" \
        --arg container_state "$container_state_value" \
        --arg http_code "$http_code" \
        --arg config_image "$config_image" \
        --arg version_label "$version_label" \
        --arg expected_image "$EXPECTED_IMAGE" \
        --arg expected_version "$(resolve_expected_version)" \
        --arg expected_default_model "$(resolve_expected_default_model)" \
        --arg expected_provider "$EXPECTED_PROVIDER" \
        --arg default_model "$default_model" \
        --arg store_path "$store_path" \
        --arg provider_status "$provider_status" \
        --argjson repo_digests "$repo_digests_json" \
        --argjson models_status "${models_status_json:-null}" \
        '{
          status: $status,
          target: $target,
          action: $action,
          timestamp: $timestamp,
          details: {
            container: $container,
            base_url: $base_url,
            container_state: $container_state,
            http_code: $http_code,
            config_image: (if $config_image == "" then null else $config_image end),
            version_label: (if $version_label == "" then null else $version_label end),
            expected_image: (if $expected_image == "" then null else $expected_image end),
            expected_version: (if $expected_version == "" then null else $expected_version end),
            expected_default_model: (if $expected_default_model == "" then null else $expected_default_model end),
            expected_provider: $expected_provider,
            default_model: (if $default_model == "" then null else $default_model end),
            store_path: (if $store_path == "" then null else $store_path end),
            provider_status: (if $provider_status == "" then null else $provider_status end),
            repo_digests: $repo_digests,
            models_status: $models_status
          },
          errors: [{ code: $code, message: $message }]
        }'
}

emit_success_json() {
    local container_state_value="$1"
    local http_code="$2"
    local config_image="$3"
    local version_label="$4"
    local repo_digests_json="$5"
    local default_model="$6"
    local store_path="$7"
    local provider_status="$8"
    local models_status_json="$9"

    jq -n \
        --arg status "success" \
        --arg target "clawdiy" \
        --arg action "runtime-attestation" \
        --arg timestamp "$(timestamp)" \
        --arg container "$CONTAINER" \
        --arg base_url "$BASE_URL" \
        --arg container_state "$container_state_value" \
        --arg http_code "$http_code" \
        --arg config_image "$config_image" \
        --arg version_label "$version_label" \
        --arg expected_image "$EXPECTED_IMAGE" \
        --arg expected_version "$(resolve_expected_version)" \
        --arg expected_default_model "$(resolve_expected_default_model)" \
        --arg expected_provider "$EXPECTED_PROVIDER" \
        --arg default_model "$default_model" \
        --arg store_path "$store_path" \
        --arg provider_status "$provider_status" \
        --argjson repo_digests "$repo_digests_json" \
        --argjson models_status "$models_status_json" \
        '{
          status: $status,
          target: $target,
          action: $action,
          timestamp: $timestamp,
          details: {
            container: $container,
            base_url: $base_url,
            container_state: $container_state,
            http_code: $http_code,
            config_image: $config_image,
            version_label: $version_label,
            expected_image: (if $expected_image == "" then null else $expected_image end),
            expected_version: (if $expected_version == "" then null else $expected_version end),
            expected_default_model: (if $expected_default_model == "" then null else $expected_default_model end),
            expected_provider: $expected_provider,
            default_model: $default_model,
            store_path: $store_path,
            provider_status: $provider_status,
            repo_digests: $repo_digests,
            models_status: $models_status
          }
        }'
}

fail_with() {
    local code="$1"
    local message="$2"
    local container_state_value="${3:-unknown}"
    local http_code="${4:-000}"
    local config_image="${5:-}"
    local version_label="${6:-}"
    local repo_digests_json="${7:-[]}"
    local default_model="${8:-}"
    local store_path="${9:-}"
    local provider_status="${10:-}"
    local models_status_json="${11:-null}"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        emit_failure_json \
            "$code" \
            "$message" \
            "$container_state_value" \
            "$http_code" \
            "$config_image" \
            "$version_label" \
            "$repo_digests_json" \
            "$default_model" \
            "$store_path" \
            "$provider_status" \
            "$models_status_json"
    else
        printf 'clawdiy-runtime-attestation.sh: [%s] %s\n' "$code" "$message" >&2
    fi
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --container)
            CONTAINER="${2:-}"
            shift 2
            ;;
        --base-url)
            BASE_URL="${2:-}"
            shift 2
            ;;
        --expected-image)
            EXPECTED_IMAGE="${2:-}"
            shift 2
            ;;
        --expected-default-model)
            EXPECTED_DEFAULT_MODEL="${2:-}"
            shift 2
            ;;
        --expected-version)
            EXPECTED_VERSION="${2:-}"
            shift 2
            ;;
        --expected-provider)
            EXPECTED_PROVIDER="${2:-}"
            shift 2
            ;;
        --tracked-config-file)
            TRACKED_CONFIG_FILE="${2:-}"
            shift 2
            ;;
        --runtime-config-file)
            RUNTIME_CONFIG_FILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'clawdiy-runtime-attestation.sh: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

for command in docker jq curl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        fail_with "MISSING_DEPENDENCY" "Required command is missing: $command"
    fi
done

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    fail_with "CONTAINER_NOT_FOUND" "Container '$CONTAINER' was not found"
fi

CONTAINER_STATE_VALUE="$(container_state)"
HTTP_CODE="$(health_status_code)"
CONFIG_IMAGE="$(container_config_image)"
IMAGE_ID="$(container_image_id)"
VERSION_LABEL="$(container_version_label)"
REPO_DIGESTS_JSON="$(container_repo_digests_json "$IMAGE_ID")"
EXPECTED_DEFAULT_MODEL_RESOLVED="$(resolve_expected_default_model)"
EXPECTED_VERSION_RESOLVED="$(resolve_expected_version)"

if [[ "$CONTAINER_STATE_VALUE" != "healthy" ]]; then
    fail_with "CONTAINER_NOT_HEALTHY" "Container '$CONTAINER' is not healthy" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON"
fi

if [[ "$HTTP_CODE" != "200" ]]; then
    fail_with "HEALTH_ENDPOINT_FAILED" "Health endpoint returned HTTP $HTTP_CODE" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON"
fi

if [[ -n "$EXPECTED_IMAGE" ]]; then
    if [[ "$EXPECTED_IMAGE" == *@sha256:* ]]; then
        if ! jq -e --arg expected "$EXPECTED_IMAGE" 'index($expected) != null' <<<"$REPO_DIGESTS_JSON" >/dev/null 2>&1; then
            fail_with "IMAGE_DIGEST_MISMATCH" "Live Clawdiy image does not match the expected pinned digest" \
                "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON"
        fi
    elif [[ "$CONFIG_IMAGE" != "$EXPECTED_IMAGE" ]]; then
        fail_with "IMAGE_REF_MISMATCH" "Live Clawdiy image ref does not match the expected image" \
            "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON"
    fi
fi

if [[ -n "$EXPECTED_VERSION_RESOLVED" && "$VERSION_LABEL" != "$EXPECTED_VERSION_RESOLVED" ]]; then
    fail_with "IMAGE_VERSION_MISMATCH" "Live Clawdiy image version does not match the tracked baseline" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON"
fi

MODELS_STATUS_JSON="$(docker exec "$CONTAINER" sh -lc "timeout $MODELS_STATUS_TIMEOUT openclaw models status --agent main --json" 2>/dev/null || true)"
if [[ -z "$MODELS_STATUS_JSON" ]] || ! jq empty >/dev/null 2>&1 <<<"$MODELS_STATUS_JSON"; then
    fail_with "MODELS_STATUS_UNAVAILABLE" "Could not collect live 'openclaw models status --agent main --json'" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON"
fi

DEFAULT_MODEL="$(jq -r '.defaultModel // empty' <<<"$MODELS_STATUS_JSON")"
STORE_PATH="$(jq -r '.auth.storePath // empty' <<<"$MODELS_STATUS_JSON")"
PROVIDER_STATUS="$(jq -r --arg provider "$EXPECTED_PROVIDER" '.auth.oauth.providers[]? | select(.provider == $provider) | .status' <<<"$MODELS_STATUS_JSON" | head -n 1)"
MISSING_PROVIDERS_COUNT="$(jq -r '(.auth.missingProvidersInUse // []) | length' <<<"$MODELS_STATUS_JSON")"
PROVIDER_PROFILE_COUNT="$(jq -r --arg provider "$EXPECTED_PROVIDER" '.auth.oauth.providers[]? | select(.provider == $provider) | (.profiles | length)' <<<"$MODELS_STATUS_JSON" | head -n 1)"

if [[ -z "$DEFAULT_MODEL" ]]; then
    fail_with "DEFAULT_MODEL_MISSING" "Live Clawdiy models status did not report a default model" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if [[ -n "$EXPECTED_DEFAULT_MODEL_RESOLVED" && "$DEFAULT_MODEL" != "$EXPECTED_DEFAULT_MODEL_RESOLVED" ]]; then
    fail_with "DEFAULT_MODEL_MISMATCH" "Live Clawdiy default model diverges from tracked config" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if [[ -z "$STORE_PATH" ]]; then
    fail_with "AUTH_STORE_PATH_MISSING" "Live Clawdiy models status did not report an auth store path" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if ! docker exec "$CONTAINER" sh -lc "test -f '$STORE_PATH'" >/dev/null 2>&1; then
    fail_with "AUTH_STORE_FILE_MISSING" "Live Clawdiy auth store file is missing" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if [[ "${PROVIDER_STATUS:-}" != "ok" ]]; then
    fail_with "AUTH_PROVIDER_INVALID" "Expected Clawdiy OAuth provider is not ready" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if [[ "${PROVIDER_PROFILE_COUNT:-0}" == "0" ]]; then
    fail_with "AUTH_PROFILE_COUNT_ZERO" "Expected Clawdiy OAuth provider has no usable profiles" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if [[ "$MISSING_PROVIDERS_COUNT" != "0" ]]; then
    fail_with "MISSING_PROVIDERS_IN_USE" "Live Clawdiy still reports missing providers in use" \
        "$CONTAINER_STATE_VALUE" "$HTTP_CODE" "$CONFIG_IMAGE" "$VERSION_LABEL" "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" "$STORE_PATH" "$PROVIDER_STATUS" "$MODELS_STATUS_JSON"
fi

if [[ "$OUTPUT_JSON" == "true" ]]; then
    emit_success_json \
        "$CONTAINER_STATE_VALUE" \
        "$HTTP_CODE" \
        "$CONFIG_IMAGE" \
        "$VERSION_LABEL" \
        "$REPO_DIGESTS_JSON" \
        "$DEFAULT_MODEL" \
        "$STORE_PATH" \
        "$PROVIDER_STATUS" \
        "$MODELS_STATUS_JSON"
else
    printf 'clawdiy-runtime-attestation.sh: [OK] Live Clawdiy runtime matches the tracked image and OAuth baseline\n'
fi
