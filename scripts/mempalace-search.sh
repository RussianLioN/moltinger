#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mempalace-common.sh
source "$SCRIPT_DIR/mempalace-common.sh"

main() {
    [[ $# -ge 1 ]] || die "Usage: ./scripts/mempalace-search.sh \"<query>\" [extra mempalace search args]"

    ensure_index_ready
    run_mempalace "$MEMPALACE_PALACE_PATH" search "$@" --wing "$MEMPALACE_DEFAULT_WING"
}

main "$@"
