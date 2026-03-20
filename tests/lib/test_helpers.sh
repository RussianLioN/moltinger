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

assert_json_array_length() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local message="${4:-JSON array length mismatch}"
    local actual
    if ! command -v jq >/dev/null 2>&1; then
        test_fail "$message (jq not installed)"
        return 1
    fi
    actual=$(printf '%s' "$json" | jq -r "${path} | length" 2>/dev/null || echo "")
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    test_fail "$message (path: '$path', expected: '$expected', got: '$actual')"
    return 0
}

assert_json_array_contains() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local message="${4:-JSON array should contain value}"
    local actual
    if ! command -v jq >/dev/null 2>&1; then
        test_fail "$message (jq not installed)"
        return 1
    fi
    actual=$(printf '%s' "$json" | jq -r --arg expected "$expected" "${path} | index(\$expected)" 2>/dev/null || echo "")
    if [[ "$actual" != "null" && -n "$actual" ]]; then
        return 0
    fi
    test_fail "$message (path: '$path', expected: '$expected')"
    return 0
}

assert_json_filter_count() {
    local json="$1"
    local filter="$2"
    local expected="$3"
    local message="${4:-JSON filter count mismatch}"
    local actual
    if ! command -v jq >/dev/null 2>&1; then
        test_fail "$message (jq not installed)"
        return 1
    fi
    actual=$(printf '%s' "$json" | jq -r "${filter} | length" 2>/dev/null || echo "")
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    test_fail "$message (filter: '$filter', expected: '$expected', got: '$actual')"
    return 0
}
