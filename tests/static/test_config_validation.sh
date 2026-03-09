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

    test_start "static_clawdiy_workflow_uses_dedicated_env_path"
    if rg -q 'CLAWDIY_ENV_PATH: /opt/moltinger/clawdiy/\.env' "$CLAWDIY_WORKFLOW" && \
       ! rg -q '/opt/moltinger/\.env[^[:alnum:]_]' "$CLAWDIY_WORKFLOW"; then
        test_pass
    else
        test_fail "Clawdiy deploy workflow must keep a dedicated env path separate from /opt/moltinger/.env"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_static_config_validation_tests
fi
