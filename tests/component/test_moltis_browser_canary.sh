#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

CANARY_SCRIPT="$PROJECT_ROOT/scripts/moltis-browser-canary.sh"

create_fake_browser_canary_bin() {
    local fixture_root="$1"
    local fake_bin="$fixture_root/bin"

    mkdir -p "$fake_bin"

    cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "logs" ]]; then
    shift
    if [[ "${1:-}" == "--since" ]]; then
        shift 2
    fi
    printf '%s\n' "${FAKE_DOCKER_LOGS:-}"
    exit 0
fi

printf 'unsupported fake docker command: %s\n' "${1:-}" >&2
exit 1
EOF

    chmod +x "$fake_bin/docker"
    printf '%s\n' "$fake_bin"
}

run_component_moltis_browser_canary_tests() {
    start_timer

    local fixture_root fake_bin fake_smoke stdout_log stderr_log smoke_calls
    fixture_root="$(secure_temp_dir moltis-browser-canary)"
    fake_bin="$(create_fake_browser_canary_bin "$fixture_root")"
    fake_smoke="$fixture_root/fake-smoke.sh"
    stdout_log="$fixture_root/stdout.log"
    stderr_log="$fixture_root/stderr.log"
    smoke_calls="$fixture_root/smoke-calls.log"

    cat >"$fake_smoke" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_SMOKE_CALLS:-}" ]]; then
    {
        printf 'CHAT_WAIT_MS=%s\n' "${CHAT_WAIT_MS:-}"
        printf 'TEST_TIMEOUT=%s\n' "${TEST_TIMEOUT:-}"
        printf 'EXPECTED_REPLY_TEXT=%s\n' "${EXPECTED_REPLY_TEXT:-}"
        printf -- '---\n'
    } >>"${FAKE_SMOKE_CALLS:?}"
fi
printf '%s\n' "${FAKE_SMOKE_STDOUT:-smoke ok}"
if [[ "${FAKE_SMOKE_EXIT_CODE:-0}" -ne 0 ]]; then
    exit "${FAKE_SMOKE_EXIT_CODE}"
fi
EOF
    chmod +x "$fake_smoke"

    test_start "component_moltis_browser_canary_passes_when_smoke_and_live_browser_log_match"
    : >"$smoke_calls"
    if ! PATH="$fake_bin:$PATH" \
        DOCKER_BIN="docker" \
        MOLTIS_BROWSER_CANARY_SMOKE_SCRIPT="$fake_smoke" \
        FAKE_SMOKE_CALLS="$smoke_calls" \
        MOLTIS_BROWSER_CANARY_CHAT_WAIT_MS="654" \
        MOLTIS_BROWSER_CANARY_TEST_TIMEOUT="45" \
        MOLTIS_BROWSER_CANARY_EXPECTED_REPLY="Introduction - Moltis Documentation" \
        FAKE_SMOKE_EXIT_CODE="0" \
        FAKE_DOCKER_LOGS=$'INFO tool execution succeeded tool=browser\nINFO navigated to URL' \
        bash "$CANARY_SCRIPT" >"$stdout_log" 2>"$stderr_log"; then
        test_fail "Browser canary should pass when smoke succeeds and live logs prove browser tool execution"
        rm -rf "$fixture_root"
        return
    fi

    if ! grep -Fq '[OK] Moltis browser canary passed' "$stdout_log" || \
       ! grep -Fq 'CHAT_WAIT_MS=654' "$smoke_calls" || \
       ! grep -Fq 'TEST_TIMEOUT=45' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_REPLY_TEXT=Introduction - Moltis Documentation' "$smoke_calls"; then
        test_fail "Browser canary success path must include the OK marker and forward wait/timeout/reply expectations into the smoke helper"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_moltis_browser_canary_uses_extended_default_wait_budget"
    : >"$smoke_calls"
    if ! PATH="$fake_bin:$PATH" \
        DOCKER_BIN="docker" \
        MOLTIS_BROWSER_CANARY_SMOKE_SCRIPT="$fake_smoke" \
        FAKE_SMOKE_CALLS="$smoke_calls" \
        FAKE_SMOKE_EXIT_CODE="0" \
        FAKE_DOCKER_LOGS=$'INFO tool execution succeeded tool=browser\nINFO navigated to URL' \
        bash "$CANARY_SCRIPT" >"$stdout_log" 2>"$stderr_log"; then
        test_fail "Browser canary should use the tracked extended wait budget when env overrides are absent"
        rm -rf "$fixture_root"
        return
    fi

    if ! grep -Fq 'CHAT_WAIT_MS=120000' "$smoke_calls" || \
       ! grep -Fq 'TEST_TIMEOUT=90' "$smoke_calls"; then
        test_fail "Browser canary defaults must keep the extended wait and timeout budget for real browser runs"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    test_start "component_moltis_browser_canary_fails_when_live_logs_still_contain_browser_errors"
    set +e
    PATH="$fake_bin:$PATH" \
        DOCKER_BIN="docker" \
        MOLTIS_BROWSER_CANARY_SMOKE_SCRIPT="$fake_smoke" \
        FAKE_SMOKE_EXIT_CODE="0" \
        FAKE_DOCKER_LOGS=$'INFO tool execution succeeded tool=browser\nWARN browser launch failed: failed to connect to containerized browser' \
        bash "$CANARY_SCRIPT" >"$stdout_log" 2>"$stderr_log"
    local exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] || \
       ! grep -Fq 'browser canary matched a browser failure signature' "$stderr_log"; then
        test_fail "Browser canary must fail closed when live logs still contain browser failure signatures"
        rm -rf "$fixture_root"
        return
    fi
    test_pass

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_browser_canary_tests
fi
