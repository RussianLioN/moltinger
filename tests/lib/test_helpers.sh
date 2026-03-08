#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/core.sh
source "$LIB_DIR/core.sh"
# shellcheck source=tests/lib/env.sh
source "$LIB_DIR/env.sh"
# shellcheck source=tests/lib/http.sh
source "$LIB_DIR/http.sh"
# shellcheck source=tests/lib/process.sh
source "$LIB_DIR/process.sh"
# shellcheck source=tests/lib/docker.sh
source "$LIB_DIR/docker.sh"
# shellcheck source=tests/lib/rpc.sh
source "$LIB_DIR/rpc.sh"
