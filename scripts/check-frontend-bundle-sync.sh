#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SOURCE_ROOT="$PROJECT_ROOT/web/agent-factory-demo"
BASE_URL="http://127.0.0.1:18791"

usage() {
    cat <<'USAGE'
Usage:
  scripts/check-frontend-bundle-sync.sh [--base-url URL] [--source-root PATH]

Options:
  --base-url URL      Base URL of served web shell (default: http://127.0.0.1:18791)
  --source-root PATH  Canonical frontend source root (default: web/agent-factory-demo)
  -h, --help          Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            BASE_URL="${2:-}"
            shift 2
            ;;
        --source-root)
            SOURCE_ROOT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[bundle-sync] unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$BASE_URL" ]]; then
    echo "[bundle-sync] --base-url must not be empty" >&2
    exit 2
fi

if [[ ! -d "$SOURCE_ROOT" ]]; then
    echo "[bundle-sync] source root not found: $SOURCE_ROOT" >&2
    exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[bundle-sync] curl is required" >&2
    exit 2
fi

if ! command -v shasum >/dev/null 2>&1; then
    echo "[bundle-sync] shasum is required" >&2
    exit 2
fi

BASE_URL="${BASE_URL%/}"
FILES=("index.html" "app.css" "app.js")
status=0

for file in "${FILES[@]}"; do
    local_path="$SOURCE_ROOT/$file"
    if [[ ! -f "$local_path" ]]; then
        echo "[bundle-sync] missing source file: $local_path" >&2
        status=1
        continue
    fi

    expected_hash="$(shasum -a 256 "$local_path" | awk '{print $1}')"
    actual_hash="$(curl -fsSL "$BASE_URL/$file" | shasum -a 256 | awk '{print $1}' || true)"

    if [[ -z "$actual_hash" ]]; then
        echo "[bundle-sync] failed to fetch $BASE_URL/$file" >&2
        status=1
        continue
    fi

    if [[ "$expected_hash" != "$actual_hash" ]]; then
        echo "[bundle-sync] mismatch $file expected=$expected_hash actual=$actual_hash" >&2
        status=1
    else
        echo "[bundle-sync] ok $file $actual_hash"
    fi
done

exit "$status"

