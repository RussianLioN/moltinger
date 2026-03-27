#!/bin/bash
# Unit tests for GitHub Actions deploy stall watchdog helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WATCHDOG_SCRIPT="$PROJECT_ROOT/scripts/deploy-stall-watchdog.sh"

iso_minutes_ago() {
    local minutes="$1"
    python3 - "$minutes" <<'PY'
from datetime import datetime, timedelta, timezone
import sys
minutes = int(sys.argv[1])
print((datetime.now(timezone.utc) - timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

write_fixture() {
    local fixture_path="$1"
    local stale_in_progress stale_queued fresh_run

    stale_in_progress="$(iso_minutes_ago 70)"
    stale_queued="$(iso_minutes_ago 50)"
    fresh_run="$(iso_minutes_ago 5)"

    cat > "$fixture_path" <<EOF
{
  "workflow_runs": [
    {
      "id": 101,
      "name": "Deploy Moltis",
      "run_number": 91,
      "run_attempt": 1,
      "status": "in_progress",
      "event": "push",
      "head_branch": "main",
      "head_sha": "aaa111",
      "created_at": "$stale_in_progress",
      "updated_at": "$stale_in_progress",
      "html_url": "https://example.invalid/101"
    },
    {
      "id": 102,
      "name": "Deploy Moltis",
      "run_number": 92,
      "run_attempt": 1,
      "status": "queued",
      "event": "workflow_dispatch",
      "head_branch": "main",
      "head_sha": "bbb222",
      "created_at": "$stale_queued",
      "updated_at": "$stale_queued",
      "html_url": "https://example.invalid/102"
    },
    {
      "id": 103,
      "name": "Deploy Moltis",
      "run_number": 93,
      "run_attempt": 1,
      "status": "in_progress",
      "event": "push",
      "head_branch": "main",
      "head_sha": "ccc333",
      "created_at": "$fresh_run",
      "updated_at": "$fresh_run",
      "html_url": "https://example.invalid/103"
    },
    {
      "id": 104,
      "name": "Other Workflow",
      "run_number": 12,
      "run_attempt": 1,
      "status": "in_progress",
      "event": "push",
      "head_branch": "main",
      "head_sha": "ddd444",
      "created_at": "$stale_in_progress",
      "updated_at": "$stale_in_progress",
      "html_url": "https://example.invalid/104"
    }
  ]
}
EOF
}

test_watchdog_requires_repo_or_fixture() {
    test_start "deploy stall watchdog should require repo or fixture input"

    if "$WATCHDOG_SCRIPT" --json >/dev/null 2>&1; then
        test_fail "Expected watchdog helper to reject missing repo/fixture input"
    else
        local rc=$?
        assert_eq "2" "$rc" "Missing repo/fixture should return usage error"
        test_pass
    fi
}

test_watchdog_detects_stalled_runs_from_fixture() {
    test_start "deploy stall watchdog should detect stale queued and in-progress runs"

    local tmp_dir fixture_path result_json
    tmp_dir="$(mktemp -d)"
    fixture_path="$tmp_dir/runs.json"
    write_fixture "$fixture_path"

    result_json="$("$WATCHDOG_SCRIPT" \
        --runs-json-file "$fixture_path" \
        --workflow-name "Deploy Moltis" \
        --threshold-minutes 30 \
        --json)"

    assert_eq "stalled" "$(jq -r '.status' <<<"$result_json")" "Watchdog should report stalled status"
    assert_eq "2" "$(jq -r '.stalled_count' <<<"$result_json")" "Expected two stalled runs over threshold"
    assert_eq "101" "$(jq -r '.stalled_runs[0].id' <<<"$result_json")" "First stalled run id mismatch"
    assert_eq "102" "$(jq -r '.stalled_runs[1].id' <<<"$result_json")" "Second stalled run id mismatch"

    rm -rf "$tmp_dir"
    test_pass
}

test_watchdog_ignores_recent_runs_when_threshold_is_high() {
    test_start "deploy stall watchdog should ignore runs below the configured threshold"

    local tmp_dir fixture_path result_json
    tmp_dir="$(mktemp -d)"
    fixture_path="$tmp_dir/runs.json"
    write_fixture "$fixture_path"

    result_json="$("$WATCHDOG_SCRIPT" \
        --runs-json-file "$fixture_path" \
        --workflow-name "Deploy Moltis" \
        --threshold-minutes 90 \
        --json)"

    assert_eq "ok" "$(jq -r '.status' <<<"$result_json")" "Status should stay ok when threshold exceeds run age"
    assert_eq "0" "$(jq -r '.stalled_count' <<<"$result_json")" "No stalled runs should be reported"

    rm -rf "$tmp_dir"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ ! -x "$WATCHDOG_SCRIPT" ]]; then
        test_fail "Watchdog helper is missing or not executable: $WATCHDOG_SCRIPT"
        generate_report
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        test_skip "python3 and jq are required for watchdog unit tests"
        generate_report
        return 0
    fi

    test_watchdog_requires_repo_or_fixture
    test_watchdog_detects_stalled_runs_from_fixture
    test_watchdog_ignores_recent_runs_when_threshold_is_high

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
