#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cookie_file_to_header() {
    local cookie_file="$1"
    [[ -f "$cookie_file" ]] || return 1
    awk '
        BEGIN { sep = "" }
        /^#HttpOnly_/ { sub(/^#HttpOnly_/, "", $1) }
        (!/^#/ || /^#HttpOnly_/) && NF >= 7 {
            printf "%s%s=%s", sep, $6, $7
            sep = "; "
        }
        END { print "" }
    ' "$cookie_file"
}

ws_rpc_request() {
    local method="$1"
    local params_json="$2"
    local output_file="$3"
    local wait_ms="${4:-0}"
    local subscribe_csv="${5:-}"

    local -a cmd=(node "$LIB_DIR/ws_rpc_cli.mjs" request --method "$method" --params "$params_json")
    [[ "$wait_ms" != "0" ]] && cmd+=(--wait-ms "$wait_ms")
    [[ -n "$subscribe_csv" ]] && cmd+=(--subscribe "$subscribe_csv")

    "${cmd[@]}" >"$output_file"
}

ws_rpc_request_noauth() {
    local method="$1"
    local params_json="$2"
    local output_file="$3"

    TEST_TIMEOUT="${WS_RPC_NOAUTH_TIMEOUT:-5}" \
        node "$LIB_DIR/ws_rpc_cli.mjs" request --method "$method" --params "$params_json" --no-auth >"$output_file"
}

ws_rpc_invalid_frame() {
    local raw_frame="$1"
    local output_file="$2"
    local wait_ms="${3:-500}"

    node "$LIB_DIR/ws_rpc_cli.mjs" invalid-frame --raw "$raw_frame" --wait-ms "$wait_ms" >"$output_file"
}
