#!/usr/bin/env bash
set -euo pipefail

run_with_timeout_capture() {
    local timeout_secs="$1"
    local output_file="$2"
    shift 2

    : > "$output_file"
    "$@" >"$output_file" 2>&1 &
    local pid=$!
    local waited=0
    local exit_code=0

    while kill -0 "$pid" 2>/dev/null; do
        if [[ $waited -ge $timeout_secs ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        ((waited += 1)) || true
    done

    set +e
    wait "$pid"
    exit_code=$?
    set -e
    return "$exit_code"
}

format_duration() {
    local total_seconds="$1"
    printf '%ss' "$total_seconds"
}
