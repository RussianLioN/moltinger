#!/bin/bash
# Unit tests for CI helpers used by Z.ai GitHub workflows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

HELPER="$PROJECT_ROOT/scripts/ci/zai_chat_completion.sh"

get_free_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

start_mock_server() {
    local mode="$1"
    local port="$2"

    python3 - "$mode" "$port" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

mode = sys.argv[1]
port = int(sys.argv[2])

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            _ = self.rfile.read(length)

        if mode == "success":
            payload = {"choices": [{"message": {"content": "## Mock review response\\n- finding A"}}]}
            code = 200
        elif mode == "array":
            payload = {"choices": [{"message": {"content": [{"text": "line 1"}, {"text": "line 2"}]}}]}
            code = 200
        else:
            payload = {"error": {"message": "rate limited"}}
            code = 429

        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return

server = HTTPServer(("127.0.0.1", port), Handler)
server.timeout = 5
server.handle_request()
PY
    MOCK_SERVER_PID=$!
    sleep 0.2
}

# Test 1: Missing key should fail with dedicated code.
test_missing_glm_api_key() {
    test_start "zai_chat_completion should fail when GLM_API_KEY is missing"

    local prompt_file output_file
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    echo "hello" > "$prompt_file"

    unset GLM_API_KEY || true

    if "$HELPER" --prompt-file "$prompt_file" --output-file "$output_file" >/dev/null 2>&1; then
        test_fail "Expected helper to fail without GLM_API_KEY"
    else
        local rc=$?
        assert_eq "3" "$rc" "Exit code should indicate missing GLM_API_KEY"
        test_pass
    fi

    rm -f "$prompt_file" "$output_file"
}

# Test 2: Successful response should be written to output file.
test_success_response_parsing() {
    test_start "zai_chat_completion should write content on successful response"

    local prompt_file output_file port
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    echo "review this" > "$prompt_file"

    port="$(get_free_port)"
    start_mock_server success "$port"

    export GLM_API_KEY="dummy"

    if "$HELPER" \
      --prompt-file "$prompt_file" \
      --output-file "$output_file" \
        --api-base "http://127.0.0.1:${port}" \
        --timeout-seconds 10 >/dev/null 2>&1; then
        wait "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
        assert_file_contains "$output_file" "Mock review response" "Output should contain model response"
        test_pass
    else
        wait "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
        test_fail "Expected helper to succeed with mock success server"
    fi

    rm -f "$prompt_file" "$output_file"
}

# Test 3: API non-200 should return dedicated error code.
test_api_error_code() {
    test_start "zai_chat_completion should return code 5 on API error"

    local prompt_file output_file port
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    echo "review this" > "$prompt_file"

    port="$(get_free_port)"
    start_mock_server error "$port"

    export GLM_API_KEY="dummy"

    if "$HELPER" \
      --prompt-file "$prompt_file" \
      --output-file "$output_file" \
        --api-base "http://127.0.0.1:${port}" \
        --timeout-seconds 10 >/dev/null 2>&1; then
        wait "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
        test_fail "Expected helper to fail when API returns 429"
    else
        local rc=$?
        wait "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
        assert_eq "5" "$rc" "Exit code should indicate API request failure"
        test_pass
    fi

    rm -f "$prompt_file" "$output_file"
}

# Test 4: Array content payload should be flattened safely.
test_array_content_parsing() {
    test_start "zai_chat_completion should flatten array-based content"

    local prompt_file output_file port output
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    echo "review this" > "$prompt_file"

    port="$(get_free_port)"
    start_mock_server array "$port"

    export GLM_API_KEY="dummy"

    if "$HELPER" \
      --prompt-file "$prompt_file" \
      --output-file "$output_file" \
        --api-base "http://127.0.0.1:${port}" \
        --timeout-seconds 10 >/dev/null 2>&1; then
        wait "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
        output="$(cat "$output_file")"
        assert_contains "$output" "line 1" "Flattened output should include first array line"
        assert_contains "$output" "line 2" "Flattened output should include second array line"
        test_pass
    else
        wait "$MOCK_SERVER_PID" >/dev/null 2>&1 || true
        test_fail "Expected helper to parse array content response"
    fi

    rm -f "$prompt_file" "$output_file"
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Z.ai CI Helper Unit Tests"
        echo "========================================="
        echo ""
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        test_skip "python3 is required for mock HTTP server"
        generate_report
        return 2
    fi

    if [[ ! -x "$HELPER" ]]; then
        test_fail "Helper script missing or not executable: $HELPER"
        generate_report
        return 1
    fi

    test_missing_glm_api_key
    test_success_response_parsing
    test_api_error_code
    test_array_content_parsing

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
