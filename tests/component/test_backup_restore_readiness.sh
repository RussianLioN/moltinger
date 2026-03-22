#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup-moltis-enhanced.sh"

create_fake_docker_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "$fake_bin"
    cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf 'Docker version 27.0.0, build fake\n'
    ;;
  ps)
    exit 0
    ;;
  inspect)
    exit 1
    ;;
  *)
    printf 'unsupported fake docker command: %s\n' "${1:-}" >&2
    exit 1
    ;;
esac
EOF
    chmod +x "${fake_bin}/docker"
    printf '%s\n' "$fake_bin"
}

run_component_backup_restore_readiness_tests() {
    start_timer

    test_start "component_backup_restore_check_requires_runtime_files"

    local fixture_root fake_bin project_dir backup_dir backup_conf backup_json backup_path extract_dir runtime_config_dir runtime_home_dir
    fixture_root="$(mktemp -d /tmp/moltis-backup-component.XXXXXX)"
    fake_bin="$(create_fake_docker_bin "$fixture_root")"
    project_dir="${fixture_root}/project"
    backup_dir="${fixture_root}/backups"
    extract_dir="${fixture_root}/extract"
    runtime_config_dir="${fixture_root}/runtime-config"
    runtime_home_dir="${fixture_root}/runtime-home"

    mkdir -p "${project_dir}/config" "${project_dir}/data" "${runtime_config_dir}" "${runtime_home_dir}/sessions" "${runtime_home_dir}/memory"
    printf '[server]\nbind = "0.0.0.0"\n' > "${project_dir}/config/moltis.toml"
    printf 'state\n' > "${project_dir}/data/runtime.txt"
    printf 'MOLTIS_PASSWORD=test-password\n' > "${project_dir}/.env"
    printf 'services:\n  moltis:\n    image: ghcr.io/moltis-org/moltis:v1.8.0\n' > "${project_dir}/docker-compose.yml"
    printf 'services:\n  moltis:\n    image: ghcr.io/moltis-org/moltis:v1.8.0\n' > "${project_dir}/docker-compose.prod.yml"
    printf 'oauth\n' > "${runtime_config_dir}/oauth_tokens.json"
    printf 'providers\n' > "${runtime_config_dir}/provider_keys.json"
    printf 'session\n' > "${runtime_home_dir}/sessions/main.jsonl"
    printf 'knowledge\n' > "${runtime_home_dir}/memory/project-knowledge.md"

    backup_conf="${fixture_root}/backup.conf"
    cat > "$backup_conf" <<EOF
RETENTION_DAYS=30
RETENTION_WEEKS=12
RETENTION_MONTHS=12
ENCRYPTION_ENABLED=false
BACKUP_DIR="${backup_dir}"
BACKUP_CONFIG_DIR="${project_dir}/config"
BACKUP_DATA_DIR="${project_dir}/data"
BACKUP_ENV_FILE="${project_dir}/.env"
BACKUP_COMPOSE_FILE_MAIN="${project_dir}/docker-compose.yml"
BACKUP_COMPOSE_FILE_PROD="${project_dir}/docker-compose.prod.yml"
BACKUP_RUNTIME_CONFIG_DIR="${runtime_config_dir}"
BACKUP_RUNTIME_HOME_DIR="${runtime_home_dir}"
CLAWDIY_BACKUP_ENABLED=false
EOF

    backup_json="$(
        PATH="${fake_bin}:$PATH" \
        BACKUP_CONFIG="$backup_conf" \
        "$BACKUP_SCRIPT" --json backup
    )"
    backup_path="$(printf '%s' "$backup_json" | jq -r '.details.local_path // empty')"

    if [[ -z "$backup_path" || ! -f "$backup_path" ]]; then
        rm -rf "$fixture_root"
        test_fail "Backup script should create an archive for restore-readiness checks"
    fi

    PATH="${fake_bin}:$PATH" BACKUP_CONFIG="$backup_conf" "$BACKUP_SCRIPT" restore-check "$backup_path"

    mkdir -p "$extract_dir"
    tar -xzf "$backup_path" -C "$extract_dir"

    if [[ -f "${extract_dir}/.env" ]] && \
       [[ -f "${extract_dir}/docker-compose.yml" ]] && \
       [[ -f "${extract_dir}/docker-compose.prod.yml" ]] && \
       [[ -f "${extract_dir}/moltis-runtime-evidence-manifest.json" ]] && \
       [[ -f "${extract_dir}/moltis-runtime-config.tar.gz" ]] && \
       [[ -f "${extract_dir}/moltis-runtime-home.tar.gz" ]] && \
       jq -e '.restore_readiness.moltis.ready == true
         and .runtime_files.env_file.included == true
         and .runtime_files.compose_file_main.included == true
         and .runtime_files.compose_file_prod.included == true
         and .runtime_files.runtime_config_archive.included == true
         and .runtime_files.runtime_home_archive.included == true' "${extract_dir}/backup-metadata.json" >/dev/null 2>&1; then
        rm -rf "$fixture_root"
        test_pass
    else
        rm -rf "$fixture_root"
        test_fail "Backup archive should contain Moltis runtime state inventory and mark restore readiness as ready only when runtime state archives are included"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_backup_restore_readiness_tests
fi
