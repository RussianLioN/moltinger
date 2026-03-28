#!/usr/bin/env bash
# Detect long-running Deploy Moltis workflow runs and emit structured JSON.

set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Deploy Moltis}"
WORKFLOW_FILE="${WORKFLOW_FILE:-deploy.yml}"
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
  --workflow-file <path>       Workflow file/id to inspect via GitHub API (default: deploy.yml)
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
    local per_page pages_needed page payload_file page_file merged_file tmp_dir

    if [[ -n "$RUNS_JSON_FILE" ]]; then
        cat "$RUNS_JSON_FILE"
        return 0
    fi

    if [[ -z "$REPO" ]]; then
        echo "deploy-stall-watchdog.sh: --repo is required when --runs-json-file is not used" >&2
        exit 2
    fi

    require_command gh
    per_page=$(( MAX_RUNS < 100 ? MAX_RUNS : 100 ))
    pages_needed=$(( (MAX_RUNS + per_page - 1) / per_page ))
    tmp_dir="$(mktemp -d)"
    payload_file="$tmp_dir/payload.json"
    page_file="$tmp_dir/page.json"
    merged_file="$tmp_dir/merged.json"
    printf '%s\n' '{"total_count":0,"workflow_runs":[]}' > "$payload_file"

    for ((page = 1; page <= pages_needed; page++)); do
        gh api \
            -H "Accept: application/vnd.github+json" \
            "repos/${REPO}/actions/workflows/${WORKFLOW_FILE}/runs?per_page=${per_page}&page=${page}" \
            > "$page_file"

        jq -cn \
            --slurpfile current "$payload_file" \
            --slurpfile page_payload "$page_file" \
            --argjson max_runs "$MAX_RUNS" '
                ($current[0] // {}) as $current
                | ($page_payload[0] // {}) as $page_payload
                |
                {
                  total_count: ($page_payload.total_count // $current.total_count // 0),
                  workflow_runs: (($current.workflow_runs + ($page_payload.workflow_runs // []))[:$max_runs])
                }' > "$merged_file"
        mv "$merged_file" "$payload_file"

        if [[ "$(jq '.workflow_runs | length' < "$page_file")" -lt "$per_page" ]]; then
            break
        fi
    done

    cat "$payload_file"
    rm -rf "$tmp_dir"
}

render_human_output() {
    local result_json="$1"
    local status stalled_count

    status="$(jq -r '.status' <<<"$result_json")"
    stalled_count="$(jq -r '.stalled_count' <<<"$result_json")"

    echo "status=$status"
    echo "workflow_name=$(jq -r '.workflow_name' <<<"$result_json")"
    echo "workflow_file=$(jq -r '.workflow_file' <<<"$result_json")"
    echo "threshold_minutes=$(jq -r '.threshold_minutes' <<<"$result_json")"
    echo "stalled_count=$stalled_count"

    if [[ "$stalled_count" == "0" ]]; then
        echo "message=No stalled workflow runs detected"
        return 0
    fi

    jq -r '
        .stalled_runs[]
        | "run_id=\(.id) run_number=\(.run_number) age_minutes=\(.age_minutes) idle_minutes=\(.idle_minutes // "n/a") status=\(.status) reason=\(.stall_reason) branch=\(.head_branch // "detached") url=\(.html_url)"
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
        --workflow-file)
            WORKFLOW_FILE="${2:-}"
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
TMP_JSON_DIR="$(mktemp -d)"
RUNS_JSON_PATH="$TMP_JSON_DIR/runs.json"
fetch_runs_json > "$RUNS_JSON_PATH"

RESULT_JSON="$(
    jq -cn \
        --argjson now_epoch "$NOW_EPOCH" \
        --arg workflow_name "$WORKFLOW_NAME" \
        --arg workflow_file "$WORKFLOW_FILE" \
        --argjson threshold_minutes "$THRESHOLD_MINUTES" \
        --argjson max_runs "$MAX_RUNS" \
        --slurpfile payload "$RUNS_JSON_PATH" '
        ($payload[0] // {}) as $payload
        |
        def age_minutes($created_at):
            ((($now_epoch - ($created_at | fromdateiso8601)) / 60) | floor);

        def idle_minutes($updated_at):
            ((($now_epoch - ($updated_at | fromdateiso8601)) / 60) | floor);

        def active_runs:
            [
              $payload.workflow_runs[]?
              | select(.status == "queued" or .status == "in_progress" or .status == "waiting")
              | . + {
                  age_minutes: age_minutes(.created_at),
                  idle_minutes: idle_minutes(.updated_at)
                }
            ];

        def has_older_in_progress($active; $run):
            any(
              $active[]?;
              .status == "in_progress"
              and .id != $run.id
              and (.created_at | fromdateiso8601) <= ($run.created_at | fromdateiso8601)
            );

        def stalled_runs:
            (active_runs | map(select(.name == $workflow_name))) as $active
            | [
                $active[]?
                | if .status == "in_progress" then
                    select(.idle_minutes >= $threshold_minutes)
                    | . + {stall_reason: "idle_in_progress"}
                  elif (.status == "queued" or .status == "waiting") then
                    select(.age_minutes >= $threshold_minutes)
                    | select((has_older_in_progress($active; .)) | not)
                    | . + {stall_reason: "queue_timeout_without_active_predecessor"}
                  else
                    empty
                  end
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
                    age_minutes,
                    idle_minutes,
                    stall_reason
                  }
              ];

        (stalled_runs) as $stalled
        | {
            status: (if ($stalled | length) > 0 then "stalled" else "ok" end),
            workflow_name: $workflow_name,
            workflow_file: $workflow_file,
            threshold_minutes: $threshold_minutes,
            inspected_runs: ($payload.workflow_runs | length),
            max_runs: $max_runs,
            checked_at: (now | todateiso8601),
            stalled_count: ($stalled | length),
            stalled_runs: $stalled
          }'
)"
rm -rf "$TMP_JSON_DIR"

if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '%s\n' "$RESULT_JSON"
else
    render_human_output "$RESULT_JSON"
fi
