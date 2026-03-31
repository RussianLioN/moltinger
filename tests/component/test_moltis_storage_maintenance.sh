#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

STORAGE_SCRIPT="$PROJECT_ROOT/scripts/moltis-storage-maintenance.sh"

test_storage_reclaim_prunes_safe_targets_only() {
    test_start "storage maintenance should reclaim safe targets only"

    local tmp_dir mock_bin calls_file backup_dir output
    tmp_dir="$(mktemp -d)"
    mock_bin="$tmp_dir/bin"
    calls_file="$tmp_dir/calls.log"
    backup_dir="$tmp_dir/backups"
    mkdir -p "$mock_bin" "$backup_dir"
    : > "$calls_file"

    touch "$backup_dir/pre_deploy_20260328_010000.tar.gz"
    touch "$backup_dir/pre_deploy_20260328_010000.tar.gz.compose"
    touch "$backup_dir/pre_deploy_20260329_010000.tar.gz"
    touch "$backup_dir/pre_deploy_20260329_010000.tar.gz.compose"

    cat > "$mock_bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$CALLS_FILE"
if [[ "$1" == "volume" && "$2" == "ls" ]]; then
  printf '%s\n' "moltis-probe-data-1" "moltinger_ollama-data"
fi
exit 0
EOF

    cat > "$mock_bin/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'journalctl %s\n' "$*" >> "$CALLS_FILE"
if [[ "$1" == "--disk-usage" ]]; then
  printf 'Archived and active journals take up 1.5G in the file system.\n'
fi
exit 0
EOF

    cat > "$mock_bin/df" <<'EOF'
#!/usr/bin/env bash
cat <<OUT
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/mock 100 92 8 92% /var/lib/docker
OUT
EOF

    chmod +x "$mock_bin/docker" "$mock_bin/journalctl" "$mock_bin/df"

    output="$(
        PATH="$mock_bin:$PATH" \
        CALLS_FILE="$calls_file" \
        MOLTIS_STORAGE_BACKUP_DIR="$backup_dir" \
        MOLTIS_STORAGE_KEEP_PREDEPLOY_BACKUPS=1 \
        "$STORAGE_SCRIPT" --json reclaim
    )"

    assert_contains "$(cat "$calls_file")" "docker image prune -af --filter until=168h" "Expected image prune call"
    assert_contains "$(cat "$calls_file")" "docker builder prune -af --filter until=168h" "Expected builder prune call"
    assert_contains "$(cat "$calls_file")" "docker volume rm moltis-probe-data-1" "Expected ephemeral probe volume removal"
    if [[ "$(cat "$calls_file")" == *"docker volume rm moltinger_ollama-data"* ]]; then
        test_fail "Storage maintenance must not remove the Ollama data volume"
        rm -rf "$tmp_dir"
        return
    fi
    assert_contains "$(cat "$calls_file")" "journalctl --vacuum-size=1G" "Expected journal vacuum call"
    assert_contains "$output" "\"removed_backup_stems\"" "Expected JSON summary with backup trimming"

    rm -rf "$tmp_dir"
    test_pass
}

test_storage_reclaim_skips_while_deploy_mutex_is_active() {
    test_start "storage maintenance should skip reclaim while deploy mutex is active"

    local tmp_dir mock_bin calls_file mutex_meta output
    tmp_dir="$(mktemp -d)"
    mock_bin="$tmp_dir/bin"
    calls_file="$tmp_dir/calls.log"
    mutex_meta="$tmp_dir/deploy.lock.meta"
    mkdir -p "$mock_bin"
    : > "$calls_file"

    cat > "$mock_bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$CALLS_FILE"
exit 0
EOF

    cat > "$mock_bin/journalctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--disk-usage" ]]; then
  printf 'Archived and active journals take up 1.0G in the file system.\n'
fi
exit 0
EOF

    cat > "$mock_bin/df" <<'EOF'
#!/usr/bin/env bash
cat <<OUT
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/mock 100 75 25 75% /var/lib/docker
OUT
EOF

    chmod +x "$mock_bin/docker" "$mock_bin/journalctl" "$mock_bin/df"
    cat > "$mutex_meta" <<EOF
owner=test
expires_at=$(( $(date +%s) + 3600 ))
EOF

    output="$(
        PATH="$mock_bin:$PATH" \
        CALLS_FILE="$calls_file" \
        DEPLOY_MUTEX_PATH="${tmp_dir}/deploy.lock" \
        "$STORAGE_SCRIPT" --json reclaim
    )"

    assert_eq "0" "$(wc -l < "$calls_file" | tr -d ' ')" "No docker commands should run while deploy mutex is active"
    assert_contains "$output" "deploy-mutex-active" "Expected skipped reclaim marker in JSON output"

    rm -rf "$tmp_dir"
    test_pass
}

run_component_moltis_storage_maintenance_tests() {
    start_timer

    test_storage_reclaim_prunes_safe_targets_only
    test_storage_reclaim_skips_while_deploy_mutex_is_active

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_storage_maintenance_tests
fi
