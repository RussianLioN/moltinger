#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mempalace-common.sh
source "$SCRIPT_DIR/mempalace-common.sh"

main() {
    require_command python3

    mkdir -p "$MEMPALACE_STATE_ROOT" "$MEMPALACE_HOME"

    if [[ ! -x "$MEMPALACE_PYTHON" ]]; then
        log_info "Creating MemPalace virtualenv at $MEMPALACE_VENV_DIR"
        python3 -m venv "$MEMPALACE_VENV_DIR"
    fi

    local current_version
    current_version="$(mempalace_current_version 2>/dev/null || true)"
    if [[ "$current_version" != "$MEMPALACE_VERSION" ]]; then
        log_info "Installing mempalace==${MEMPALACE_VERSION}"
        "$MEMPALACE_PYTHON" -m pip install --disable-pip-version-check --upgrade "mempalace==${MEMPALACE_VERSION}"
    else
        log_info "MemPalace ${MEMPALACE_VERSION} already installed"
    fi

    write_wrapper_config

    run_mempalace "$MEMPALACE_PALACE_PATH" status >/dev/null
    HOME="$MEMPALACE_HOME" "$MEMPALACE_PYTHON" - <<'PY'
import mempalace.mcp_server
print("mcp_server_import_ok")
PY

    log_info "MemPalace bootstrap ready"
    log_info "state_root=$MEMPALACE_STATE_ROOT"
    log_info "palace_path=$MEMPALACE_PALACE_PATH"
    log_info "mcp_entry=./scripts/mempalace-mcp-server.sh"
}

main "$@"
