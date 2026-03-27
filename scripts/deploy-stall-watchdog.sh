#!/usr/bin/env bash
# Detect long-running Deploy Moltis workflow runs and emit structured JSON.

set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Deploy Moltis}"
THRESHOLD_MINUTES="${THRESHOLD_MINUTES:-45}"
MAX_RUNS="${MAX_RUNS:-100}"
RUNS_JSON_FILE=""
OUTPUT_JSON=false

usage() {
    cat <<'EOF'
Usage: deploy-stall-watchdog.sh [OPTIONS]

Options:
  --repo <owner/name>          GitHub repository (defaults to GITHUB_REPOSITORY)
  --workflow-name <name>       Workflow name to inspect (default: Deploy Moltis)
  --threshold-minutes <n>      Alert threshold in minutes (default: 45)
  --max-runs <n>               Number of recent workflow runs to inspect (default: 100)
  --runs-json-file <path>      Read workflow-runs JSON from a local fixture instead of GitHub API
  --json                       Emit JSON output
  -h, --help                   Show help
EOF
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "deploy-stall-watchdog.sh: missing required command: $command_name" >&2
        exit 2
    fi
}

fetch_runs_json() {
    if [[ -n "$RUNS_JSON_FILE" ]]; then
        cat "$RUNS_JSON_FILE"
        return 0
    fi

    if [[ -z "$REPO" ]]; then
        echo "deploy-stall-watchdog.sh: --repo is required when --runs-json-file is not used" >&2
        exit 2
    fi

    require_command gh
    gh api \
        -H "Accept: application/vnd.github+json" \
        "repos/${REPO}/actions/runs?per_page=${MAX_RUNS}"
}

render_human_output() {
    local result_json="$1"
    local status stalled_count

    status="$(jq -r '.status' <<<"$result_json")"
    stalled_count="$(jq -r '.stalled_count' <<<"$result_json")"

    echo "status=$status"
    echo "workflow_name=$(jq -r '.workflow_name' <<<"$result_json")"
    echo "threshold_minutes=$(jq -r '.threshold_minutes' <<<"$result_json")"
    echo "stalled_count=$stalled_count"

    if [[ "$stalled_count" == "0" ]]; then
        echo "message=No stalled workflow runs detected"
        return 0
    fi

    jq -r '
        .stalled_runs[]
        | "run_id=\(.id) run_number=\(.run_number) age_minutes=\(.age_minutes) status=\(.status) branch=\(.head_branch // "detached") url=\(.html_url)"
    ' <<<"$result_json"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"
            shift 2
            ;;
        --workflow-name)
            WORKFLOW_NAME="${2:-}"
            shift 2
            ;;
        --threshold-minutes)
            THRESHOLD_MINUTES="${2:-}"
            shift 2
            ;;
        --max-runs)
            MAX_RUNS="${2:-}"
            shift 2
            ;;
        --runs-json-file)
            RUNS_JSON_FILE="${2:-}"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "deploy-stall-watchdog.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_command jq

if [[ ! "$THRESHOLD_MINUTES" =~ ^[0-9]+$ || ! "$MAX_RUNS" =~ ^[0-9]+$ ]]; then
    echo "deploy-stall-watchdog.sh: --threshold-minutes and --max-runs must be integers" >&2
    exit 2
fi

if [[ -n "$RUNS_JSON_FILE" && ! -f "$RUNS_JSON_FILE" ]]; then
    echo "deploy-stall-watchdog.sh: fixture file not found: $RUNS_JSON_FILE" >&2
    exit 2
fi

NOW_EPOCH="$(date -u +%s)"
RUNS_JSON="$(fetch_runs_json)"

RESULT_JSON="$(
    jq -cn \
        --argjson now_epoch "$NOW_EPOCH" \
        --arg workflow_name "$WORKFLOW_NAME" \
        --argjson threshold_minutes "$THRESHOLD_MINUTES" \
        --argjson max_runs "$MAX_RUNS" \
        --argjson payload "$RUNS_JSON" '
        def age_minutes($created_at):
            ((($now_epoch - ($created_at | fromdateiso8601)) / 60) | floor);

        def stalled_runs:
            [
              $payload.workflow_runs[]?
              | select(.name == $workflow_name)
              | select(.status == "queued" or .status == "in_progress" or .status == "waiting")
              | . + {age_minutes: age_minutes(.created_at)}
              | select(.age_minutes >= $threshold_minutes)
              | {
                  id,
                  name,
                  run_number,
                  run_attempt,
                  status,
                  event,
                  head_branch,
                  head_sha,
                  created_at,
                  updated_at,
                  html_url,
                  age_minutes
                }
            ];

        (stalled_runs) as $stalled
        | {
            status: (if ($stalled | length) > 0 then "stalled" else "ok" end),
            workflow_name: $workflow_name,
            threshold_minutes: $threshold_minutes,
            inspected_runs: ($payload.workflow_runs | length),
            max_runs: $max_runs,
            checked_at: (now | todateiso8601),
            stalled_count: ($stalled | length),
            stalled_runs: $stalled
          }'
)"

if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '%s\n' "$RESULT_JSON"
else
    render_human_output "$RESULT_JSON"
fi
