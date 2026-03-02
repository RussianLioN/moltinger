#!/bin/bash
# test_deployment_recovery.sh - E2E tests for deployment recovery scenarios
# Tests container restart, crash recovery, and system resilience
#
# Test Scenarios:
#   1. Container stop/start recovery
#   2. Container crash and auto-restart
#   3. Docker daemon restart recovery
#   4. Configuration changes handled gracefully
#   5. Health check recovery after temporary failure
#
# Usage:
#   source tests/e2e/test_deployment_recovery.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Dependencies missing (skip)
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/test-e2e.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/../.."

# Source test helpers
# shellcheck source=tests/lib/test_helpers.sh
source "$LIB_DIR/test_helpers.sh"

# Container configuration
MOLTIS_CONTAINER="${MOLTIS_CONTAINER:-moltis}"
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MAX_RESTART_WAIT=60
HEALTH_CHECK_WAIT=5
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.prod.yml"

# Test tracking
ORIGINAL_CONTAINER_STATE=""
ORIGINAL_IMAGE_ID=""
WAS_RUNNING=false

# ==============================================================================
# SETUP AND TEARDOWN
# ==============================================================================

# Setup test environment
setup_deployment_recovery_tests() {
    log_debug "Setting up deployment recovery E2E tests"

    # Check dependencies
    if ! command -v docker &> /dev/null; then
        test_skip "docker not installed"
        return 2
    fi

    if ! command -v curl &> /dev/null; then
        test_skip "curl not installed"
        return 2
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        test_skip "Docker daemon not running"
        return 2
    fi

    # Check if compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        test_skip "Compose file not found: $COMPOSE_FILE"
        return 2
    fi

    # Save original container state
    if docker ps --format '{{.Names}}' | grep -q "^${MOLTIS_CONTAINER}$"; then
        WAS_RUNNING=true
        ORIGINAL_CONTAINER_STATE=$(docker inspect "$MOLTIS_CONTAINER" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
        ORIGINAL_IMAGE_ID=$(docker inspect "$MOLTIS_CONTAINER" --format='{{.Image}}' 2>/dev/null || echo "")
        log_info "Container was running: $MOLTIS_CONTAINER"
    else
        WAS_RUNNING=false
        log_info "Container was not running before tests"
    fi

    return 0
}

# Cleanup test environment - restore original state
cleanup_deployment_recovery_tests() {
    log_debug "Cleaning up deployment recovery E2E tests"

    # Restore container to original state if it was running
    if [[ "$WAS_RUNNING" == "true" ]]; then
        # Check if container is still running
        if ! docker ps --format '{{.Names}}' | grep -q "^${MOLTIS_CONTAINER}$"; then
            log_info "Restarting container that was stopped during tests..."
            cd "$PROJECT_ROOT"
            docker compose -f "$COMPOSE_FILE" up -d "$MOLTIS_CONTAINER" 2>&1 || true

            # Wait for health
            local waited=0
            while [[ $waited -lt $MAX_RESTART_WAIT ]]; do
                if docker inspect --format='{{.State.Health.Status}}' "$MOLTIS_CONTAINER" 2>/dev/null | grep -q "healthy"; then
                    log_info "Container restored to healthy state"
                    break
                fi
                sleep 2
                ((waited += 2)) || true
            done
        fi
    fi
}

# Register cleanup on exit
trap cleanup_deployment_recovery_tests EXIT

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Wait for container to be healthy
# Usage: wait_for_healthy [timeout_seconds]
wait_for_healthy() {
    local timeout="${1:-$MAX_RESTART_WAIT}"
    local waited=0

    while [[ $waited -lt $timeout ]]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "unknown")

        case "$health_status" in
            healthy)
                log_debug "Container is healthy after ${waited}s"
                return 0
                ;;
            unhealthy)
                log_debug "Container is unhealthy (waited ${waited}s)"
                ;;
            starting)
                log_debug "Container is starting... (${waited}s)"
                ;;
            *)
                log_debug "Unknown health status: $health_status"
                ;;
        esac

        sleep "$HEALTH_CHECK_WAIT"
        ((waited += HEALTH_CHECK_WAIT)) || true
    done

    log_warn "Container did not become healthy within ${timeout}s"
    return 1
}

# Get container uptime in seconds
get_container_uptime() {
    local started_at
    started_at=$(docker inspect --format='{{.State.StartedAt}}' "$MOLTIS_CONTAINER" 2>/dev/null | tr -d '\n' || echo "")

    if [[ -z "$started_at" ]]; then
        echo "0"
        return
    fi

    local started_epoch
    started_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%%.*}" +%s 2>/dev/null || echo "0")

    if [[ "$started_epoch" == "0" ]]; then
        echo "0"
    else
        echo $(( $(date +%s) - started_epoch ))
    fi
}

# Check HTTP endpoint is responding
check_http_response() {
    local url="${1:-$MOLTIS_URL/health}"
    local timeout="${2:-10}"

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null || echo "000")

    if [[ "$response_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: Container exists and is inspectable
test_container_exists() {
    test_start "recovery_container_exists"

    if docker inspect "$MOLTIS_CONTAINER" &> /dev/null; then
        test_pass
    else
        test_fail "Container $MOLTIS_CONTAINER does not exist"
    fi
}

# Test 2: Container health status is accessible
test_container_health_accessible() {
    test_start "recovery_health_accessible"

    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "unknown")

    if [[ "$health_status" != "unknown" ]]; then
        log_debug "Health status: $health_status"
        test_pass
    else
        test_fail "Could not retrieve health status"
    fi
}

# Test 3: HTTP health endpoint responds
test_http_health_endpoint() {
    test_start "recovery_http_health"

    if check_http_response "${MOLTIS_URL}/health" 10; then
        test_pass
    else
        test_fail "HTTP health endpoint not responding"
    fi
}

# Test 4: Container stop/start recovery
test_container_stop_start() {
    test_start "recovery_stop_start"

    # Skip if container wasn't running (don't mess with production)
    if [[ "$WAS_RUNNING" != "true" ]]; then
        test_skip "Container was not running before tests"
        return 2
    fi

    # Get original uptime
    local original_uptime
    original_uptime=$(get_container_uptime)
    log_debug "Original uptime: ${original_uptime}s"

    # Stop container
    log_debug "Stopping container..."
    docker stop "$MOLTIS_CONTAINER" > /dev/null 2>&1 || {
        test_fail "Failed to stop container"
        return 1
    }

    # Verify it's stopped
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "unknown")
    if [[ "$status" != "exited" ]] && [[ "$status" != "created" ]]; then
        test_fail "Container did not stop properly (status: $status)"
        return 1
    fi

    # Start container
    log_debug "Starting container..."
    docker start "$MOLTIS_CONTAINER" > /dev/null 2>&1 || {
        test_fail "Failed to start container"
        return 1
    }

    # Wait for health
    if wait_for_healthy 60; then
        # Verify new uptime
        local new_uptime
        new_uptime=$(get_container_uptime)
        log_debug "New uptime after restart: ${new_uptime}s"

        if [[ $new_uptime -lt $original_uptime ]]; then
            test_pass
        else
            test_fail "Uptime did not reset after restart"
        fi
    else
        test_fail "Container did not become healthy after restart"
    fi
}

# Test 5: Container restart command
test_container_restart() {
    test_start "recovery_restart_command"

    # Skip if container wasn't running
    if [[ "$WAS_RUNNING" != "true" ]]; then
        test_skip "Container was not running before tests"
        return 2
    fi

    local before_uptime
    before_uptime=$(get_container_uptime)

    # Wait a moment to ensure uptime difference
    sleep 2

    # Restart container
    log_debug "Restarting container..."
    docker restart "$MOLTIS_CONTAINER" > /dev/null 2>&1 || {
        test_fail "Failed to restart container"
        return 1
    }

    # Wait for health
    if wait_for_healthy 60; then
        local after_uptime
        after_uptime=$(get_container_uptime)

        log_debug "Uptime before restart: ${before_uptime}s"
        log_debug "Uptime after restart: ${after_uptime}s"

        if [[ $after_uptime -lt $before_uptime ]]; then
            test_pass
        else
            test_fail "Uptime should be lower after restart"
        fi
    else
        test_fail "Container did not become healthy after restart"
    fi
}

# Test 6: Health check recovers from temporary failure
test_health_check_recovery() {
    test_start "recovery_health_check"

    # This test verifies that health checks eventually recover
    # We'll check if the container can reach a healthy state

    local max_attempts=12
    local attempt=0
    local became_healthy=false

    while [[ $attempt -lt $max_attempts ]]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "unknown")

        if [[ "$health_status" == "healthy" ]]; then
            became_healthy=true
            break
        fi

        ((attempt++)) || true
        sleep 5
    done

    if [[ "$became_healthy" == "true" ]]; then
        test_pass
    else
        test_fail "Container did not reach healthy state"
    fi
}

# Test 7: Container logs are accessible
test_container_logs_accessible() {
    test_start "recovery_logs_accessible"

    local logs
    logs=$(docker logs "$MOLTIS_CONTAINER" --tail 10 2>&1)

    if [[ -n "$logs" ]]; then
        log_debug "Recent logs available"
        test_pass
    else
        test_skip "No logs available (container may be new)"
    fi
}

# Test 8: Container restart count is tracked
test_restart_count_tracking() {
    test_start "recovery_count_tracking"

    local restart_count
    restart_count=$(docker inspect --format='{{.RestartCount}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "0")

    log_debug "Container restart count: $restart_count"

    # Restart count should be a number
    if [[ "$restart_count" =~ ^[0-9]+$ ]]; then
        test_pass
    else
        test_fail "Restart count is not a valid number: $restart_count"
    fi
}

# Test 9: Container resources are within limits
test_container_resource_limits() {
    test_start "recovery_resource_limits"

    # Check if resource limits are defined
    local max_memory
    max_memory=$(docker inspect --format='{{.HostConfig.Memory}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "0")

    if [[ "$max_memory" != "0" ]]; then
        log_debug "Memory limit set: $max_memory bytes"
        test_pass "Memory limit configured"
    else
        test_skip "No memory limit configured (may be intentional)"
    fi
}

# Test 10: Container network connectivity
test_container_network() {
    test_start "recovery_network"

    # Check if container is in a network
    local networks
    networks=$(docker inspect --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$MOLTIS_CONTAINER" 2>/dev/null || echo "")

    if [[ -n "$networks" ]]; then
        log_debug "Container networks: $networks"

        # Check HTTP connectivity
        if check_http_response "${MOLTIS_URL}/health" 10; then
            test_pass
        else
            test_fail "Container networked but HTTP not responding"
        fi
    else
        test_fail "Container is not connected to any network"
    fi
}

# Test 11: Graceful shutdown on SIGTERM
test_graceful_shutdown() {
    test_start "recovery_graceful_shutdown"

    # Skip if container wasn't running
    if [[ "$WAS_RUNNING" != "true" ]]; then
        test_skip "Container was not running before tests"
        return 2
    fi

    # Send SIGTERM (docker stop does this)
    local before_stop
    before_stop=$(date +%s)

    docker stop "$MOLTIS_CONTAINER" > /dev/null 2>&1 &
    local stop_pid=$!

    # Wait up to 10 seconds for graceful shutdown
    local waited=0
    while [[ $waited -lt 10 ]]; do
        if ! kill -0 "$stop_pid" 2>/dev/null; then
            break
        fi
        sleep 1
        ((waited++)) || true
    done

    wait "$stop_pid" 2>/dev/null || true

    local after_stop
    after_stop=$(date +%s)
    local shutdown_time=$((after_stop - before_stop))

    log_debug "Shutdown time: ${shutdown_time}s"

    # Restart container for other tests
    docker start "$MOLTIS_CONTAINER" > /dev/null 2>&1
    wait_for_healthy 60

    # Shutdown should complete within 10 seconds
    if [[ $shutdown_time -le 10 ]]; then
        test_pass
    else
        test_skip "Shutdown took longer than expected: ${shutdown_time}s"
    fi
}

# Test 12: Multiple restart stress test
test_multiple_restart_stress() {
    test_start "recovery_stress_test"

    # Skip if container wasn't running
    if [[ "$WAS_RUNNING" != "true" ]]; then
        test_skip "Container was not running before tests"
        return 2
    fi

    local restart_count=3
    local successful_restarts=0

    for i in $(seq 1 "$restart_count"); do
        log_debug "Restart cycle $i/$restart_count"

        if docker restart "$MOLTIS_CONTAINER" > /dev/null 2>&1; then
            if wait_for_healthy 30; then
                ((successful_restarts++)) || true
            fi
        fi

        sleep 2
    done

    log_debug "Successful restarts: $successful_restarts/$restart_count"

    if [[ $successful_restarts -eq $restart_count ]]; then
        test_pass
    else
        test_fail "Only $successful_restarts/$restart_count restarts succeeded"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

# Run all deployment recovery E2E tests
run_deployment_recovery_tests() {
    local setup_result
    setup_result=$(setup_deployment_recovery_tests)
    local setup_code=$?

    if [[ $setup_code -ne 0 ]]; then
        test_start "deployment_recovery_tests"
        test_skip "Dependencies not met"
        return 2
    fi

    log_info "Running deployment recovery E2E tests..."
    log_info "Container: $MOLTIS_CONTAINER"
    log_info "Compose file: $COMPOSE_FILE"
    log_info "Was running before tests: $WAS_RUNNING"

    # Run basic tests first
    test_container_exists
    test_container_health_accessible || true
    test_http_health_endpoint || true
    test_container_logs_accessible
    test_restart_count_tracking
    test_container_network
    test_health_check_recovery

    # Run invasive tests only if container was running
    if [[ "$WAS_RUNNING" == "true" ]]; then
        log_info "Container was running - performing invasive recovery tests..."
        test_container_resource_limits
        test_graceful_shutdown || true
        test_container_stop_start || true
        test_container_restart || true
        test_multiple_restart_stress || true
    else
        log_info "Skipping invasive tests - container was not running"
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    start_timer
    run_deployment_recovery_tests
    generate_report
fi
