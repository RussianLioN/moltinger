#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

TELEGRAM_CHAT_PROBE_SCRIPT="$PROJECT_ROOT/scripts/telegram-chat-probe.sh"

setup_unit_telegram_chat_probe_wrapper() {
    require_commands_or_skip bash jq mktemp cat chmod rm || return 2
    return 0
}

create_fake_python_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "$fake_bin"
    cat > "${fake_bin}/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${TELEGRAM_CHAT_PROBE_TEST_MODE:-pass}"
capture_file="${TELEGRAM_CHAT_PROBE_CAPTURE_FILE:-}"

if [[ -n "$capture_file" ]]; then
    {
        printf 'argv=%s\n' "$*"
        printf 'TELEGRAM_API_ID=%s\n' "${TELEGRAM_API_ID:-}"
        printf 'TELEGRAM_API_HASH=%s\n' "${TELEGRAM_API_HASH:-}"
        printf 'TELEGRAM_SESSION=%s\n' "${TELEGRAM_SESSION:-}"
    } >"$capture_file"
fi

case "$mode" in
    pass)
        printf '%s\n' '{"ok":true,"status":"pass","reply_text":"scheduler is active"}'
        ;;
    timeout)
        printf '%s\n' '{"ok":false,"status":"fail","error":"Timeout waiting for reply"}'
        exit 3
        ;;
    invalid_json)
        printf 'not-json\n'
        ;;
    fail)
        printf 'telethon exploded\n' >&2
        exit 17
        ;;
    *)
        printf 'unexpected fake python mode: %s\n' "$mode" >&2
        exit 19
        ;;
esac
EOF
    chmod +x "${fake_bin}/python3"

    printf '%s\n' "$fake_bin"
}

run_unit_telegram_chat_probe_wrapper_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_unit_telegram_chat_probe_wrapper
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local fixture_root fake_bin output json_out status observed capture_file capture_text
    fixture_root="$(secure_temp_dir telegram-chat-probe-wrapper)"
    fake_bin="$(create_fake_python_bin "$fixture_root")"
    json_out="${fixture_root}/probe.json"
    capture_file="${fixture_root}/capture.txt"

    test_start "unit_telegram_chat_probe_wrapper_maps_missing_env_to_precondition_failed"

    output="$(env -u TELEGRAM_TEST_API_ID -u TELEGRAM_TEST_API_HASH -u TELEGRAM_TEST_SESSION -u TELEGRAM_API_ID -u TELEGRAM_API_HASH -u TELEGRAM_SESSION PATH="${fake_bin}:$PATH" bash "$TELEGRAM_CHAT_PROBE_SCRIPT" --message '/status' --json-out "$json_out")"
    status="$(jq -r '.status' <<<"$output")"
    observed="$(jq -r '.observed_reply' <<<"$output")"

    if [[ "$status" != "precondition_failed" ]]; then
        test_fail "Expected precondition_failed, got: $status"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    if [[ "$observed" != "" ]]; then
        test_fail "Expected empty observed_reply for precondition_failed, got: $observed"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_file_exists "$json_out" "Wrapper should persist JSON output when --json-out is provided"
    test_pass

    test_start "unit_telegram_chat_probe_wrapper_maps_pass_json_to_completed"

    output="$(TELEGRAM_TEST_API_ID=1 TELEGRAM_TEST_API_HASH=hash TELEGRAM_TEST_SESSION=session TELEGRAM_CHAT_PROBE_TEST_MODE=pass TELEGRAM_CHAT_PROBE_CAPTURE_FILE="$capture_file" PATH="${fake_bin}:$PATH" bash "$TELEGRAM_CHAT_PROBE_SCRIPT" --message 'cron?' --target '@moltinger_bot' --timeout-sec 7)"
    status="$(jq -r '.status' <<<"$output")"
    observed="$(jq -r '.observed_reply' <<<"$output")"
    capture_text="$(cat "$capture_file")"

    if [[ "$status" != "completed" ]]; then
        test_fail "Expected completed, got: $status"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    if [[ "$observed" != "scheduler is active" ]]; then
        test_fail "Expected wrapper to surface reply_text, got: $observed"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_contains "$capture_text" "argv=${PROJECT_ROOT}/scripts/telegram-user-probe.py --to @moltinger_bot --text cron? --timeout-seconds 7" "Wrapper must forward canonical helper argv"
    assert_contains "$capture_text" "TELEGRAM_API_ID=1" "Wrapper must pass TELEGRAM_TEST_API_ID as TELEGRAM_API_ID"
    assert_contains "$capture_text" "TELEGRAM_API_HASH=hash" "Wrapper must pass TELEGRAM_TEST_API_HASH as TELEGRAM_API_HASH"
    assert_contains "$capture_text" "TELEGRAM_SESSION=session" "Wrapper must pass TELEGRAM_TEST_SESSION as TELEGRAM_SESSION"

    test_pass

    test_start "unit_telegram_chat_probe_wrapper_maps_timeout_json_to_timeout"

    output="$(TELEGRAM_TEST_API_ID=1 TELEGRAM_TEST_API_HASH=hash TELEGRAM_TEST_SESSION=session TELEGRAM_CHAT_PROBE_TEST_MODE=timeout PATH="${fake_bin}:$PATH" bash "$TELEGRAM_CHAT_PROBE_SCRIPT" --message 'cron?' --target '@moltinger_bot')"
    status="$(jq -r '.status' <<<"$output")"

    if [[ "$status" != "timeout" ]]; then
        test_fail "Expected timeout, got: $status"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    test_pass

    test_start "unit_telegram_chat_probe_wrapper_rejects_generic_telegram_env_fallback"

    output="$(env -u TELEGRAM_TEST_API_ID -u TELEGRAM_TEST_API_HASH -u TELEGRAM_TEST_SESSION TELEGRAM_API_ID=1 TELEGRAM_API_HASH=hash TELEGRAM_SESSION=session PATH="${fake_bin}:$PATH" bash "$TELEGRAM_CHAT_PROBE_SCRIPT" --message '/status')"
    status="$(jq -r '.status' <<<"$output")"

    if [[ "$status" != "precondition_failed" ]]; then
        test_fail "Expected precondition_failed when only generic TELEGRAM_API_* env is set, got: $status"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    test_pass

    test_start "unit_telegram_chat_probe_wrapper_maps_nonzero_upstream_exit_to_upstream_failed"

    output="$(TELEGRAM_TEST_API_ID=1 TELEGRAM_TEST_API_HASH=hash TELEGRAM_TEST_SESSION=session TELEGRAM_CHAT_PROBE_TEST_MODE=fail PATH="${fake_bin}:$PATH" bash "$TELEGRAM_CHAT_PROBE_SCRIPT" --message 'cron?' --target '@moltinger_bot')"
    status="$(jq -r '.status' <<<"$output")"
    observed="$(jq -r '.observed_reply' <<<"$output")"

    if [[ "$status" != "upstream_failed" ]]; then
        test_fail "Expected upstream_failed, got: $status"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    if [[ "$observed" != "telethon exploded" ]]; then
        test_fail "Expected wrapper to preserve stderr from failed helper, got: $observed"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    test_pass

    test_start "unit_telegram_chat_probe_wrapper_maps_invalid_json_to_upstream_failed"

    output="$(TELEGRAM_TEST_API_ID=1 TELEGRAM_TEST_API_HASH=hash TELEGRAM_TEST_SESSION=session TELEGRAM_CHAT_PROBE_TEST_MODE=invalid_json PATH="${fake_bin}:$PATH" bash "$TELEGRAM_CHAT_PROBE_SCRIPT" --message 'cron?' --target '@moltinger_bot')"
    status="$(jq -r '.status' <<<"$output")"
    observed="$(jq -r '.observed_reply' <<<"$output")"

    if [[ "$status" != "upstream_failed" ]]; then
        test_fail "Expected upstream_failed for invalid JSON, got: $status"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    if [[ "$observed" != "not-json" ]]; then
        test_fail "Expected wrapper to surface invalid stdout, got: $observed"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    rm -rf "$fixture_root"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_unit_telegram_chat_probe_wrapper_tests
fi
