#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WORKFLOW_SCRIPT="$PROJECT_ROOT/scripts/gitops-metrics-workflow.sh"

create_fake_ssh_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "$fake_bin"
    cat >"${fake_bin}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"mkdir -p"* ]]; then
    exit 0
fi

cat <<'JSON'
{"timestamp":"2026-04-21T15:06:27Z","tracked_files":7,"compliant_files":7,"compliance_percentage":100,"last_deploy_age_minutes":3,"slos":{"compliance_target":95,"compliance_met":true}}
JSON
EOF
    chmod +x "${fake_bin}/ssh"
    printf '%s\n' "$fake_bin"
}

run_component_gitops_metrics_workflow_tests() {
    start_timer

    local fixture_root fake_bin output_file github_output summary_file stderr_file
    fixture_root="$(mktemp -d /tmp/gitops-metrics-workflow.XXXXXX)"
    fake_bin="$(create_fake_ssh_bin "$fixture_root")"
    output_file="${fixture_root}/gitops-metrics.json"
    github_output="${fixture_root}/github-output.txt"
    summary_file="${fixture_root}/summary.md"
    stderr_file="${fixture_root}/stderr.log"

    test_start "component_gitops_metrics_workflow_collect_writes_json_and_github_outputs"
    if PATH="${fake_bin}:$PATH" \
        SSH_HOST="ainetic.tech" \
        SSH_USER="root" \
        DEPLOY_PATH="/opt/moltinger-active" \
        METRICS_DIR="/var/log/gitops-metrics" \
        GITOPS_METRICS_OUTPUT_FILE="$output_file" \
        GITHUB_OUTPUT="$github_output" \
        bash "$WORKFLOW_SCRIPT" collect >/dev/null 2>"$stderr_file" && \
        jq -e '.compliance_percentage == 100 and .tracked_files == 7' "$output_file" >/dev/null 2>&1 && \
        grep -Fq 'compliance=100' "$github_output" && \
        grep -Fq 'tracked_files=7' "$github_output"; then
        test_pass
    else
        test_fail "gitops-metrics workflow helper must collect the remote JSON payload and publish the compliance outputs"
    fi

    test_start "component_gitops_metrics_workflow_summary_writes_step_summary_without_warning_on_green_slo"
    if COMPLIANCE="100" \
        TRACKED_FILES="7" \
        GITHUB_STEP_SUMMARY="$summary_file" \
        bash "$WORKFLOW_SCRIPT" summary >/dev/null 2>"$stderr_file" && \
        grep -Fq '## GitOps SLO Report' "$summary_file" && \
        grep -Fq '100% | ✅ MET' "$summary_file" && \
        ! grep -Fq 'GitOps compliance below target' "$stderr_file"; then
        test_pass
    else
        test_fail "gitops-metrics workflow helper must render the green SLO summary without emitting a breach warning"
    fi

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_gitops_metrics_workflow_tests
fi
