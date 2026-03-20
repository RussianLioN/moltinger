#!/bin/bash
# Deployment workflow guard tests
# Prevents regressions in production locking and active-root migration logic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DEPLOY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy.yml"
UAT_WORKFLOW="$PROJECT_ROOT/.github/workflows/uat-gate.yml"
EXPECTED_LOCK_GROUP="prod-remote-ainetic-tech-opt-moltinger"

test_deploy_workflow_uses_shared_production_lock() {
    test_start "Deploy workflow should use shared production concurrency group"

    if [[ ! -f "$DEPLOY_WORKFLOW" ]]; then
        test_skip "Missing workflow file: $DEPLOY_WORKFLOW"
        return
    fi

    if ! grep -Fq "group: $EXPECTED_LOCK_GROUP" "$DEPLOY_WORKFLOW"; then
        test_fail "Deploy workflow missing shared lock group: $EXPECTED_LOCK_GROUP"
        return
    fi

    if grep -Fq 'group: deploy-${{ github.ref }}' "$DEPLOY_WORKFLOW"; then
        test_fail "Deploy workflow still uses branch-scoped lock group"
        return
    fi

    test_pass
}

test_uat_deploy_job_uses_shared_production_lock() {
    test_start "UAT deploy job should use shared production concurrency group"

    if [[ ! -f "$UAT_WORKFLOW" ]]; then
        test_skip "Missing workflow file: $UAT_WORKFLOW"
        return
    fi

    if ! grep -Fq "group: $EXPECTED_LOCK_GROUP" "$UAT_WORKFLOW"; then
        test_fail "UAT deploy job missing shared lock group: $EXPECTED_LOCK_GROUP"
        return
    fi

    test_pass
}

test_active_root_symlink_step_handles_legacy_directory() {
    test_start "Symlink update should migrate legacy non-symlink active root"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$UAT_WORKFLOW" ]]; then
        test_skip "Workflow files missing for symlink migration guard check"
        return
    fi

    local deploy_guard=false
    local uat_guard=false

    if grep -Fq "Detected legacy non-symlink active root" "$DEPLOY_WORKFLOW" && \
       grep -Fq 'mv "$ACTIVE_PATH" "$LEGACY_BACKUP"' "$DEPLOY_WORKFLOW"; then
        deploy_guard=true
    fi

    if grep -Fq "Detected legacy non-symlink active root" "$UAT_WORKFLOW" && \
       grep -Fq 'mv "$ACTIVE_PATH" "$LEGACY_BACKUP"' "$UAT_WORKFLOW"; then
        uat_guard=true
    fi

    if [[ "$deploy_guard" == "true" && "$uat_guard" == "true" ]]; then
        test_pass
    else
        test_fail "Legacy directory migration guard missing in deploy.yml and/or uat-gate.yml"
    fi
}

workflow_symlink_step_uses_quoted_heredoc() {
    local workflow_file="$1"
    local in_step=false
    local saw_quoted=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]name:[[:space:]]Update[[:space:]]active[[:space:]]deploy[[:space:]]root[[:space:]]symlink[[:space:]]*$ ]]; then
            in_step=true
            continue
        fi

        if [[ "$in_step" == "true" && "$line" =~ ^[[:space:]]*-[[:space:]]name:[[:space:]] ]]; then
            break
        fi

        if [[ "$in_step" == "true" ]]; then
            if [[ "$line" == *"<< 'EOF'"* ]]; then
                saw_quoted=true
            fi

            if [[ "$line" == *"<< EOF"* ]]; then
                return 1
            fi
        fi
    done < "$workflow_file"

    [[ "$in_step" == "true" && "$saw_quoted" == "true" ]]
}

test_active_root_symlink_step_uses_quoted_heredoc() {
    test_start "Symlink update should use quoted heredoc to avoid runner-side expansion"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$UAT_WORKFLOW" ]]; then
        test_skip "Workflow files missing for heredoc quoting guard check"
        return
    fi

    if ! workflow_symlink_step_uses_quoted_heredoc "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml symlink update step must use << 'EOF' (quoted heredoc)"
        return
    fi

    if ! workflow_symlink_step_uses_quoted_heredoc "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml symlink update step must use << 'EOF' (quoted heredoc)"
        return
    fi

    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Deploy Workflow Guard Unit Tests"
        echo "========================================="
        echo ""
    fi

    test_deploy_workflow_uses_shared_production_lock
    test_uat_deploy_job_uses_shared_production_lock
    test_active_root_symlink_step_handles_legacy_directory
    test_active_root_symlink_step_uses_quoted_heredoc

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
