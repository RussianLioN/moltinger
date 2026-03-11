#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ALLOW_DESTRUCTIVE_TESTS="${ALLOW_DESTRUCTIVE_TESTS:-0}"
TARGET_CLAWDIY_CONTAINER="${TARGET_CLAWDIY_CONTAINER:-clawdiy}"
LIVE_CLAWDIY_URL="${LIVE_CLAWDIY_URL:-${CLAWDIY_URL:-}}"
LIVE_MOLTIS_URL="${LIVE_MOLTIS_URL:-${MOLTIS_URL:-}}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/moltis}"
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"

run_clawdiy_rollback_resilience_tests() {
    start_timer

    if ! is_live_mode; then
        test_start "resilience_clawdiy_requires_live_mode"
        test_skip "Suite requires --live"
        generate_report
        return
    fi

    require_commands_or_skip docker curl jq || {
        test_start "resilience_clawdiy_setup"
        test_skip "Dependencies unavailable"
        generate_report
        return
    }

    test_start "resilience_clawdiy_opt_in_required"
    if [[ "$ALLOW_DESTRUCTIVE_TESTS" != "1" ]]; then
        test_skip "Set ALLOW_DESTRUCTIVE_TESTS=1 to run Clawdiy rollback checks"
        generate_report
        return
    fi
    test_pass

    test_start "resilience_clawdiy_container_exists"
    if docker inspect "$TARGET_CLAWDIY_CONTAINER" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Target Clawdiy container $TARGET_CLAWDIY_CONTAINER does not exist"
    fi

    test_start "resilience_clawdiy_health_endpoint"
    if [[ -z "$LIVE_CLAWDIY_URL" ]]; then
        test_skip "Set LIVE_CLAWDIY_URL or CLAWDIY_URL for Clawdiy health verification"
    else
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" "${LIVE_CLAWDIY_URL}/health" 2>/dev/null || echo '000')
        if [[ "$code" == "200" ]]; then
            test_pass
        else
            test_fail "Clawdiy health endpoint should return 200 before rollback (got $code)"
        fi
    fi

    test_start "resilience_clawdiy_rollback_command"
    local rollback_output
    rollback_output="$(secure_temp_file clawdiy-rollback-output)"
    if "$PROJECT_ROOT/scripts/deploy.sh" --json clawdiy rollback >"$rollback_output"; then
        if jq -e '.status == "success" and .action == "rollback"' "$rollback_output" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Clawdiy rollback command should report success JSON"
        fi
    else
        test_fail "Clawdiy rollback command failed"
    fi

    test_start "resilience_clawdiy_rollback_evidence"
    local smoke_output
    smoke_output="$(secure_temp_file clawdiy-rollback-smoke)"
    if "$PROJECT_ROOT/scripts/clawdiy-smoke.sh" --stage rollback-evidence --json >"$smoke_output"; then
        if jq -e '.status == "pass"' "$smoke_output" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Rollback evidence smoke should pass after Clawdiy rollback"
        fi
    else
        test_fail "Rollback evidence smoke failed"
    fi

    test_start "resilience_clawdiy_restore_readiness"
    local latest_backup
    if [[ -f "$PROJECT_ROOT/data/clawdiy/.last-backup" ]]; then
        latest_backup="$(cat "$PROJECT_ROOT/data/clawdiy/.last-backup")"
    else
        latest_backup=""
    fi
    if [[ -z "$latest_backup" || ! -f "$latest_backup" ]]; then
        latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'pre_deploy_*.tar.gz*' | sort | tail -1 || true)
    fi
    if [[ -z "$latest_backup" || ! -f "$latest_backup" ]]; then
        latest_backup=$(ls -t "$BACKUP_DIR"/daily/moltis_* "$BACKUP_DIR"/weekly/moltis_* "$BACKUP_DIR"/monthly/moltis_* 2>/dev/null | head -1 || true)
    fi
    if [[ -z "$latest_backup" ]]; then
        test_fail "Expected a backup archive for Clawdiy restore readiness"
    elif "$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh" verify "$latest_backup" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Latest backup archive should verify successfully for restore readiness"
    fi

    test_start "resilience_clawdiy_moltis_health_unchanged"
    if [[ -z "$LIVE_MOLTIS_URL" ]]; then
        test_skip "Set LIVE_MOLTIS_URL or MOLTIS_URL to verify Moltinger health"
    else
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TEST_TIMEOUT" "${LIVE_MOLTIS_URL}/health" 2>/dev/null || echo '000')
        if [[ "$code" == "200" ]]; then
            test_pass
        else
            test_fail "Moltinger health should remain 200 during Clawdiy rollback (got $code)"
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_clawdiy_rollback_resilience_tests
fi
