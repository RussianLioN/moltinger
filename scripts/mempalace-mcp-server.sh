#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mempalace-common.sh
source "$SCRIPT_DIR/mempalace-common.sh"

main() {
    ensure_index_ready
    exec env \
        HOME="$MEMPALACE_HOME" \
        MEMPALACE_PALACE_PATH="$MEMPALACE_PALACE_PATH" \
        "$MEMPALACE_PYTHON" -m mempalace.mcp_server
}

main "$@"
