#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ATTESTATION_SCRIPT="$PROJECT_ROOT/scripts/clawdiy-runtime-attestation.sh"
EXPECTED_DIGEST="ghcr.io/openclaw/openclaw@sha256:d7e8c5c206b107c2e65b610f57f97408e8c07fe9d0ee5cc9193939e48ffb3006"
REPORT_FINALIZED=false

finalize_component_clawdiy_runtime_attestation_report() {
    local exit_code="${1:-0}"

    if [[ "$REPORT_FINALIZED" != "true" ]]; then
        REPORT_FINALIZED=true

        if [[ "$exit_code" -ne 0 && -n "${TEST_CURRENT:-}" ]]; then
            test_fail "Unexpected command failure (exit ${exit_code})"
        fi

        set +e
        generate_report
        set -e
    fi

    cleanup_registered_paths || true
}

on_component_clawdiy_runtime_attestation_exit() {
    local exit_code="$?"
    trap - EXIT
    finalize_component_clawdiy_runtime_attestation_report "$exit_code"
    exit "$exit_code"
}

create_fake_clawdiy_runtime_bin() {
    local fixture_root="$1"
    local fake_bin="$fixture_root/bin"

    mkdir -p "$fake_bin"

    cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

image_id="${FAKE_IMAGE_ID:-sha256:fixture-image}"
config_image="${FAKE_CONFIG_IMAGE:-ghcr.io/openclaw/openclaw:latest}"
version_label="${FAKE_VERSION_LABEL:-2026.3.13-1}"
repo_digests="${FAKE_REPO_DIGESTS_JSON:-[]}"
models_status_file="${FAKE_MODELS_STATUS_FILE:?}"
auth_store_path="${FAKE_AUTH_STORE_PATH:-/home/node/.openclaw-data/state/agents/main/agent/auth-profiles.json}"

case "${1:-}" in
  inspect)
    if [[ $# -eq 2 && "${2:-}" == "clawdiy" ]]; then
      exit 0
    fi
    if [[ "${2:-}" == "--format" ]]; then
      case "${3:-}" in
        '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')
          printf '%s\n' "${FAKE_DOCKER_STATE:-healthy}"
          exit 0
          ;;
        '{{.Config.Image}}')
          printf '%s\n' "$config_image"
          exit 0
          ;;
        '{{.Image}}')
          printf '%s\n' "$image_id"
          exit 0
          ;;
        '{{json .Config.Labels}}')
          printf '{"org.opencontainers.image.version":"%s"}\n' "$version_label"
          exit 0
          ;;
      esac
    fi
    printf 'unsupported fake docker inspect invocation: %s\n' "$*" >&2
    exit 1
    ;;
  image)
    if [[ "${2:-}" == "inspect" && "${3:-}" == "$image_id" && "${4:-}" == "--format" && "${5:-}" == '{{json .RepoDigests}}' ]]; then
      printf '%s\n' "$repo_digests"
      exit 0
    fi
    printf 'unsupported fake docker image invocation: %s\n' "$*" >&2
    exit 1
    ;;
  exec)
    shift
    if [[ "${1:-}" != "clawdiy" || "${2:-}" != "sh" || "${3:-}" != "-lc" ]]; then
      printf 'unsupported fake docker exec invocation: %s\n' "$*" >&2
      exit 1
    fi

    case "${4:-}" in
      timeout\ *openclaw\ models\ status\ --agent\ main\ --json)
        cat "$models_status_file"
        exit 0
        ;;
      "test -f '$auth_store_path'")
        if [[ "${FAKE_AUTH_STORE_EXISTS:-true}" == "true" ]]; then
          exit 0
        fi
        exit 1
        ;;
    esac

    printf 'unsupported fake docker exec payload: %s\n' "${4:-}" >&2
    exit 1
    ;;
  *)
    printf 'unsupported fake docker command: %s\n' "${1:-}" >&2
    exit 1
    ;;
esac
EOF

    cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "${FAKE_HTTP_CODE:-200}"
EOF

    chmod +x "$fake_bin/docker" "$fake_bin/curl"
    printf '%s\n' "$fake_bin"
}

write_models_status_fixture() {
    local path="$1"
    local provider_status="${2:-ok}"
    local default_model="${3:-openai-codex/gpt-5.4}"
    local missing_count="${4:-0}"

    cat >"$path" <<EOF
{
  "defaultModel": "$default_model",
  "auth": {
    "storePath": "/home/node/.openclaw-data/state/agents/main/agent/auth-profiles.json",
    "missingProvidersInUse": [$(if [[ "$missing_count" == "0" ]]; then printf ''; else printf '"openai-codex"'; fi)],
    "oauth": {
      "providers": [
        {
          "provider": "openai-codex",
          "status": "$provider_status",
          "profiles": [
            {
              "profileId": "openai-codex:default",
              "status": "$provider_status"
            }
          ]
        }
      ]
    }
  }
}
EOF
}

run_component_clawdiy_runtime_attestation_tests() {
    start_timer

    local fixture_root fake_bin models_status_file tracked_config_file output_json
    fixture_root="$(secure_temp_dir clawdiy-runtime-attestation)"
    fake_bin="$(create_fake_clawdiy_runtime_bin "$fixture_root")"
    models_status_file="$fixture_root/models-status.json"
    tracked_config_file="$fixture_root/openclaw.json"
    output_json="$fixture_root/output.json"

    cat >"$tracked_config_file" <<'EOF'
{
  "meta": {
    "lastTouchedVersion": "2026.3.13-1"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai-codex/gpt-5.4"
      }
    }
  }
}
EOF

    write_models_status_fixture "$models_status_file"

    test_start "component_clawdiy_runtime_attestation_passes_for_live_verified_digest_and_oauth_store"
    if PATH="$fake_bin:$PATH" \
       FAKE_MODELS_STATUS_FILE="$models_status_file" \
       FAKE_REPO_DIGESTS_JSON="[\"$EXPECTED_DIGEST\"]" \
       "$ATTESTATION_SCRIPT" \
         --json \
         --expected-image "$EXPECTED_DIGEST" \
         --tracked-config-file "$tracked_config_file" \
         >"$output_json"; then
        if jq -e '.status == "success"
            and .details.version_label == "2026.3.13-1"
            and .details.default_model == "openai-codex/gpt-5.4"
            and .details.provider_status == "ok"
            and (.details.repo_digests | index("'"$EXPECTED_DIGEST"'") != null)' "$output_json" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Clawdiy runtime attestation success path must emit the live version, default model, provider status, and pinned digest evidence"
        fi
    else
        test_fail "Clawdiy runtime attestation should pass for the live-verified digest and ready OAuth store"
    fi

    test_start "component_clawdiy_runtime_attestation_fails_when_live_digest_does_not_match"
    if PATH="$fake_bin:$PATH" \
       FAKE_MODELS_STATUS_FILE="$models_status_file" \
       FAKE_REPO_DIGESTS_JSON='["ghcr.io/openclaw/openclaw@sha256:deadbeef"]' \
       "$ATTESTATION_SCRIPT" \
         --json \
         --expected-image "$EXPECTED_DIGEST" \
         --tracked-config-file "$tracked_config_file" \
         >"$output_json"; then
        test_fail "Clawdiy runtime attestation must fail when the live image digest diverges from the tracked baseline"
    elif jq -e '.errors[0].code == "IMAGE_DIGEST_MISMATCH"' "$output_json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Clawdiy runtime attestation must report IMAGE_DIGEST_MISMATCH for digest drift"
    fi

    test_start "component_clawdiy_runtime_attestation_fails_when_auth_store_is_missing"
    if PATH="$fake_bin:$PATH" \
       FAKE_MODELS_STATUS_FILE="$models_status_file" \
       FAKE_REPO_DIGESTS_JSON="[\"$EXPECTED_DIGEST\"]" \
       FAKE_AUTH_STORE_EXISTS=false \
       "$ATTESTATION_SCRIPT" \
         --json \
         --expected-image "$EXPECTED_DIGEST" \
         --tracked-config-file "$tracked_config_file" \
         >"$output_json"; then
        test_fail "Clawdiy runtime attestation must fail when the reported auth store file is absent"
    elif jq -e '.errors[0].code == "AUTH_STORE_FILE_MISSING"' "$output_json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Clawdiy runtime attestation must report AUTH_STORE_FILE_MISSING when the runtime auth store disappears"
    fi

}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap on_component_clawdiy_runtime_attestation_exit EXIT
    run_component_clawdiy_runtime_attestation_tests
fi
