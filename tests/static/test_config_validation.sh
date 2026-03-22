#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

TOML_CONFIG="$PROJECT_ROOT/config/moltis.toml"
TEST_FIXTURE_CONFIG="$PROJECT_ROOT/tests/fixtures/config/moltis.toml"
COMPOSE_PROD="$PROJECT_ROOT/docker-compose.prod.yml"
COMPOSE_TEST="$PROJECT_ROOT/compose.test.yml"
COMPOSE_CLAWDIY="$PROJECT_ROOT/docker-compose.clawdiy.yml"
DEPLOY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy.yml"
MOLTIS_UPDATE_PROPOSAL_WORKFLOW="$PROJECT_ROOT/.github/workflows/moltis-update-proposal.yml"
CLAWDIY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy-clawdiy.yml"
UAT_GATE_WORKFLOW="$PROJECT_ROOT/.github/workflows/uat-gate.yml"
ROLLBACK_DRILL_WORKFLOW="$PROJECT_ROOT/.github/workflows/rollback-drill.yml"
TEST_WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"
TEST_RUNNER_DOCKERFILE="$PROJECT_ROOT/tests/Dockerfile.runner"
BACKUP_CONFIG="$PROJECT_ROOT/config/backup/backup.conf"
FLEET_POLICY="$PROJECT_ROOT/config/fleet/policy.json"
PREFLIGHT_SCRIPT="$PROJECT_ROOT/scripts/preflight-check.sh"
DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy.sh"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh"
MOLTIS_VERSION_HELPER="$PROJECT_ROOT/scripts/moltis-version.sh"
MOLTIS_VERSION_SCRIPT="$PROJECT_ROOT/scripts/moltis-version.sh"
TELEGRAM_WEBHOOK_MONITOR_SCRIPT="$PROJECT_ROOT/scripts/telegram-webhook-monitor.sh"
TELEGRAM_WEBHOOK_MONITOR_CRON="$PROJECT_ROOT/scripts/cron.d/moltis-telegram-webhook-monitor"
TELEGRAM_USER_MONITOR_CRON="$PROJECT_ROOT/scripts/cron.d/moltis-telegram-user-monitor"
HOST_AUTOMATION_SCRIPT="$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh"
MOLTIS_ENV_RENDER_SCRIPT="$PROJECT_ROOT/scripts/render-moltis-env.sh"
TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/run-tracked-moltis-deploy.sh"
SSH_TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/ssh-run-tracked-moltis-deploy.sh"
CHECKOUT_ALIGN_SCRIPT="$PROJECT_ROOT/scripts/align-server-checkout.sh"
SYNC_SURFACE_SCRIPT="$PROJECT_ROOT/scripts/gitops-sync-managed-surface.sh"

validate_toml() {
    local file_path="$1"
    python3 - "$file_path" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
with path.open('rb') as fh:
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib
    tomllib.load(fh)
PY
}

run_static_config_validation_tests() {
    start_timer

    test_start "static_config_primary_toml_exists"
    if [[ -f "$TOML_CONFIG" ]]; then
        test_pass
    else
        test_fail "Missing config/moltis.toml"
    fi

    test_start "static_config_primary_toml_valid"
    if validate_toml "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary TOML configuration is invalid"
    fi

    test_start "static_config_fixture_toml_valid"
    if validate_toml "$TEST_FIXTURE_CONFIG"; then
        test_pass
    else
        test_fail "Fixture TOML configuration is invalid"
    fi

    test_start "static_compose_test_valid"
    if docker compose -f "$COMPOSE_TEST" config --quiet >/dev/null 2>&1; then
        test_pass
    else
        test_fail "compose.test.yml does not render cleanly"
    fi

    test_start "static_compose_prod_valid"
    if docker compose -f "$COMPOSE_PROD" config --quiet >/dev/null 2>&1; then
        test_pass
    else
        test_fail "docker-compose.prod.yml does not render cleanly"
    fi

    test_start "static_moltis_compose_exposes_repo_as_runtime_visible_server_workspace"
    if rg -q '^    working_dir: /server$' "$COMPOSE_PROD" && \
       rg -q '^\s+- \./:/server:ro$' "$COMPOSE_PROD" && \
       rg -q '^    working_dir: /server$' "$PROJECT_ROOT/docker-compose.yml" && \
       rg -q '^\s+- \./:/server:ro$' "$PROJECT_ROOT/docker-compose.yml"; then
        test_pass
    else
        test_fail "Moltis compose files must mount the tracked checkout as /server and use it as the working directory for live skill visibility"
    fi

    test_start "static_moltis_browser_docker_contract_matches_official_sibling_container_requirements"
    if rg -q 'container_host = "host\.docker\.internal"' "$TOML_CONFIG" && \
       rg -q '^profile_dir = "/tmp/moltis-browser-profile/shared"' "$TOML_CONFIG" && \
       rg -q 'DOCKER_SOCKET_GID:-999' "$COMPOSE_PROD" && \
       rg -q '/tmp/moltis-browser-profile:/tmp/moltis-browser-profile' "$COMPOSE_PROD" && \
       rg -q 'host\.docker\.internal:host-gateway' "$COMPOSE_PROD" && \
       rg -q 'export DOCKER_SOCKET_GID="\$docker_socket_gid"' "$DEPLOY_SCRIPT" && \
       rg -q 'prepare_moltis_browser_profile_dir' "$DEPLOY_SCRIPT" && \
       rg -q 'chmod 0777 "\$CANONICAL_MOLTIS_BROWSER_PROFILE_DIR" "\$CANONICAL_MOLTIS_BROWSER_PROFILE_SHARED_DIR"' "$DEPLOY_SCRIPT" && \
       rg -q 'prepull_moltis_browser_sandbox_image' "$DEPLOY_SCRIPT" && \
       rg -q 'docker pull "\$sandbox_image"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Browser-in-Docker contract must pin a host-visible shared profile_dir, mount it into Moltis, prepare writable permissions, set container_host, inject the live Docker socket GID, pre-pull the sandbox image, and publish host.docker.internal for sibling browser containers"
    fi

    test_start "static_compose_clawdiy_valid"
    if env CLAWDIY_IMAGE="ghcr.io/openclaw/openclaw:2026.3.11" docker compose -f "$COMPOSE_CLAWDIY" config --quiet >/dev/null 2>&1; then
        test_pass
    else
        test_fail "docker-compose.clawdiy.yml does not render cleanly with a valid CLAWDIY_IMAGE"
    fi

    test_start "static_clawdiy_config_pins_codex_default_model"
    if python3 - "$PROJECT_ROOT/config/clawdiy/openclaw.json" <<'PY'
import json, sys
from pathlib import Path
cfg = json.loads(Path(sys.argv[1]).read_text())
primary = cfg.get("agents", {}).get("defaults", {}).get("model", {}).get("primary")
models = cfg.get("agents", {}).get("defaults", {}).get("models", {})
raise SystemExit(0 if primary == "openai-codex/gpt-5.4" and "openai-codex/gpt-5.4" in models else 1)
PY
    then
        test_pass
    else
        test_fail "Tracked Clawdiy config must keep the Codex OAuth / gpt-5.4 baseline as the GitOps default model"
    fi

    test_start "static_config_uses_env_substitution"
    if rg -q '\$\{[A-Z0-9_]+\}' "$TOML_CONFIG" "$COMPOSE_PROD" "$COMPOSE_TEST"; then
        test_pass
    else
        test_fail "Expected environment variable substitution in config files"
    fi

    test_start "static_moltis_version_helper_enforces_tracked_nonlatest_version"
    if [[ -x "$MOLTIS_VERSION_HELPER" ]] && \
       bash "$MOLTIS_VERSION_HELPER" assert-tracked >/dev/null 2>&1 && \
       ! rg -q '\$\{MOLTIS_VERSION:-latest\}|image:\s*ghcr\.io/moltis-org/moltis:latest' "$PROJECT_ROOT/docker-compose.yml" "$COMPOSE_PROD"; then
        test_pass
    else
        test_fail "Moltis version helper must exist, validate compose alignment, and forbid latest as the tracked default"
    fi

    test_start "static_telegram_webhook_monitor_never_falls_back_to_allowed_users"
    if rg -Fq 'TELEGRAM_REQUIRE_TEST_USER="${TELEGRAM_REQUIRE_TEST_USER:-false}"' "$TELEGRAM_WEBHOOK_MONITOR_SCRIPT" && \
       rg -Fq 'TELEGRAM_PROBE_DISABLE_NOTIFICATION="${TELEGRAM_PROBE_DISABLE_NOTIFICATION:-true}"' "$TELEGRAM_WEBHOOK_MONITOR_SCRIPT" && \
       ! rg -Fq 'TELEGRAM_TEST_USER="${TELEGRAM_ALLOWED_USERS%%,*}"' "$TELEGRAM_WEBHOOK_MONITOR_SCRIPT"; then
        test_pass
    else
        test_fail "Webhook monitor must not infer TELEGRAM_TEST_USER from allowlist and should keep probe notification policy explicit"
    fi

    test_start "static_telegram_webhook_cron_defaults_to_passive_probe_mode"
    if rg -q '^TELEGRAM_REQUIRE_WEBHOOK=false$' "$TELEGRAM_WEBHOOK_MONITOR_CRON" && \
       rg -q '^TELEGRAM_REQUIRE_TEST_USER=false$' "$TELEGRAM_WEBHOOK_MONITOR_CRON" && \
       rg -q '^TELEGRAM_PROBE_DISABLE_NOTIFICATION=true$' "$TELEGRAM_WEBHOOK_MONITOR_CRON"; then
        test_pass
    else
        test_fail "Webhook cron defaults must stay polling-friendly and keep active Telegram probe opt-in + quiet"
    fi

    test_start "static_telegram_user_monitor_cron_is_disabled_by_default"
    if rg -q '^# \*/10 .*telegram-user-monitor\.sh' "$TELEGRAM_USER_MONITOR_CRON" && \
       ! rg -q '^\*/10 .*telegram-user-monitor\.sh' "$TELEGRAM_USER_MONITOR_CRON"; then
        test_pass
    else
        test_fail "MTProto user-monitor cron should be opt-in and disabled by default to avoid unsolicited chat noise"
    fi

    test_start "static_config_has_no_hardcoded_secrets"
    if rg -n 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' "$PROJECT_ROOT/config" "$PROJECT_ROOT/tests/fixtures/config" "$COMPOSE_PROD" "$COMPOSE_TEST" >/dev/null 2>&1; then
        test_fail "Detected potential hardcoded secret material"
    else
        test_pass
    fi

    test_start "static_moltis_version_contract_stays_git_tracked_and_pinned"
    if [[ -x "$MOLTIS_VERSION_SCRIPT" ]] && \
       "$MOLTIS_VERSION_SCRIPT" assert-tracked && \
       [[ "$("$MOLTIS_VERSION_SCRIPT" version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z._-]+)?$ ]]; then
        test_pass
    else
        test_fail "Tracked Moltis version must resolve to an explicit GHCR tag without leading v and be validated by scripts/moltis-version.sh"
    fi

    test_start "static_fixture_disables_openai_for_pr_gate"
    if rg -n '^\[providers\.openai\]' -A3 "$TEST_FIXTURE_CONFIG" | rg -q 'enabled = false'; then
        test_pass
    else
        test_fail "Fixture config should disable OpenAI provider"
    fi

    test_start "static_fixture_uses_internal_ollama_service"
    if rg -q 'base_url = "http://ollama:11434"' "$TEST_FIXTURE_CONFIG"; then
        test_pass
    else
        test_fail "Fixture config should target internal ollama service DNS"
    fi

    test_start "static_config_codex_update_uses_container_visible_runtime_paths"
    if rg -Fq 'MOLTIS_CODEX_UPDATE_STATE_FILE = "/home/moltis/.moltis/codex-update/state.json"' "$TOML_CONFIG" && \
       rg -Fq 'MOLTIS_CODEX_UPDATE_STATE_SCRIPT = "/server/scripts/moltis-codex-update-state.sh"' "$TOML_CONFIG" && \
       rg -Fq 'MOLTIS_CODEX_UPDATE_PROFILE_SCRIPT = "/server/scripts/moltis-codex-update-profile.sh"' "$TOML_CONFIG" && \
       rg -Fq 'MOLTIS_CODEX_UPDATE_AUDIT_DIR = "/home/moltis/.moltis/codex-update/audit"' "$TOML_CONFIG" && \
       rg -Fq 'MOLTIS_CODEX_UPDATE_PROFILE_SCHEMA = "/server/specs/023-full-moltis-codex-update-skill/contracts/project-profile.schema.json"' "$TOML_CONFIG" && \
       rg -Fq 'MOLTIS_CODEX_UPDATE_TELEGRAM_SEND_SCRIPT = "/server/scripts/telegram-bot-send.sh"' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis config must use container-visible /server paths for codex-update skill code and ~/.moltis paths for writable state"
    fi

    test_start "static_config_pins_memory_provider_and_repo_watch_dirs"
    if rg -Fq 'provider = "ollama"' "$TOML_CONFIG" && \
       rg -Fq 'base_url = "http://ollama:11434/v1"' "$TOML_CONFIG" && \
       rg -Fq 'model = "nomic-embed-text"' "$TOML_CONFIG" && \
       rg -Fq '"~/.moltis/memory"' "$TOML_CONFIG" && \
       rg -Fq '"/server/knowledge"' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis config must pin the memory embeddings backend and repo-visible watch_dirs instead of relying on auto-detect"
    fi

    test_start "static_codex_cli_update_delivery_script_is_executable"
    if [[ -x "$PROJECT_ROOT/scripts/codex-cli-update-delivery.sh" ]]; then
        test_pass
    else
        test_fail "scripts/codex-cli-update-delivery.sh must be executable to stay GitOps-clean after managed surface sync applies executable bits"
    fi

    test_start "static_deploy_audit_markers_stored_in_ignored_data_dir"
    if rg -q 'run-tracked-moltis-deploy\.sh' "$DEPLOY_WORKFLOW" && \
       rg -q 'data/\.deployed-sha' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -q 'data/\.deployment-info' "$TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Deploy workflow should delegate audit markers to the tracked deploy script and keep them under data/"
    fi

    test_start "static_deploy_audit_markers_not_written_to_repo_root"
    if rg -n '> \\.deployed-sha|cat > \\.deployment-info|cat \\.deployed-sha' "$DEPLOY_WORKFLOW" >/dev/null 2>&1 || \
       rg -n '> \\.deployed-sha|cat > \\.deployment-info|cat \\.deployed-sha' "$TRACKED_DEPLOY_SCRIPT" >/dev/null 2>&1; then
        test_fail "Deploy control-plane still writes audit markers to repo root"
    else
        test_pass
    fi

    test_start "static_production_workflows_use_shared_checkout_align_entrypoint"
    if rg -q 'align-server-checkout\.sh' "$DEPLOY_WORKFLOW" && \
       rg -q 'align-server-checkout\.sh' "$UAT_GATE_WORKFLOW" && \
       [[ -f "$CHECKOUT_ALIGN_SCRIPT" ]] && \
       rg -Fq 'emit_remote_script | ssh "$SSH_TARGET" '"'"'bash -seu'"'"'' "$CHECKOUT_ALIGN_SCRIPT" && \
       rg -q 'git clean -fd >&2' "$CHECKOUT_ALIGN_SCRIPT" && \
       ! rg -q 'git fetch --depth=1 origin "\$\{\{ github\.ref_name \}\}"' "$DEPLOY_WORKFLOW" && \
       ! rg -q 'git reset --hard "\$\{\{ github\.sha \}\}"' "$DEPLOY_WORKFLOW" && \
       ! rg -q 'git clean -fd$' "$UAT_GATE_WORKFLOW"; then
        test_pass
    else
        test_fail "Deploy and UAT workflows should align remote checkout through the shared checkout-align script before GitOps sync"
    fi

    test_start "static_deploy_server_git_checkout_aligned_after_success"
    if rg -q 'run-tracked-moltis-deploy\.sh' "$DEPLOY_WORKFLOW" && \
       rg -q 'git fetch --depth=1 origin "\$GIT_REF" >&2' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -q 'git reset --hard "\$GIT_SHA" >&2' "$TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Deploy control-plane should align the server checkout after success inside the shared tracked deploy script"
    fi

    test_start "static_deploy_workflows_use_shared_moltis_env_renderer"
    if rg -q 'render-moltis-env\.sh' "$DEPLOY_WORKFLOW" && \
       rg -q 'render-moltis-env\.sh' "$UAT_GATE_WORKFLOW" && \
       ! rg -q 'cat > /tmp/moltis\.env << EOF' "$DEPLOY_WORKFLOW" && \
       ! rg -q 'cat > /tmp/moltis\.env << EOF' "$UAT_GATE_WORKFLOW" && \
       [[ -f "$MOLTIS_ENV_RENDER_SCRIPT" ]]; then
        test_pass
    else
        test_fail "Deploy and UAT workflows should use the shared Moltis env renderer instead of inline heredocs"
    fi

    test_start "static_deploy_workflows_pin_canonical_moltis_runtime_config_dir"
    if rg -Fq 'MOLTIS_RUNTIME_CONFIG_DIR: /opt/moltinger-state/config-runtime' "$DEPLOY_WORKFLOW" && \
       rg -Fq 'MOLTIS_RUNTIME_CONFIG_DIR: /opt/moltinger-state/config-runtime' "$UAT_GATE_WORKFLOW" && \
       ! rg -Fq "vars.MOLTIS_RUNTIME_CONFIG_DIR" "$DEPLOY_WORKFLOW" && \
       ! rg -Fq "vars.MOLTIS_RUNTIME_CONFIG_DIR" "$UAT_GATE_WORKFLOW"; then
        test_pass
    else
        test_fail "Deploy and UAT workflows must pin the canonical Moltis runtime config dir instead of accepting mutable vars overrides"
    fi

    test_start "static_deploy_workflows_use_shared_tracked_deploy_entrypoint"
    if rg -q 'ssh-run-tracked-moltis-deploy\.sh' "$DEPLOY_WORKFLOW" && \
       rg -q 'ssh-run-tracked-moltis-deploy\.sh' "$UAT_GATE_WORKFLOW" && \
       [[ -f "$SSH_TRACKED_DEPLOY_SCRIPT" ]] && \
       rg -q 'run-tracked-moltis-deploy\.sh' "$SSH_TRACKED_DEPLOY_SCRIPT" && \
       ! rg -q 'Prepare writable Moltis runtime config' "$DEPLOY_WORKFLOW" && \
       ! rg -q 'Deploy tracked version' "$UAT_GATE_WORKFLOW" && \
       [[ -f "$TRACKED_DEPLOY_SCRIPT" ]]; then
        test_pass
    else
        test_fail "Deploy and UAT workflows should delegate tracked Moltis deploy orchestration to the shared script entrypoint"
    fi

    test_start "static_tracked_deploy_workflows_pass_remote_args_without_inline_shell_strings"
    if rg -q 'ssh-run-tracked-moltis-deploy\.sh' "$DEPLOY_WORKFLOW" && \
       rg -q 'ssh-run-tracked-moltis-deploy\.sh' "$UAT_GATE_WORKFLOW" && \
       [[ -f "$SSH_TRACKED_DEPLOY_SCRIPT" ]] && \
       rg -Fq 'emit_remote_script | ssh "$SSH_TARGET" '"'"'bash -seu'"'"'' "$SSH_TRACKED_DEPLOY_SCRIPT" && \
       ! rg -Fq 'REMOTE_CMD=' "$DEPLOY_WORKFLOW" && \
       ! rg -Fq 'REMOTE_CMD=' "$UAT_GATE_WORKFLOW" && \
       ! rg -Fq 'ssh "$SSH_TARGET" bash -s -- \' "$SSH_TRACKED_DEPLOY_SCRIPT" && \
       ! rg -Fq '"$REMOTE_CMD"' "$SSH_TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Deploy and UAT workflows must pass tracked deploy arguments via a constant remote command plus stdin-delivered script instead of inline remote command strings"
    fi

    test_start "static_tracked_deploy_script_treats_env_file_as_data"
    if [[ -f "$TRACKED_DEPLOY_SCRIPT" ]] && \
       ! rg -Fq 'source "$env_file"' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -q 'read_env_file_value' "$TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Tracked deploy script must not source .env as shell code"
    fi

    test_start "static_deploy_workflow_parses_tracked_deploy_json_contract"
    if rg -Fq "jq -r '.details.health // empty'" "$DEPLOY_WORKFLOW" && \
       rg -Fq "jq -r '.details.rollback_verified // false'" "$DEPLOY_WORKFLOW" && \
       rg -Fq "jq -r '.status // empty'" "$UAT_GATE_WORKFLOW"; then
        test_pass
    else
        test_fail "Workflows must stay aligned with the tracked deploy JSON contract they parse"
    fi

    test_start "static_tracked_deploy_propagates_ci_context_for_noninteractive_guarded_deploy"
    if [[ -f "$TRACKED_DEPLOY_SCRIPT" ]] && \
       rg -Fq 'GITHUB_ACTIONS="${GITHUB_ACTIONS:-true}"' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -Fq 'GITHUB_RUN_ID="${GITHUB_RUN_ID:-$WORKFLOW_RUN}"' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -Fq 'GITOPS_CONFIRM_SKIP=true' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -Fq '"$DEPLOY_PATH/scripts/deploy.sh" --json moltis deploy' "$TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Tracked deploy script must propagate CI context and skip interactive GitOps confirmation when invoking deploy.sh over remote SSH orchestration"
    fi

    test_start "static_tracked_deploy_detects_missing_json_contract_from_deploy_sh"
    if [[ -f "$TRACKED_DEPLOY_SCRIPT" ]] && \
       rg -Fq "deploy.sh exited with code \$DEPLOY_EXIT before returning JSON" "$TRACKED_DEPLOY_SCRIPT" && \
       rg -Fq "jq empty >/dev/null 2>&1 <<<\"\$DEPLOY_OUTPUT\"" "$TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Tracked deploy script must fail with an explicit error when deploy.sh exits before returning JSON"
    fi

    test_start "static_deploy_script_cleans_legacy_container_name_conflicts_before_rollout"
    if [[ -f "$DEPLOY_SCRIPT" ]] && \
       rg -Fq 'resolve_container_name_conflicts' "$DEPLOY_SCRIPT" && \
       rg -Fq 'expected_project="$(basename "$PROJECT_ROOT")"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'docker rm -f "$container_id"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'echo "ollama-fallback"' "$DEPLOY_SCRIPT" && \
       ! rg -Fq 'echo "prometheus"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "deploy.sh must clean conflicting legacy containers for Moltis managed services only (without touching monitoring-stack container names)"
    fi

    test_start "static_deploy_script_scopes_moltis_rollout_to_core_and_sidecars"
    if [[ -f "$DEPLOY_SCRIPT" ]] && \
       rg -Fq 'TARGET_AUXILIARY_SERVICES=("watchtower" "ollama")' "$DEPLOY_SCRIPT" && \
       rg -Fq 'deploy_args+=(--force-recreate)' "$DEPLOY_SCRIPT" && \
       rg -Fq 'compose_cmd normal "${deploy_args[@]}" "${deploy_services[@]}"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Moltis deploy path must target only moltis + required sidecars and force-recreate the runtime so config changes take effect immediately"
    fi

    test_start "static_deploy_syncs_tracked_knowledge_into_official_runtime_memory_path"
    if [[ -f "$DEPLOY_SCRIPT" ]] && \
       [[ -f "$PROJECT_ROOT/scripts/sync-moltis-project-knowledge.sh" ]] && \
       rg -Fq 'sync_moltis_project_knowledge()' "$DEPLOY_SCRIPT" && \
       rg -Fq '/home/moltis/.moltis/memory/project-knowledge.md' "$DEPLOY_SCRIPT" && \
       rg -Fq -- '--knowledge-root "$PROJECT_ROOT/knowledge"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'This file is generated from tracked repository knowledge' "$PROJECT_ROOT/scripts/sync-moltis-project-knowledge.sh"; then
        test_pass
    else
        test_fail "Deploy contract must mirror tracked knowledge into the official ~/.moltis/memory path instead of relying only on optional watch_dirs behavior"
    fi

    test_start "static_deploy_workflow_uses_shared_host_automation_entrypoint"
    if rg -q 'apply-moltis-host-automation\.sh' "$DEPLOY_WORKFLOW" && \
       ! rg -q 'Install cron jobs' "$DEPLOY_WORKFLOW" && \
       ! rg -q 'Install Moltis health monitor unit from active deploy root' "$DEPLOY_WORKFLOW" && \
       ! grep -Fq '${{ env.DEPLOY_ACTIVE_PATH }}/scripts/cron.d/moltis-telegram-web-user-monitor' "$DEPLOY_WORKFLOW" && \
       [[ -f "$HOST_AUTOMATION_SCRIPT" ]]; then
        test_pass
    else
        test_fail "Deploy workflow should delegate host automation to the shared script entrypoint and avoid mutating tracked files under active root"
    fi

    test_start "static_host_automation_script_converges_managed_cron_and_systemd_surface"
    if [[ -f "$HOST_AUTOMATION_SCRIPT" ]] && \
       rg -q 'Removing stale managed cron job' "$HOST_AUTOMATION_SCRIPT" && \
       rg -q 'Removing stale managed systemd unit' "$HOST_AUTOMATION_SCRIPT" && \
       rg -q 'Installing systemd unit:' "$HOST_AUTOMATION_SCRIPT" && \
       rg -q 'systemctl daemon-reload' "$HOST_AUTOMATION_SCRIPT"; then
        test_pass
    else
        test_fail "Host automation should converge managed cron/systemd artifacts instead of only appending files"
    fi

    test_start "static_gitops_sync_managed_surface_skips_hidden_top_level_entries"
    if [[ -f "$SYNC_SURFACE_SCRIPT" ]] && \
       rg -Fq "find \"\$local_dir\" -mindepth 1 -maxdepth 1 ! -name '.*' -print0" "$SYNC_SURFACE_SCRIPT"; then
        test_pass
    else
        test_fail "Managed-surface sync should ignore hidden top-level entries to avoid copying accidental local artifacts"
    fi

    test_start "static_deploy_pending_sync_is_not_treated_as_hard_drift"
    if rg -q 'Pending Sync' "$DEPLOY_WORKFLOW" && \
       rg -q 'Hard block applies only to dirty server worktree' "$DEPLOY_WORKFLOW"; then
        test_pass
    else
        test_fail "Deploy workflow should distinguish pending sync from dirty worktree drift"
    fi

    test_start "static_deploy_compliance_checks_prod_compose_hash"
    if rg -Fq 'compare_files "docker-compose.prod.yml"' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "GitOps compliance must compare docker-compose.prod.yml as part of the deploy-managed surface"
    fi

    test_start "static_deploy_supports_gitops_checkout_repair_for_managed_drift"
    if rg -q 'repair_server_checkout:' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'gitops-repair-managed-checkout\.sh' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'gitops-drift' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh"; then
        test_pass
    else
        test_fail "Deploy workflow must offer an auditable checkout repair path for deploy-managed server drift"
    fi

    test_start "static_deploy_checkout_repair_avoids_inline_ssh_heredoc_parser_hazards"
    if rg -q 'gitops-repair-managed-checkout\.sh' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       ! rg -Fq "ssh \${{ env.SSH_USER }}@\${{ env.SSH_HOST }} <<'EOF'" "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow must not embed the managed checkout repair as an inline SSH heredoc inside the run block"
    fi

    test_start "static_deploy_checkout_repair_keeps_snapshot_stdout_clean"
    if rg -q 'git fetch --depth=1 origin "\$TARGET_REF" >&2' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh" && \
       rg -q 'git checkout --force "\$TARGET_REF" >&2' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh" && \
       rg -q 'git reset --hard "\$TARGET_SHA" >&2' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh"; then
        test_pass
    else
        test_fail "Managed checkout repair must redirect git progress to stderr so stdout stays reserved for the drift snapshot path"
    fi

    test_start "static_deploy_uses_tracked_moltis_version_and_blocks_feature_prod_deploys"
    if rg -q 'scripts/moltis-version\.sh version' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       ! rg -q "default: 'latest'" "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       ! rg -q ' - staging' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       ! rg -q '^[[:space:]]+version:[[:space:]]*$' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'supports production target only' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'Production deploys must run from main' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'tag must point to current origin/main HEAD' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow must resolve tracked Moltis version, remove ad-hoc version input, forbid staging bypass, and block non-main tag deploys"
    fi

    test_start "static_deploy_blocks_tracked_version_regression_against_running_baseline"
    if rg -q 'Prevent tracked version regressions against running production baseline' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'Tracked Moltis version regression detected' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'sort -V' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow must block tracked version regressions when running production Moltis version is newer"
    fi

    test_start "static_deploy_surfaces_post_upgrade_protocol_skew_as_operator_signal"
    if rg -q 'Check post-upgrade web protocol skew' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'stale browser tabs' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'not a rollback trigger' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q '## Post-upgrade stale web client' "$PROJECT_ROOT/docs/CLEAN-DEPLOY-TELEGRAM-WEB-USER-MONITOR.md"; then
        test_pass
    else
        test_fail "Deploy verification and runbook must classify post-upgrade protocol skew as an operator signal before rollback"
    fi

    test_start "static_moltis_workflow_validates_restore_readiness"
    if rg -q 'Validate Moltis restore readiness' "$DEPLOY_WORKFLOW" && \
       rg -q 'compose-main' "$DEPLOY_WORKFLOW" && \
       rg -q 'data/moltis/audit/restore-checks' "$DEPLOY_WORKFLOW" && \
       rg -q 'has_env' "$DEPLOY_WORKFLOW"; then
        test_pass
    else
        test_fail "Deploy workflow must enforce a restore-readiness gate for the fresh Moltis pre-update backup"
    fi

    test_start "static_backup_script_captures_runtime_restore_payload"
    if rg -q 'RUNTIME_ENV_FILE' "$BACKUP_SCRIPT" && \
       rg -q 'docker-compose.prod.yml' "$BACKUP_SCRIPT" && \
       rg -q 'restore-check' "$BACKUP_SCRIPT" && \
       rg -q 'restore_readiness' "$BACKUP_SCRIPT"; then
        test_pass
    else
        test_fail "Backup script must archive Moltis runtime files and expose restore-check readiness validation"
    fi

    test_start "static_deploy_script_enforces_moltis_backup_safe_rollout"
    if rg -q 'restore-check "\$backup_path"' "$DEPLOY_SCRIPT" && \
       rg -q 'data/moltis/\.last-moltis-restore-check' "$DEPLOY_SCRIPT" && \
       rg -q 'data/moltis/audit/rollback-evidence' "$DEPLOY_SCRIPT" && \
       rg -q 'pre_deploy_\*\.tar\.gz' "$DEPLOY_SCRIPT" && \
       rg -q 'latest_file_under "\$PROJECT_ROOT/data/moltis/audit/restore-checks"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "deploy.sh must require restore-check before Moltis deploy and record rollback evidence for rollback-safe updates"
    fi

    test_start "static_deploy_workflow_tracks_git_managed_rollback_pointers"
    if rg -q 'data/moltis/\.last-deployed-image' "$DEPLOY_WORKFLOW" && \
       rg -q 'data/moltis/\.last-moltis-backup' "$DEPLOY_WORKFLOW" && \
       rg -q 'data/moltis/\.last-moltis-restore-check' "$DEPLOY_WORKFLOW" && \
       rg -q 'migrate legacy Moltis runtime pointers' "$DEPLOY_WORKFLOW" && \
       rg -q 'deploy\.sh --json moltis rollback' "$DEPLOY_WORKFLOW"; then
        test_pass
    else
        test_fail "Deploy workflow must keep Moltis rollback pointers under data/moltis, migrate legacy root markers, and route rollback through deploy.sh"
    fi

    test_start "static_uat_gate_uses_tracked_git_version_and_backup_safe_deploy"
    if ! rg -q 'target_version' "$UAT_GATE_WORKFLOW" && \
       rg -q 'scripts/moltis-version\.sh version' "$UAT_GATE_WORKFLOW" && \
       rg -q 'run-tracked-moltis-deploy\.sh' "$UAT_GATE_WORKFLOW" && \
       rg -q 'deploy\.sh --json moltis deploy' "$TRACKED_DEPLOY_SCRIPT" && \
       ! rg -q 'docker pull ghcr\.io/moltis-org/moltis:\$VERSION' "$UAT_GATE_WORKFLOW" && \
       ! rg -q 'MOLTIS_VERSION="\$VERSION"' "$UAT_GATE_WORKFLOW"; then
        test_pass
    else
        test_fail "UAT gate must derive the Moltis version from git and deploy only through the shared tracked deploy entrypoint backed by deploy.sh"
    fi

    test_start "static_production_workflows_share_remote_lock_group"
    if rg -q 'group: prod-remote-ainetic-tech-opt-moltinger' "$DEPLOY_WORKFLOW" && \
       rg -q 'group: prod-remote-ainetic-tech-opt-moltinger' "$CLAWDIY_WORKFLOW" && \
       rg -q 'group: prod-remote-ainetic-tech-opt-moltinger' "$UAT_GATE_WORKFLOW"; then
        test_pass
    else
        test_fail "Production-mutating workflows must share one remote lock group to prevent parallel deploy collisions"
    fi

    test_start "static_deploy_compliance_checks_prod_compose_hash"
    if rg -Fq 'compare_files "docker-compose.prod.yml"' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "GitOps compliance must compare docker-compose.prod.yml as part of the deploy-managed surface"
    fi

    test_start "static_deploy_supports_gitops_checkout_repair_for_managed_drift"
    if rg -q 'repair_server_checkout:' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'gitops-repair-managed-checkout\.sh' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'gitops-drift' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh"; then
        test_pass
    else
        test_fail "Deploy workflow must offer an auditable checkout repair path for deploy-managed server drift"
    fi

    test_start "static_deploy_checkout_repair_avoids_inline_ssh_heredoc_parser_hazards"
    if rg -q 'gitops-repair-managed-checkout\.sh' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       ! rg -Fq "ssh \${{ env.SSH_USER }}@\${{ env.SSH_HOST }} <<'EOF'" "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow must not embed the managed checkout repair as an inline SSH heredoc inside the run block"
    fi

    test_start "static_deploy_checkout_repair_keeps_snapshot_stdout_clean"
    if rg -q 'git fetch --depth=1 origin "\$TARGET_REF" >&2' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh" && \
       rg -q 'git checkout --force "\$TARGET_REF" >&2' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh" && \
       rg -q 'git reset --hard "\$TARGET_SHA" >&2' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh"; then
        test_pass
    else
        test_fail "Managed checkout repair must redirect git progress to stderr so stdout stays reserved for the drift snapshot path"
    fi

    test_start "static_deploy_uses_tracked_moltis_version_and_blocks_feature_prod_deploys"
    if rg -q 'scripts/moltis-version\.sh version' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'Production deploys must run from main' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'tag must point to current origin/main HEAD' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'Production tag deploy version must match tracked Moltis version' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow must resolve the tracked Moltis version, block feature-branch deploys, and reject tags that do not point to current main HEAD"
    fi

    test_start "static_deploy_surfaces_post_upgrade_protocol_skew_as_operator_signal"
    if rg -q 'Check post-upgrade web protocol skew' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'stale browser tabs' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'not a rollback trigger' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q '## Post-upgrade stale web client' "$PROJECT_ROOT/docs/CLEAN-DEPLOY-TELEGRAM-WEB-USER-MONITOR.md"; then
        test_pass
    else
        test_fail "Deploy verification and runbook must classify post-upgrade protocol skew as an operator signal before rollback"
    fi

    test_start "static_moltis_update_proposal_workflow_is_safe_and_non_deploying"
    if [[ -f "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" ]] && \
       rg -q '^name: Moltis Update Proposal$' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q '^  schedule:$' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q '^  workflow_dispatch:$' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q '^  contents: write$' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q '^  pull-requests: write$' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q 'group: moltis-update-proposal' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q 'scripts/moltis-version\.sh version' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q 'gh api repos/moltis-org/moltis/releases/latest' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q 'docker manifest inspect "ghcr\.io/moltis-org/moltis:' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -q 'gh pr create --base main' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       ! rg -q 'gh workflow run "Deploy Moltis"|deploy\.sh --json moltis deploy|docker compose -f docker-compose\.prod\.yml up -d moltis' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW"; then
        test_pass
    else
        test_fail "Moltis update proposal workflow must stay isolated (schedule/dispatch PR-only flow) and must not perform direct deploy actions"
    fi

    test_start "static_moltis_update_proposal_perl_update_is_unambiguous_for_zero_prefixed_versions"
    if rg -Fq '#\${1}${CANDIDATE_VERSION}\${2}#g' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       ! rg -Fq '#\\1${CANDIDATE_VERSION}\\2#g' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW"; then
        test_pass
    else
        test_fail "Moltis update proposal workflow must use braced perl backreferences so 0.x.y candidate versions do not collapse replacement captures"
    fi

    test_start "static_moltis_update_proposal_falls_back_to_compare_url_when_pr_create_is_forbidden"
    if rg -Fq 'not permitted to create or approve pull requests' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'manual_compare_url' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'compare/main...${BRANCH}?expand=1' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'supported manual compare URL approval path' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW"; then
        test_pass
    else
        test_fail "Moltis update proposal workflow must fall back to a compare URL when GitHub token cannot create PRs"
    fi

    test_start "static_version_update_docs_fix_manual_compare_url_contract"
    if rg -Fq 'manual_compare_url' "$PROJECT_ROOT/docs/version-update.md" && \
       rg -Fq 'supported permanent contract' "$PROJECT_ROOT/docs/version-update.md" && \
       rg -Fq 'not a failure state' "$PROJECT_ROOT/docs/version-update.md" && \
       rg -Fq 'compare URL' "$PROJECT_ROOT/docs/version-update.md"; then
        test_pass
    else
        test_fail "Version update docs must explicitly treat manual compare URL mode as a supported non-failure contract"
    fi

    test_start "static_moltis_update_proposal_email_action_uses_node24_compatible_major"
    if rg -Fq 'uses: dawidd6/action-send-mail@v16' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       ! rg -Fq 'uses: dawidd6/action-send-mail@v3' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW"; then
        test_pass
    else
        test_fail "Moltis update proposal workflow must use a Node24-compatible action-send-mail major to avoid Node20 deprecation failures"
    fi

    test_start "static_moltis_update_proposal_supports_optional_telegram_notification"
    if rg -Fq 'send_telegram:' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'Evaluate Telegram prerequisites' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'Send Telegram notification (optional)' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'MOLTIS_UPDATE_NOTIFY_TELEGRAM_CHAT_ID' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW" && \
       rg -Fq 'scripts/telegram-bot-send.sh' "$MOLTIS_UPDATE_PROPOSAL_WORKFLOW"; then
        test_pass
    else
        test_fail "Moltis update proposal workflow must support optional Telegram notification via dedicated chat-id secret"
    fi

    test_start "static_version_update_docs_list_optional_telegram_delivery_secrets"
    if rg -Fq 'Optional Telegram delivery secrets for proposal workflow' "$PROJECT_ROOT/docs/version-update.md" && \
       rg -Fq 'TELEGRAM_BOT_TOKEN' "$PROJECT_ROOT/docs/version-update.md" && \
       rg -Fq 'MOLTIS_UPDATE_NOTIFY_TELEGRAM_CHAT_ID' "$PROJECT_ROOT/docs/version-update.md"; then
        test_pass
    else
        test_fail "Version update docs must list optional Telegram delivery secrets for proposal workflow"
    fi

    test_start "static_ci_runtime_installs_sqlite3_for_codex_session_path_repair_suite"
    if rg -q 'Install OS dependencies' "$TEST_WORKFLOW" && \
       rg -q 'apt-get install -y -qq jq sqlite3' "$TEST_WORKFLOW" && \
       rg -q 'apt-get install -y --no-install-recommends .*sqlite3' "$TEST_RUNNER_DOCKERFILE"; then
        test_pass
    else
        test_fail "CI host and test-runner container must both provide sqlite3 because pr lane executes component_codex_session_path_repair inside test-runner"
    fi

    test_start "static_clawdiy_workflow_exists"
    if [[ -f "$CLAWDIY_WORKFLOW" ]]; then
        test_pass
    else
        test_fail "Missing .github/workflows/deploy-clawdiy.yml"
    fi

    test_start "static_clawdiy_compose_extends_startup_health_grace_for_official_openclaw_warmup"
    if rg -q 'start_period: 180s' "$COMPOSE_CLAWDIY" && \
       rg -q 'retries: 5' "$COMPOSE_CLAWDIY"; then
        test_pass
    else
        test_fail "Clawdiy compose healthcheck must allow enough startup grace for official OpenClaw Docker warmup"
    fi

    test_start "static_clawdiy_deploy_wait_tolerates_transient_unhealthy_during_startup"
    if rg -q 'temporarily unhealthy during startup; continuing to wait until timeout' "$DEPLOY_SCRIPT" && \
       rg -q 'health endpoint is already serving HTTP 200 while Docker health is still catching up' "$DEPLOY_SCRIPT" && \
       rg -q 'CLAWDIY_HEALTH_CHECK_TIMEOUT' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Clawdiy deploy logic must tolerate transient startup unhealthy states until the overall timeout expires"
    fi

    test_start "static_clawdiy_workflow_uses_targeted_preflight_and_deploy"
    if rg -q 'preflight-check\.sh --ci --target clawdiy' "$CLAWDIY_WORKFLOW" && \
       rg -q 'deploy\.sh --json clawdiy deploy' "$CLAWDIY_WORKFLOW" && \
       rg -q 'deploy\.sh --json clawdiy rollback' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must use target-aware preflight and deploy/rollback entrypoints"
    fi

    test_start "static_clawdiy_workflow_propagates_remote_ci_context"
    if rg -q 'export GITHUB_ACTIONS=true' "$CLAWDIY_WORKFLOW" && \
       rg -q 'export GITHUB_RUN_ID="\$\{\{ github\.run_id \}\}"' "$CLAWDIY_WORKFLOW" && \
       rg -q 'deploy_rc=0' "$CLAWDIY_WORKFLOW" && \
       rg -q 'missing_result' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must propagate CI context to remote deploy.sh and surface JSON failure output"
    fi

    test_start "static_clawdiy_workflow_bootstraps_fleet_network"
    if rg -q 'Bootstrap Clawdiy fleet network' "$CLAWDIY_WORKFLOW" && \
       rg -q 'docker network create \$\{\{ env\.FLEET_INTERNAL_NETWORK \}\}' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must bootstrap fleet-internal through CI instead of requiring manual server setup"
    fi

    test_start "static_clawdiy_workflow_migrates_legacy_root_markers_before_gitops_check"
    if rg -q 'Migrate legacy Clawdiy deploy markers' "$CLAWDIY_WORKFLOW" && \
       rg -q 'mv \.last-clawdiy-backup data/clawdiy/\.last-backup' "$CLAWDIY_WORKFLOW" && \
       rg -q 'mv \.last-deployed-clawdiy-image data/clawdiy/\.last-deployed-image' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must migrate legacy repo-root marker files before enforcing the clean-worktree GitOps gate"
    fi

    test_start "static_clawdiy_workflow_supports_gitops_checkout_repair_for_clawdiy_surface"
    if rg -q 'repair_server_checkout:' "$CLAWDIY_WORKFLOW" && \
       rg -q 'gitops-repair-managed-checkout\.sh' "$CLAWDIY_WORKFLOW" && \
       rg -q 'Dirty path is outside Clawdiy-managed surface' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must offer an auditable checkout repair path limited to the Clawdiy-managed surface"
    fi

    test_start "static_clawdiy_workflow_syncs_backup_config_dependencies"
    if rg -q '\$\{\{ env\.DEPLOY_PATH \}\}/config/backup' "$CLAWDIY_WORKFLOW" && \
       rg -q 'scp -r config/backup/\*' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must sync config/backup because deploy.sh sources backup-moltis-enhanced.sh and backup.conf during rollout"
    fi

    test_start "static_clawdiy_workflow_uses_dedicated_env_path"
    if rg -q 'CLAWDIY_ENV_PATH: /opt/moltinger/clawdiy/\.env' "$CLAWDIY_WORKFLOW" && \
       ! rg -q '/opt/moltinger/\.env[^[:alnum:]_]' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must keep a dedicated env path separate from /opt/moltinger/.env"
    fi

    test_start "static_clawdiy_compose_uses_explicit_bind_syntax_for_runtime_paths"
    if rg -q 'type: bind' "$COMPOSE_CLAWDIY" && \
       rg -q 'source: \./data/clawdiy/runtime' "$COMPOSE_CLAWDIY" && \
       rg -q 'target: /home/node/\.openclaw' "$COMPOSE_CLAWDIY" && \
       rg -q 'source: \./config/fleet' "$COMPOSE_CLAWDIY" && \
       rg -q 'target: /home/node/\.openclaw/registry' "$COMPOSE_CLAWDIY" && \
       ! rg -q 'target: /home/node/\.openclaw/openclaw\.json' "$COMPOSE_CLAWDIY"; then
        test_pass
    else
        test_fail "Clawdiy compose must use explicit bind syntax for writable runtime home and read-only registry mounts so official OpenClaw wizards can persist config and auth artifacts"
    fi

    test_start "static_clawdiy_deploy_script_stores_runtime_markers_under_ignored_data_dir"
    if rg -q 'TARGET_LAST_IMAGE_FILE="\$PROJECT_ROOT/data/clawdiy/\.last-deployed-image"' "$DEPLOY_SCRIPT" && \
       rg -q 'TARGET_LAST_BACKUP_FILE="\$PROJECT_ROOT/data/clawdiy/\.last-backup"' "$DEPLOY_SCRIPT" && \
       ! rg -q 'TARGET_LAST_IMAGE_FILE="\$PROJECT_ROOT/\.last-deployed-clawdiy-image"|TARGET_LAST_BACKUP_FILE="\$PROJECT_ROOT/\.last-clawdiy-backup"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Clawdiy deploy script must keep last-image and backup markers under ignored data/clawdiy state"
    fi

    test_start "static_clawdiy_deploy_script_normalizes_runtime_state_ownership"
    if rg -q 'CLAWDIY_RUNTIME_UID="\$\{CLAWDIY_RUNTIME_UID:-1000\}"' "$DEPLOY_SCRIPT" && \
       rg -q 'CLAWDIY_RUNTIME_GID="\$\{CLAWDIY_RUNTIME_GID:-1000\}"' "$DEPLOY_SCRIPT" && \
       rg -q 'Skipping Clawdiy runtime ownership normalization because deploy\.sh is not running as root' "$DEPLOY_SCRIPT" && \
       rg -q '\$PROJECT_ROOT/data/clawdiy/runtime' "$DEPLOY_SCRIPT" && \
       rg -q 'chown -R "\$\{CLAWDIY_RUNTIME_UID\}:\$\{CLAWDIY_RUNTIME_GID\}" "\$path"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Clawdiy deploy script must normalize runtime, state, workspace, and audit ownership for the node runtime user during server-side rollout"
    fi

    test_start "static_clawdiy_smoke_avoids_reserved_jq_variable_names"
    if rg -q 'local label_key="\$2"' "$PROJECT_ROOT/scripts/clawdiy-smoke.sh" && \
       rg -q 'Labels\[\$label_key\]' "$PROJECT_ROOT/scripts/clawdiy-smoke.sh" && \
       ! rg -q 'local label="\$2"' "$PROJECT_ROOT/scripts/clawdiy-smoke.sh" && \
       ! rg -q 'Labels\[\$label\]' "$PROJECT_ROOT/scripts/clawdiy-smoke.sh"; then
        test_pass
    else
        test_fail "Clawdiy smoke script must avoid jq reserved variable names when reading docker labels"
    fi

    test_start "static_clawdiy_smoke_resolves_bind_backed_volume_devices"
    if rg -q 'docker volume inspect "\$mount_name"' "$PROJECT_ROOT/scripts/clawdiy-smoke.sh" && \
       rg -q '\.\[0\]\.Options\.device // \.\[0\]\.Mountpoint // empty' "$PROJECT_ROOT/scripts/clawdiy-smoke.sh"; then
        test_pass
    else
        test_fail "Clawdiy smoke script must resolve bind-backed local Docker volumes to their effective host device paths"
    fi

    test_start "static_deploy_script_keeps_json_stdout_clean"
    if rg -q 'docker compose "\$\{compose_args\[@\]\}" "\$\{args\[@\]\}" 1>&2' "$DEPLOY_SCRIPT" && \
       rg -q 'docker logs "\$container" --tail 80 >&2' "$DEPLOY_SCRIPT" && \
       rg -q '"\$BACKUP_SCRIPT" restore-check "\$backup_path" 1>&2' "$DEPLOY_SCRIPT" && \
       rg -q 'if \[\[ "\$OUTPUT_JSON" != "true" \]\]; then' "$DEPLOY_SCRIPT" && \
       rg -q 'echo -n "\."' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "deploy.sh must keep restore-check logs, docker compose progress, docker logs, and wait dots out of JSON stdout"
    fi

    test_start "static_clawdiy_workflow_validates_auth_rendering_rules"
    if rg -q 'Validate auth material rendering rules' "$CLAWDIY_WORKFLOW" && \
       rg -q 'api\.responses\.write' "$CLAWDIY_WORKFLOW" && \
       rg -q 'gpt-5\.4' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must validate auth material rendering rules for Telegram and Codex OAuth"
    fi

    test_start "static_clawdiy_workflow_renders_fail_closed_auth_flags"
    if rg -q 'CLAWDIY_AUTH_FAIL_CLOSED=' "$CLAWDIY_WORKFLOW" && \
       rg -q 'CLAWDIY_OPENAI_CODEX_AUTH_ENABLED' "$CLAWDIY_WORKFLOW" && \
       rg -q 'CLAWDIY_OPENAI_CODEX_REQUIRED_SCOPES' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must render fail-closed auth flags into the dedicated env file"
    fi

    test_start "static_clawdiy_workflow_validates_restore_readiness"
    if rg -q 'Validate Clawdiy restore readiness' "$CLAWDIY_WORKFLOW" && \
       rg -q 'data/clawdiy/\.last-backup' "$CLAWDIY_WORKFLOW" && \
       rg -q "pre_deploy_\\*\\.tar\\.gz" "$CLAWDIY_WORKFLOW" && \
       rg -q 'clawdiy-evidence-manifest\.json' "$CLAWDIY_WORKFLOW" && \
       rg -q 'has_evidence_manifest' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must validate restore-readiness from the tracked Clawdiy backup reference and evidence inventory"
    fi

    test_start "static_rollback_drill_covers_clawdiy_inventory"
    if rg -q 'clawdiy_included' "$ROLLBACK_DRILL_WORKFLOW" && \
       rg -q 'has_clawdiy_audit' "$ROLLBACK_DRILL_WORKFLOW" && \
       rg -q 'has_clawdiy_evidence_manifest' "$ROLLBACK_DRILL_WORKFLOW"; then
        test_pass
    else
        test_fail "Rollback drill workflow must validate Clawdiy config, state, audit, and evidence manifest inventory"
    fi

    test_start "static_backup_config_guards_partial_clawdiy_restore"
    if rg -q '^CLAWDIY_ALLOW_PARTIAL_RESTORE=false' "$BACKUP_CONFIG"; then
        test_pass
    else
        test_fail "Backup config must default to fail-closed partial restore protection for Clawdiy"
    fi

    test_start "static_backup_config_uses_unix_line_endings"
    if LC_ALL=C grep -q $'\r' "$BACKUP_CONFIG"; then
        test_fail "Backup config must use LF line endings because backup-moltis-enhanced.sh sources it directly"
    else
        test_pass
    fi

    test_start "static_clawdiy_compose_security_hardening"
    if rg -q '^    init: true$' "$COMPOSE_CLAWDIY" && \
       rg -q 'source: \./data/clawdiy/runtime' "$COMPOSE_CLAWDIY" && \
       rg -q 'target: /home/node/\.openclaw' "$COMPOSE_CLAWDIY" && \
       rg -q 'clawdiy-workspace:/home/node/\.openclaw/workspace' "$COMPOSE_CLAWDIY" && \
       rg -q 'no-new-privileges:true' "$COMPOSE_CLAWDIY" && \
       rg -q '      - ALL' "$COMPOSE_CLAWDIY" && \
       rg -q '/tmp:rw,noexec,nosuid,nodev,size=64m' "$COMPOSE_CLAWDIY" && \
       ! rg -q '/var/run/docker\.sock' "$COMPOSE_CLAWDIY"; then
        test_pass
    else
        test_fail "Clawdiy compose file must keep init, privilege drops, hardened tmpfs, and no docker socket mount"
    fi

    test_start "static_clawdiy_deploy_normalizes_workspace_permissions"
    if rg -q '\$PROJECT_ROOT/data/clawdiy/workspace' "$DEPLOY_SCRIPT" && \
       rg -q '\$PROJECT_ROOT/data/clawdiy/runtime' "$DEPLOY_SCRIPT" && \
       rg -q 'CLAWDIY_RUNTIME_UID' "$DEPLOY_SCRIPT" && \
       rg -q 'CLAWDIY_RUNTIME_GID' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "deploy.sh must create and normalize the dedicated Clawdiy runtime home and workspace paths for the runtime uid/gid"
    fi

    test_start "static_clawdiy_render_script_normalizes_runtime_home_ownership"
    if rg -q 'CLAWDIY_RUNTIME_UID="\$\{CLAWDIY_RUNTIME_UID:-1000\}"' "$PROJECT_ROOT/scripts/render-clawdiy-runtime-config.sh" && \
       rg -q 'CLAWDIY_RUNTIME_GID="\$\{CLAWDIY_RUNTIME_GID:-1000\}"' "$PROJECT_ROOT/scripts/render-clawdiy-runtime-config.sh" && \
       rg -q 'chown -R "\$\{CLAWDIY_RUNTIME_UID\}:\$\{CLAWDIY_RUNTIME_GID\}" "\$\(dirname "\$OUTPUT_FILE"\)"' "$PROJECT_ROOT/scripts/render-clawdiy-runtime-config.sh"; then
        test_pass
    else
        test_fail "render-clawdiy-runtime-config.sh must normalize the writable runtime home ownership after rendering openclaw.json"
    fi

    test_start "static_clawdiy_backup_inventory_includes_runtime_home"
    if rg -q '^CLAWDIY_RUNTIME_DIR="\$\{PROJECT_ROOT\}/data/clawdiy/runtime"' "$BACKUP_CONFIG" && \
       rg -q 'CLAWDIY_RUNTIME_DIR="\$\{CLAWDIY_RUNTIME_DIR:-\$PROJECT_ROOT/data/clawdiy/runtime\}"' "$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh" && \
       rg -q '"runtime_dir": "\$CLAWDIY_RUNTIME_DIR"' "$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh"; then
        test_pass
    else
        test_fail "Clawdiy backup inventory must explicitly track the writable runtime home because official OpenClaw wizards can persist config and OAuth artifacts there"
    fi

    test_start "static_clawdiy_policy_header_binding_fail_closed"
    if jq -e '
        .defaults.require_topology_profile_alignment == true
        and .service_auth.reject_on_missing_required_headers == true
        and .service_auth.reject_on_agent_header_mismatch == true
      ' "$FLEET_POLICY" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fleet policy must fail closed on missing required headers, agent mismatch, and topology profile drift"
    fi

    test_start "static_preflight_enforces_clawdiy_topology_alignment"
    if rg -q 'require_topology_profile_alignment' "$PREFLIGHT_SCRIPT" && \
       rg -q 'fleet_topology_alignment' "$PREFLIGHT_SCRIPT"; then
        test_pass
    else
        test_fail "Preflight must validate Clawdiy topology-profile alignment against runtime, registry, and policy"
    fi

    test_start "static_preflight_allows_clawdiy_fleet_bootstrap"
    if rg -q 'BOOTSTRAP_NETWORKS' "$PREFLIGHT_SCRIPT" && \
       rg -q 'network_bootstrap' "$PREFLIGHT_SCRIPT" && \
       rg -q 'created during Clawdiy deploy via GitOps' "$PREFLIGHT_SCRIPT"; then
        test_pass
    else
        test_fail "Preflight must distinguish bootstrap-capable Clawdiy networks from blocking external network failures"
    fi

    test_start "static_preflight_enforces_clawdiy_runtime_home_writability_contract"
    if rg -q 'check_clawdiy_runtime_home' "$PREFLIGHT_SCRIPT" && \
       rg -q 'runtime_home_present' "$PREFLIGHT_SCRIPT" && \
       rg -q 'runtime_home_ownership' "$PREFLIGHT_SCRIPT" && \
       rg -q 'official OpenClaw wizard writes' "$PREFLIGHT_SCRIPT"; then
        test_pass
    else
        test_fail "Preflight must fail if Clawdiy runtime home is missing or owned incorrectly for official OpenClaw wizard writes"
    fi

    test_start "static_preflight_keeps_clawdiy_runtime_home_check_target_aware_in_ci"
    if rg -q 'if \[\[ "\$CI_MODE" == "true" \]\]; then' "$PREFLIGHT_SCRIPT" && \
       rg -q 'runtime home is not materialized in CI checkout' "$PREFLIGHT_SCRIPT" && \
       rg -q 'deploy/render must create' "$PREFLIGHT_SCRIPT"; then
        test_pass
    else
        test_fail "Preflight must treat Clawdiy runtime-home materialization as a deploy-target concern in CI mode instead of failing the local checkout"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_static_config_validation_tests
fi
