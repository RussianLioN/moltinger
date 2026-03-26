#!/usr/bin/env python3
"""Apply the runtime-only PR1 carrier onto a mainline checkout tree.

This script exists because PR1 is intentionally a selected-hunks carrier rather
than a full branch merge. It mutates a target tree in place, failing fast when
the expected origin/main anchors drift.
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile


def join_lines(*lines: str) -> str:
    return "\n".join(lines)


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: pathlib.Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> None:
    text = read_text(path)
    if old not in text:
        raise RuntimeError(f"replace target not found in {path}: {label}")
    write_text(path, text.replace(old, new, 1))


def insert_before(path: pathlib.Path, anchor: str, addition: str, label: str) -> None:
    replace_once(path, anchor, addition + anchor, label)


def copy_from_source(source_repo: pathlib.Path, target_root: pathlib.Path, rel_path: str) -> None:
    src = source_repo / rel_path
    dst = target_root / rel_path
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def normalize_patch_paths(text: str, before_root: pathlib.Path, after_root: pathlib.Path) -> str:
    before = f"{before_root.as_posix()}/"
    after = f"{after_root.as_posix()}/"
    return text.replace(before, "a/").replace(after, "b/")


def build_patch(before_root: pathlib.Path, after_root: pathlib.Path) -> str:
    result = subprocess.run(
        ["diff", "-urN", str(before_root), str(after_root)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr or result.stdout or "diff failed")
    return normalize_patch_paths(result.stdout, before_root, after_root)


def apply_runtime_carrier(source_repo: pathlib.Path, target_root: pathlib.Path) -> list[str]:
    changed: list[str] = []

    # 1. config/moltis.toml
    path = target_root / "config/moltis.toml"
    replace_once(
        path,
        join_lines(
            "[memory]",
            'llm_reranking = false',
            'session_export = false',
            '# provider = "local"              # Embedding provider:',
            '                                  #   "local"   - Built-in local embeddings',
            '                                  #   "ollama"  - Ollama server',
            '                                  #   "openai"  - OpenAI API',
            '                                  #   "custom"  - Custom endpoint',
            '                                  #   (none)    - Auto-detect from available providers',
            '# base_url = "http://localhost:11434/v1"  # API endpoint for embeddings',
            '# model = "nomic-embed-text"      # Embedding model name',
            '# api_key = "..."                 # API key (optional for local endpoints like Ollama)',
            "",
            '# Knowledge base directories for RAG (semantic search)',
            '# watch_dirs = [',
            '#   "~/.moltis/memory",           # Default memory location',
            '#   "/server/knowledge",          # Project knowledge base',
            '# ]',
            "",
        ),
        join_lines(
            "[memory]",
            'llm_reranking = false',
            'session_export = false',
            'provider = "ollama"              # Pin embeddings to Ollama instead of chat-provider auto-detect',
            '                                  #   "local"   - Built-in local embeddings',
            '                                  #   "ollama"  - Ollama server',
            '                                  #   "openai"  - OpenAI API',
            '                                  #   "custom"  - Custom endpoint',
            '                                  #   (none)    - Auto-detect from available providers',
            'base_url = "http://ollama:11434"  # Root Ollama endpoint keeps model probes/pulls on /api/* working in Docker',
            'model = "nomic-embed-text"       # Lightweight embedding model verified on the live Ollama sidecar',
            '# api_key = "..."                 # API key (optional for local endpoints like Ollama)',
            "",
            '# Knowledge base directories for RAG (semantic search)',
            'watch_dirs = [',
            '  "~/.moltis/memory",            # Default memory location',
            '  "/server/knowledge",           # Project knowledge base',
            ']',
            "",
        ),
        "memory contract",
    )
    changed.append("config/moltis.toml")

    # 2. docker-compose.prod.yml
    path = target_root / "docker-compose.prod.yml"
    replace_once(
        path,
        join_lines(
            "      # GLM-5 API key for Z.ai Coding Plan (OpenAI-compatible)",
            "      GLM_API_KEY: ${GLM_API_KEY}",
            "",
        ),
        join_lines(
            "      # GLM-5 API key for Z.ai Coding Plan (OpenAI-compatible)",
            "      GLM_API_KEY: ${GLM_API_KEY}",
            "      # Ollama Cloud API key for cloud-backed fallback chat models",
            "      OLLAMA_API_KEY: ${OLLAMA_API_KEY:-}",
            "",
        ),
        "ollama env",
    )
    changed.append("docker-compose.prod.yml")

    # 3. scripts/deploy.sh
    path = target_root / "scripts/deploy.sh"
    replace_once(
        path,
        join_lines(
            'CLAWDIY_RUNTIME_UID="${CLAWDIY_RUNTIME_UID:-1000}"',
            'CLAWDIY_RUNTIME_GID="${CLAWDIY_RUNTIME_GID:-1000}"',
            "",
            "HEALTH_CHECK_TIMEOUT=",
        ),
        join_lines(
            'CLAWDIY_RUNTIME_UID="${CLAWDIY_RUNTIME_UID:-1000}"',
            'CLAWDIY_RUNTIME_GID="${CLAWDIY_RUNTIME_GID:-1000}"',
            'CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR="${CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}"',
            'MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="${MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"',
            "",
            "HEALTH_CHECK_TIMEOUT=",
        ),
        "deploy vars",
    )
    replace_once(
        path,
        join_lines(
            "    printf '%s' \"$value\"",
            "}",
            "",
            "tracked_moltis_version() {",
        ),
        join_lines(
            "    printf '%s' \"$value\"",
            "}",
            "",
            "canonicalize_existing_path() {",
            '    local path="$1"',
            "",
            '    if [[ -z "$path" ]]; then',
            "        return 1",
            "    fi",
            "",
            '    if [[ -d "$path" ]]; then',
            '        (cd "$path" && pwd -P)',
            "        return 0",
            "    fi",
            "",
            '    if [[ -e "$path" ]]; then',
            "        local parent base",
            '        parent="$(dirname "$path")"',
            '        base="$(basename "$path")"',
            '        printf \'%s/%s\\n\' "$(cd "$parent" && pwd -P)" "$base"',
            "        return 0",
            "    fi",
            "",
            "    return 1",
            "}",
            "",
            "normalize_runtime_config_path() {",
            '    local path="$1"',
            "",
            '    if [[ -z "$path" ]]; then',
            "        return 1",
            "    fi",
            "",
            '    while [[ "$path" != "/" && "$path" == */ ]]; do',
            '        path="${path%/}"',
            "    done",
            "",
            '    printf \'%s\' "$path"',
            "}",
            "",
            "runtime_config_dir_allowed() {",
            '    local candidate="$1"',
            "    local normalized_candidate normalized_allowlist entry",
            '    normalized_candidate="$(normalize_runtime_config_path "$candidate" || true)"',
            '    [[ -n "$normalized_candidate" ]] || return 1',
            "",
            '    local old_ifs="$IFS"',
            "    IFS=':'",
            "    for entry in $MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST; do",
            '        normalized_allowlist="$(normalize_runtime_config_path "$entry" || true)"',
            '        if [[ -n "$normalized_allowlist" && "$normalized_candidate" == "$normalized_allowlist" ]]; then',
            '            IFS="$old_ifs"',
            "            return 0",
            "        fi",
            "    done",
            '    IFS="$old_ifs"',
            "",
            "    return 1",
            "}",
            "",
            "container_mount_source() {",
            '    local container="$1"',
            '    local destination="$2"',
            "",
            '    docker inspect "$container" 2>/dev/null | \\',
            '        jq -r --arg destination "$destination" \'.[0].Mounts[]? | select(.Destination == $destination) | .Source\' | \\',
            "        head -n 1",
            "}",
            "",
            "container_mount_rw() {",
            '    local container="$1"',
            '    local destination="$2"',
            "",
            '    docker inspect "$container" 2>/dev/null | \\',
            '        jq -r --arg destination "$destination" \'.[0].Mounts[]? | select(.Destination == $destination) | .RW\' | \\',
            "        head -n 1",
            "}",
            "",
            "tracked_moltis_version() {",
        ),
        "deploy helpers",
    )
    replace_once(
        path,
        join_lines(
            "deploy_containers() {",
            '    log_info "Deploying containers for target $TARGET..."',
            '    local -a deploy_services=("$TARGET_SERVICE")',
            "    local service",
            "",
            '    for service in "${TARGET_AUXILIARY_SERVICES[@]}"; do',
            '        [[ -n "$service" ]] || continue',
            '        deploy_services+=("$service")',
            "    done",
            "",
            '    compose_cmd normal up -d --remove-orphans "${deploy_services[@]}"',
            '    log_success "Containers deployed for target $TARGET"',
            "}",
            "",
        ),
        join_lines(
            "deploy_containers() {",
            '    log_info "Deploying containers for target $TARGET..."',
            '    local -a deploy_services=("$TARGET_SERVICE")',
            "    local -a deploy_args=(up -d --remove-orphans)",
            "    local service",
            "",
            '    for service in "${TARGET_AUXILIARY_SERVICES[@]}"; do',
            '        [[ -n "$service" ]] || continue',
            '        deploy_services+=("$service")',
            "    done",
            "",
            '    if [[ "$TARGET" == "moltis" ]]; then',
            "        # Moltis loads runtime config at process start, so bind-mounted config",
            "        # changes must force a recreate to avoid stale live state.",
            "        deploy_args+=(--force-recreate)",
            "    fi",
            "",
            '    compose_cmd normal "${deploy_args[@]}" "${deploy_services[@]}"',
            '    log_success "Containers deployed for target $TARGET"',
            "}",
            "",
        ),
        "force recreate",
    )
    replace_once(
        path,
        join_lines(
            "verify_deployment() {",
            '    log_info "Verifying deployment for target $TARGET..."',
            "",
            '    if ! wait_for_healthy "$TARGET_CONTAINER" "$TARGET_HEALTH_TIMEOUT"; then',
            "        return 1",
            "    fi",
            "",
            "    local http_code",
            '    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")',
            '    if [[ "$http_code" != "200" ]]; then',
            '        log_error "Health endpoint returned HTTP $http_code for target $TARGET"',
            "        return 1",
            "    fi",
            "",
            '    if [[ -n "$TARGET_METRICS_URL" ]]; then',
            '        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_METRICS_URL" 2>/dev/null || echo "000")',
            '        if [[ "$http_code" != "200" ]]; then',
            '            log_warn "Metrics endpoint returned HTTP $http_code for target $TARGET (non-critical)"',
            "        fi",
            "    fi",
            "",
            '    log_success "Deployment verification passed for target $TARGET"',
            "    return 0",
            "}",
            "",
        ),
        join_lines(
            "verify_deployment() {",
            '    log_info "Verifying deployment for target $TARGET..."',
            "",
            '    if ! wait_for_healthy "$TARGET_CONTAINER" "$TARGET_HEALTH_TIMEOUT"; then',
            "        return 1",
            "    fi",
            "",
            "    local http_code",
            '    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_HEALTH_URL" 2>/dev/null || echo "000")',
            '    if [[ "$http_code" != "200" ]]; then',
            '        log_error "Health endpoint returned HTTP $http_code for target $TARGET"',
            "        return 1",
            "    fi",
            "",
            '    if [[ -n "$TARGET_METRICS_URL" ]]; then',
            '        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_METRICS_URL" 2>/dev/null || echo "000")',
            '        if [[ "$http_code" != "200" ]]; then',
            '            log_warn "Metrics endpoint returned HTTP $http_code for target $TARGET (non-critical)"',
            "        fi",
            "    fi",
            "",
            '    if [[ "$TARGET" == "moltis" ]]; then',
            "        local expected_workspace expected_runtime_config",
            "        local actual_workspace_source actual_runtime_config_source",
            "        local actual_runtime_config_rw working_dir",
            "        local tracked_runtime_toml runtime_runtime_toml",
            "",
            '        working_dir="$(docker inspect --format \'{{.Config.WorkingDir}}\' "$TARGET_CONTAINER" 2>/dev/null || echo "")"',
            '        if [[ "$working_dir" != "/server" ]]; then',
            '            log_error "Moltis runtime contract mismatch: working_dir is \'$working_dir\', expected \'/server\'"',
            "            return 1",
            "        fi",
            "",
            '        expected_workspace="$(canonicalize_existing_path "$PROJECT_ROOT" || printf \'%s\\n\' "$PROJECT_ROOT")"',
            '        actual_workspace_source="$(container_mount_source "$TARGET_CONTAINER" "/server")"',
            '        if [[ -z "$actual_workspace_source" ]]; then',
            '            log_error "Moltis runtime contract mismatch: /server mount is missing in container $TARGET_CONTAINER"',
            "            return 1",
            "        fi",
            '        actual_workspace_source="$(canonicalize_existing_path "$actual_workspace_source" || printf \'%s\\n\' "$actual_workspace_source")"',
            '        if [[ "$actual_workspace_source" != "$expected_workspace" ]]; then',
            '            log_error "Moltis runtime contract mismatch: /server source is \'$actual_workspace_source\', expected \'$expected_workspace\'"',
            "            return 1",
            "        fi",
            "",
            '        expected_runtime_config="$(read_env_file_value "MOLTIS_RUNTIME_CONFIG_DIR" || true)"',
            '        expected_runtime_config="${expected_runtime_config:-$CANONICAL_MOLTIS_RUNTIME_CONFIG_DIR}"',
            '        expected_runtime_config="$(normalize_runtime_config_path "$expected_runtime_config")"',
            '        if ! runtime_config_dir_allowed "$expected_runtime_config"; then',
            '            log_error "Moltis runtime contract mismatch: runtime config dir \'$expected_runtime_config\' is outside the production allowlist \'$MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST\'"',
            "            return 1",
            "        fi",
            '        expected_runtime_config="$(canonicalize_existing_path "$expected_runtime_config" || printf \'%s\\n\' "$expected_runtime_config")"',
            '        actual_runtime_config_source="$(container_mount_source "$TARGET_CONTAINER" "/home/moltis/.config/moltis")"',
            '        if [[ -z "$actual_runtime_config_source" ]]; then',
            '            log_error "Moltis runtime contract mismatch: runtime config mount is missing for /home/moltis/.config/moltis"',
            "            return 1",
            "        fi",
            '        actual_runtime_config_source="$(canonicalize_existing_path "$actual_runtime_config_source" || printf \'%s\\n\' "$actual_runtime_config_source")"',
            '        if [[ "$actual_runtime_config_source" != "$expected_runtime_config" ]]; then',
            '            log_error "Moltis runtime contract mismatch: runtime config source is \'$actual_runtime_config_source\', expected \'$expected_runtime_config\'"',
            "            return 1",
            "        fi",
            "",
            '        actual_runtime_config_rw="$(container_mount_rw "$TARGET_CONTAINER" "/home/moltis/.config/moltis")"',
            '        if [[ "$actual_runtime_config_rw" != "true" ]]; then',
            '            log_error "Moltis runtime contract mismatch: runtime config mount must be writable for runtime-managed auth/key files"',
            "            return 1",
            "        fi",
            "",
            '        tracked_runtime_toml="$PROJECT_ROOT/config/moltis.toml"',
            '        runtime_runtime_toml="$expected_runtime_config/moltis.toml"',
            '        if [[ ! -f "$tracked_runtime_toml" || ! -f "$runtime_runtime_toml" ]]; then',
            '            log_error "Moltis runtime contract mismatch: tracked or runtime moltis.toml is missing"',
            "            return 1",
            "        fi",
            '        if ! cmp -s "$tracked_runtime_toml" "$runtime_runtime_toml"; then',
            '            log_error "Moltis runtime contract mismatch: runtime moltis.toml diverges from tracked config/moltis.toml"',
            "            return 1",
            "        fi",
            "",
            '        if ! docker exec "$TARGET_CONTAINER" sh -lc \'',
            "            test -d /server &&",
            "            test -d /server/skills &&",
            "            test -f /home/moltis/.config/moltis/moltis.toml &&",
            '            tmp_path="/home/moltis/.config/moltis/provider_keys.json.tmp.contract-check.$$" &&',
            '            : > "$tmp_path" &&',
            '            rm -f "$tmp_path"',
            "        ' >/dev/null 2>&1; then",
            '            log_error "Moltis runtime contract mismatch: repo skills are not visible or runtime config is not writable inside the container"',
            "            return 1",
            "        fi",
            "    fi",
            "",
            '    log_success "Deployment verification passed for target $TARGET"',
            "    return 0",
            "}",
            "",
        ),
        "verify contract",
    )
    changed.append("scripts/deploy.sh")

    for rel in (
        "scripts/run-tracked-moltis-deploy.sh",
        "scripts/moltis-runtime-attestation.sh",
        "scripts/moltis-search-memory-diagnostics.sh",
        "tests/component/test_moltis_runtime_attestation.sh",
        "tests/component/test_moltis_search_memory_diagnostics.sh",
    ):
        copy_from_source(source_repo, target_root, rel)
        changed.append(rel)

    # 8. tests/static/test_config_validation.sh
    path = target_root / "tests/static/test_config_validation.sh"
    replace_once(
        path,
        join_lines(
            'TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/run-tracked-moltis-deploy.sh"',
            'SSH_TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/ssh-run-tracked-moltis-deploy.sh"',
            'CHECKOUT_ALIGN_SCRIPT="$PROJECT_ROOT/scripts/align-server-checkout.sh"',
        ),
        join_lines(
            'TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/run-tracked-moltis-deploy.sh"',
            'SSH_TRACKED_DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/ssh-run-tracked-moltis-deploy.sh"',
            'RUNTIME_ATTESTATION_SCRIPT="$PROJECT_ROOT/scripts/moltis-runtime-attestation.sh"',
            'CHECKOUT_ALIGN_SCRIPT="$PROJECT_ROOT/scripts/align-server-checkout.sh"',
        ),
        "static vars",
    )
    replace_once(
        path,
        join_lines(
            "    else",
            '        test_fail "Primary Moltis config must use container-visible /server paths for codex-update skill code and ~/.moltis paths for writable state"',
            "    fi",
            "",
            '    test_start "static_codex_cli_update_delivery_script_is_executable"',
        ),
        join_lines(
            "    else",
            '        test_fail "Primary Moltis config must use container-visible /server paths for codex-update skill code and ~/.moltis paths for writable state"',
            "    fi",
            "",
            '    test_start "static_config_pins_memory_provider_and_repo_watch_dirs"',
            '    if rg -Fq \'provider = "ollama"\' "$TOML_CONFIG" && \\',
            '       rg -Fq \'base_url = "http://ollama:11434"\' "$TOML_CONFIG" && \\',
            '       rg -Fq \'model = "nomic-embed-text"\' "$TOML_CONFIG" && \\',
            '       rg -Fq \'"~/.moltis/memory"\' "$TOML_CONFIG" && \\',
            '       rg -Fq \'"/server/knowledge"\' "$TOML_CONFIG"; then',
            "        test_pass",
            "    else",
            '        test_fail "Primary Moltis config must pin the memory embeddings backend, use the root Ollama endpoint for model probes, and keep repo-visible watch_dirs instead of relying on auto-detect"',
            "    fi",
            "",
            '    test_start "static_moltis_compose_forwards_ollama_cloud_key_to_runtime"',
            '    if rg -Fq \'OLLAMA_API_KEY: ${OLLAMA_API_KEY:-}\' "$COMPOSE_PROD"; then',
            "        test_pass",
            "    else",
            '        test_fail "Production Moltis container must receive OLLAMA_API_KEY so cloud-backed Ollama chat models can appear in the runtime provider catalog"',
            "    fi",
            "",
            '    test_start "static_codex_cli_update_delivery_script_is_executable"',
        ),
        "static embedding tests",
    )
    replace_once(
        path,
        join_lines(
            '    test_start "static_deploy_script_scopes_moltis_rollout_to_core_and_sidecars"',
            '    if [[ -f "$DEPLOY_SCRIPT" ]] && \\',
            '       rg -Fq \'TARGET_AUXILIARY_SERVICES=("watchtower" "ollama")\' "$DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'compose_cmd normal up -d --remove-orphans "${deploy_services[@]}"\' "$DEPLOY_SCRIPT"; then',
            "        test_pass",
            "    else",
            '        test_fail "Moltis deploy path must target only moltis + required sidecars so unrelated monitoring services cannot block tracked upgrades"',
            "    fi",
            "",
        ),
        join_lines(
            '    test_start "static_deploy_script_scopes_moltis_rollout_to_core_and_sidecars"',
            '    if [[ -f "$DEPLOY_SCRIPT" ]] && \\',
            '       rg -Fq \'TARGET_AUXILIARY_SERVICES=("watchtower" "ollama")\' "$DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'deploy_args+=(--force-recreate)\' "$DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'compose_cmd normal "${deploy_args[@]}" "${deploy_services[@]}"\' "$DEPLOY_SCRIPT"; then',
            "        test_pass",
            "    else",
            '        test_fail "Moltis deploy path must target only moltis + required sidecars and force-recreate the runtime so config changes take effect immediately"',
            "    fi",
            "",
        ),
        "static force recreate",
    )
    insert_before(
        path,
        '    test_start "static_production_workflows_share_remote_lock_group"',
        join_lines(
            '    test_start "static_tracked_deploy_attests_live_runtime_provenance"',
            '    if [[ -f "$TRACKED_DEPLOY_SCRIPT" ]] && \\',
            '       [[ -f "$RUNTIME_ATTESTATION_SCRIPT" ]] && \\',
            '       rg -Fq \'moltis-runtime-attestation.sh\' "$TRACKED_DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'"attest-live-runtime"\' "$TRACKED_DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'runtime_attestation\' "$TRACKED_DEPLOY_SCRIPT"; then',
            "        test_pass",
            "    else",
            '        test_fail "Tracked deploy control-plane must attest live runtime provenance through the shared runtime attestation script"',
            "    fi",
            "",
            '    test_start "static_runtime_contract_enforces_tracked_runtime_config_parity"',
            '    if [[ -f "$DEPLOY_SCRIPT" ]] && \\',
            '       [[ -f "$RUNTIME_ATTESTATION_SCRIPT" ]] && \\',
            '       rg -Fq \'cmp -s "$tracked_runtime_toml" "$runtime_runtime_toml"\' "$DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'runtime moltis.toml diverges from tracked config/moltis.toml\' "$DEPLOY_SCRIPT" && \\',
            '       rg -Fq \'cmp -s "$TRACKED_RUNTIME_TOML" "$RUNTIME_RUNTIME_TOML"\' "$RUNTIME_ATTESTATION_SCRIPT" && \\',
            '       rg -Fq \'RUNTIME_CONFIG_FILE_MISMATCH\' "$RUNTIME_ATTESTATION_SCRIPT"; then',
            "        test_pass",
            "    else",
            '        test_fail "Deploy verification and runtime attestation must fail closed when live runtime moltis.toml drifts from tracked config/moltis.toml"',
            "    fi",
            "",
            "",
        ),
        "static attestation tests",
    )
    changed.append("tests/static/test_config_validation.sh")

    # 9. tests/unit/test_deploy_workflow_guards.sh
    path = target_root / "tests/unit/test_deploy_workflow_guards.sh"
    insert_before(
        path,
        "test_tracked_deploy_workflows_pass_remote_args_without_inline_shell_string() {",
        join_lines(
            "test_deploy_script_verifies_live_moltis_runtime_contract() {",
            '    test_start "Deploy verification should enforce the live Moltis runtime contract"',
            "",
            '    if [[ ! -f "$PROJECT_ROOT/scripts/deploy.sh" ]]; then',
            '        test_skip "Missing deploy script"',
            "        return",
            "    fi",
            "",
            '    if ! grep -Fq "working_dir is" "$PROJECT_ROOT/scripts/deploy.sh" || \\',
            '       ! grep -Fq "/server mount is missing" "$PROJECT_ROOT/scripts/deploy.sh" || \\',
            '       ! grep -Fq "/server/skills" "$PROJECT_ROOT/scripts/deploy.sh" || \\',
            '       ! grep -Fq "MOLTIS_RUNTIME_CONFIG_DIR" "$PROJECT_ROOT/scripts/deploy.sh" || \\',
            '       ! grep -Fq "provider_keys.json.tmp.contract-check" "$PROJECT_ROOT/scripts/deploy.sh"; then',
            '        test_fail "deploy.sh must verify /server visibility, runtime config mount source, and writable runtime config behavior for Moltis"',
            "        return",
            "    fi",
            "",
            "    test_pass",
            "}",
            "",
            "test_deploy_script_force_recreates_moltis_runtime_on_rollout() {",
            '    test_start "Deploy rollout should force-recreate Moltis so runtime config changes are applied"',
            "",
            '    if [[ ! -f "$PROJECT_ROOT/scripts/deploy.sh" ]]; then',
            '        test_skip "Missing deploy script"',
            "        return",
            "    fi",
            "",
            '    if ! grep -Fq \'deploy_args+=(--force-recreate)\' "$PROJECT_ROOT/scripts/deploy.sh" || \\',
            '       ! grep -Fq \'compose_cmd normal "${deploy_args[@]}" "${deploy_services[@]}"\' "$PROJECT_ROOT/scripts/deploy.sh" || \\',
            '       ! grep -Fq \'bind-mounted config\' "$PROJECT_ROOT/scripts/deploy.sh"; then',
            '        test_fail "deploy.sh must force-recreate Moltis during deploy so updated runtime config is not left pending until a manual restart"',
            "        return",
            "    fi",
            "",
            "    test_pass",
            "}",
            "",
            "",
        ),
        "unit new tests",
    )
    replace_once(
        path,
        "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/srv/runtime-config\\n' > \"$project_root/.env\"",
        "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/opt/moltinger-state/config-runtime\\n' > \"$project_root/.env\"",
        "unit runtime dir 1",
    )
    replace_once(
        path,
        join_lines(
            '    output_file="$tmp_dir/output.json"',
            "",
            '    mkdir -p "$project_root/config" "$project_root/scripts"',
            "    printf 'services: {}\\n' > \"$project_root/docker-compose.prod.yml\"",
            "    printf 'name = \"moltis\"\\n' > \"$project_root/config/moltis.toml\"",
            "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/opt/moltinger-state/config-runtime\\n' > \"$project_root/.env\"",
            '    : > "$project_root/scripts/prepare-moltis-runtime-config.sh"',
            '    : > "$project_root/scripts/moltis-version.sh"',
            '    : > "$project_root/scripts/deploy.sh"',
        ),
        join_lines(
            '    output_file="$tmp_dir/output.json"',
            "",
            '    mkdir -p "$project_root/config" "$project_root/scripts"',
            "    printf 'services: {}\\n' > \"$project_root/docker-compose.prod.yml\"",
            "    printf 'name = \"moltis\"\\n' > \"$project_root/config/moltis.toml\"",
            "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/opt/moltinger-state/config-runtime\\n' > \"$project_root/.env\"",
            '    : > "$project_root/scripts/prepare-moltis-runtime-config.sh"',
            '    : > "$project_root/scripts/moltis-version.sh"',
            '    : > "$project_root/scripts/deploy.sh"',
            '    : > "$project_root/scripts/moltis-runtime-attestation.sh"',
        ),
        "unit attestation file 1",
    )
    replace_once(
        path,
        join_lines(
            '       ! grep -Fq \'"align-server-checkout"\' "$output_file" || \\',
            '       ! grep -Fq \'"/srv/runtime-config"\' "$output_file"; then',
        ),
        join_lines(
            '       ! grep -Fq \'"align-server-checkout"\' "$output_file" || \\',
            '       ! grep -Fq \'"attest-live-runtime"\' "$output_file" || \\',
            '       ! grep -Fq \'"/opt/moltinger-state/config-runtime"\' "$output_file"; then',
        ),
        "unit dry-run steps",
    )
    replace_once(
        path,
        "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/srv/runtime-config\\n' > \"$project_root/.env\"",
        "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/opt/moltinger-state/config-runtime\\n' > \"$project_root/.env\"",
        "unit runtime dir 2",
    )
    replace_once(
        path,
        join_lines(
            '    output_json="$tmp_dir/output.json"',
            "",
            '    mkdir -p "$project_root/config" "$project_root/scripts"',
            "    printf 'services: {}\\n' > \"$project_root/docker-compose.prod.yml\"",
            "    printf 'name = \"moltis\"\\n' > \"$project_root/config/moltis.toml\"",
            "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/opt/moltinger-state/config-runtime\\n' > \"$project_root/.env\"",
            '    : > "$project_root/scripts/prepare-moltis-runtime-config.sh"',
            '    : > "$project_root/scripts/moltis-version.sh"',
            '    : > "$project_root/scripts/deploy.sh"',
        ),
        join_lines(
            '    output_json="$tmp_dir/output.json"',
            "",
            '    mkdir -p "$project_root/config" "$project_root/scripts"',
            "    printf 'services: {}\\n' > \"$project_root/docker-compose.prod.yml\"",
            "    printf 'name = \"moltis\"\\n' > \"$project_root/config/moltis.toml\"",
            "    printf 'MOLTIS_RUNTIME_CONFIG_DIR=/opt/moltinger-state/config-runtime\\n' > \"$project_root/.env\"",
            '    : > "$project_root/scripts/prepare-moltis-runtime-config.sh"',
            '    : > "$project_root/scripts/moltis-version.sh"',
            '    : > "$project_root/scripts/deploy.sh"',
            '    : > "$project_root/scripts/moltis-runtime-attestation.sh"',
        ),
        "unit attestation file 2",
    )
    replace_once(
        path,
        join_lines(
            '       [[ "$(jq -r \'.details.tracked_version\' "$output_json")" != "1.2.3" ]] || \\',
            '       [[ "$(jq -r \'.details.runtime_config_dir\' "$output_json")" != "/srv/runtime-config" ]]; then',
        ),
        join_lines(
            '       [[ "$(jq -r \'.details.tracked_version\' "$output_json")" != "1.2.3" ]] || \\',
            '       [[ "$(jq -r \'.details.runtime_config_dir\' "$output_json")" != "/opt/moltinger-state/config-runtime" ]]; then',
        ),
        "unit dry-run abi",
    )
    replace_once(
        path,
        join_lines(
            '    : > "$deploy_dir/scripts/deploy.sh"',
            '    chmod +x "$deploy_dir/scripts/prepare-moltis-runtime-config.sh" "$deploy_dir/scripts/moltis-version.sh" "$deploy_dir/scripts/deploy.sh"',
        ),
        join_lines(
            '    : > "$deploy_dir/scripts/deploy.sh"',
            '    : > "$deploy_dir/scripts/moltis-runtime-attestation.sh"',
            '    chmod +x "$deploy_dir/scripts/prepare-moltis-runtime-config.sh" "$deploy_dir/scripts/moltis-version.sh" "$deploy_dir/scripts/deploy.sh" "$deploy_dir/scripts/moltis-runtime-attestation.sh"',
        ),
        "unit failure json attestation",
    )
    replace_once(
        path,
        join_lines(
            '    cat > "$scripts_dir/deploy.sh" <<\'EOF\'',
            '#!/bin/bash',
            'exit 0',
            'EOF',
            '    chmod +x "$scripts_dir/prepare-moltis-runtime-config.sh" "$scripts_dir/moltis-version.sh" "$scripts_dir/deploy.sh"',
        ),
        join_lines(
            '    cat > "$scripts_dir/deploy.sh" <<\'EOF\'',
            '#!/bin/bash',
            'exit 0',
            'EOF',
            '    : > "$scripts_dir/moltis-runtime-attestation.sh"',
            '    chmod +x "$scripts_dir/prepare-moltis-runtime-config.sh" "$scripts_dir/moltis-version.sh" "$scripts_dir/deploy.sh" "$scripts_dir/moltis-runtime-attestation.sh"',
        ),
        "unit env-as-data attestation",
    )
    replace_once(
        path,
        join_lines(
            '    if ! output_json="$(bash "$TRACKED_DEPLOY_SCRIPT" \\',
            '        --deploy-path "$deploy_dir" \\',
        ),
        join_lines(
            '    if ! output_json="$(MOLTIS_RUNTIME_CONFIG_DIR_ALLOWLIST="$runtime_dir" bash "$TRACKED_DEPLOY_SCRIPT" \\',
            '        --deploy-path "$deploy_dir" \\',
        ),
        "unit env-as-data allowlist",
    )
    replace_once(
        path,
        join_lines(
            "    test_tracked_deploy_workflows_use_shared_script_entrypoint",
            "    test_tracked_deploy_workflows_pass_remote_args_without_inline_shell_string",
        ),
        join_lines(
            "    test_tracked_deploy_workflows_use_shared_script_entrypoint",
            "    test_deploy_script_verifies_live_moltis_runtime_contract",
            "    test_deploy_script_force_recreates_moltis_runtime_on_rollout",
            "    test_tracked_deploy_workflows_pass_remote_args_without_inline_shell_string",
        ),
        "unit run_all_tests",
    )
    changed.append("tests/unit/test_deploy_workflow_guards.sh")

    return changed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-repo",
        default=str(pathlib.Path(__file__).resolve().parents[3]),
        help="Path to the 031 worktree that already contains the proven PR1 source deltas.",
    )
    parser.add_argument(
        "--target-tree",
        required=True,
        help="Path to the mainline checkout tree that should receive the PR1 carrier.",
    )
    parser.add_argument(
        "--emit-patch",
        help="Optional path for a unified diff between the original target tree and the transformed tree.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_repo = pathlib.Path(args.source_repo).resolve()
    target_root = pathlib.Path(args.target_tree).resolve()
    if not source_repo.exists():
        raise SystemExit(f"source repo not found: {source_repo}")
    if not target_root.exists():
        raise SystemExit(f"target tree not found: {target_root}")

    with tempfile.TemporaryDirectory(prefix="pr1-main-carrier-before-") as tmp:
        before_root = pathlib.Path(tmp) / "before"
        shutil.copytree(target_root, before_root, dirs_exist_ok=True)
        changed = apply_runtime_carrier(source_repo, target_root)
        patch_text = build_patch(before_root, target_root)
        if args.emit_patch:
            emit_path = pathlib.Path(args.emit_patch).resolve()
            emit_path.parent.mkdir(parents=True, exist_ok=True)
            write_text(emit_path, patch_text)
        print("\n".join(changed))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"apply_pr1_main_carrier.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
