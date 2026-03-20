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
HOST_AUTOMATION_SCRIPT="$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh"
ENV_RENDER_SCRIPT="$PROJECT_ROOT/scripts/render-moltis-env.sh"
TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/run-tracked-moltis-deploy.sh"
EXPECTED_LOCK_GROUP="prod-remote-ainetic-tech-opt-moltinger"
EXPECTED_ACTIVE_ROOT_SCRIPT="scripts/update-active-deploy-root.sh"
EXPECTED_SYNC_SURFACE_SCRIPT="scripts/gitops-sync-managed-surface.sh"
EXPECTED_HOST_AUTOMATION_SCRIPT="scripts/apply-moltis-host-automation.sh"
EXPECTED_ENV_RENDER_SCRIPT="scripts/render-moltis-env.sh"
EXPECTED_TRACKED_DEPLOY_SCRIPT="scripts/run-tracked-moltis-deploy.sh"

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

test_moltis_env_workflows_use_shared_render_script() {
    test_start "Moltis env rendering should use one shared script entrypoint"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$UAT_WORKFLOW" || ! -f "$ENV_RENDER_SCRIPT" ]]; then
        test_skip "Workflow/script files missing for env rendering entrypoint check"
        return
    fi

    if ! grep -Fq "$EXPECTED_ENV_RENDER_SCRIPT" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml must call $EXPECTED_ENV_RENDER_SCRIPT"
        return
    fi

    if ! grep -Fq "$EXPECTED_ENV_RENDER_SCRIPT" "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml must call $EXPECTED_ENV_RENDER_SCRIPT"
        return
    fi

    if grep -Fq "cat > /tmp/moltis.env << EOF" "$DEPLOY_WORKFLOW" || \
       grep -Fq "cat > /tmp/moltis.env << EOF" "$UAT_WORKFLOW"; then
        test_fail "Workflow YAML should not inline Moltis env rendering logic"
        return
    fi

    test_pass
}

test_tracked_deploy_workflows_use_shared_script_entrypoint() {
    test_start "Tracked Moltis deploy should use one shared control-plane script entrypoint"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$UAT_WORKFLOW" || ! -f "$TRACKED_DEPLOY_SCRIPT" ]]; then
        test_skip "Workflow/script files missing for tracked deploy entrypoint check"
        return
    fi

    if ! grep -Fq "$EXPECTED_TRACKED_DEPLOY_SCRIPT" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml must call $EXPECTED_TRACKED_DEPLOY_SCRIPT"
        return
    fi

    if ! grep -Fq "$EXPECTED_TRACKED_DEPLOY_SCRIPT" "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml must call $EXPECTED_TRACKED_DEPLOY_SCRIPT"
        return
    fi

    if grep -Fq "Prepare writable Moltis runtime config" "$DEPLOY_WORKFLOW" || \
       grep -Fq "Pull new image" "$DEPLOY_WORKFLOW" || \
       grep -Fq "Deploy container" "$DEPLOY_WORKFLOW" || \
       grep -Fq "steps.health.outcome == 'failure'" "$DEPLOY_WORKFLOW" || \
       grep -Fq "Record deployed git SHA (GitOps audit)" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml should not inline tracked Moltis deploy orchestration"
        return
    fi

    if grep -Fq "Validate tracked remote configuration" "$UAT_WORKFLOW" || \
       grep -Fq "Deploy tracked version" "$UAT_WORKFLOW" || \
       grep -Fq "Verify deployment" "$UAT_WORKFLOW" || \
       grep -Fq "Record deployed git SHA (GitOps audit)" "$UAT_WORKFLOW"; then
        test_fail "uat-gate.yml should not inline tracked Moltis deploy orchestration"
        return
    fi

    test_pass
}

test_deploy_workflow_uses_shared_host_automation_script() {
    test_start "Deploy workflow should use a shared host-automation script entrypoint"

    if [[ ! -f "$DEPLOY_WORKFLOW" || ! -f "$HOST_AUTOMATION_SCRIPT" ]]; then
        test_skip "Workflow/script files missing for host-automation entrypoint check"
        return
    fi

    if ! grep -Fq "$EXPECTED_HOST_AUTOMATION_SCRIPT" "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml must call $EXPECTED_HOST_AUTOMATION_SCRIPT"
        return
    fi

    if grep -Fq "Install cron jobs" "$DEPLOY_WORKFLOW" || \
       grep -Fq "Install Moltis health monitor unit from active deploy root" "$DEPLOY_WORKFLOW" || \
       grep -Fq 'rm -f "${{ env.DEPLOY_ACTIVE_PATH }}/scripts/cron.d/moltis-telegram-web-user-monitor"' "$DEPLOY_WORKFLOW"; then
        test_fail "deploy.yml should not inline host-automation mutation logic or delete tracked files from active root"
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

test_render_moltis_env_script_renders_runtime_contract() {
    test_start "Shared Moltis env renderer should emit runtime config and secrets contract"

    if [[ ! -f "$ENV_RENDER_SCRIPT" ]]; then
        test_skip "Missing script file: $ENV_RENDER_SCRIPT"
        return
    fi

    local tmp_dir output_file
    tmp_dir="$(mktemp -d)"
    output_file="$tmp_dir/moltis.env"

    if ! MOLTIS_PASSWORD="secret" \
        GLM_API_KEY="glm-key" \
        OLLAMA_API_KEY="ollama-key" \
        TAVILY_API_KEY="tavily-key" \
        TELEGRAM_BOT_TOKEN="telegram-token" \
        TELEGRAM_ALLOWED_USERS="123,456" \
        TELEGRAM_WEBHOOK_URL="https://example.com/hook" \
        TELEGRAM_WEBHOOK_SECRET="hook-secret" \
        MOLTIS_DOMAIN="moltis.example.com" \
        MOLTIS_RUNTIME_CONFIG_DIR="/srv/runtime-config" \
        bash "$ENV_RENDER_SCRIPT" --output "$output_file" >"$tmp_dir/output.log" 2>&1; then
        test_fail "render-moltis-env.sh failed to render env file"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "MOLTIS_PASSWORD=secret" "$output_file" || \
       ! grep -Fq "GLM_API_KEY=glm-key" "$output_file" || \
       ! grep -Fq "MOLTIS_DOMAIN=moltis.example.com" "$output_file" || \
       ! grep -Fq "MOLTIS_RUNTIME_CONFIG_DIR=/srv/runtime-config" "$output_file"; then
        test_fail "render-moltis-env.sh output is missing required runtime contract keys"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_tracked_deploy_script_dry_run_reports_control_plane_steps() {
    test_start "Shared tracked deploy script dry-run should report the planned control-plane steps"

    if [[ ! -f "$TRACKED_DEPLOY_SCRIPT" ]]; then
        test_skip "Missing script file: $TRACKED_DEPLOY_SCRIPT"
        return
    fi

    local tmp_dir project_root output_file
    tmp_dir="$(mktemp -d)"
    project_root="$tmp_dir/project"
    output_file="$tmp_dir/output.json"

    mkdir -p "$project_root/config" "$project_root/scripts"
    printf 'services: {}\n' > "$project_root/docker-compose.prod.yml"
    printf 'name = "moltis"\n' > "$project_root/config/moltis.toml"
    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/srv/runtime-config\n' > "$project_root/.env"
    : > "$project_root/scripts/prepare-moltis-runtime-config.sh"
    : > "$project_root/scripts/moltis-version.sh"
    : > "$project_root/scripts/deploy.sh"

    if ! bash "$TRACKED_DEPLOY_SCRIPT" \
        --dry-run \
        --json \
        --deploy-path "$project_root" \
        --git-sha deadbeef \
        --git-ref main \
        --workflow-run 123456 \
        --version 1.2.3 >"$output_file" 2>&1; then
        test_fail "run-tracked-moltis-deploy.sh dry-run failed"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq '"status": "dry-run"' "$output_file" || \
       ! grep -Fq '"prepare-runtime-config"' "$output_file" || \
       ! grep -Fq '"align-server-checkout"' "$output_file" || \
       ! grep -Fq '"/srv/runtime-config"' "$output_file"; then
        test_fail "Tracked deploy dry-run output should describe the shared control-plane contract"
        rm -rf "$tmp_dir"
        return
    fi

    rm -rf "$tmp_dir"
    test_pass
}

test_host_automation_script_dry_run_keeps_scheduler_disabled_without_mutating_active_root() {
    test_start "Shared host-automation script should disable the fallback scheduler without mutating active root"

    if [[ ! -f "$HOST_AUTOMATION_SCRIPT" ]]; then
        test_skip "Missing script file: $HOST_AUTOMATION_SCRIPT"
        return
    fi

    local tmp_dir active_root output_file
    tmp_dir="$(mktemp -d)"
    active_root="$tmp_dir/active-root"
    output_file="$tmp_dir/output.log"

    mkdir -p "$active_root/scripts/cron.d" "$active_root/systemd"
    printf 'backup\n' > "$active_root/scripts/cron.d/moltis-backup-verify"
    printf 'fallback\n' > "$active_root/scripts/cron.d/moltis-telegram-web-user-monitor"
    printf '[Unit]\nDescription=health monitor\n' > "$active_root/systemd/moltis-health-monitor.service"

    if ! bash "$HOST_AUTOMATION_SCRIPT" \
        --dry-run \
        --active-root "$active_root" >"$output_file" 2>&1; then
        test_fail "apply-moltis-host-automation.sh dry-run failed"
        rm -rf "$tmp_dir"
        return
    fi

    if ! grep -Fq "/etc/cron.d/moltis-backup-verify" "$output_file" || \
       ! grep -Fq "Skipping disabled fallback scheduler: moltis-telegram-web-user-monitor" "$output_file" || \
       ! grep -Fq "/etc/systemd/system/moltis-health-monitor.service" "$output_file" || \
       ! grep -Fq "systemctl disable --now moltis-telegram-web-user-monitor.timer" "$output_file"; then
        test_fail "Host-automation dry-run should describe cron install, health monitor install, and disabled scheduler cleanup"
        rm -rf "$tmp_dir"
        return
    fi

    if grep -Fq "$active_root/scripts/cron.d/moltis-telegram-web-user-monitor" "$output_file"; then
        test_fail "Host-automation script must not delete the tracked fallback scheduler from active root"
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
    test_moltis_env_workflows_use_shared_render_script
    test_tracked_deploy_workflows_use_shared_script_entrypoint
    test_deploy_workflow_uses_shared_host_automation_script
    test_gitops_sync_script_dry_run_covers_managed_surface
    test_render_moltis_env_script_renders_runtime_contract
    test_tracked_deploy_script_dry_run_reports_control_plane_steps
    test_host_automation_script_dry_run_keeps_scheduler_disabled_without_mutating_active_root
    test_active_root_script_migrates_legacy_directory
    test_active_root_script_requires_existing_target_directory

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
