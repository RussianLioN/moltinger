#!/usr/bin/env bash
# Safely invoke Moltis runtime attestation over SSH.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  ssh-run-moltis-runtime-attestation.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    [--active-path <path>] \
    [--container <name>] \
    [--base-url <url>] \
    [--expected-git-sha <sha>] \
    [--expected-git-ref <ref>] \
    [--expected-version <version>] \
    [--expected-runtime-config-dir <path>] \
    [--expected-auth-provider <provider>] \
    [--dry-run]
EOF
}

require_argument() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "ssh-run-moltis-runtime-attestation.sh: missing required argument: $key" >&2
        usage
        exit 64
    fi
}

shell_quote() {
    printf '%q' "$1"
}

SSH_USER=""
SSH_HOST=""
DEPLOY_PATH=""
ACTIVE_PATH="/opt/moltinger-active"
MOLTIS_CONTAINER="moltis"
MOLTIS_URL="http://localhost:13131"
EXPECTED_GIT_SHA=""
EXPECTED_GIT_REF=""
EXPECTED_VERSION=""
EXPECTED_RUNTIME_CONFIG_DIR=""
EXPECTED_AUTH_PROVIDER=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-user)
            SSH_USER="${2:-}"
            shift 2
            ;;
        --ssh-host)
            SSH_HOST="${2:-}"
            shift 2
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ssh-run-moltis-runtime-attestation.sh: unknown argument: $1" >&2
            usage
            exit 64
            ;;
    esac
done

require_argument "--ssh-user" "$SSH_USER"
require_argument "--ssh-host" "$SSH_HOST"
require_argument "--deploy-path" "$DEPLOY_PATH"

SSH_TARGET="${SSH_USER}@${SSH_HOST}"

emit_remote_script() {
    printf 'set -euo pipefail\n'
    printf 'DEPLOY_PATH=%s\n' "$(shell_quote "$DEPLOY_PATH")"
    printf 'ACTIVE_PATH=%s\n' "$(shell_quote "$ACTIVE_PATH")"
    printf 'MOLTIS_CONTAINER=%s\n' "$(shell_quote "$MOLTIS_CONTAINER")"
    printf 'MOLTIS_URL=%s\n' "$(shell_quote "$MOLTIS_URL")"
    printf 'EXPECTED_GIT_SHA=%s\n' "$(shell_quote "$EXPECTED_GIT_SHA")"
    printf 'EXPECTED_GIT_REF=%s\n' "$(shell_quote "$EXPECTED_GIT_REF")"
    printf 'EXPECTED_VERSION=%s\n' "$(shell_quote "$EXPECTED_VERSION")"
    printf 'EXPECTED_RUNTIME_CONFIG_DIR=%s\n' "$(shell_quote "$EXPECTED_RUNTIME_CONFIG_DIR")"
    printf 'EXPECTED_AUTH_PROVIDER=%s\n' "$(shell_quote "$EXPECTED_AUTH_PROVIDER")"
    cat <<'EOF'
cd "$DEPLOY_PATH"

CMD=(
  "$DEPLOY_PATH/scripts/moltis-runtime-attestation.sh"
  --json
  --deploy-path "$DEPLOY_PATH"
  --active-path "$ACTIVE_PATH"
  --container "$MOLTIS_CONTAINER"
  --base-url "$MOLTIS_URL"
)

if [[ -n "$EXPECTED_GIT_SHA" ]]; then
  CMD+=(--expected-git-sha "$EXPECTED_GIT_SHA")
fi

if [[ -n "$EXPECTED_GIT_REF" ]]; then
  CMD+=(--expected-git-ref "$EXPECTED_GIT_REF")
fi

if [[ -n "$EXPECTED_VERSION" ]]; then
  CMD+=(--expected-version "$EXPECTED_VERSION")
fi

if [[ -n "$EXPECTED_RUNTIME_CONFIG_DIR" ]]; then
  CMD+=(--expected-runtime-config-dir "$EXPECTED_RUNTIME_CONFIG_DIR")
fi

if [[ -n "$EXPECTED_AUTH_PROVIDER" ]]; then
  CMD+=(--expected-auth-provider "$EXPECTED_AUTH_PROVIDER")
fi

"${CMD[@]}"
EOF
}

if [[ "$DRY_RUN" == "true" ]]; then
    printf '+ ssh %q bash -seu <<REMOTE_SCRIPT\n' "$SSH_TARGET"
    emit_remote_script
    printf 'REMOTE_SCRIPT\n'
    exit 0
fi

emit_remote_script | ssh "$SSH_TARGET" 'bash -seu'
