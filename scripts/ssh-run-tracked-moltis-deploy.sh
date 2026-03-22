#!/usr/bin/env bash
# Safely invoke the tracked Moltis deploy control-plane script over SSH.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  ssh-run-tracked-moltis-deploy.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    [--active-path <path>] \
    --git-sha <sha> \
    --git-ref <ref> \
    --workflow-run <run-id> \
    [--version <version>] \
    [--dry-run]
EOF
}

require_argument() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "ssh-run-tracked-moltis-deploy.sh: missing required argument: $key" >&2
        usage
        exit 64
    fi
}

SSH_USER=""
SSH_HOST=""
DEPLOY_PATH=""
ACTIVE_PATH="/opt/moltinger-active"
GIT_SHA=""
GIT_REF=""
WORKFLOW_RUN=""
EXPECTED_VERSION=""
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ssh-run-tracked-moltis-deploy.sh: unknown argument: $1" >&2
            usage
            exit 64
            ;;
    esac
done

require_argument "--ssh-user" "$SSH_USER"
require_argument "--ssh-host" "$SSH_HOST"
require_argument "--deploy-path" "$DEPLOY_PATH"
require_argument "--git-sha" "$GIT_SHA"
require_argument "--git-ref" "$GIT_REF"
require_argument "--workflow-run" "$WORKFLOW_RUN"

SSH_TARGET="${SSH_USER}@${SSH_HOST}"

shell_quote() {
    printf '%q' "$1"
}

emit_remote_script() {
    printf 'set -euo pipefail\n'
    printf 'DEPLOY_PATH=%s\n' "$(shell_quote "$DEPLOY_PATH")"
    printf 'ACTIVE_DEPLOY_PATH=%s\n' "$(shell_quote "$ACTIVE_PATH")"
    printf 'GIT_SHA=%s\n' "$(shell_quote "$GIT_SHA")"
    printf 'GIT_REF=%s\n' "$(shell_quote "$GIT_REF")"
    printf 'WORKFLOW_RUN=%s\n' "$(shell_quote "$WORKFLOW_RUN")"
    printf 'EXPECTED_VERSION=%s\n' "$(shell_quote "$EXPECTED_VERSION")"
    cat <<'EOF'
cd "$DEPLOY_PATH"

CMD=(
    ./scripts/run-tracked-moltis-deploy.sh
    --json
    --deploy-path "$DEPLOY_PATH"
    --git-sha "$GIT_SHA"
    --git-ref "$GIT_REF"
    --workflow-run "$WORKFLOW_RUN"
)

if [[ -n "$EXPECTED_VERSION" ]]; then
    CMD+=(--version "$EXPECTED_VERSION")
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
