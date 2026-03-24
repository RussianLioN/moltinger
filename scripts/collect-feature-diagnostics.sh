#!/usr/bin/env bash
# Collect read-only feature-branch diagnostics against the live Moltis target.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SSH_USER=""
SSH_HOST=""
DEPLOY_PATH=""
DEPLOY_ACTIVE_PATH=""
GIT_REF=""
GIT_SHA=""
OUTPUT_DIR=""

usage() {
    cat >&2 <<'EOF'
Usage:
  collect-feature-diagnostics.sh \
    --ssh-user <user> \
    --ssh-host <host> \
    --deploy-path <path> \
    --active-path <path> \
    --git-ref <ref> \
    --git-sha <sha> \
    [--output-dir <path>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-user)
            SSH_USER="${2:-}"
            shift 2
            ;;
        --ssh-host)
            SSH_HOST="${2:-}"
            shift 2
            ;;
        --deploy-path)
            DEPLOY_PATH="${2:-}"
            shift 2
            ;;
        --active-path)
            DEPLOY_ACTIVE_PATH="${2:-}"
            shift 2
            ;;
        --git-ref)
            GIT_REF="${2:-}"
            shift 2
            ;;
        --git-sha)
            GIT_SHA="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "collect-feature-diagnostics.sh: unknown argument: $1" >&2
            usage
            exit 64
            ;;
    esac
done

if [[ -z "$SSH_USER" || -z "$SSH_HOST" || -z "$DEPLOY_PATH" || -z "$DEPLOY_ACTIVE_PATH" || -z "$GIT_REF" || -z "$GIT_SHA" ]]; then
    usage
    exit 64
fi

OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/test-results/feature-diagnostics}"
mkdir -p "$OUTPUT_DIR"

REMOTE_JSON="$OUTPUT_DIR/remote-state.json"
LOCAL_PREFLIGHT_JSON="$OUTPUT_DIR/local-preflight.json"
REPORT_JSON="$OUTPUT_DIR/report.json"
SUMMARY_MD="$OUTPUT_DIR/summary.md"
ALIGN_PLAN_TXT="$OUTPUT_DIR/align-plan.txt"
TRACKED_DEPLOY_PLAN_TXT="$OUTPUT_DIR/tracked-deploy-plan.txt"

TRACKED_VERSION="$(bash "$PROJECT_ROOT/scripts/moltis-version.sh" version)"
LOCAL_PREFLIGHT_STATUS="pass"
LOCAL_COMPOSE_STATUS="pass"
REMOTE_REACHABLE="true"
REMOTE_ERROR=""

if ! bash "$PROJECT_ROOT/scripts/preflight-check.sh" --ci --json >"$LOCAL_PREFLIGHT_JSON" 2>&1; then
    LOCAL_PREFLIGHT_STATUS="fail"
fi

if ! env -u MOLTIS_VERSION docker compose -f "$PROJECT_ROOT/docker-compose.prod.yml" config --quiet >/dev/null 2>&1; then
    LOCAL_COMPOSE_STATUS="fail"
fi

bash "$PROJECT_ROOT/scripts/align-server-checkout.sh" \
    --ssh-user "$SSH_USER" \
    --ssh-host "$SSH_HOST" \
    --deploy-path "$DEPLOY_PATH" \
    --target-ref "$GIT_REF" \
    --target-sha "$GIT_SHA" \
    --clean-untracked \
    --dry-run >"$ALIGN_PLAN_TXT"

bash "$PROJECT_ROOT/scripts/ssh-run-tracked-moltis-deploy.sh" \
    --ssh-user "$SSH_USER" \
    --ssh-host "$SSH_HOST" \
    --deploy-path "$DEPLOY_PATH" \
    --git-sha "$GIT_SHA" \
    --git-ref "$GIT_REF" \
    --workflow-run "${GITHUB_RUN_ID:-feature-diagnostics}" \
    --version "$TRACKED_VERSION" \
    --dry-run >"$TRACKED_DEPLOY_PLAN_TXT"

if ! ssh "$SSH_USER@$SSH_HOST" \
    "DEPLOY_PATH=$(printf '%q' "$DEPLOY_PATH") ACTIVE_PATH=$(printf '%q' "$DEPLOY_ACTIVE_PATH") bash -seu" >"$REMOTE_JSON" <<'EOF'
set -euo pipefail

cd "$DEPLOY_PATH"

git_head="$(git rev-parse HEAD 2>/dev/null || true)"
git_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo detached)"
git_status="$(git status --porcelain 2>/dev/null || true)"
deployed_sha="$(cat data/.deployed-sha 2>/dev/null || true)"
deployment_info="$(cat data/.deployment-info 2>/dev/null || true)"
active_target="$(readlink "$ACTIVE_PATH" 2>/dev/null || true)"
container_image="$(docker inspect --format='{{.Config.Image}}' moltis 2>/dev/null || true)"
container_health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' moltis 2>/dev/null || echo not_found)"
local_health_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:13131/health 2>/dev/null || echo 000)"
external_health_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://moltis.ainetic.tech/health 2>/dev/null || echo 000)"

jq -n \
  --arg git_head "$git_head" \
  --arg git_branch "$git_branch" \
  --arg git_status "$git_status" \
  --arg deployed_sha "$deployed_sha" \
  --arg deployment_info "$deployment_info" \
  --arg active_target "$active_target" \
  --arg container_image "$container_image" \
  --arg container_health "$container_health" \
  --arg local_health_code "$local_health_code" \
  --arg external_health_code "$external_health_code" \
  '{
    git: {
      head: (if $git_head == "" then null else $git_head end),
      branch: $git_branch,
      status_lines: ($git_status | split("\n") | map(select(length > 0)))
    },
    deploy: {
      deployed_sha: (if $deployed_sha == "" then null else $deployed_sha end),
      deployment_info: (if $deployment_info == "" then null else $deployment_info end),
      active_target: (if $active_target == "" then null else $active_target end)
    },
    runtime: {
      container_image: (if $container_image == "" then null else $container_image end),
      container_health: $container_health,
      localhost_health_http: $local_health_code,
      external_health_http: $external_health_code
    }
  }'
EOF
then
    REMOTE_REACHABLE="false"
    REMOTE_ERROR="$(cat "$REMOTE_JSON" 2>/dev/null || true)"
    jq -n --arg error "$REMOTE_ERROR" '{error: $error}' >"$REMOTE_JSON"
fi

jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg git_ref "$GIT_REF" \
    --arg git_sha "$GIT_SHA" \
    --arg tracked_version "$TRACKED_VERSION" \
    --arg local_preflight_status "$LOCAL_PREFLIGHT_STATUS" \
    --arg local_compose_status "$LOCAL_COMPOSE_STATUS" \
    --arg remote_reachable "$REMOTE_REACHABLE" \
    --arg remote_error "$REMOTE_ERROR" \
    --arg align_plan "$(cat "$ALIGN_PLAN_TXT")" \
    --arg tracked_deploy_plan "$(cat "$TRACKED_DEPLOY_PLAN_TXT")" \
    --slurpfile remote "$REMOTE_JSON" \
    '{
      workflow: "feature-diagnostics",
      timestamp: $timestamp,
      branch_ref: $git_ref,
      branch_sha: $git_sha,
      tracked_version: $tracked_version,
      contracts: {
        diagnostics_only: true,
        production_mutation_allowed: false
      },
      local: {
        preflight_status: $local_preflight_status,
        compose_status: $local_compose_status
      },
      remote: $remote[0],
      dry_run_plans: {
        align_server_checkout: $align_plan,
        tracked_deploy: $tracked_deploy_plan
      },
      errors: (if $remote_error == "" then [] else [{code: "REMOTE_DIAGNOSTICS_UNAVAILABLE", message: $remote_error}] end)
    }' >"$REPORT_JSON"

REMOTE_DEPLOYED_SHA="$(jq -r '.remote.deploy.deployed_sha // empty' "$REPORT_JSON")"
REMOTE_CONTAINER_HEALTH="$(jq -r '.remote.runtime.container_health // "unknown"' "$REPORT_JSON")"
REMOTE_LOCAL_HTTP="$(jq -r '.remote.runtime.localhost_health_http // "000"' "$REPORT_JSON")"
REMOTE_EXTERNAL_HTTP="$(jq -r '.remote.runtime.external_health_http // "000"' "$REPORT_JSON")"

{
    echo "# Feature Branch Diagnostics"
    echo
    echo "- Branch ref: \`$GIT_REF\`"
    echo "- Branch sha: \`$GIT_SHA\`"
    echo "- Tracked Moltis version: \`$TRACKED_VERSION\`"
    echo "- Local preflight: \`$LOCAL_PREFLIGHT_STATUS\`"
    echo "- Local compose render: \`$LOCAL_COMPOSE_STATUS\`"
    echo "- Remote reachable: \`$REMOTE_REACHABLE\`"
    echo "- Remote deployed sha: \`${REMOTE_DEPLOYED_SHA:-unknown}\`"
    echo "- Remote container health: \`$REMOTE_CONTAINER_HEALTH\`"
    echo "- Remote localhost /health: \`$REMOTE_LOCAL_HTTP\`"
    echo "- Remote external /health: \`$REMOTE_EXTERNAL_HTTP\`"
    echo
    echo "## Safety contract"
    echo
    echo "- This workflow is read-only and must not mutate production."
    echo "- The attached dry-run plans are evidence only. Promote to \`main\` before any production rollout."
    echo
    echo "## Artifacts"
    echo
    echo "- \`report.json\`"
    echo "- \`local-preflight.json\`"
    echo "- \`remote-state.json\`"
    echo "- \`align-plan.txt\`"
    echo "- \`tracked-deploy-plan.txt\`"
} >"$SUMMARY_MD"
