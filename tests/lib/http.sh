#!/usr/bin/env bash
set -euo pipefail

curl_with_test_client_ip() {
    local -a args=("$@")
    if [[ -n "${TEST_CLIENT_IP:-}" ]]; then
        args=(-H "X-Forwarded-For: ${TEST_CLIENT_IP}" -H "X-Real-IP: ${TEST_CLIENT_IP}" "${args[@]}")
    fi
    curl "${args[@]}"
}

json_escape() {
    local raw="${1:-}"
    printf '%s' "$raw" | jq -Rs .
}

health_status_code() {
    local base_url="$1"
    local timeout="${2:-5}"
    curl_with_test_client_ip -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "${base_url}/health" 2>/dev/null || echo "000"
}

header_file_matches() {
    local headers_file="$1"
    local pattern="$2"
    [[ -f "$headers_file" ]] || return 1
    tr -d '\r' < "$headers_file" | grep -Eiq "$pattern"
}

response_is_onboarding_redirect() {
    local status_code="$1"
    local headers_file="$2"
    [[ "$status_code" == "302" || "$status_code" == "303" ]] || return 1
    header_file_matches "$headers_file" '^location:[[:space:]]*/onboarding/?$'
}

header_has_httponly_cookie() {
    local headers_file="$1"
    header_file_matches "$headers_file" '^set-cookie:.*httponly'
}

moltis_login_code() {
    local base_url="$1"
    local password="$2"
    local cookie_file="$3"
    local timeout="${4:-15}"

    curl_with_test_client_ip -s -c "$cookie_file" -b "$cookie_file" \
        -X POST "${base_url}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"password\":$(json_escape "$password")}" \
        -o /dev/null \
        -w '%{http_code}' \
        --max-time "$timeout" 2>/dev/null || echo "000"
}

moltis_login_with_headers() {
    local base_url="$1"
    local password="$2"
    local cookie_file="$3"
    local headers_file="$4"
    local response_file="$5"
    local timeout="${6:-15}"

    curl_with_test_client_ip -s -D "$headers_file" -c "$cookie_file" -b "$cookie_file" \
        -X POST "${base_url}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"password\":$(json_escape "$password")}" \
        -o "$response_file" \
        -w '%{http_code}' \
        --max-time "$timeout" 2>/dev/null || echo "000"
}

moltis_logout_code() {
    local base_url="$1"
    local cookie_file="$2"
    local timeout="${3:-15}"

    curl_with_test_client_ip -s -b "$cookie_file" -c "$cookie_file" \
        -X POST "${base_url}/api/auth/logout" \
        -H 'Content-Type: application/json' \
        -o /dev/null \
        -w '%{http_code}' \
        --max-time "$timeout" 2>/dev/null || echo "000"
}

moltis_request() {
    local method="$1"
    local base_url="$2"
    local endpoint="$3"
    local cookie_file="$4"
    local response_file="$5"
    local timeout="${6:-15}"
    local data="${7:-}"
    local headers_file="${8:-}"

    local args=(-s -X "$method" "${base_url}${endpoint}" -o "$response_file" -w '%{http_code}' --max-time "$timeout")
    [[ -n "$cookie_file" ]] && args=(-b "$cookie_file" -c "$cookie_file" "${args[@]}")
    [[ -n "$headers_file" ]] && args=(-D "$headers_file" "${args[@]}")
    if [[ -n "$data" ]]; then
        args=(-H 'Content-Type: application/json' -d "$data" "${args[@]}")
    fi

    curl_with_test_client_ip "${args[@]}" 2>/dev/null || echo "000"
}
