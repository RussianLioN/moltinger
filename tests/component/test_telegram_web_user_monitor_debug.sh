#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MONITOR_SCRIPT="$PROJECT_ROOT/scripts/telegram-web-user-monitor.sh"

run_component_telegram_web_user_monitor_debug_tests() {
    start_timer

    local test_tmpdir
    test_tmpdir="$(mktemp -d)"
    trap 'rm -rf "$test_tmpdir"' EXIT

    cp "$MONITOR_SCRIPT" "$test_tmpdir/telegram-web-user-monitor.sh"
    chmod +x "$test_tmpdir/telegram-web-user-monitor.sh"
    touch "$test_tmpdir/telegram-web-user-probe.mjs"

    cat > "$test_tmpdir/node" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${NODE_ARGS_CAPTURE:?}"
printf '{"ok":true,"status":"pass"}\n'
SH
    chmod +x "$test_tmpdir/node"

    test_start "component_telegram_web_user_monitor_passes_debug_flag_to_probe"
    if PATH="$test_tmpdir:$PATH" \
        NODE_ARGS_CAPTURE="$test_tmpdir/node-args-debug.txt" \
        TELEGRAM_WEB_DEBUG=true \
        MOLTIS_ENV_FILE=/nonexistent \
        "$test_tmpdir/telegram-web-user-monitor.sh" >/dev/null 2>&1 \
        && grep -qx -- '--debug' "$test_tmpdir/node-args-debug.txt"
    then
        test_pass
    else
        test_fail "Telegram Web monitor must pass --debug to the probe when TELEGRAM_WEB_DEBUG=true"
    fi

    test_start "component_telegram_web_user_monitor_omits_debug_flag_by_default"
    if PATH="$test_tmpdir:$PATH" \
        NODE_ARGS_CAPTURE="$test_tmpdir/node-args-default.txt" \
        MOLTIS_ENV_FILE=/nonexistent \
        "$test_tmpdir/telegram-web-user-monitor.sh" >/dev/null 2>&1 \
        && ! grep -qx -- '--debug' "$test_tmpdir/node-args-default.txt"
    then
        test_pass
    else
        test_fail "Telegram Web monitor must keep --debug opt-in"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_web_user_monitor_debug_tests
fi
