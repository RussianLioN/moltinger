#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

export DISK_AUTO_CLEANUP_ENABLED=true
export DISK_CLEANUP_COOLDOWN_SECONDS=3600
export COMPOSE_PROJECT_NAME=moltinger

# shellcheck source=scripts/health-monitor.sh
source "$PROJECT_ROOT/scripts/health-monitor.sh"

DOCKER_CALLS=()
RECORDED_CLEANUP=false

send_alert() { :; }
log_info() { :; }
log_warn() { :; }
log_error() { :; }
sleep() { :; }
check_container_health() { return 0; }
docker() {
    DOCKER_CALLS+=("$*")
    return 0
}
df() {
    cat <<'EOF'
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/mock 100 95 5 95% /var/lib/docker
EOF
}

test_disk_cleanup_skips_while_deploy_mutex_is_active() {
    test_start "health monitor should skip image cleanup while deploy mutex is active"

    DOCKER_CALLS=()
    RECORDED_CLEANUP=false
    deploy_mutex_active() { return 0; }
    disk_cleanup_due() { return 0; }
    record_disk_cleanup_epoch() { RECORDED_CLEANUP=true; }

    if check_disk_space 90; then
        test_fail "Disk warning should return non-zero when threshold is exceeded"
        return
    fi

    assert_eq "0" "${#DOCKER_CALLS[@]}" "No docker cleanup should run during active deploy mutex"
    assert_eq "false" "$RECORDED_CLEANUP" "Cleanup cooldown should not be recorded when cleanup is skipped"
    test_pass
}

test_disk_cleanup_prunes_images_only_after_cooldown() {
    test_start "health monitor should prune images only when cooldown allows it"

    DOCKER_CALLS=()
    RECORDED_CLEANUP=false
    deploy_mutex_active() { return 1; }
    disk_cleanup_due() { return 0; }
    record_disk_cleanup_epoch() { RECORDED_CLEANUP=true; }

    if check_disk_space 90; then
        test_fail "Disk warning should return non-zero when threshold is exceeded"
        return
    fi

    assert_contains "${DOCKER_CALLS[*]}" "image prune -af" "Expected image-only cleanup call"
    if [[ "${DOCKER_CALLS[*]}" == *"system prune"* ]]; then
        test_fail "Global docker system prune must not be used by health monitor disk cleanup"
        return
    fi
    assert_eq "true" "$RECORDED_CLEANUP" "Cleanup cooldown should be recorded after image prune"
    test_pass
}

test_full_recovery_skips_mutation_while_deploy_mutex_is_active() {
    test_start "full recovery should skip mutating actions while deploy mutex is active"

    DOCKER_CALLS=()
    deploy_mutex_active() { return 0; }

    if full_recovery "moltis"; then
        test_fail "Full recovery should refuse to mutate while deploy mutex is active"
        return
    fi

    assert_eq "0" "${#DOCKER_CALLS[@]}" "No docker calls should be issued while deploy mutex is active"
    test_pass
}

test_full_recovery_recreates_only_target_container() {
    test_start "full recovery should recreate only the target container without global prune"

    local tmp_dir compose_file
    tmp_dir="$(mktemp -d)"
    compose_file="$tmp_dir/docker-compose.yml"
    : > "$compose_file"

    DOCKER_CALLS=()
    deploy_mutex_active() { return 1; }
    COMPOSE_FILE="$compose_file"

    if ! full_recovery "moltis"; then
        test_fail "Full recovery should succeed when deploy mutex is not active"
        rm -rf "$tmp_dir"
        return
    fi

    assert_contains "${DOCKER_CALLS[*]}" "stop moltis" "Full recovery should stop the target container"
    assert_contains "${DOCKER_CALLS[*]}" "compose -p moltinger -f $compose_file up -d --no-deps --force-recreate moltis" "Full recovery should recreate only the target container with --no-deps"
    if [[ "${DOCKER_CALLS[*]}" == *"system prune"* ]]; then
        test_fail "Full recovery must not invoke global docker system prune"
        rm -rf "$tmp_dir"
        return
    fi
    rm -rf "$tmp_dir"
    test_pass
}

run_component_health_monitor_runtime_guard_tests() {
    start_timer

    test_disk_cleanup_skips_while_deploy_mutex_is_active
    test_disk_cleanup_prunes_images_only_after_cooldown
    test_full_recovery_skips_mutation_while_deploy_mutex_is_active
    test_full_recovery_recreates_only_target_container

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_health_monitor_runtime_guard_tests
fi
