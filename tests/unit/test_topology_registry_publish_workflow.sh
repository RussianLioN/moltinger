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
       rg -q 'git switch -C "\$PUBLISH_BRANCH"' "$WORKFLOW_FILE" && \
       rg -q './scripts/git-topology-registry.sh refresh --write-doc' "$WORKFLOW_FILE" && \
       rg -q 'docs/GIT-TOPOLOGY-REGISTRY.md' "$WORKFLOW_FILE" && \
       ! rg -q 'docs/GIT-TOPOLOGY-INTENT.yaml' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "Topology registry publish workflow must reconcile only the publish branch and the generated registry doc"
    fi

    test_start "topology_registry_publish_workflow_creates_or_updates_pr"
    if [[ -f "$WORKFLOW_FILE" ]] && \
       rg -q 'gh pr list --base main --head "\$PUBLISH_BRANCH"' "$WORKFLOW_FILE" && \
       rg -q 'gh pr edit "\$EXISTING_PR_NUMBER"' "$WORKFLOW_FILE" && \
       rg -q 'gh pr create --base main --head "\$PUBLISH_BRANCH"' "$WORKFLOW_FILE"; then
        test_pass
    else
        test_fail "Topology registry publish workflow must create or update the dedicated publish PR"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
