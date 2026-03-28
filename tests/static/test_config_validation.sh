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
DEPLOY_STATUS_NOTIFY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy-status-notify.yml"
DEPLOY_STALL_WATCHDOG_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy-stall-watchdog.yml"
MOLTIS_UPDATE_PROPOSAL_WORKFLOW="$PROJECT_ROOT/.github/workflows/moltis-update-proposal.yml"
CLAWDIY_WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy-clawdiy.yml"
UAT_GATE_WORKFLOW="$PROJECT_ROOT/.github/workflows/uat-gate.yml"
FEATURE_DIAGNOSTICS_WORKFLOW="$PROJECT_ROOT/.github/workflows/feature-diagnostics.yml"
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
DEPLOY_STALL_WATCHDOG_SCRIPT="$PROJECT_ROOT/scripts/deploy-stall-watchdog.sh"
HEALTH_MONITOR_SCRIPT="$PROJECT_ROOT/scripts/health-monitor.sh"
HEALTH_MONITOR_UNIT="$PROJECT_ROOT/systemd/moltis-health-monitor.service"
HEALTH_MONITOR_CONFIG_UNIT="$PROJECT_ROOT/config/systemd/moltis-health-monitor.service"
MOLTIS_ENV_RENDER_SCRIPT="$PROJECT_ROOT/scripts/render-moltis-env.sh"
TELEGRAM_REMOTE_UAT_SCRIPT="$PROJECT_ROOT/scripts/telegram-e2e-on-demand.sh"
TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/run-tracked-moltis-deploy.sh"
SSH_TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/ssh-run-tracked-moltis-deploy.sh"
RUNTIME_ATTESTATION_SCRIPT="$PROJECT_ROOT/scripts/moltis-runtime-attestation.sh"
CHECKOUT_ALIGN_SCRIPT="$PROJECT_ROOT/scripts/align-server-checkout.sh"
SYNC_SURFACE_SCRIPT="$PROJECT_ROOT/scripts/gitops-sync-managed-surface.sh"
FEATURE_DIAGNOSTICS_SCRIPT="$PROJECT_ROOT/scripts/collect-feature-diagnostics.sh"
PROD_MUTATION_GUARD_SCRIPT="$PROJECT_ROOT/scripts/prod-mutation-guard.sh"
GITOPS_CHECK_SCRIPT="$PROJECT_ROOT/scripts/gitops-check-managed-surface.sh"

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
        test_fail "Moltis compose files must mount the tracked checkout as /server and use it as the working directory for Git-tracked scripts, docs, and repo-managed skill sources"
    fi

    test_start "static_moltis_browser_docker_contract_matches_official_sibling_container_requirements"
    if rg -q 'container_host = "host\.docker\.internal"' "$TOML_CONFIG" && \
       rg -q '^profile_dir = "/tmp/moltis-browser-profile/browserless"' "$TOML_CONFIG" && \
       rg -q '^persist_profile = false' "$TOML_CONFIG" && \
       rg -q '^max_instances = 1' "$TOML_CONFIG" && \
       rg -q '^sandbox_image = "moltis-browserless-chrome:tracked"' "$TOML_CONFIG" && \
       rg -q 'DOCKER_SOCKET_GID:-999' "$COMPOSE_PROD" && \
       rg -q '/tmp/moltis-browser-profile:/tmp/moltis-browser-profile' "$COMPOSE_PROD" && \
       rg -q '/tmp/moltis-browser-profile:/tmp/moltis-browser-profile' "$PROJECT_ROOT/docker-compose.yml" && \
       rg -q 'host\.docker\.internal:host-gateway' "$COMPOSE_PROD" && \
       rg -q 'host\.docker\.internal:host-gateway' "$PROJECT_ROOT/docker-compose.yml" && \
       rg -q 'DOCKER_SOCKET_GID=\$docker_socket_gid' "$DEPLOY_SCRIPT" && \
       rg -q 'prepare_moltis_browser_profile_dir' "$DEPLOY_SCRIPT" && \
       rg -q 'rm -rf "\$browser_profile_dir"' "$DEPLOY_SCRIPT" && \
       rg -q 'Tracked browser contract must pin max_instances=1 when persist_profile=false' "$DEPLOY_SCRIPT" && \
       rg -q 'prepare_moltis_browser_sandbox_image' "$DEPLOY_SCRIPT" && \
       [[ -f "$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile" ]] && \
       [[ -f "$PROJECT_ROOT/scripts/moltis-browser-sandbox/entrypoint.sh" ]] && \
       rg -q 'scripts/moltis-browser-sandbox/Dockerfile' "$DEPLOY_SCRIPT" && \
       rg -q 'docker build \\' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Browser-in-Docker contract must keep a dedicated non-persistent browser profile dir, pin max_instances=1, build the tracked browser sandbox wrapper image during deploy, purge stale profile state on deploy, set container_host, inject the live Docker socket GID, and publish host.docker.internal for sibling browser containers"
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

    test_start "static_identity_prompt_forbids_internal_activity_leaks_in_telegram"
    if rg -Fq 'В пользовательских мессенджер-каналах, особенно Telegram, никогда не отправляй внутренние activity/tool-progress трассы.' "$TOML_CONFIG" && \
       rg -Fq 'Запрещено публиковать как обычный ответ `Activity log`, `Running`, `Searching memory`, `thinking`' "$TOML_CONFIG" && \
       rg -Fq 'Разрешено максимум одно короткое человеческое префейс-сообщение' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis identity prompt must fail closed against internal activity/tool-progress leakage in Telegram and other user-facing messaging channels"
    fi

    test_start "static_telegram_account_pins_classic_final_message_delivery"
    if rg -Fq '[channels.telegram.moltis-bot]' "$TOML_CONFIG" && \
       rg -Fq 'stream_mode = "off"' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "User-facing Telegram account must explicitly pin stream_mode = \"off\" so runtime defaults or per-account streaming features cannot leak internal activity/tool-progress into chat"
    fi

    test_start "static_telegram_account_pins_text_only_safe_provider_lane"
    if python3 - "$TOML_CONFIG" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open('rb') as fh:
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib
    config = tomllib.load(fh)

providers = config.get('providers', {})
telegram = config.get('channels', {}).get('telegram', {}).get('moltis-bot', {})
default_zai = providers.get('openai', {})
safe_lane = providers.get('custom-zai-telegram-safe', {})

conditions = [
    safe_lane.get('enabled') is True,
    safe_lane.get('tool_mode') == 'off',
    safe_lane.get('model') == 'glm-5',
    safe_lane.get('models') == ['glm-5'],
    safe_lane.get('alias') == 'custom-zai-telegram-safe',
    safe_lane.get('api_key') == default_zai.get('api_key'),
    safe_lane.get('base_url') == default_zai.get('base_url'),
    telegram.get('model') == 'glm-5',
    telegram.get('model_provider') == 'custom-zai-telegram-safe',
]

raise SystemExit(0 if all(conditions) else 1)
PY
    then
        test_pass
    else
        test_fail "User-facing Telegram must pin a dedicated text-only provider lane so DM traffic cannot inherit the shared tool-capable runtime surface"
    fi

    test_start "static_browser_config_declares_container_host_for_docker_runtime"
    if rg -Fq 'container_host = "host.docker.internal"' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis browser config must declare host-gateway container_host when Moltis itself runs in Docker"
    fi

    test_start "static_browser_agent_timeout_keeps_headroom_above_navigation_budget"
    if python3 - "$TOML_CONFIG" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open('rb') as fh:
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib
    config = tomllib.load(fh)

tools = config.get('tools', {})
browser = tools.get('browser', {})
agent_timeout_secs = int(tools.get('agent_timeout_secs', 0))
navigation_timeout_ms = int(browser.get('navigation_timeout_ms', 0))
required_minimum = max(90, (navigation_timeout_ms // 1000) + 60)
raise SystemExit(0 if agent_timeout_secs >= required_minimum else 1)
PY
    then
        test_pass
    else
        test_fail "Overall agent timeout must stay materially above the browser navigation timeout so multi-step browser runs do not abort at the same 30s ceiling as page navigation"
    fi

    test_start "static_identity_prompt_scopes_broad_moltis_skill_authoring_requests"
    if rg -Fq 'Для запросов про создание или обновление Moltis skills сначала используй локальные проектные гайды' "$TOML_CONFIG" && \
       rg -Fq 'Official docs Moltis для skill-authoring открывай точечно по релевантным разделам' "$TOML_CONFIG" && \
       rg -Fq 'не зависай в долгом browse-цикле' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis identity prompt must scope broad Moltis skill-authoring/doc-review requests to relevant sections and local project guides"
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

    test_start "static_moltis_smoke_uses_current_auth_and_ws_rpc_contract"
    if rg -Fq 'Authenticating via /api/auth/login' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'tests/lib/ws_rpc_cli.mjs' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'RESET_CHAT_CONTEXT_BEFORE_SEND="${RESET_CHAT_CONTEXT_BEFORE_SEND:-true}"' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'TEST_SESSION_KEY="${TEST_SESSION_KEY:-}"' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'DELETE_TEST_SESSION_ON_EXIT="${DELETE_TEST_SESSION_ON_EXIT:-false}"' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'sequence --steps' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'sessions.switch' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'sessions.delete' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'chat.clear' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'chat.send' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'Browser session contamination detected' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'Browser pool exhaustion detected' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       rg -Fq 'detect_browser_failure_taxonomy()' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       ! rg -Fq '/api/v1/chat' "$PROJECT_ROOT/scripts/test-moltis-api.sh" && \
       ! rg -Fq '"/login"' "$PROJECT_ROOT/scripts/test-moltis-api.sh"; then
        test_pass
    else
        test_fail "scripts/test-moltis-api.sh must use /api/auth/login plus WS RPC status/chat calls, run the chat workflow in one RPC sequence for session fidelity, support dedicated session switch/delete for operator canaries, classify stale browser session/pool-exhaustion failures before the generic timeout, clear stale chat context before send, and avoid the retired /login + /api/v1/chat contract"
    fi

    test_start "static_telegram_remote_uat_enforces_status_and_activity_semantics"
    if rg -Fq 'STATUS_EXPECTED_MODEL="${STATUS_EXPECTED_MODEL:-custom-zai-telegram-safe::glm-5}"' "$TELEGRAM_REMOTE_UAT_SCRIPT" && \
       rg -Fq 'verification_gate_reply' "$TELEGRAM_REMOTE_UAT_SCRIPT" && \
       rg -Fq 'semantic_activity_leak' "$TELEGRAM_REMOTE_UAT_SCRIPT" && \
       rg -Fq 'semantic_pre_send_activity_leak' "$TELEGRAM_REMOTE_UAT_SCRIPT" && \
       rg -Fq 'semantic_status_mismatch' "$TELEGRAM_REMOTE_UAT_SCRIPT" && \
       rg -Fq '*"mcp__"*)' "$TELEGRAM_REMOTE_UAT_SCRIPT" && \
       rg -Fq 'evaluate_authoritative_semantics' "$TELEGRAM_REMOTE_UAT_SCRIPT"; then
        test_pass
    else
        test_fail "Authoritative Telegram remote UAT must fail on verification gates, internal activity leaks, contaminated pre-send activity, and /status model mismatches"
    fi

    test_start "static_runtime_attestation_and_deploy_guard_browser_sandbox_contract"
    if rg -Fq 'BROWSER_SANDBOX_IMAGE_UNAVAILABLE' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'docker image inspect "$BROWSER_SANDBOX_IMAGE"' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'BROWSER_DOCKER_SOCKET_GID_MISMATCH' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'BROWSER_CONTAINER_HOST_INVALID' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'BROWSER_PROFILE_ROOT_PERMISSION_MISMATCH' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'BROWSER_PROFILE_DIR_PERMISSION_MISMATCH' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'BROWSER_PROFILE_CONCURRENCY_MISMATCH' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'prepare_moltis_browser_sandbox_image()' "$DEPLOY_SCRIPT" && \
       rg -q 'docker build \\' "$DEPLOY_SCRIPT" && \
       rg -Fq 'scripts/moltis-browser-sandbox/Dockerfile' "$DEPLOY_SCRIPT" && \
       rg -Fq 'DOCKER_SOCKET_GID' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Runtime attestation and deploy control plane must guard browser sandbox image availability, docker.sock access, host-gateway routing, writable browser profile storage, and single-instance non-persistent browser concurrency before production traffic hits Telegram"
    fi

    test_start "static_moltis_identity_degrades_tool_heavy_telegram_paths"
    if rg -Fq 'В пользовательских Telegram/DM чатах по умолчанию избегай browser, Tavily/web-search, memory_search и других многошаговых tool-heavy workflow' "$TOML_CONFIG" && \
       rg -Fq 'Если задача требует интерактивного браузера, цепочки tool calls или длительной диагностики' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis identity must explicitly degrade browser/search/memory-heavy Telegram/DM paths instead of silently triggering tool-heavy workflows on user-facing chat"
    fi

    test_start "static_tracked_browser_sandbox_wrapper_normalizes_profile_ownership_and_drops_privileges"
    if [[ -f "$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile" ]] && \
       [[ -f "$PROJECT_ROOT/scripts/moltis-browser-sandbox/entrypoint.sh" ]] && \
       rg -q '^ARG BASE_IMAGE=browserless/chrome$' "$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile" && \
       rg -q '^FROM \$\{BASE_IMAGE\}$' "$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile" && \
       rg -q '^USER root$' "$PROJECT_ROOT/scripts/moltis-browser-sandbox/Dockerfile" && \
       rg -Fq 'chown -R 999:999 "$profile_dir"' "$PROJECT_ROOT/scripts/moltis-browser-sandbox/entrypoint.sh" && \
       rg -Fq 'export HOME="$runtime_home"' "$PROJECT_ROOT/scripts/moltis-browser-sandbox/entrypoint.sh" && \
       rg -Fq "exec setpriv --reuid=999 --regid=999 --init-groups /bin/sh -lc 'cd /usr/src/app && exec ./start.sh'" "$PROJECT_ROOT/scripts/moltis-browser-sandbox/entrypoint.sh"; then
        test_pass
    else
        test_fail "Tracked browser sandbox wrapper must normalize the bind-mounted profile ownership as root, provide a writable non-root HOME, and then drop privileges back to the upstream browserless runtime user before Chrome starts"
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
        test_fail "Primary Moltis config must keep repo-side codex-update scripts container-visible under /server and keep writable runtime state under ~/.moltis"
    fi

    test_start "static_config_codex_update_remote_surface_contract_is_advisory_safe"
    if rg -Fq 'Если `codex-update` уже объявлен в списке доступных навыков, считай этот навык существующим.' "$TOML_CONFIG" && \
       rg -Fq 'Не пытайся опровергнуть это через `exec`, `cat`, `find`' "$TOML_CONFIG" && \
       rg -Fq 'Для запросов про новые версии Codex CLI в user-facing remote surface действуй в advisory-only режиме' "$TOML_CONFIG" && \
       rg -Fq 'На remote user-facing surface не запускай молча `make codex-update`, `moltis-codex-update-run.sh`' "$TOML_CONFIG" && \
       rg -Fq 'primary truth — runtime state helper `bash /server/scripts/moltis-codex-update-state.sh get --json`' "$TOML_CONFIG" && \
       rg -Fq 'не используй `memory_search`, общую память чата' "$TOML_CONFIG" && \
       rg -Fq 'Если trusted operator/local surface реально видит `/server`' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis config must treat codex-update as an advisory-safe capability on remote Telegram surfaces while reserving direct /server runtime usage for trusted operator/local contexts"
    fi

    test_start "static_config_does_not_claim_repo_search_paths_are_live_skill_contract"
    if rg -Fq 'search_paths = []' "$TOML_CONFIG" && \
       ! rg -Fq 'search_paths = ["/server/skills"]' "$TOML_CONFIG" && \
       rg -Fq 'auto_load = ["telegram-learner", "codex-update"]' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis config must not rely on repo-mounted /server/skills for live discovery and should keep auto_load only for already-discoverable skills"
    fi

    test_start "static_config_pins_memory_provider_and_repo_watch_dirs"
    if rg -Fq 'provider = "ollama"' "$TOML_CONFIG" && \
       rg -Fq 'base_url = "http://ollama:11434"' "$TOML_CONFIG" && \
       rg -Fq 'model = "nomic-embed-text"' "$TOML_CONFIG" && \
       rg -Fq '"~/.moltis/memory"' "$TOML_CONFIG" && \
       rg -Fq '"/server/knowledge"' "$TOML_CONFIG"; then
        test_pass
    else
        test_fail "Primary Moltis config must pin the memory embeddings backend, use the root Ollama endpoint for model probes, and keep repo-visible watch_dirs instead of relying on auto-detect"
    fi

    test_start "static_moltis_compose_forwards_ollama_cloud_key_to_runtime"
    if rg -Fq 'OLLAMA_API_KEY: ${OLLAMA_API_KEY:-}' "$COMPOSE_PROD"; then
        test_pass
    else
        test_fail "Production Moltis container must receive OLLAMA_API_KEY so cloud-backed Ollama chat models can appear in the runtime provider catalog"
    fi

    test_start "static_codex_cli_update_delivery_script_is_executable"
    if [[ -x "$PROJECT_ROOT/scripts/codex-cli-update-delivery.sh" ]]; then
        test_pass
    else
        test_fail "scripts/codex-cli-update-delivery.sh must be executable to stay GitOps-clean after managed surface sync applies executable bits"
    fi

    test_start "static_moltis_repo_skills_sync_script_is_executable"
    if [[ -x "$PROJECT_ROOT/scripts/moltis-repo-skills-sync.sh" ]]; then
        test_pass
    else
        test_fail "scripts/moltis-repo-skills-sync.sh must be executable so deploy can materialize repo-managed skills into the runtime discovery path"
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

    test_start "static_feature_diagnostics_workflow_stays_read_only"
    if [[ -f "$FEATURE_DIAGNOSTICS_WORKFLOW" ]] && \
       rg -q 'collect-feature-diagnostics\.sh' "$FEATURE_DIAGNOSTICS_WORKFLOW" && \
       ! rg -q 'prod-remote-ainetic-tech-opt-moltinger' "$FEATURE_DIAGNOSTICS_WORKFLOW" && \
       ! rg -q 'gitops-sync-managed-surface\.sh' "$FEATURE_DIAGNOSTICS_WORKFLOW" && \
       ! rg -q 'update-active-deploy-root\.sh' "$FEATURE_DIAGNOSTICS_WORKFLOW" && \
       ! rg -q 'render-moltis-env\.sh' "$FEATURE_DIAGNOSTICS_WORKFLOW" && \
       ! rg -q 'scp ' "$FEATURE_DIAGNOSTICS_WORKFLOW"; then
        test_pass
    else
        test_fail "Feature diagnostics workflow must remain read-only and must not reuse the production mutation path"
    fi

    test_start "static_feature_diagnostics_script_collects_evidence_without_mutation"
    if [[ -f "$FEATURE_DIAGNOSTICS_SCRIPT" ]] && \
       rg -q 'preflight-check\.sh' "$FEATURE_DIAGNOSTICS_SCRIPT" && \
       rg -q -- '--ci --json' "$FEATURE_DIAGNOSTICS_SCRIPT" && \
       rg -q -- '--dry-run' "$FEATURE_DIAGNOSTICS_SCRIPT" && \
       rg -q 'align-server-checkout\.sh' "$FEATURE_DIAGNOSTICS_SCRIPT" && \
       rg -q 'ssh-run-tracked-moltis-deploy\.sh' "$FEATURE_DIAGNOSTICS_SCRIPT" && \
       ! rg -q 'gitops-sync-managed-surface\.sh' "$FEATURE_DIAGNOSTICS_SCRIPT" && \
       ! rg -q 'scp ' "$FEATURE_DIAGNOSTICS_SCRIPT"; then
        test_pass
    else
        test_fail "Feature diagnostics script must collect evidence via read-only checks and dry-run plans only"
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

    test_start "static_prod_mutation_guard_is_wired_into_key_moltinger_mutators"
    if [[ -f "$PROD_MUTATION_GUARD_SCRIPT" ]] && \
       rg -q 'MOLTINGER_PROD_GUARD_GITHUB_TOKEN' "$PROD_MUTATION_GUARD_SCRIPT" && \
       rg -q 'api.github.com/repos/' "$PROD_MUTATION_GUARD_SCRIPT" && \
       rg -q 'prod-mutation-guard\.sh' "$CHECKOUT_ALIGN_SCRIPT" && \
       rg -q 'prod-mutation-guard\.sh' "$SYNC_SURFACE_SCRIPT" && \
       rg -q 'prod-mutation-guard\.sh' "$PROJECT_ROOT/scripts/gitops-repair-managed-checkout.sh" && \
       rg -q 'prod-mutation-guard\.sh' "$SSH_TRACKED_DEPLOY_SCRIPT" && \
       rg -q 'prod-mutation-guard\.sh' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -q 'prod-mutation-guard\.sh' "$HOST_AUTOMATION_SCRIPT" && \
       rg -q 'prod-mutation-guard\.sh' "$PROJECT_ROOT/scripts/update-active-deploy-root.sh"; then
        test_pass
    else
        test_fail "Key Moltinger production-mutating entrypoints must be protected by the shared production mutation guard"
    fi

    test_start "static_uat_and_clawdiy_workflows_block_feature_branch_promotion"
    if rg -q 'feature-diagnostics\.yml' "$UAT_GATE_WORKFLOW" && \
       rg -q 'UAT promotion to production is blocked for feature branches' "$UAT_GATE_WORKFLOW" && \
       rg -q 'Production Clawdiy deploys must run from main' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "UAT and Clawdiy workflows must explicitly block feature-branch promotion and point operators to sanctioned paths"
    fi

    test_start "static_production_workflows_pass_guard_github_run_context"
    if rg -q 'MOLTINGER_PROD_GUARD_GITHUB_TOKEN' "$DEPLOY_WORKFLOW" && \
       rg -q 'MOLTINGER_PROD_GUARD_REPOSITORY' "$DEPLOY_WORKFLOW" && \
       rg -q 'MOLTINGER_PROD_GUARD_WORKFLOW' "$DEPLOY_WORKFLOW" && \
       rg -q 'MOLTINGER_PROD_GUARD_GITHUB_TOKEN' "$UAT_GATE_WORKFLOW" && \
       rg -q 'permissions:' "$DEPLOY_WORKFLOW" && \
       rg -q 'actions: read' "$DEPLOY_WORKFLOW" && \
       rg -q 'actions: read' "$UAT_GATE_WORKFLOW" && \
       rg -q 'actions: read' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Production-adjacent workflows must pass GitHub run context to the mutation guard and grant actions:read"
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
       rg -Fq 'prepare_moltis_container_for_rollout' "$DEPLOY_SCRIPT" && \
       rg -Fq 'docker stop --timeout "$stop_timeout" "$TARGET_CONTAINER"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'docker rm -f "$TARGET_CONTAINER"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'compose_cmd normal up -d --remove-orphans "${auxiliary_services[@]}"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'compose_cmd normal up -d --no-deps --force-recreate "$TARGET_SERVICE"' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Moltis deploy path must converge sidecars separately, pre-stop/remove the fixed-name Moltis container, and recreate only Moltis with --no-deps so config changes apply without a second compose recreate race"
    fi

    test_start "static_deploy_script_rollback_reuses_serialized_moltis_contract"
    if [[ -f "$DEPLOY_SCRIPT" ]] && \
       [[ "$(rg -F -c 'prepare_moltis_container_for_rollout' "$DEPLOY_SCRIPT")" -ge 2 ]] && \
       [[ "$(rg -F -c 'compose_cmd normal up -d --no-deps --force-recreate "$TARGET_SERVICE"' "$DEPLOY_SCRIPT")" -ge 2 ]] && \
       rg -Fq 'Auto rollback trigger reason:' "$DEPLOY_SCRIPT" && \
       rg -Fq 'verify_failure_reason' "$DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Moltis rollback path must reuse the same serialized no-deps recreate contract as rollout and preserve the failing verify reason in deploy JSON/logging"
    fi

    test_start "static_deploy_workflow_bounds_critical_jobs_and_emits_hardened_completion_notifications"
    if [[ -f "$DEPLOY_WORKFLOW" ]] && [[ -f "$DEPLOY_STATUS_NOTIFY_WORKFLOW" ]] && \
       python3 - "$DEPLOY_WORKFLOW" "$DEPLOY_STATUS_NOTIFY_WORKFLOW" <<'PY'
import pathlib, re, sys
deploy = pathlib.Path(sys.argv[1]).read_text()
notify = pathlib.Path(sys.argv[2]).read_text()

required_job_timeouts = {
    'gitops-compliance': 'timeout-minutes: 15',
    'preflight': 'timeout-minutes: 15',
    'test': 'timeout-minutes: 15',
    'backup': 'timeout-minutes: 15',
    'deploy': 'timeout-minutes: 20',
    'rollback': 'timeout-minutes: 15',
    'verify': 'timeout-minutes: 15',
}
for job_name, timeout_fragment in required_job_timeouts.items():
    job_match = re.search(rf'(?ms)^  {re.escape(job_name)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)', deploy)
    if not job_match or timeout_fragment not in job_match.group(1):
        raise SystemExit(1)

test_job_match = re.search(r'(?ms)^  test:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)', deploy)
if not test_job_match or 'test_moltis_repo_skills_sync.sh' not in test_job_match.group(1):
    raise SystemExit(1)

required_notify_fragments = [
    'workflow_run:',
    'Deploy Moltis',
    'completed',
    'timeout-minutes: 10',
    'workflow_run.conclusion',
    'https://api.telegram.org/bot',
    'action-send-mail@v16',
    "always() && steps.email.outputs.should_send == 'true'",
    "always() && steps.telegram.outputs.should_send == 'true'",
    'continue-on-error: true',
    'All configured deploy notification channels failed',
]
for fragment in required_notify_fragments:
    if fragment not in notify:
        raise SystemExit(1)

for forbidden_fragment in [
    'ref: ${{ github.event.workflow_run.head_sha }}',
    'actions/checkout@v6',
]:
    if forbidden_fragment in notify:
        raise SystemExit(1)
PY
    then
        test_pass
    else
        test_fail "Deploy workflow must bound all critical jobs and use a hardened workflow_run completion notifier that does not execute head_sha code under secrets"
    fi

    test_start "static_deploy_stall_watchdog_is_read_only_and_timeout_aware"
    if [[ -f "$DEPLOY_STALL_WATCHDOG_WORKFLOW" ]] && [[ -f "$DEPLOY_STALL_WATCHDOG_SCRIPT" ]] && \
       python3 - "$DEPLOY_STALL_WATCHDOG_WORKFLOW" "$DEPLOY_STALL_WATCHDOG_SCRIPT" <<'PY'
import pathlib, sys
workflow = pathlib.Path(sys.argv[1]).read_text()
script = pathlib.Path(sys.argv[2]).read_text()

required_workflow_fragments = [
    "name: Deploy Moltis Stall Watchdog",
    "schedule:",
    "7,22,37,52 * * * *",
    "timeout-minutes: 10",
    "ref: main",
    "actions: read",
    "contents: read",
    "scripts/deploy-stall-watchdog.sh",
    '--workflow-file "deploy.yml"',
    "--threshold-minutes 45",
    "api.telegram.org/bot",
    "always() && steps.watchdog.outputs.stalled_count != '0' && steps.email.outputs.should_send == 'true'",
    "always() && steps.watchdog.outputs.stalled_count != '0' && steps.telegram.outputs.should_send == 'true'",
    "continue-on-error: true",
]
for fragment in required_workflow_fragments:
    if fragment not in workflow:
        raise SystemExit(1)

for forbidden_fragment in [
    "cancel-in-progress: true",
    "contents: write",
    "actions: write",
]:
    if forbidden_fragment in workflow:
        raise SystemExit(1)

required_script_fragments = [
    "gh api",
    "actions/workflows/${WORKFLOW_FILE}/runs",
    "status == \"queued\"",
    "status == \"in_progress\"",
    "status == \"waiting\"",
    "idle_in_progress",
    "queue_timeout_without_active_predecessor",
    "has_older_in_progress",
    "fromdateiso8601",
    "stalled_count",
]
for fragment in required_script_fragments:
    if fragment not in script:
        raise SystemExit(1)
PY
    then
        test_pass
    else
        test_fail "Deploy stall watchdog must stay read-only, query the workflow-specific GitHub Actions API, ignore serialized/progressing runs, and keep email/Telegram channels isolated"
    fi

    test_start "static_health_monitor_respects_deploy_mutex_and_avoids_global_prune"
    if [[ -f "$HEALTH_MONITOR_SCRIPT" ]] && [[ -f "$HEALTH_MONITOR_UNIT" ]] && [[ -f "$HEALTH_MONITOR_CONFIG_UNIT" ]] && \
       rg -Fq 'DEPLOY_MUTEX_PATH="${DEPLOY_MUTEX_PATH:-/var/lock/moltinger/deploy.lock}"' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'deploy_mutex_active()' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'Deploy mutex active; suspending mutating health-monitor actions' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'docker image prune -af' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'up -d --no-deps --force-recreate "$container"' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'check_disk_space 90 || true' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'check_memory 90 || true' "$HEALTH_MONITOR_SCRIPT" && \
       ! rg -Fq 'docker system prune' "$HEALTH_MONITOR_SCRIPT" && \
       rg -Fq 'Environment=DEPLOY_MUTEX_PATH=/var/lock/moltinger/deploy.lock' "$HEALTH_MONITOR_UNIT" && \
       rg -Fq 'Environment="DISK_CLEANUP_COOLDOWN_SECONDS=3600"' "$HEALTH_MONITOR_UNIT" && \
       rg -Fq 'Environment=DEPLOY_MUTEX_PATH=/var/lock/moltinger/deploy.lock' "$HEALTH_MONITOR_CONFIG_UNIT" && \
       rg -Fq 'Environment="DISK_CLEANUP_COOLDOWN_SECONDS=3600"' "$HEALTH_MONITOR_CONFIG_UNIT"; then
        test_pass
    else
        test_fail "Health monitor must suppress mutating actions during deploy mutex, avoid global docker system prune, and ship the same mutex/cooldown unit contract through both tracked service definitions"
    fi

    test_start "static_moltis_compose_uses_extended_stop_grace_period"
    if [[ -f "$PROJECT_ROOT/docker-compose.prod.yml" ]] && \
       [[ -f "$PROJECT_ROOT/docker-compose.yml" ]] && \
       rg -Fq 'stop_grace_period: 45s' "$PROJECT_ROOT/docker-compose.prod.yml" && \
       rg -Fq 'stop_grace_period: 45s' "$PROJECT_ROOT/docker-compose.yml"; then
        test_pass
    else
        test_fail "Moltis compose files must grant Moltis a longer stop_grace_period so deploys do not depend on Docker's 10s default stop timeout"
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

    test_start "static_deploy_batches_managed_surface_hash_checks"
    if [[ -f "$GITOPS_CHECK_SCRIPT" ]] && \
       rg -Fq 'gitops-check-managed-surface.sh' "$DEPLOY_WORKFLOW" && \
       rg -Fq 'managed_files_compared=' "$DEPLOY_WORKFLOW" && \
       rg -Fq "emit_remote_script \"\$manifest_file\" | ssh \"\$SSH_TARGET\" 'bash -seu'" "$GITOPS_CHECK_SCRIPT" && \
       rg -Fq 'Fetching remote hashes in one SSH roundtrip' "$GITOPS_CHECK_SCRIPT"; then
        test_pass
    else
        test_fail "Deploy workflow must batch managed-surface hash checks through the dedicated helper and expose summary counts"
    fi

    test_start "static_deploy_compliance_checks_prod_compose_hash"
    if [[ -f "$GITOPS_CHECK_SCRIPT" ]] && \
       rg -Fq 'append_manifest_entry "docker-compose.prod.yml"' "$GITOPS_CHECK_SCRIPT"; then
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

    test_start "static_tracked_deploy_attests_live_runtime_provenance"
    if [[ -f "$TRACKED_DEPLOY_SCRIPT" ]] && \
       [[ -f "$RUNTIME_ATTESTATION_SCRIPT" ]] && \
       rg -Fq 'moltis-runtime-attestation.sh' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -Fq '"attest-live-runtime"' "$TRACKED_DEPLOY_SCRIPT" && \
       rg -Fq 'runtime_attestation' "$TRACKED_DEPLOY_SCRIPT"; then
        test_pass
    else
        test_fail "Tracked deploy control-plane must attest live runtime provenance through the shared runtime attestation script"
    fi

    test_start "static_runtime_contract_enforces_tracked_runtime_config_parity"
    if [[ -f "$DEPLOY_SCRIPT" ]] && \
       [[ -f "$RUNTIME_ATTESTATION_SCRIPT" ]] && \
       rg -Fq 'cmp -s "$tracked_runtime_toml" "$runtime_runtime_toml"' "$DEPLOY_SCRIPT" && \
       rg -Fq 'runtime moltis.toml diverges from tracked config/moltis.toml' "$DEPLOY_SCRIPT" && \
       rg -Fq 'cmp -s "$TRACKED_RUNTIME_TOML" "$RUNTIME_RUNTIME_TOML"' "$RUNTIME_ATTESTATION_SCRIPT" && \
       rg -Fq 'RUNTIME_CONFIG_FILE_MISMATCH' "$RUNTIME_ATTESTATION_SCRIPT"; then
        test_pass
    else
        test_fail "Deploy verification and runtime attestation must fail closed when live runtime moltis.toml drifts from tracked config/moltis.toml"
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
    if [[ -f "$GITOPS_CHECK_SCRIPT" ]] && \
       rg -Fq 'append_manifest_entry "docker-compose.prod.yml"' "$GITOPS_CHECK_SCRIPT"; then
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
