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

read_auth_status() {
  if [[ -n "${FAKE_AUTH_STATUS_SEQUENCE_FILE:-}" && -f "${FAKE_AUTH_STATUS_SEQUENCE_FILE:-}" ]]; then
    local state_file="${FAKE_AUTH_STATUS_SEQUENCE_STATE_FILE:-${FAKE_AUTH_STATUS_SEQUENCE_FILE}.state}"
    local index=1
    if [[ -f "$state_file" ]]; then
      index="$(cat "$state_file")"
    fi

    local line
    line="$(sed -n "${index}p" "$FAKE_AUTH_STATUS_SEQUENCE_FILE")"
    if [[ -z "$line" ]]; then
      line="$(tail -n 1 "$FAKE_AUTH_STATUS_SEQUENCE_FILE")"
    else
      printf '%s\n' "$((index + 1))" >"$state_file"
    fi

    printf '%s\n' "$line"
    return 0
  fi

  printf '%s\n' "${FAKE_AUTH_STATUS:-openai-codex [valid (10m remaining)]}"
}

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
      read_auth_status
      exit 0
    fi
    if [[ "${1:-}" == "moltis" && "${2:-}" == "sh" && "${3:-}" == "-lc" ]]; then
      case "${4:-}" in
        'id -G')
          printf '%s\n' "${FAKE_CONTAINER_GROUP_IDS:-1001 999}"
          exit 0
          ;;
        'stat -c "%g" /var/run/docker.sock')
          printf '%s\n' "${FAKE_DOCKER_SOCKET_GID:-999}"
          exit 0
          ;;
        'stat -c "%a" /var/run/docker.sock')
          printf '%s\n' "${FAKE_DOCKER_SOCKET_MODE:-660}"
          exit 0
          ;;
        'grep -Eq "(^|[[:space:]])host\.docker\.internal([[:space:]]|$)" /etc/hosts')
          if [[ "${FAKE_HOST_DOCKER_INTERNAL_MAPPED:-true}" == "true" ]]; then
            exit 0
          fi
          exit 1
          ;;
        'test -d /server &&
            test -d /server/skills &&
            test -f /home/moltis/.config/moltis/moltis.toml &&
            tmp_path="/home/moltis/.config/moltis/provider_keys.json.tmp.contract-check.$$" &&
            : > "$tmp_path" &&
            rm -f "$tmp_path"')
          exit 0
          ;;
      esac
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

    cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == *"/tests/lib/ws_rpc_cli.mjs" ]]; then
  if [[ "${FAKE_AUTH_CANARY_RESULT:-success}" == "success" ]]; then
    cat <<'JSON'
{
  "ok": true,
  "login": { "status": 200 },
  "result": { "ok": true, "payload": { "ok": true } },
  "events": [{ "event": "chat", "payload": { "state": "final" } }]
}
JSON
    exit 0
  fi

  cat <<'JSON'
{
  "ok": false,
  "message": "canary failed"
}
JSON
  exit "${FAKE_AUTH_CANARY_EXIT_CODE:-1}"
fi

printf 'unsupported fake node invocation: %s\n' "$*" >&2
exit 1
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

    chmod +x "$fake_bin/docker" "$fake_bin/curl" "$fake_bin/node" "$fake_bin/git"
    printf '%s\n' "$fake_bin"
}

create_workspace_fixture() {
    local workspace_root="$1"
    local browser_profile_dir="$2"

    mkdir -p "$workspace_root/data" "$workspace_root/skills" "$workspace_root/config"
    git -C "$workspace_root" init -q
    git -C "$workspace_root" config user.name "Codex Test"
    git -C "$workspace_root" config user.email "codex@example.com"
    printf 'runtime\n' >"$workspace_root/runtime.txt"
    cat >"$workspace_root/config/moltis.toml" <<EOF
[memory]
provider = "ollama"
base_url = "http://ollama:11434"
model = "nomic-embed-text"

[tools.browser]
enabled = true
sandbox_image = "browserless/chrome"
max_instances = 1
profile_dir = "$browser_profile_dir"
persist_profile = false
container_host = "host.docker.internal"
EOF
    git -C "$workspace_root" add runtime.txt
    git -C "$workspace_root" add config/moltis.toml
    git -C "$workspace_root" commit -q -m "fixture"
}

run_component_moltis_runtime_attestation_tests() {
    start_timer

    local fixture_root fake_bin workspace_root workspace_root_canonical active_root runtime_config_dir runtime_config_dir_canonical runtime_home_dir mounts_file output_json live_sha browser_profile_root browser_profile_dir browser_profile_root_canonical browser_profile_dir_canonical original_tracked_toml
    fixture_root="$(secure_temp_dir moltis-runtime-attestation)"
    fake_bin="$(create_fake_runtime_bin "$fixture_root")"
    workspace_root="$fixture_root/deploy-root"
    active_root="$fixture_root/moltis-active"
    runtime_config_dir="$fixture_root/runtime-config"
    runtime_home_dir="$fixture_root/runtime-home"
    browser_profile_root="$fixture_root/browser-profile"
    browser_profile_dir="$browser_profile_root/browserless"
    mounts_file="$fixture_root/mounts.json"
    output_json="$fixture_root/output.json"
    original_tracked_toml="$fixture_root/original-moltis.toml"

    mkdir -p "$runtime_config_dir" "$runtime_home_dir" "$browser_profile_dir"
    chmod 0777 "$browser_profile_root" "$browser_profile_dir"
    create_workspace_fixture "$workspace_root" "$browser_profile_dir"
    workspace_root_canonical="$(cd "$workspace_root" && pwd -P)"
    runtime_config_dir_canonical="$(cd "$runtime_config_dir" && pwd -P)"
    browser_profile_root_canonical="$(cd "$browser_profile_root" && pwd -P)"
    browser_profile_dir_canonical="$(cd "$browser_profile_dir" && pwd -P)"
    live_sha="$(git -C "$workspace_root" rev-parse HEAD)"
    cp "$workspace_root/config/moltis.toml" "$original_tracked_toml"
    cp "$workspace_root/config/moltis.toml" "$runtime_config_dir/moltis.toml"

    cat >"$workspace_root/.env" <<EOF
MOLTIS_RUNTIME_CONFIG_DIR=$runtime_config_dir
MOLTIS_PASSWORD=test-password
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
      {"Destination": "/home/moltis/.moltis", "Source": "$runtime_home_dir", "RW": true},
      {"Destination": "$browser_profile_root", "Source": "$browser_profile_root", "RW": true},
      {"Destination": "/var/run/docker.sock", "Source": "$fixture_root/docker.sock", "RW": false}
    ]
  }
]
EOF
    : >"$fixture_root/docker.sock"

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
       [[ "$(jq -r '.details.browser_enabled' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.browser_sandbox_image' "$output_json")" != "browserless/chrome" ]] || \
       [[ "$(jq -r '.details.browser_container_host' "$output_json")" != "host.docker.internal" ]] || \
       [[ "$(jq -r '.details.browser_max_instances' "$output_json")" != "1" ]] || \
       [[ "$(jq -r '.details.browser_profile_dir' "$output_json")" != "$browser_profile_dir_canonical" ]] || \
       [[ "$(jq -r '.details.browser_profile_root' "$output_json")" != "$browser_profile_root_canonical" ]] || \
       [[ "$(jq -r '.details.browser_profile_source' "$output_json")" != "$browser_profile_root_canonical" ]] || \
       [[ "$(jq -r '.details.browser_profile_rw' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.browser_persist_profile' "$output_json")" != "false" ]] || \
       [[ "$(jq -r '.details.browser_profile_root_writable' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.browser_profile_dir_writable' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.docker_socket_gid' "$output_json")" != "999" ]] || \
       [[ "$(jq -r '.details.host_docker_internal_mapped' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.expected_auth_provider' "$output_json")" != "openai-codex" ]] || \
       [[ "$(jq -r '.details.auth_status_valid' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.auth_validation_path' "$output_json")" != "status" ]]; then
        test_fail "Runtime attestation success output does not reflect the expected provenance details"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_runtime_attestation_fails_when_non_persistent_browser_profile_allows_concurrency"
    python3 - "$workspace_root/config/moltis.toml" "$runtime_config_dir/moltis.toml" <<'PY'
from pathlib import Path
import sys
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    text = path.read_text()
    path.write_text(text.replace("max_instances = 1", "max_instances = 3", 1))
PY
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
            --active-path "$active_root" >"$output_json" 2>"$fixture_root/stderr-browser-concurrency.log"
    exit_code=$?
    set -e
    cp "$original_tracked_toml" "$workspace_root/config/moltis.toml"
    cp "$original_tracked_toml" "$runtime_config_dir/moltis.toml"

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "BROWSER_PROFILE_CONCURRENCY_MISMATCH")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when a non-persistent browser profile allows concurrent instances"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_runtime_attestation_fails_when_browser_profile_root_is_not_world_writable"
    chmod 0755 "$browser_profile_root"
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
            --active-path "$active_root" >"$output_json" 2>"$fixture_root/stderr-browser-profile.log"
    exit_code=$?
    set -e
    chmod 0777 "$browser_profile_root"

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "BROWSER_PROFILE_ROOT_PERMISSION_MISMATCH")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when the browser profile root is not writable for arbitrary non-root browser users"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_runtime_attestation_fails_when_browser_socket_gid_mismatches_live_groups"
    set +e
    PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        FAKE_CONTAINER_GROUP_IDS="1001 1000" \
        FAKE_DOCKER_SOCKET_GID="999" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" >"$output_json" 2>"$fixture_root/stderr-browser-gid.log"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "BROWSER_DOCKER_SOCKET_GID_MISMATCH")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when the docker.sock gid is not present in the live Moltis process groups"
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
      {"Destination": "/home/moltis/.moltis", "Source": "$runtime_home_dir", "RW": true},
      {"Destination": "$browser_profile_root", "Source": "$browser_profile_root", "RW": true},
      {"Destination": "/var/run/docker.sock", "Source": "$fixture_root/docker.sock", "RW": false}
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
      {"Destination": "/home/moltis/.moltis", "Source": "$runtime_home_dir", "RW": true},
      {"Destination": "$browser_profile_root", "Source": "$browser_profile_root", "RW": true},
      {"Destination": "/var/run/docker.sock", "Source": "$fixture_root/docker.sock", "RW": false}
    ]
  }
]
EOF

    cat >"$runtime_config_dir/oauth_tokens.json" <<'EOF'
{
  "openai-codex": {
    "refresh_token": "refresh-token"
  }
}
EOF
    cat >"$fixture_root/auth-status-sequence.txt" <<'EOF'
openai-codex [expired]
openai-codex [valid (10m remaining)]
EOF

    test_start "component_runtime_attestation_recovers_refreshable_expired_auth_provider_via_canary"
    if ! PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        FAKE_AUTH_STATUS_SEQUENCE_FILE="$fixture_root/auth-status-sequence.txt" \
        FAKE_AUTH_CANARY_RESULT="success" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" \
            --expected-auth-provider "openai-codex" >"$output_json" 2>"$fixture_root/stderr-auth-refresh.log"; then
        test_fail "Runtime attestation should recover a refreshable expired auth provider via canary"
        rm -rf "$fixture_root"
        return
    fi

    if [[ "$(jq -r '.details.auth_status_valid' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.auth_validation_path' "$output_json")" != "refreshable-canary" ]] || \
       [[ "$(jq -r '.details.auth_canary_attempted' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.auth_canary_succeeded' "$output_json")" != "true" ]] || \
       [[ "$(jq -r '.details.auth_status_raw' "$output_json")" != "openai-codex [expired]" ]] || \
       [[ "$(jq -r '.details.auth_status_post_canary' "$output_json")" != "openai-codex [valid (10m remaining)]" ]]; then
        test_fail "Runtime attestation should record refreshable auth recovery details after a successful canary"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    cat >"$fixture_root/auth-status-sequence.txt" <<'EOF'
openai-codex [expired]
openai-codex [expired]
EOF

    test_start "component_runtime_attestation_fails_when_refreshable_expired_auth_provider_does_not_recover"
    set +e
    PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_MOUNTS_FILE="$mounts_file" \
        FAKE_MOLTIS_VERSION="0.10.18" \
        FAKE_DOCKER_STATE="healthy" \
        FAKE_DOCKER_WORKDIR="/server" \
        FAKE_CURL_HTTP_CODE="200" \
        FAKE_LIVE_GIT_SHA="$live_sha" \
        FAKE_AUTH_STATUS_SEQUENCE_FILE="$fixture_root/auth-status-sequence.txt" \
        FAKE_AUTH_CANARY_RESULT="failure" \
        MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_config_dir" \
        bash "$ATTESTATION_SCRIPT" \
            --json \
            --deploy-path "$workspace_root" \
            --active-path "$active_root" \
            --expected-auth-provider "openai-codex" >"$output_json" 2>"$fixture_root/stderr-auth-refresh-fail.log"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || \
       [[ "$(jq -r '.status' "$output_json")" != "failure" ]] || \
       ! jq -e '.errors[] | select(.code == "AUTH_PROVIDER_CANARY_FAILED")' "$output_json" >/dev/null 2>&1; then
        test_fail "Runtime attestation should fail when a refreshable expired auth provider does not recover after canary"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

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
