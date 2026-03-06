#!/bin/bash
# test_telegram_integration.sh - Integration tests for Telegram bot
# Tests Telegram Bot API connectivity and configuration
#
# Test Scenarios:
#   - test_bot_token_valid - Bot token is valid (getMe API call)
#   - test_webhook_configured - Webhook is configured (if applicable)
#   - test_message_send - Can send test message (optional, requires test user)
#
# Usage:
#   source tests/integration/test_telegram_integration.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Dependencies missing (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-integration.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Telegram configuration
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_API_BASE="https://api.telegram.org/bot"
TELEGRAM_TEST_USER="${TELEGRAM_TEST_USER:-}"
TEST_TIMEOUT=30

# Bot info cache
BOT_USERNAME=""
BOT_ID=""
WEBHOOK_URL=""

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_telegram_tests() {
    log_debug "Setting up Telegram integration tests"

    # Check dependencies
    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
        return 2
    fi

    if ! command -v jq &> /dev/null; then
        test_skip "jq not installed"
        return 2
    fi

    # Get token from environment
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        # Try to read from .env file
        local env_file="${PROJECT_ROOT:-/opt/moltinger}/.env"
        if [[ -f "$env_file" ]]; then
            TELEGRAM_BOT_TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2-)
        fi
    fi

    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        test_skip "TELEGRAM_BOT_TOKEN not set"
        return 2
    fi

    return 0
}

# Cleanup test environment
cleanup_telegram_tests() {
    log_debug "Cleaning up Telegram integration tests"
    # No cleanup needed
}

# Register cleanup on exit
trap cleanup_telegram_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Call Telegram Bot API
# Usage: telegram_api "method" [data]
telegram_api() {
    local method="$1"
    local data="${2:-}"
    local url="${TELEGRAM_API_BASE}${TELEGRAM_BOT_TOKEN}/${method}"

    if [[ -n "$data" ]]; then
        curl -s --max-time "$TEST_TIMEOUT" \
            -X POST "$url" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null
    else
        curl -s --max-time "$TEST_TIMEOUT" "$url" 2>/dev/null
    fi
}

# Check if bot token is valid
# Returns: 0 if valid, 1 if invalid
is_bot_token_valid() {
    local response
    response=$(telegram_api "getMe")

    if echo "$response" | jq -e '.ok == true' > /dev/null 2>&1; then
        # Cache bot info
        BOT_USERNAME=$(echo "$response" | jq -r '.result.username // ""')
        BOT_ID=$(echo "$response" | jq -r '.result.id // ""')
        return 0
    fi

    return 1
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Bot token is valid
test_bot_token_valid() {
    test_start "bot_token_valid"

    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        test_skip "TELEGRAM_BOT_TOKEN not set"
        return 2
    fi

    local response
    response=$(telegram_api "getMe")

    if ! echo "$response" | jq -e '.' > /dev/null 2>&1; then
        test_fail "Invalid JSON response from Telegram API"
        return 1
    fi

    local ok
    ok=$(echo "$response" | jq -r '.ok // false')

    if [[ "$ok" == "true" ]]; then
        # Cache bot info
        BOT_USERNAME=$(echo "$response" | jq -r '.result.username // ""')
        BOT_ID=$(echo "$response" | jq -r '.result.id // ""')

        log_debug "Bot username: @$BOT_USERNAME"
        log_debug "Bot ID: $BOT_ID"

        test_pass
    else
        local error_code
        error_code=$(echo "$response" | jq -r '.error_code // "unknown"')
        local description
        description=$(echo "$response" | jq -r '.description // "unknown"')

        test_fail "Bot token invalid: [$error_code] $description"
    fi
}

# Test 2: Bot info contains required fields
test_bot_info_fields() {
    test_start "bot_info_fields"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    local response
    response=$(telegram_api "getMe")

    local id
    id=$(echo "$response" | jq -r '.result.id // ""')
    local username
    username=$(echo "$response" | jq -r '.result.username // ""')
    local first_name
    first_name=$(echo "$response" | jq -r '.result.first_name // ""')
    local is_bot
    is_bot=$(echo "$response" | jq -r '.result.is_bot // false')

    # Verify required fields
    if [[ -z "$id" ]] || [[ "$id" == "null" ]]; then
        test_fail "Bot ID is missing"
        return 1
    fi

    if [[ "$is_bot" != "true" ]]; then
        test_fail "is_bot field is not true"
        return 1
    fi

    if [[ -z "$username" ]] && [[ -z "$first_name" ]]; then
        test_fail "Bot has no username or first_name"
        return 1
    fi

    test_pass
}

# Test 3: Get webhook info
test_webhook_info() {
    test_start "webhook_info"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    local response
    response=$(telegram_api "getWebhookInfo")

    local ok
    ok=$(echo "$response" | jq -r '.ok // false')

    if [[ "$ok" != "true" ]]; then
        test_fail "Failed to get webhook info"
        return 1
    fi

    # Cache webhook URL
    WEBHOOK_URL=$(echo "$response" | jq -r '.result.url // ""')

    local has_custom_certificate
    has_custom_certificate=$(echo "$response" | jq -r '.result.has_custom_certificate // false')
    local pending_update_count
    pending_update_count=$(echo "$response" | jq -r '.result.pending_update_count // 0')

    log_debug "Webhook URL: $WEBHOOK_URL"
    log_debug "Has custom certificate: $has_custom_certificate"
    log_debug "Pending updates: $pending_update_count"

    test_pass
}

# Test 4: Webhook is configured (optional test)
test_webhook_configured() {
    test_start "webhook_configured"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    local response
    response=$(telegram_api "getWebhookInfo")

    local webhook_url
    webhook_url=$(echo "$response" | jq -r '.result.url // ""')

    if [[ -n "$webhook_url" ]] && [[ "$webhook_url" != "null" ]]; then
        log_debug "Webhook configured: $webhook_url"
        test_pass
    else
        test_skip "No webhook configured (bot may be using polling)"
    fi
}

# Test 5: Webhook URL uses HTTPS (if configured)
test_webhook_https() {
    test_start "webhook_https"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    local response
    response=$(telegram_api "getWebhookInfo")

    local webhook_url
    webhook_url=$(echo "$response" | jq -r '.result.url // ""')

    if [[ -z "$webhook_url" ]] || [[ "$webhook_url" == "null" ]]; then
        test_skip "No webhook configured"
        return 2
    fi

    if [[ "$webhook_url" =~ ^https:// ]]; then
        test_pass
    else
        test_fail "Webhook URL does not use HTTPS: $webhook_url"
    fi
}

# Test 6: Bot can accept commands (check bot commands)
test_bot_commands() {
    test_start "bot_commands"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    local response
    response=$(telegram_api "getMyCommands")

    local ok
    ok=$(echo "$response" | jq -r '.ok // false')

    if [[ "$ok" != "true" ]]; then
        test_skip "Failed to get bot commands (may not have any configured)"
    fi

    local command_count
    command_count=$(echo "$response" | jq -r '.result | length // 0')

    if [[ "$command_count" -gt 0 ]]; then
        log_debug "Bot has $command_count commands"
    fi

    test_pass
}

# Test 7: Send test message (optional, requires test user)
test_message_send() {
    test_start "message_send"

    if [[ -z "$TELEGRAM_TEST_USER" ]]; then
        test_skip "TELEGRAM_TEST_USER not set (will not send messages)"
        return 2
    fi

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    # Validate test user format (should be numeric user ID)
    if ! [[ "$TELEGRAM_TEST_USER" =~ ^[0-9]+$ ]]; then
        test_fail "TELEGRAM_TEST_USER must be a numeric Telegram user ID"
        return 1
    fi

    local test_message="Integration test from Moltis"

    local response
    response=$(telegram_api "sendMessage" "{\"chat_id\":\"$TELEGRAM_TEST_USER\",\"text\":\"$test_message\"}")

    local ok
    ok=$(echo "$response" | jq -r '.ok // false')

    if [[ "$ok" == "true" ]]; then
        local message_id
        message_id=$(echo "$response" | jq -r '.result.message_id // ""')
        log_debug "Message sent successfully (ID: $message_id)"
        test_pass
    else
        local error_code
        error_code=$(echo "$response" | jq -r '.error_code // "unknown"')
        local description
        description=$(echo "$response" | jq -r '.description // "unknown"')

        # User may have blocked the bot or not started a conversation
        if [[ "$error_code" == "403" ]]; then
            test_skip "User has not started a conversation with the bot (403 Forbidden)"
        elif [[ "$error_code" == "400" ]]; then
            test_skip "Invalid chat ID or user has blocked the bot (400 Bad Request)"
        else
            test_fail "Failed to send message: [$error_code] $description"
        fi
    fi
}

# Test 8: Bot API response time is acceptable
test_api_response_time() {
    test_start "api_response_time"

    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        test_skip "TELEGRAM_BOT_TOKEN not set"
        return 2
    fi

    local start_time
    start_time=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")

    telegram_api "getMe" > /dev/null 2>&1 || true

    local end_time
    end_time=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")

    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))

    log_debug "Telegram API response time: ${duration_ms}ms"

    # API response should be under 10 seconds
    if [[ $duration_ms -lt 10000 ]]; then
        test_pass
    else
        test_fail "API response time too high: ${duration_ms}ms"
    fi
}

# Test 9: Bot has no pending updates (webhook is processing correctly)
test_pending_updates() {
    test_start "pending_updates"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    local response
    response=$(telegram_api "getWebhookInfo")

    local pending_count
    pending_count=$(echo "$response" | jq -r '.result.pending_update_count // 0')

    if [[ "$pending_count" -eq 0 ]]; then
        test_pass
    else
        log_warn "Bot has $pending_count pending updates (webhook may be delayed)"
        test_skip "Pending updates detected"
    fi
}

# Test 10: Bot can get updates (if not using webhook)
test_get_updates() {
    test_start "get_updates"

    if ! is_bot_token_valid; then
        test_skip "Bot token is not valid"
        return 2
    fi

    # Check if webhook is configured
    local webhook_response
    webhook_response=$(telegram_api "getWebhookInfo")
    local webhook_url
    webhook_url=$(echo "$webhook_response" | jq -r '.result.url // ""')

    if [[ -n "$webhook_url" ]] && [[ "$webhook_url" != "null" ]]; then
        test_skip "Webhook is configured, getUpdates not available"
        return 2
    fi

    # Try to get updates (limit to 1, timeout 0 for quick test)
    local response
    response=$(telegram_api "getUpdates?timeout=0&limit=1")

    local ok
    ok=$(echo "$response" | jq -r '.ok // false')

    if [[ "$ok" == "true" ]]; then
        test_pass
    else
        test_fail "Failed to get updates"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all Telegram integration tests
run_telegram_integration_tests() {
    local setup_code=0
    set +e
    setup_telegram_tests
    setup_code=$?
    set -e

    if [[ $setup_code -ne 0 ]]; then
        # Skip all tests
        test_start "telegram_integration_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running Telegram integration tests..."

    # Mask token in logs
    local token_mask="${TELEGRAM_BOT_TOKEN:0:10}********"
    log_info "Bot token: $token_mask"

    # Run all test cases
    test_bot_token_valid
    test_bot_info_fields || true
    test_webhook_info || true
    test_webhook_configured || true
    test_webhook_https || true
    test_bot_commands || true
    test_message_send || true
    test_api_response_time || true
    test_pending_updates || true
    test_get_updates || true

    # Print bot info summary
    if [[ "$OUTPUT_JSON" != "true" ]] && [[ -n "$BOT_USERNAME" ]]; then
        echo ""
        log_info "Telegram Bot Info:"
        echo "  Username: @$BOT_USERNAME"
        echo "  Bot ID: $BOT_ID"
        if [[ -n "$WEBHOOK_URL" ]] && [[ "$WEBHOOK_URL" != "null" ]]; then
            echo "  Webhook: $WEBHOOK_URL"
        else
            echo "  Webhook: Not configured (using polling)"
        fi
    fi
}

# Run tests if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_telegram_integration_tests
    generate_report
fi
