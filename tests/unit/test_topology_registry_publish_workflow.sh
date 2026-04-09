#!/bin/bash
# Workflow guard tests for topology registry publish automation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/topology-registry-publish.yml"

run_all_tests() {
    start_timer

    test_start "topology_registry_publish_workflow_exists_and_is_manual"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q '^name: Topology Registry Publish$' "$WORKFLOW_FILE" && \
       rg -q '^on:$' "$WORKFLOW_FILE" && \
       rg -q '^  workflow_dispatch:$' "$WORKFLOW_FILE" && \
       ! rg -q '^  push:$|^  pull_request:$|^  schedule:$' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "Topology registry publish workflow must exist and stay workflow_dispatch-only"
    fi

    test_start "topology_registry_publish_workflow_uses_minimal_permissions"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q '^permissions:$' "$WORKFLOW_FILE" && \
       rg -q '^  contents: write$' "$WORKFLOW_FILE" && \
       rg -q '^  pull-requests: write$' "$WORKFLOW_FILE" && \
       ! rg -q '^  actions: write$|^  packages: write$|^  id-token: write$' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "Topology registry publish workflow must keep permissions minimal"
    fi

    test_start "topology_registry_publish_workflow_updates_only_publish_branch_and_registry_doc"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q 'PUBLISH_BRANCH="chore/topology-registry-publish"' "$WORKFLOW_FILE" && \
       rg -q 'git switch -C "\$PUBLISH_BRANCH" "origin/main"' "$WORKFLOW_FILE" && \
       rg -q './scripts/git-topology-registry.sh refresh --write-doc' "$WORKFLOW_FILE" && \
       rg -q 'git diff --name-only origin/main\.\.HEAD' "$WORKFLOW_FILE" && \
       rg -q 'docs/GIT-TOPOLOGY-REGISTRY.md' "$WORKFLOW_FILE" && \
       ! rg -q 'docs/GIT-TOPOLOGY-INTENT.yaml' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "Topology registry publish workflow must recreate the publish branch from origin/main and keep the branch diff limited to the generated registry doc"
    fi

    test_start "topology_registry_publish_workflow_handles_pr_creation_or_manual_fallback"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q 'gh pr list --base main --head "\$PUBLISH_BRANCH"' "$WORKFLOW_FILE" && \
       rg -q 'gh pr edit "\$EXISTING_PR_NUMBER"' "$WORKFLOW_FILE" && \
       rg -q 'gh pr create --base main --head "\$PUBLISH_BRANCH"' "$WORKFLOW_FILE" && \
       rg -q 'createPullRequest\|not permitted to create or approve pull requests' "$WORKFLOW_FILE" && \
       rg -q 'pr_state=manual_required' "$WORKFLOW_FILE" && \
       rg -q '::warning::GitHub Actions cannot open the publish PR automatically' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "Topology registry publish workflow must update the publish PR when possible and degrade cleanly when GitHub Actions cannot create it"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
