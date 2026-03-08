#!/usr/bin/env bash
set -euo pipefail

compose_cmd() {
    docker compose -f "$1" ${2:+-p "$2"} ${3:+$3}
}

compose_wait_healthy() {
    local compose_file="$1"
    local project_name="$2"
    local service="$3"
    local timeout_seconds="$4"
    local waited=0
    local status=""

    while [[ "$waited" -lt "$timeout_seconds" ]]; do
        status=$(docker compose -f "$compose_file" -p "$project_name" ps --format json 2>/dev/null | jq -r --arg service "$service" '.[] | select(.Service == $service) | .Health' | head -n1)
        if [[ "$status" == "healthy" ]]; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

collect_compose_diagnostics() {
    local compose_file="$1"
    local project_name="$2"
    local output_dir="$3"
    mkdir -p "$output_dir"
    docker compose -f "$compose_file" -p "$project_name" ps > "$output_dir/compose-ps.txt" 2>&1 || true
    docker compose -f "$compose_file" -p "$project_name" logs --no-color > "$output_dir/compose-logs.txt" 2>&1 || true
}
