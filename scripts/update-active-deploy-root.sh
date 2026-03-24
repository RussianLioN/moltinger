#!/usr/bin/env bash
# Update the active deploy root symlink with legacy-directory migration and validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat >&2 <<'EOF'
Usage:
  update-active-deploy-root.sh --target-path <path> [--active-path <path>]

Options:
  --target-path <path>   Existing deploy root that must become the symlink target.
  --active-path <path>   Active symlink path to update. Defaults to /opt/moltinger-active.
EOF
}

notice() {
    echo "::notice::$*"
}

warn() {
    echo "::warning::$*"
}

error() {
    echo "::error::$*" >&2
}

ACTIVE_PATH="/opt/moltinger-active"
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --active-path)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            ACTIVE_PATH="$2"
            shift 2
            ;;
        --target-path)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            TARGET_PATH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

if [[ -z "$TARGET_PATH" ]]; then
    usage
    exit 64
fi

if [[ ! -d "$TARGET_PATH" ]]; then
    error "Target deploy root does not exist or is not a directory: $TARGET_PATH"
    exit 1
fi

if [[ "$ACTIVE_PATH" == "$TARGET_PATH" ]]; then
    error "Active deploy root path must differ from target path: $ACTIVE_PATH"
    exit 1
fi

bash "$SCRIPT_DIR/prod-mutation-guard.sh" \
    --action "update-active-deploy-root" \
    --target-path "$TARGET_PATH"

# Legacy migration: ln -sfn does NOT replace an existing real directory.
# In that case it creates a nested link and test -L fails.
if [[ -e "$ACTIVE_PATH" && ! -L "$ACTIVE_PATH" ]]; then
    LEGACY_BACKUP="${ACTIVE_PATH}.legacy-$(date -u +%Y%m%dT%H%M%SZ)"
    warn "Detected legacy non-symlink active root: $ACTIVE_PATH; moving to $LEGACY_BACKUP"
    mv "$ACTIVE_PATH" "$LEGACY_BACKUP"
fi

ln -sfn "$TARGET_PATH" "$ACTIVE_PATH"

if [[ ! -L "$ACTIVE_PATH" ]]; then
    error "Active deploy root is not a symlink after update: $ACTIVE_PATH"
    ls -ld "$ACTIVE_PATH" || true
    exit 1
fi

RESOLVED_TARGET="$(readlink "$ACTIVE_PATH")"
if [[ "$RESOLVED_TARGET" != "$TARGET_PATH" ]]; then
    error "Active deploy root points to unexpected target: $RESOLVED_TARGET (expected $TARGET_PATH)"
    ls -ld "$ACTIVE_PATH" || true
    exit 1
fi

ls -ld "$ACTIVE_PATH"
notice "Active deploy root -> $TARGET_PATH"
