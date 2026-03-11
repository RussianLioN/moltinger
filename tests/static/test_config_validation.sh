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
CLAWDIY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy-clawdiy.yml"
ROLLBACK_DRILL_WORKFLOW="$PROJECT_ROOT/.github/workflows/rollback-drill.yml"
BACKUP_CONFIG="$PROJECT_ROOT/config/backup/backup.conf"
FLEET_POLICY="$PROJECT_ROOT/config/fleet/policy.json"
PREFLIGHT_SCRIPT="$PROJECT_ROOT/scripts/preflight-check.sh"
DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy.sh"

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

    test_start "static_compose_clawdiy_valid"
    if env CLAWDIY_IMAGE="ghcr.io/openclaw/openclaw:latest" docker compose -f "$COMPOSE_CLAWDIY" config --quiet >/dev/null 2>&1; then
        test_pass
    else
        test_fail "docker-compose.clawdiy.yml does not render cleanly with a valid CLAWDIY_IMAGE"
    fi

    test_start "static_config_uses_env_substitution"
    if rg -q '\$\{[A-Z0-9_]+\}' "$TOML_CONFIG" "$COMPOSE_PROD" "$COMPOSE_TEST"; then
        test_pass
    else
        test_fail "Expected environment variable substitution in config files"
    fi

    test_start "static_config_has_no_hardcoded_secrets"
    if rg -n 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' "$PROJECT_ROOT/config" "$PROJECT_ROOT/tests/fixtures/config" "$COMPOSE_PROD" "$COMPOSE_TEST" >/dev/null 2>&1; then
        test_fail "Detected potential hardcoded secret material"
    else
        test_pass
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

    test_start "static_deploy_audit_markers_stored_in_ignored_data_dir"
    if rg -q 'data/\.deployed-sha' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'data/\.deployment-info' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow should write audit markers under data/"
    fi

    test_start "static_deploy_audit_markers_not_written_to_repo_root"
    if rg -n '> \\.deployed-sha|cat > \\.deployment-info|cat \\.deployed-sha' "$PROJECT_ROOT/.github/workflows/deploy.yml" >/dev/null 2>&1; then
        test_fail "Deploy workflow still writes audit markers to repo root"
    else
        test_pass
    fi

    test_start "static_deploy_server_git_checkout_aligned_after_success"
    if rg -Fq 'git fetch --depth=1 origin "${{ github.ref_name }}"' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -Fq 'git reset --hard "${{ github.sha }}"' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow should align server git checkout after successful sync"
    fi

    test_start "static_deploy_pending_sync_is_not_treated_as_hard_drift"
    if rg -q 'Pending Sync' "$PROJECT_ROOT/.github/workflows/deploy.yml" && \
       rg -q 'Hard block applies only to dirty server worktree' "$PROJECT_ROOT/.github/workflows/deploy.yml"; then
        test_pass
    else
        test_fail "Deploy workflow should distinguish pending sync from dirty worktree drift"
    fi

    test_start "static_clawdiy_workflow_exists"
    if [[ -f "$CLAWDIY_WORKFLOW" ]]; then
        test_pass
    else
        test_fail "Missing .github/workflows/deploy-clawdiy.yml"
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
       rg -q 'source: \./data/clawdiy/runtime/openclaw\.json' "$COMPOSE_CLAWDIY" && \
       rg -q 'target: /home/node/\.openclaw/openclaw\.json' "$COMPOSE_CLAWDIY" && \
       rg -q 'source: \./config/fleet' "$COMPOSE_CLAWDIY" && \
       rg -q 'target: /home/node/\.openclaw/registry' "$COMPOSE_CLAWDIY"; then
        test_pass
    else
        test_fail "Clawdiy compose must use explicit bind syntax for runtime config and registry so server-side docker compose does not misrender them"
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
       rg -q 'Skipping Clawdiy state ownership normalization because deploy\.sh is not running as root' "$DEPLOY_SCRIPT" && \
       rg -q 'chown -R "\$\{CLAWDIY_RUNTIME_UID\}:\$\{CLAWDIY_RUNTIME_GID\}" "\$path"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Clawdiy deploy script must normalize state and audit ownership for the node runtime user during server-side rollout"
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
       rg -q 'docker logs "\$container" --tail 50 >&2' "$DEPLOY_SCRIPT" && \
       rg -q 'if \[\[ "\$OUTPUT_JSON" != "true" \]\]; then' "$DEPLOY_SCRIPT" && \
       rg -q 'echo -n "\."' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "deploy.sh must keep docker compose progress, docker logs, and wait dots out of JSON stdout"
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
       rg -q 'source: \./data/clawdiy/runtime/openclaw\.json' "$COMPOSE_CLAWDIY" && \
       rg -q 'target: /home/node/\.openclaw/openclaw\.json' "$COMPOSE_CLAWDIY" && \
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
       rg -q 'CLAWDIY_RUNTIME_UID' "$DEPLOY_SCRIPT" && \
       rg -q 'CLAWDIY_RUNTIME_GID' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "deploy.sh must create and normalize the dedicated Clawdiy workspace path for the runtime uid/gid"
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

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_static_config_validation_tests
fi
