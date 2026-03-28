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
    local stale_in_progress stale_queued_blocked stale_queued_unblocked fresh_in_progress old_but_progressing

    stale_in_progress="$(iso_minutes_ago 70)"
    stale_queued_blocked="$(iso_minutes_ago 50)"
    stale_queued_unblocked="$(iso_minutes_ago 80)"
    fresh_in_progress="$(iso_minutes_ago 5)"
    old_but_progressing="$(iso_minutes_ago 60)"

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
      "created_at": "$stale_queued_blocked",
      "updated_at": "$stale_queued_blocked",
      "html_url": "https://example.invalid/102"
    },
    {
      "id": 103,
      "name": "Deploy Moltis",
      "run_number": 93,
      "run_attempt": 1,
      "status": "queued",
      "event": "workflow_dispatch",
      "head_branch": "release",
      "head_sha": "ccc333",
      "created_at": "$stale_queued_unblocked",
      "updated_at": "$stale_queued_unblocked",
      "html_url": "https://example.invalid/103"
    },
    {
      "id": 104,
      "name": "Deploy Moltis",
      "run_number": 94,
      "run_attempt": 1,
      "status": "in_progress",
      "event": "push",
      "head_branch": "main",
      "head_sha": "ddd444",
      "created_at": "$old_but_progressing",
      "updated_at": "$fresh_in_progress",
      "html_url": "https://example.invalid/104"
    },
    {
      "id": 105,
      "name": "Other Workflow",
      "run_number": 12,
      "run_attempt": 1,
      "status": "in_progress",
      "event": "push",
      "head_branch": "main",
      "head_sha": "eee555",
      "created_at": "$stale_in_progress",
      "updated_at": "$stale_in_progress",
      "html_url": "https://example.invalid/105"
    }
  ]
}
EOF
}

write_large_api_fixture() {
    local fixture_path="$1"

    python3 - "$fixture_path" <<'PY'
from datetime import datetime, timedelta, timezone
import json
import sys

path = sys.argv[1]
now = datetime.now(timezone.utc)
padding = "x" * 40000
runs = []

for idx in range(1, 101):
    created_at = (now - timedelta(minutes=idx + 5)).strftime("%Y-%m-%dT%H:%M:%SZ")
    runs.append({
        "id": 2000 + idx,
        "name": "Deploy Moltis",
        "run_number": 3000 + idx,
        "run_attempt": 1,
        "status": "completed",
        "event": "push",
        "head_branch": "main",
        "head_sha": f"{idx:040d}",
        "created_at": created_at,
        "updated_at": created_at,
        "html_url": f"https://example.invalid/{2000 + idx}",
        "padding": padding,
    })

with open(path, "w", encoding="utf-8") as handle:
    json.dump({"total_count": len(runs), "workflow_runs": runs}, handle)
PY
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

test_watchdog_detects_only_true_stalls_from_fixture() {
    test_start "deploy stall watchdog should distinguish real stalls from serialized or progressing runs"

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
    assert_eq "idle_in_progress" "$(jq -r '.stalled_runs[0].stall_reason' <<<"$result_json")" "First stall reason mismatch"
    assert_eq "103" "$(jq -r '.stalled_runs[1].id' <<<"$result_json")" "Second stalled run id mismatch"
    assert_eq "queue_timeout_without_active_predecessor" "$(jq -r '.stalled_runs[1].stall_reason' <<<"$result_json")" "Second stall reason mismatch"

    if jq -e '.stalled_runs[] | select(.id == 102 or .id == 104)' <<<"$result_json" >/dev/null 2>&1; then
        test_fail "Serialized queued runs or actively progressing in-progress runs must not be reported as stalled"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_watchdog_handles_large_github_api_payload_without_arg_overflow() {
    test_start "deploy stall watchdog should handle oversized GitHub API payloads without jq argv overflow"

    local tmp_dir fixture_path mock_bin result_json
    tmp_dir="$(mktemp -d)"
    fixture_path="$tmp_dir/runs-page.json"
    mock_bin="$tmp_dir/bin"
    mkdir -p "$mock_bin"
    write_large_api_fixture "$fixture_path"

    cat > "$mock_bin/gh" <<EOF
#!/bin/bash
cat "$fixture_path"
EOF
    chmod +x "$mock_bin/gh"

    result_json="$(
        PATH="$mock_bin:$PATH" \
        "$WATCHDOG_SCRIPT" \
            --repo "RussianLioN/moltinger" \
            --workflow-name "Deploy Moltis" \
            --workflow-file "deploy.yml" \
            --threshold-minutes 45 \
            --max-runs 100 \
            --json
    )"

    assert_eq "ok" "$(jq -r '.status' <<<"$result_json")" "Large payload should still produce valid JSON output"
    assert_eq "100" "$(jq -r '.inspected_runs' <<<"$result_json")" "Expected watchdog to inspect the oversized fixture page"
    assert_eq "0" "$(jq -r '.stalled_count' <<<"$result_json")" "Completed runs must not be treated as stalled"

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
    test_watchdog_detects_only_true_stalls_from_fixture
    test_watchdog_handles_large_github_api_payload_without_arg_overflow
    test_watchdog_ignores_recent_runs_when_threshold_is_high

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
