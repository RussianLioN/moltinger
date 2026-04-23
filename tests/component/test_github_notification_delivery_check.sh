#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

CHECK_SCRIPT="$PROJECT_ROOT/scripts/github-notification-delivery-check.sh"

run_component_github_notification_delivery_check_tests() {
    start_timer

    test_start "component_notification_guard_stays_green_when_no_channels_are_configured"
    if NOTIFICATION_SCOPE="deploy" \
        EMAIL_ENABLED="false" \
        TELEGRAM_ENABLED="false" \
        EMAIL_OUTCOME="skipped" \
        TELEGRAM_OUTCOME="skipped" \
        bash "$CHECK_SCRIPT" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Notification guard should stay green when no channels are configured"
    fi

    test_start "component_notification_guard_accepts_partial_success"
    if NOTIFICATION_SCOPE="deploy" \
        EMAIL_ENABLED="true" \
        TELEGRAM_ENABLED="true" \
        EMAIL_OUTCOME="success" \
        TELEGRAM_OUTCOME="failure" \
        bash "$CHECK_SCRIPT" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Notification guard should stay green when at least one configured channel succeeds"
    fi

    test_start "component_notification_guard_fails_when_all_configured_channels_fail"
    local output_file
    output_file="$(mktemp)"
    if NOTIFICATION_SCOPE="watchdog" \
        EMAIL_ENABLED="true" \
        TELEGRAM_ENABLED="true" \
        EMAIL_OUTCOME="failure" \
        TELEGRAM_OUTCOME="failure" \
        bash "$CHECK_SCRIPT" >"$output_file" 2>&1; then
        test_fail "Notification guard must fail closed when every configured channel fails"
    elif grep -Fq "All configured watchdog notification channels failed" "$output_file"; then
        test_pass
    else
        test_fail "Notification guard failure must emit the scoped workflow annotation message"
    fi
    rm -f "$output_file"

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_github_notification_delivery_check_tests
fi
