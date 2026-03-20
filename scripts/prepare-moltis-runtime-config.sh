#!/bin/bash
# Prepare a writable Moltis runtime config directory outside the git-synced tree.
# Static config is copied from the repo-managed config/ directory.
# Auth/state files stay in the runtime directory and are never overwritten here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

STATIC_CONFIG_DIR="${1:-${MOLTIS_STATIC_CONFIG_DIR:-$PROJECT_ROOT/config}}"
RUNTIME_CONFIG_DIR="${2:-${MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}}"
SERVICE_UID="${MOLTIS_SERVICE_UID:-1000}"
SERVICE_GID="${MOLTIS_SERVICE_GID:-1000}"

log() {
    echo "[prepare-moltis-runtime-config] $*"
}

copy_static_item() {
    local src="$1"
    local dst="$2"

    if [[ -d "$src" ]]; then
        mkdir -p "$dst"
        cp -R "$src/." "$dst/"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    fi
}

main() {
    if [[ ! -d "$STATIC_CONFIG_DIR" ]]; then
        echo "Static config directory not found: $STATIC_CONFIG_DIR" >&2
        exit 1
    fi

    mkdir -p "$RUNTIME_CONFIG_DIR"
    chmod 700 "$RUNTIME_CONFIG_DIR" 2>/dev/null || true

    for src in "$STATIC_CONFIG_DIR"/*; do
        [[ -e "$src" ]] || continue
        name="$(basename "$src")"

        case "$name" in
            oauth_tokens.json|provider_keys.json|credentials.json)
                log "preserving runtime-managed auth file: $name"
                continue
                ;;
        esac

        copy_static_item "$src" "$RUNTIME_CONFIG_DIR/$name"
    done

    if [[ "$(id -u)" -eq 0 ]]; then
        chown -R "$SERVICE_UID:$SERVICE_GID" "$RUNTIME_CONFIG_DIR"
    fi

    for runtime_file in oauth_tokens.json provider_keys.json credentials.json; do
        if [[ -f "$RUNTIME_CONFIG_DIR/$runtime_file" ]]; then
            chmod 600 "$RUNTIME_CONFIG_DIR/$runtime_file" 2>/dev/null || true
            if [[ "$(id -u)" -eq 0 ]]; then
                chown "$SERVICE_UID:$SERVICE_GID" "$RUNTIME_CONFIG_DIR/$runtime_file"
            fi
        fi
    done

    log "runtime config prepared at $RUNTIME_CONFIG_DIR"
}

main "$@"
