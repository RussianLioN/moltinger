#!/usr/bin/env bash
# Safely align the remote deploy checkout to a specific git ref/SHA before GitOps sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat >&2 <<'EOF'
Usage:
  align-server-checkout.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    --target-ref <ref> \
    --target-sha <sha> \
    [--clean-untracked] \
    [--dry-run]
EOF
}

require_argument() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "align-server-checkout.sh: missing required argument: $key" >&2
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
TARGET_REF=""
TARGET_SHA=""
CLEAN_UNTRACKED=false
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
        --target-ref)
            TARGET_REF="${2:-}"
            shift 2
            ;;
        --target-sha)
            TARGET_SHA="${2:-}"
            shift 2
            ;;
        --clean-untracked)
            CLEAN_UNTRACKED=true
            shift
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
            echo "align-server-checkout.sh: unknown argument: $1" >&2
            usage
            exit 64
            ;;
    esac
done

require_argument "--ssh-user" "$SSH_USER"
require_argument "--ssh-host" "$SSH_HOST"
require_argument "--deploy-path" "$DEPLOY_PATH"
require_argument "--target-ref" "$TARGET_REF"
require_argument "--target-sha" "$TARGET_SHA"

SSH_TARGET="${SSH_USER}@${SSH_HOST}"

emit_remote_script() {
    printf 'set -euo pipefail\n'
    printf 'DEPLOY_PATH=%s\n' "$(shell_quote "$DEPLOY_PATH")"
    printf 'TARGET_REF=%s\n' "$(shell_quote "$TARGET_REF")"
    printf 'TARGET_SHA=%s\n' "$(shell_quote "$TARGET_SHA")"
    printf 'CLEAN_UNTRACKED=%s\n' "$(shell_quote "$CLEAN_UNTRACKED")"
    cat <<'EOF'
cd "$DEPLOY_PATH"

git fetch --depth=1 origin "$TARGET_REF" >&2
git checkout --force "$TARGET_REF" >&2
git reset --hard "$TARGET_SHA" >&2

if [[ "$CLEAN_UNTRACKED" == "true" ]]; then
    git clean -fd >&2
fi

git status --short >&2 || true
EOF
}

if [[ "$DRY_RUN" == "true" ]]; then
    printf '+ ssh %q bash -seu <<REMOTE_SCRIPT\n' "$SSH_TARGET"
    emit_remote_script
    printf 'REMOTE_SCRIPT\n'
    exit 0
fi

bash "$SCRIPT_DIR/prod-mutation-guard.sh" \
    --action "align-server-checkout" \
    --target-host "$SSH_HOST" \
    --target-path "$DEPLOY_PATH"

emit_remote_script | ssh "$SSH_TARGET" 'bash -seu'
