#!/bin/bash
# Deployment workflow guard tests
# Prevents regressions in production locking and active-root migration logic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DEPLOY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy.yml"
UAT_WORKFLOW="$PROJECT_ROOT/.github/workflows/uat-gate.yml"
ACTIVE_ROOT_SCRIPT="$PROJECT_ROOT/scripts/update-active-deploy-root.sh"
SYNC_SURFACE_SCRIPT="$PROJECT_ROOT/scripts/gitops-sync-managed-surface.sh"
EXPECTED_LOCK_GROUP="prod-remote-ainetic-tech-opt-moltinger"
EXPECTED_ACTIVE_ROOT_SCRIPT="scripts/update-active-deploy-root.sh"
EXPECTED_SYNC_SURFACE_SCRIPT="scripts/gitops-sync-managed-surface.sh"

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

test_active_root_workflows_use_shared_script_entrypoint() {
    test_start "Active-root workflow step should use shared script entrypoint"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$UAT_WORKFLOW" || ! -f "$ACTIVE_ROOT_SCRIPT" ]]; then
        test_skip "Workflow/script files missing for active-root entrypoint check"
        return
    fi

    if ! grep -Fq "$EXPECTED_ACTIVE_ROOT_SCRIPT" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml must call $EXPECTED_ACTIVE_ROOT_SCRIPT"
        return
    fi

    if ! grep -Fq "$EXPECTED_ACTIVE_ROOT_SCRIPT" "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml must call $EXPECTED_ACTIVE_ROOT_SCRIPT"
        return
    fi

    if grep -Fq "Detected legacy non-symlink active root" "$DEPLOY_WORKFLOW" || \
       grep -Fq 'ln -sfn "$TARGET_PATH" "$ACTIVE_PATH"' "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml should not inline active-root mutation logic"
        return
    fi

    if grep -Fq "Detected legacy non-symlink active root" "$UAT_WORKFLOW" || \
       grep -Fq 'ln -sfn "$TARGET_PATH" "$ACTIVE_PATH"' "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml should not inline active-root mutation logic"
        return
    fi

    test_pass
}

test_gitops_sync_workflows_use_shared_script_entrypoint() {
    test_start "GitOps sync step should use shared managed-surface script entrypoint"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$UAT_WORKFLOW" || ! -f "$SYNC_SURFACE_SCRIPT" ]]; then
        test_skip "Workflow/script files missing for managed-surface entrypoint check"
        return
    fi

    if ! grep -Fq "$EXPECTED_SYNC_SURFACE_SCRIPT" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml must call $EXPECTED_SYNC_SURFACE_SCRIPT"
        return
    fi

    if ! grep -Fq "$EXPECTED_SYNC_SURFACE_SCRIPT" "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml must call $EXPECTED_SYNC_SURFACE_SCRIPT"
        return
    fi

    if grep -Fq "scp docker-compose.yml" "$DEPLOY_WORKFLOW" || \
       grep -Fq "scp docker-compose.prod.yml" "$DEPLOY_WORKFLOW" || \
       grep -Fq "scp -r config/*" "$DEPLOY_WORKFLOW" || \
       grep -Fq "scp -r scripts/*" "$DEPLOY_WORKFLOW" || \
       grep -Fq "scp -r systemd/*" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml should not inline managed-surface sync logic"
        return
    fi

    if grep -Fq "scp docker-compose.yml" "$UAT_WORKFLOW" || \
       grep -Fq "scp docker-compose.prod.yml" "$UAT_WORKFLOW" || \
       grep -Fq "scp -r config/*" "$UAT_WORKFLOW" || \
       grep -Fq "scp -r scripts/*" "$UAT_WORKFLOW" || \
       grep -Fq 'chmod +x ${{ env.DEPLOY_PATH }}/scripts/deploy.sh' "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml should not inline managed-surface sync logic"
        return
    fi

    test_pass
}

test_active_root_script_migrates_legacy_directory() {
    test_start "Shared active-root script should migrate legacy directory into backup"

    if [[ ! -f "$ACTIVE_ROOT_SCRIPT" ]]; then
        test_skip "Missing script file: $ACTIVE_ROOT_SCRIPT"
        return
    fi

    local tmp_dir target_path active_path output_file resolved_target
    tmp_dir="$(mktemp -d)"
    target_path="$tmp_dir/deploy-root"
    active_path="$tmp_dir/active-root"
    output_file="$tmp_dir/output.log"

    mkdir -p "$target_path" "$active_path"
    echo "legacy" > "$active_path/marker.txt"

    if ! bash "$ACTIVE_ROOT_SCRIPT" --target-path "$target_path" --active-path "$active_path" >"$output_file" 2>&1; then
        test_fail "update-active-deploy-root.sh failed for legacy directory scenario"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ ! -L "$active_path" ]]; then
        test_fail "Active path must become a symlink"
        rm -rf "$tmp_dir"
        return
    fi

    resolved_target="$(readlink "$active_path")"
    if [[ "$resolved_target" != "$target_path" ]]; then
        test_fail "Active path must point to target path after update"
        rm -rf "$tmp_dir"
        return
    fi

    if ! find "$tmp_dir" -maxdepth 1 -type d -name 'active-root.legacy-*' | grep -q .; then
        test_fail "Legacy directory backup should be created next to active path"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_gitops_sync_script_dry_run_covers_managed_surface() {
    test_start "Shared GitOps sync script should cover config, scripts, systemd, cleanup, and chmod alignment"

    if [[ ! -f "$SYNC_SURFACE_SCRIPT" ]]; then
        test_skip "Missing script file: $SYNC_SURFACE_SCRIPT"
        return
    fi

    local tmp_dir project_root output_file
    tmp_dir="$(mktemp -d)"
    project_root="$tmp_dir/project"
    output_file="$tmp_dir/output.log"

    mkdir -p "$project_root/config" "$project_root/scripts" "$project_root/systemd"
    printf 'services: {}\n' > "$project_root/docker-compose.yml"
    printf 'services: {}\n' > "$project_root/docker-compose.prod.yml"
    printf 'name = \"moltis\"\n' > "$project_root/config/moltis.toml"
    printf '#!/usr/bin/env bash\n' > "$project_root/scripts/local-entry.sh"
    printf 'demo\n' > "$project_root/systemd/demo.service"
    cat > "$project_root/scripts/manifest.json" <<'EOF'
{
  "scripts": {
    "local-entry.sh": {
      "entrypoint": true
    },
    "library.sh": {
      "entrypoint": false
    }
  }
}
EOF

    if ! bash "$SYNC_SURFACE_SCRIPT" \
        --dry-run \
        --project-root "$project_root" \
        --ssh-user root \
        --ssh-host example.com \
        --deploy-path /srv/moltinger >"$output_file" 2>&1; then
        test_fail "gitops-sync-managed-surface.sh dry-run failed"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "docker-compose.yml" "$output_file"; then
        test_fail "Dry-run output should include docker-compose.yml sync"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "docker-compose.prod.yml" "$output_file"; then
        test_fail "Dry-run output should include docker-compose.prod.yml sync"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "/srv/moltinger/config/provider_keys.json" "$output_file"; then
        test_fail "Dry-run output should include runtime-managed auth cleanup"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "/srv/moltinger/systemd/" "$output_file"; then
        test_fail "Dry-run output should include systemd sync when directory exists"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "/srv/moltinger/scripts/local-entry.sh" "$output_file"; then
        test_fail "Dry-run output should include manifest-driven remote chmod alignment"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_active_root_script_requires_existing_target_directory() {
    test_start "Shared active-root script should reject a missing target directory"

    if [[ ! -f "$ACTIVE_ROOT_SCRIPT" ]]; then
        test_skip "Missing script file: $ACTIVE_ROOT_SCRIPT"
        return
    fi

    local tmp_dir missing_target active_path output_file
    tmp_dir="$(mktemp -d)"
    missing_target="$tmp_dir/missing-target"
    active_path="$tmp_dir/active-root"
    output_file="$tmp_dir/output.log"

    if bash "$ACTIVE_ROOT_SCRIPT" --target-path "$missing_target" --active-path "$active_path" >"$output_file" 2>&1; then
        test_fail "update-active-deploy-root.sh must fail when target directory is missing"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "Target deploy root does not exist or is not a directory" "$output_file"; then
        test_fail "Missing-target failure should explain the target-path contract"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
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
    test_gitops_sync_workflows_use_shared_script_entrypoint
    test_active_root_workflows_use_shared_script_entrypoint
    test_gitops_sync_script_dry_run_covers_managed_surface
    test_active_root_script_migrates_legacy_directory
    test_active_root_script_requires_existing_target_directory

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
