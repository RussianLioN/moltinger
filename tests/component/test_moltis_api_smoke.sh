#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SMOKE_SCRIPT="$PROJECT_ROOT/scripts/test-moltis-api.sh"

write_fake_http_helpers() {
    local output_path="$1"
    cat >"$output_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

health_status_code() {
    printf '%s\n' "${FAKE_HEALTH_CODE:-200}"
}

moltis_login_code() {
    local _base_url="$1"
    local _password="$2"
    local cookie_file="$3"
    local _timeout="$4"

    cat >"$cookie_file" <<'COOKIE'
# Netscape HTTP Cookie File
localhost	FALSE	/	FALSE	0	session	smoke
COOKIE
    printf '%s\n' "${FAKE_LOGIN_CODE:-200}"
}

moltis_request() {
    local _method="$1"
    local _base_url="$2"
    local _path="$3"
    local _cookie_file="$4"
    local output_file="$5"
    local _timeout="$6"

    printf '%s\n' "${FAKE_AUTH_STATUS_JSON:-{\"authenticated\":true}}" >"$output_file"
}

moltis_logout_code() {
    local _base_url="$1"
    local _cookie_file="$2"
    local _timeout="$3"
    printf '%s\n' "${FAKE_LOGOUT_CODE:-204}"
}
EOF
    chmod +x "$output_path"
}

write_fake_rpc_helpers() {
    local output_path="$1"
    cat >"$output_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cookie_file_to_header() {
    printf 'session=smoke\n'
}
EOF
    chmod +x "$output_path"
}

write_fake_ws_rpc_cli() {
    local output_path="$1"
    cat >"$output_path" <<'EOF'
import fs from 'node:fs';

const args = process.argv.slice(2);
const command = args[0] || 'request';
const method = args[args.indexOf('--method') + 1] || '';
const waitMs = args.includes('--wait-ms') ? args[args.indexOf('--wait-ms') + 1] : '';
const subscribe = args.includes('--subscribe') ? args[args.indexOf('--subscribe') + 1] : '';
const params = args.includes('--params') ? args[args.indexOf('--params') + 1] : '';
const steps = args.includes('--steps') ? JSON.parse(args[args.indexOf('--steps') + 1] || '[]') : [];

function recordCall(entry) {
  if (!process.env.FAKE_WS_CALLS) return;
  fs.appendFileSync(process.env.FAKE_WS_CALLS, JSON.stringify({
    command,
    ...entry,
    testBaseUrl: process.env.TEST_BASE_URL || '',
    testTimeout: process.env.TEST_TIMEOUT || '',
    testCookieHeader: process.env.TEST_COOKIE_HEADER || '',
  }) + '\n');
}

if (command === 'sequence') {
  for (const step of steps) {
    recordCall({
      method: step.method || '',
      waitMs: step.waitMs == null ? '' : String(step.waitMs),
      subscribe,
      params: JSON.stringify(step.params || {}),
    });
  }
} else {
  recordCall({
    method,
    waitMs,
    subscribe,
    params,
  });
}

function payloadForMethod(methodName, paramsJson) {
switch (methodName) {
  case 'status':
    return {
      ok: true,
      result: { ok: true, payload: { version: '0.10.18', connections: 1 } },
      events: [],
    };
  case 'chat.clear':
    return {
      ok: true,
      result: { ok: true, payload: { ok: true } },
      events: [],
    };
  case 'sessions.switch': {
    const parsed = JSON.parse(paramsJson || '{}');
    return {
      ok: true,
      result: { ok: true, payload: { entry: { key: parsed.key || '' } } },
      events: [],
    };
  }
  case 'chat.send':
    return {
      ok: true,
      result: { ok: true, payload: { ok: true } },
      events: [
        {
          event: 'chat',
          payload: {
            state: 'final',
            provider: process.env.FAKE_FINAL_PROVIDER || 'openai-codex',
            model: process.env.FAKE_FINAL_MODEL || 'openai-codex::gpt-5.4',
            text: process.env.FAKE_FINAL_REPLY || 'OK',
          },
        },
      ],
    };
  case 'sessions.delete':
    return {
      ok: true,
      result: { ok: true, payload: { ok: true } },
      events: [],
    };
  default:
    return {
      ok: false,
      message: `unexpected method ${methodName}`,
    };
}
}

let payload;
if (command === 'sequence') {
  const results = [];
  const events = [];
  for (const step of steps) {
    const response = payloadForMethod(step.method || '', JSON.stringify(step.params || {}));
    results.push({ step, response: response.result ?? response });
    if (Array.isArray(response.events)) {
      events.push(...response.events);
    }
  }
  payload = {
    ok: true,
    result: { ok: true, payload: results },
    events,
  };
} else {
  payload = payloadForMethod(method, params);
}

process.stdout.write(JSON.stringify(payload));
EOF
    chmod +x "$output_path"
}

run_component_moltis_api_smoke_tests() {
    start_timer

    local fixture_root fake_root stdout_log stderr_log ws_calls
    fixture_root="$(secure_temp_dir moltis-api-smoke)"
    fake_root="$fixture_root/project"
    stdout_log="$fixture_root/stdout.log"
    stderr_log="$fixture_root/stderr.log"
    ws_calls="$fixture_root/ws-calls.log"

    mkdir -p "$fake_root/tests/lib"
    printf 'MOLTIS_PASSWORD=test-password\n' >"$fake_root/.env"
    write_fake_http_helpers "$fake_root/tests/lib/http.sh"
    write_fake_rpc_helpers "$fake_root/tests/lib/rpc.sh"
    write_fake_ws_rpc_cli "$fake_root/tests/lib/ws_rpc_cli.mjs"

    test_start "component_moltis_api_smoke_uses_current_auth_and_ws_rpc_contract"
    : >"$ws_calls"
    if ! MOLTIS_ACTIVE_ROOT="$fake_root" \
        MOLTIS_URL="http://example.invalid:13131" \
        TEST_TIMEOUT="27" \
        CHAT_WAIT_MS="777" \
        EXPECTED_PROVIDER="openai-codex" \
        EXPECTED_MODEL="openai-codex::gpt-5.4" \
        EXPECTED_REPLY_TEXT="OK" \
        FAKE_WS_CALLS="$ws_calls" \
        bash "$SMOKE_SCRIPT" "Reply with exactly OK and nothing else." >"$stdout_log" 2>"$stderr_log"; then
        test_fail "Smoke script should succeed when fake auth and WS RPC both satisfy the tracked contract"
        rm -rf "$fixture_root"
        return
    fi

    if ! grep -Fq 'Authenticating via /api/auth/login' "$stdout_log" || \
       ! grep -Fq 'Fetching runtime status via RPC' "$stdout_log" || \
       ! grep -Fq 'Running chat workflow via a single RPC connection' "$stdout_log" || \
       ! grep -Fq '=== Done ===' "$stdout_log" || \
       [[ "$(grep -c '"method":"status"' "$ws_calls")" != "1" ]] || \
       [[ "$(grep -c '"method":"chat.clear"' "$ws_calls")" != "1" ]] || \
       [[ "$(grep -c '"method":"chat.send"' "$ws_calls")" != "1" ]] || \
       ! grep -Fq '"waitMs":"777"' "$ws_calls" || \
       ! grep -Fq '"subscribe":"chat"' "$ws_calls" || \
       ! grep -Fq '"testCookieHeader":"session=smoke"' "$ws_calls"; then
        test_fail "Smoke script must authenticate through /api/auth/login semantics, use WS RPC for status/chat, clear chat context before send, and forward wait/cookie context into chat.send"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_moltis_api_smoke_supports_dedicated_session_switch_and_delete"
    : >"$ws_calls"
    if ! MOLTIS_ACTIVE_ROOT="$fake_root" \
        MOLTIS_URL="http://example.invalid:13131" \
        TEST_SESSION_KEY="operator:browser-canary:test" \
        DELETE_TEST_SESSION_ON_EXIT="true" \
        FAKE_WS_CALLS="$ws_calls" \
        bash "$SMOKE_SCRIPT" "Reply with exactly OK and nothing else." >"$stdout_log" 2>"$stderr_log"; then
        test_fail "Smoke script should support switching into and deleting a dedicated operator session"
        rm -rf "$fixture_root"
        return
    fi

    if [[ "$(grep -c '"method":"sessions.switch"' "$ws_calls")" != "1" ]] || \
       [[ "$(grep -c '"method":"sessions.delete"' "$ws_calls")" != "1" ]] || \
       ! grep -Fq '"params":"{\"key\":\"operator:browser-canary:test\"}"' "$ws_calls"; then
        test_fail "Smoke script must call sessions.switch and sessions.delete when TEST_SESSION_KEY lifecycle cleanup is requested"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_moltis_api_smoke_fails_closed_on_expected_reply_mismatch"
    set +e
    MOLTIS_ACTIVE_ROOT="$fake_root" \
        MOLTIS_URL="http://example.invalid:13131" \
        EXPECTED_REPLY_TEXT="OK" \
        FAKE_FINAL_REPLY="NOT-OK" \
        bash "$SMOKE_SCRIPT" "Reply with exactly OK and nothing else." >"$stdout_log" 2>"$stderr_log"
    local exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || ! grep -Fq "Final reply text mismatch" "$stderr_log"; then
        test_fail "Smoke script must fail closed when the final assistant reply breaks the expected reply contract"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_api_smoke_tests
fi
