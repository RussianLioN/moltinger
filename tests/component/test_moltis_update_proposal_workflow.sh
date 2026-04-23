#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WORKFLOW_SCRIPT="$PROJECT_ROOT/scripts/moltis-update-proposal-workflow.sh"

create_fake_gh_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "$fake_bin"
    cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
    exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "create" ]]; then
    printf 'GraphQL: not permitted to create or approve pull requests\n' >&2
    exit 1
fi

printf 'unsupported fake gh command: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${fake_bin}/gh"
    printf '%s\n' "$fake_bin"
}

kv_value() {
    local key="$1"
    local payload="$2"

    awk -F= -v key="$key" '$1 == key { sub($1 FS, ""); print; exit }' <<<"$payload"
}

run_component_moltis_update_proposal_workflow_tests() {
    start_timer

    local fixture_root fake_bin github_output
    fixture_root="$(mktemp -d /tmp/moltis-update-proposal-workflow.XXXXXX)"
    fake_bin="$(create_fake_gh_bin "$fixture_root")"
    github_output="${fixture_root}/github-output.txt"

    test_start "component_moltis_update_proposal_workflow_falls_back_to_manual_compare_url"
    if PATH="${fake_bin}:$PATH" \
        GITHUB_OUTPUT="$github_output" \
        GITHUB_REPOSITORY="RussianLioN/moltinger" \
        bash "$WORKFLOW_SCRIPT" \
            sync-pr \
            --candidate-version "20260420.02" \
            --tracked-version "0.10.18" \
            --latest-release-tag "20260420.02" \
            --branch "chore/moltis-update-20260420.02" >/dev/null 2>&1; then
        local payload
        payload="$(cat "$github_output")"
        if [[ "$(kv_value pr_mode "$payload")" == "manual_compare_url" ]] && \
           [[ "$(kv_value candidate_version "$payload")" == "20260420.02" ]] && \
           [[ "$(kv_value pr_url "$payload")" == "https://github.com/RussianLioN/moltinger/compare/main...chore/moltis-update-20260420.02?expand=1" ]]; then
            test_pass
        else
            test_fail "Workflow helper must publish the supported manual compare URL contract when Actions cannot create PRs"
        fi
    else
        test_fail "Workflow helper should stay green and emit compare URL fallback when gh pr create is forbidden"
    fi

    rm -rf "$fixture_root"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_update_proposal_workflow_tests
fi
