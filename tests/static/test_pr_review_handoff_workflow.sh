#!/bin/bash
# Static guard tests for the deterministic PR review handoff workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/claude-code-review.yml"

run_actionlint_check() {
    if command -v actionlint >/dev/null 2>&1; then
        actionlint "$WORKFLOW_FILE"
        return 0
    fi

    if command -v docker >/dev/null 2>&1; then
        docker run --rm \
          -v "$PROJECT_ROOT:/repo" \
          -w /repo \
          rhysd/actionlint:latest \
          actionlint ".github/workflows/claude-code-review.yml"
        return 0
    fi

    return 127
}

run_all_tests() {
    start_timer

    test_start "pr_review_handoff_workflow_exists_and_preserves_trigger_contract"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q '^name: Claude Code Review$' "$WORKFLOW_FILE" && \
       rg -q '^  pull_request:$' "$WORKFLOW_FILE" && \
       rg -q '^    types: \[opened, synchronize\]$' "$WORKFLOW_FILE" && \
       rg -q '^  workflow_dispatch:$' "$WORKFLOW_FILE" && \
       rg -q '^    name: AI Code Review$' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "PR review workflow must keep the expected workflow/job identity and triggers"
    fi

    test_start "pr_review_handoff_workflow_removes_ai_provider_dependencies"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       ! rg -q 'GLM_API_KEY|AI_REVIEW_PROVIDER|GLM_API_BASE|GLM_MODEL|glm_chat_completion\.sh|Provider\*\*: Z\.ai|AI review did not run' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "PR review workflow must not depend on GLM or any in-workflow AI provider path"
    fi

    test_start "pr_review_handoff_workflow_publishes_manual_ai_ide_handoff"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q 'Review execution\*\*: Manual in AI IDE' "$WORKFLOW_FILE" && \
       rg -q 'Deterministic preflight only' "$WORKFLOW_FILE" && \
       rg -q 'Does not invoke any AI provider in GitHub Actions' "$WORKFLOW_FILE" && \
       rg -q 'scripts/ci/upsert_sticky_comment\.sh' "$WORKFLOW_FILE" && \
       rg -q 'uses: actions/upload-artifact@v4' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "PR review workflow must publish a deterministic handoff artifact/comment for manual AI IDE review"
    fi

    test_start "pr_review_handoff_workflow_uses_minimal_permissions"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q '^permissions:$' "$WORKFLOW_FILE" && \
       rg -q '^  contents: read$' "$WORKFLOW_FILE" && \
       rg -q '^  pull-requests: write$' "$WORKFLOW_FILE" && \
       rg -q '^  issues: write$' "$WORKFLOW_FILE" && \
       ! rg -q '^  actions: read$|^  actions: write$|^  checks: write$|^  packages: write$|^  id-token: write$' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "PR review workflow must keep minimal permissions after removing AI execution"
    fi

    test_start "pr_review_handoff_workflow_passes_actionlint"
    set +e
    actionlint_output="$(run_actionlint_check 2>&1)"
    actionlint_rc=$?
    set -e

    if [[ $actionlint_rc -eq 0 ]]; then
        test_pass
    elif [[ $actionlint_rc -eq 127 ]]; then
        test_skip "actionlint and docker are unavailable"
    else
        test_fail "actionlint must pass for claude-code-review.yml"$'\n'"${actionlint_output}"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
