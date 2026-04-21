#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/gitops-metrics-workflow.sh collect
  scripts/gitops-metrics-workflow.sh summary
EOF
}

append_output() {
    local key="$1"
    local value="$2"

    [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
}

append_multiline_output() {
    local key="$1"
    local value="$2"

    [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
    {
        printf '%s<<EOF\n' "$key"
        printf '%s\n' "$value"
        printf 'EOF\n'
    } >> "$GITHUB_OUTPUT"
}

collect_metrics() {
    local ssh_host="${SSH_HOST:?SSH_HOST is required}"
    local ssh_user="${SSH_USER:?SSH_USER is required}"
    local deploy_path="${DEPLOY_PATH:?DEPLOY_PATH is required}"
    local metrics_dir="${METRICS_DIR:?METRICS_DIR is required}"
    local output_file="${GITOPS_METRICS_OUTPUT_FILE:-/tmp/gitops-metrics.json}"
    local metrics_raw metrics compliance tracked

    echo "::group::Collecting GitOps metrics"

    ssh -T "${ssh_user}@${ssh_host}" "mkdir -p '$metrics_dir'"

    metrics_raw="$(
        ssh -T "${ssh_user}@${ssh_host}" "DEPLOY_PATH='$deploy_path' METRICS_DIR='$metrics_dir' bash -seu" <<'ENDSSH'
DEPLOY_PATH="${DEPLOY_PATH:?}"
METRICS_DIR="${METRICS_DIR:?}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

TRACKED=0
COMPLIANT=0

if [ -f "$DEPLOY_PATH/docker-compose.yml" ]; then
  TRACKED=$((TRACKED + 1))
  if grep -q "traefik.enable=true" "$DEPLOY_PATH/docker-compose.yml"; then
    COMPLIANT=$((COMPLIANT + 1))
  fi
fi

for f in "$DEPLOY_PATH/config"/*; do
  if [ -f "$f" ]; then
    TRACKED=$((TRACKED + 1))
    COMPLIANT=$((COMPLIANT + 1))
  fi
done

for f in "$DEPLOY_PATH/scripts"/*.sh; do
  if [ -f "$f" ]; then
    TRACKED=$((TRACKED + 1))
    COMPLIANT=$((COMPLIANT + 1))
  fi
done

if [ "$TRACKED" -eq 0 ]; then
  COMPLIANCE_PCT=100
else
  COMPLIANCE_PCT=$(( (COMPLIANT * 100) / TRACKED ))
fi

LAST_DEPLOY="$(stat -c %Y "$DEPLOY_PATH/docker-compose.yml" 2>/dev/null || stat -f %m "$DEPLOY_PATH/docker-compose.yml" 2>/dev/null || echo 0)"
NOW="$(date +%s)"
DEPLOY_AGE_MINUTES=$(( (NOW - LAST_DEPLOY) / 60 ))

compliance_met=false
if [ "$COMPLIANCE_PCT" -ge 95 ]; then
  compliance_met=true
fi

printf '{"timestamp":"%s","tracked_files":%s,"compliant_files":%s,"compliance_percentage":%s,"last_deploy_age_minutes":%s,"slos":{"compliance_target":95,"compliance_met":%s}}\n' \
  "$TIMESTAMP" "$TRACKED" "$COMPLIANT" "$COMPLIANCE_PCT" "$DEPLOY_AGE_MINUTES" "$compliance_met"
ENDSSH
    )"

    metrics="$(printf '%s\n' "$metrics_raw" | awk '/^\{/{line=$0} END{print line}')"
    if ! jq -e . >/dev/null 2>&1 <<<"$metrics"; then
        echo "::error::Failed to parse GitOps metrics JSON"
        printf '%s\n' "$metrics_raw"
        exit 1
    fi

    mkdir -p "$(dirname "$output_file")"
    printf '%s\n' "$metrics" > "$output_file"

    append_multiline_output "metrics" "$metrics"

    compliance="$(jq -r '.compliance_percentage' <<<"$metrics")"
    tracked="$(jq -r '.tracked_files' <<<"$metrics")"
    append_output "compliance" "$compliance"
    append_output "tracked_files" "$tracked"

    echo "::endgroup::"
}

write_summary() {
    local compliance="${COMPLIANCE:?COMPLIANCE is required}"
    local tracked_files="${TRACKED_FILES:?TRACKED_FILES is required}"

    [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || {
        echo "GITHUB_STEP_SUMMARY is required for summary output" >&2
        exit 1
    }

    {
        echo "## GitOps SLO Report"
        echo ""
        echo "| SLO | Target | Current | Status |"
        echo "|-----|--------|---------|--------|"
        if [[ "$compliance" -ge 95 ]]; then
            echo "| Compliance | 95% | ${compliance}% | ✅ MET |"
        else
            echo "| Compliance | 95% | ${compliance}% | ❌ BREACH |"
        fi
        echo ""
        echo "**Tracked Files:** ${tracked_files}"
    } >> "$GITHUB_STEP_SUMMARY"

    if [[ "$compliance" -lt 95 ]]; then
        printf '::warning::GitOps compliance below target: %s%% < 95%%\n' "$compliance"
    fi
}

main() {
    local command_name="${1:-}"
    if [[ -z "$command_name" ]]; then
        usage >&2
        exit 1
    fi
    shift || true

    case "$command_name" in
        collect)
            collect_metrics "$@"
            ;;
        summary)
            write_summary "$@"
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
