#!/usr/bin/env bash
set -euo pipefail

TEST_LIVE="${TEST_LIVE:-0}"
TEST_ENV_FILE="${TEST_ENV_FILE:-}"
TEST_BASE_URL="${TEST_BASE_URL:-}"

declare -a TEST_CLEANUP_PATHS=()

is_live_mode() {
    case "$TEST_LIVE" in
        1|true|TRUE|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

get_live_env_file() {
    if [[ -n "$TEST_ENV_FILE" && -f "$TEST_ENV_FILE" ]]; then
        printf '%s\n' "$TEST_ENV_FILE"
        return 0
    fi

    if is_live_mode && [[ -f /opt/moltinger/.env ]]; then
        printf '%s\n' "/opt/moltinger/.env"
        return 0
    fi

    return 1
}

load_env_var_from_file() {
    local var_name="$1"
    local env_file="$2"
    [[ -f "$env_file" ]] || return 1
    awk -F= -v key="$var_name" '$1 == key { sub($1"=", ""); print; exit }' "$env_file"
}

resolve_secret_value() {
    local var_name="$1"
    local current_value="${!var_name:-}"

    if [[ -n "$current_value" ]]; then
        printf '%s\n' "$current_value"
        return 0
    fi

    local env_file
    env_file=$(get_live_env_file 2>/dev/null || true)
    if [[ -n "$env_file" ]]; then
        load_env_var_from_file "$var_name" "$env_file"
        return $?
    fi

    return 1
}

register_cleanup_path() {
    TEST_CLEANUP_PATHS+=("$1")
}

cleanup_registered_paths() {
    local path
    for path in "${TEST_CLEANUP_PATHS[@]:-}"; do
        [[ -e "$path" ]] && rm -rf "$path"
    done
}

secure_temp_file() {
    local prefix="${1:-moltis-test}"
    local path
    path=$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
    chmod 600 "$path" 2>/dev/null || true
    register_cleanup_path "$path"
    printf '%s\n' "$path"
}

secure_temp_dir() {
    local prefix="${1:-moltis-test-dir}"
    local path
    path=$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
    chmod 700 "$path" 2>/dev/null || true
    register_cleanup_path "$path"
    printf '%s\n' "$path"
}

require_commands_or_skip() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        test_skip "Missing dependencies: ${missing[*]}"
        return 1
    fi

    return 0
}

require_secret_or_skip() {
    local var_name="$1"
    local description="${2:-$1}"
    local value
    value=$(resolve_secret_value "$var_name" 2>/dev/null || true)

    if [[ -z "$value" ]]; then
        if is_live_mode; then
            test_skip "$description not set"
        else
            test_skip "$description not set in fixture mode"
        fi
        return 1
    fi

    printf -v "$var_name" '%s' "$value"
    export "$var_name"
    return 0
}
