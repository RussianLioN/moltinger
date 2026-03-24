#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ATTESTATION_SCRIPT="$PROJECT_ROOT/scripts/moltis-runtime-attestation.sh"

create_fake_runtime_bin() {
    local fixture_root="$1"
    local fake_bin="$fixture_root/bin"

    mkdir -p "$fake_bin"

    cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  inspect)
    if [[ "${2:-}" == "--format" ]]; then
      case "${3:-}" in
        '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')
          printf '%s\n' "${FAKE_DOCKER_STATE:-healthy}"
          ;;
        '{{.Config.WorkingDir}}')
          printf '%s\n' "${FAKE_DOCKER_WORKDIR:-/server}"
          ;;
        *)
          printf 'unsupported inspect format: %s\n' "${3:-}" >&2
          exit 1
          ;;
      esac
      exit 0
    fi

    if [[ $# -eq 2 && "${2:-}" == "moltis" ]]; then
      cat "${FAKE_DOCKER_MOUNTS_FILE}"
      exit 0
    fi

    printf 'unsupported docker inspect invocation\n' >&2
    exit 1
    ;;
  exec)
    shift
    if [[ "${1:-}" == "moltis" && "${2:-}" == "moltis" && "${3:-}" == "--version" ]]; then
      printf 'moltis %s\n' "${FAKE_MOLTIS_VERSION:-0.10.18}"
      exit 0
    fi
    if [[ "${1:-}" == "moltis" && "${2:-}" == "moltis" && "${3:-}" == "auth" && "${4:-}" == "status" ]]; then
      printf '%s\n' "${FAKE_AUTH_STATUS:-openai-codex [valid (10m remaining)]}"
      exit 0
    fi
    printf 'unsupported docker exec invocation: %s\n' "$*" >&2
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
printf '%s' "${FAKE_CURL_HTTP_CODE:-200}"
EOF

    cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" && "${4:-}" == "HEAD" ]]; then
  printf '%s\n' "${FAKE_LIVE_GIT_SHA:?}"
  exit 0
fi

if [[ "${1:-}" == "-C" && "${3:-}" == "symbolic-ref" && "${4:-}" == "--quiet" && "${5:-}" == "--short" && "${6:-}" == "HEAD" ]]; then
  printf '%s\n' "${FAKE_LIVE_GIT_REF:-main}"
  exit 0
fi

printf 'unsupported fake git invocation: %s\n' "$*" >&2
exit 1
EOF

    chmod +x "$fake_bin/docker" "$fake_bin/curl" "$fake_bin/git"
    printf '%s\n' "$fake_bin"
}

create_workspace_fixture() {
    local workspace_root="$1"

    mkdir -p "$workspace_root/data" "$workspace_root/skills" "$workspace_root/config"
    git -C "$workspace_root" init -q
    git -C "$workspace_root" config user.name "Codex Test"
    git -C "$workspace_root" config user.email "codex@example.com"
    printf 'runtime\n' >"$workspace_root/runtime.txt"
    cat >"$workspace_root/config/moltis.toml" <<'EOF'
[memory]
provider = "ollama"
base_url = "http://ollama:11434"
model = "nomic-embed-text"
EOF
    git -C "$workspace_root" add runtime.txt
    git -C "$workspace_root" add config/moltis.toml
    git -C "$workspace_root" commit -q -m "fixture"
}

run_component_moltis_runtime_attestation_tests() {
    start_timer

    local fixture_root fake_bin workspace_root workspace_root_canonical active_root runtime_config_dir runtime_config_dir_canonical runtime_home_dir mounts_file output_json live_sha
    fixture_root="$(secure_temp_dir moltis-runtime-attestation)"
    fake_bin="$(create_fake_runtime_bin "$fixture_root")"
    workspace_root="$fixture_root/deploy-root"
    active_root="$fixture_root/moltis-active"
    runtime_config_dir="$fixture_root/runtime-config"
    runtime_home_dir="$fixture_root/runtime-home"
    mounts_file="$fixture_root/mounts.json"
    output_json="$fixture_root/output.json"

    mkdir -p "$runtime_config_dir" "$runtime_home_dir"
    create_workspace_fixture "$workspace_root"
    workspace_root_canonical="$(cd "$workspace_root" && pwd -P)"
    runtime_config_dir_canonical="$(cd "$runtime_config_dir" && pwd -P)"
    live_sha="$(git -C "$workspace_root" rev-parse HEAD)"
    cp "$workspace_root/config/moltis.toml" "$runtime_config_dir/moltis.toml"

    cat >"$workspace_root/.env" <<EOF
MOLTIS_RUNTIME_CONFIG_DIR=$runtime_config_dir
EOF
    printf '%s\n' "$live_sha" >"$workspace_root/data/.deployed-sha"
    cat >"$workspace_root/data/.deployment-info" <<EOF
deployed_at=2026-03-22T00:00:00Z
git_sha=$live_sha
git_ref=main
workflow_run=12345
version=0.10.18
deploy_path=$workspace_root
runtime_config_dir=$runtime_config_dir
EOF

    ln -s "$workspace_root" "$active_root"

    cat >"$mounts_file" <<EOF
[
  {
    "Mounts": [
      {"Destination": "/server", "Source": "$workspace_root", "RW": false},
      {"Destination": "/home/moltis/.config/moltis", "Source": "$runtime_config_dir", "RW": true},
      {"Destination": "/home/moltis/.moltis", "Source": "$runtime_home_dir", "RW": true}
    ]
  }
]
EOF

    test_start "component_runtime_attestation_succeeds_for_live_provenance_contract"
    if ! PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" \
            --expected-auth-provider "openai-codex" >"$output_json" 2>"$fixture_root/stderr.log"; then
        test_fail "Runtime attestation should pass for matching live provenance"
        rm -rf "$fixture_root"
        return
    fi

    if [[ "$(jq -r '.status' "$output_json")" != "success" ]] || \
       [[ "$(jq -r '.details.active_target' "$output_json")" != "$workspace_root_canonical" ]] || \
       [[ "$(jq -r '.details.workspace_source' "$output_json")" != "$workspace_root_canonical" ]] || \
       [[ "$(jq -r '.details.recorded_git_sha' "$output_json")" != "$live_sha" ]] || \
       [[ "$(jq -r '.details.live_version' "$output_json")" != "0.10.18" ]] || \
       [[ "$(jq -r '.details.runtime_config_source' "$output_json")" != "$runtime_config_dir_canonical" ]] || \
       [[ "$(jq -r '.details.runtime_config_rw' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.tracked_runtime_toml' "$output_json")" != "$workspace_root_canonical/config/moltis.toml" ]] || \
       [[ "$(jq -r '.details.runtime_runtime_toml' "$output_json")" != "$runtime_config_dir_canonical/moltis.toml" ]] || \
       [[ "$(jq -r '.details.expected_auth_provider' "$output_json")" != "openai-codex" ]] || \
       [[ "$(jq -r '.details.auth_status_valid' "$output_json")" != "true" ]]; then
        test_fail "Runtime attestation success output does not reflect the expected provenance details"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    printf '[memory]\nprovider = "openai"\n' >"$runtime_config_dir/moltis.toml"

    test_start "component_runtime_attestation_fails_when_runtime_config_drifted_from_tracked_contract"
    set +e
    PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" >"$output_json" 2>"$fixture_root/stderr-runtime-config.log"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "RUNTIME_CONFIG_FILE_MISMATCH")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when runtime moltis.toml drifts from the tracked config contract"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    cp "$workspace_root/config/moltis.toml" "$runtime_config_dir/moltis.toml"

    cat >"$mounts_file" <<EOF
[
  {
    "Mounts": [
      {"Destination": "/server", "Source": "$fixture_root/untracked-root", "RW": false},
      {"Destination": "/home/moltis/.config/moltis", "Source": "$runtime_config_dir", "RW": true},
      {"Destination": "/home/moltis/.moltis", "Source": "$runtime_home_dir", "RW": true}
    ]
  }
]
EOF
    mkdir -p "$fixture_root/untracked-root"

    test_start "component_runtime_attestation_fails_when_workspace_mount_drifts_from_active_root"
    set +e
    PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" >"$output_json" 2>"$fixture_root/stderr-fail.log"
    local exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "WORKSPACE_PROVENANCE_MISMATCH")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when the live /server mount source drifts from the active deploy root"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    cat >"$mounts_file" <<EOF
[
  {
    "Mounts": [
      {"Destination": "/server", "Source": "$workspace_root", "RW": false},
      {"Destination": "/home/moltis/.config/moltis", "Source": "$runtime_config_dir", "RW": true},
      {"Destination": "/home/moltis/.moltis", "Source": "$runtime_home_dir", "RW": true}
    ]
  }
]
EOF

    test_start "component_runtime_attestation_fails_when_expected_auth_provider_is_invalid"
    set +e
    PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        FAKE_AUTH_STATUS="other-provider [valid (10m remaining)]" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" \
            --expected-auth-provider "openai-codex" >"$output_json" 2>"$fixture_root/stderr-auth.log"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "AUTH_PROVIDER_INVALID")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when the expected auth provider is not valid in live auth status"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_runtime_attestation_tests
fi
