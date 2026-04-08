#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

CHECK_SCRIPT="$PROJECT_ROOT/scripts/gitops-check-managed-surface.sh"

setup_component_gitops_check_managed_surface() {
    require_commands_or_skip bash mktemp sha256sum awk wc chmod mkdir cat cp rm find || return 2
    return 0
}

run_component_gitops_check_managed_surface_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_gitops_check_managed_surface
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    test_start "component_gitops_check_managed_surface_batches_remote_hashes_and_reports_summary"

    local fixture_root project_root remote_root bin_dir ssh_args state_file output_log
    fixture_root="$(secure_temp_dir gitops-check-managed-surface)"
    project_root="$fixture_root/project"
    remote_root="$fixture_root/remote"
    bin_dir="$fixture_root/bin"
    ssh_args="$fixture_root/ssh-args.log"
    state_file="$fixture_root/state.env"
    output_log="$fixture_root/output.log"

    mkdir -p \
        "$project_root/config/prometheus" \
        "$project_root/scripts/helpers" \
        "$project_root/systemd" \
        "$remote_root/config/prometheus" \
        "$remote_root/scripts/helpers" \
        "$remote_root/systemd" \
        "$bin_dir"

    printf 'compose\n' > "$project_root/docker-compose.yml"
    printf 'compose-prod\n' > "$project_root/docker-compose.prod.yml"
    printf 'moltis = true\n' > "$project_root/config/moltis.toml"
    printf '{"mcp":true}\n' > "$project_root/config/mcp-servers.json"
    printf 'scrape_interval: 15s\n' > "$project_root/config/prometheus/prometheus.yml"
    printf '#!/usr/bin/env bash\necho alpha\n' > "$project_root/scripts/alpha.sh"
    printf '#!/usr/bin/env bash\necho helper\n' > "$project_root/scripts/helpers/helper.sh"
    printf '[Unit]\nDescription=test\n' > "$project_root/systemd/moltis.service"

    cp "$project_root/docker-compose.yml" "$remote_root/docker-compose.yml"
    printf 'compose-prod drift\n' > "$remote_root/docker-compose.prod.yml"
    cp "$project_root/config/moltis.toml" "$remote_root/config/moltis.toml"
    printf 'scrape_interval: 30s\n' > "$remote_root/config/prometheus/prometheus.yml"
    cp "$project_root/scripts/alpha.sh" "$remote_root/scripts/alpha.sh"
    printf '#!/usr/bin/env bash\necho helper drift\n' > "$remote_root/scripts/helpers/helper.sh"
    cp "$project_root/systemd/moltis.service" "$remote_root/systemd/moltis.service"

    cat > "$bin_dir/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args_file="${FAKE_SSH_ARGS_FILE:?}"
printf '%s\n' "$@" > "$args_file"

if [[ $# -ne 2 ]]; then
    echo "fake ssh expected exactly 2 arguments after host serialization, got $#." >&2
    exit 97
fi

if [[ "$2" != "bash -seu" ]]; then
    echo "fake ssh expected constant remote command 'bash -seu', got '$2'." >&2
    exit 98
fi

exec bash -seu
EOF
    chmod +x "$bin_dir/ssh"

    if ! PATH="$bin_dir:$PATH" \
        FAKE_SSH_ARGS_FILE="$ssh_args" \
        bash "$CHECK_SCRIPT" \
            --ssh-user "deploy" \
            --ssh-host "example.com" \
            --deploy-path "$remote_root" \
            --project-root "$project_root" \
            --state-file "$state_file" > "$output_log" 2>&1; then
        test_fail "gitops-check-managed-surface.sh should succeed against fake ssh"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    assert_file_exists "$state_file" "Batch checker should emit a state file for the workflow"
    # shellcheck disable=SC1090
    source "$state_file"

    assert_eq "8" "${COMPARED_FILES:-}" "Batch checker should compare every managed file in one manifest"
    assert_eq "4" "${COMPLIANT_COUNT:-}" "Batch checker should count compliant files"
    assert_eq "4" "${PENDING_COUNT:-}" "Batch checker should count pending sync entries"
    assert_eq "1" "${MISSING_COUNT:-}" "Batch checker should count missing remote files separately"
    assert_eq "true" "${PENDING_SYNC:-}" "Batch checker should mark pending sync when hashes differ or files are missing"

    assert_contains "$(cat "$output_log")" "Fetching remote hashes in one SSH roundtrip" "Batch checker should advertise the single-roundtrip phase in logs"
    assert_contains "$(cat "$output_log")" "config/prometheus/prometheus.yml pending sync" "Batch checker should inspect nested config files"
    assert_contains "$(cat "$output_log")" "scripts/helpers/helper.sh pending sync" "Batch checker should inspect nested script files"
    assert_contains "$(cat "$output_log")" "Managed surface summary: compared=8 compliant=4 pending=4 missing_on_server=1" "Batch checker should emit a summary line with counts"

    if [[ "$(wc -l < "$ssh_args")" -ne 2 ]] || [[ "$(sed -n '2p' "$ssh_args")" != "bash -seu" ]]; then
        test_fail "Batch checker must use a single constant remote ssh command"
        rm -rf "$fixture_root"
        generate_report
        return
    fi

    rm -rf "$fixture_root"
    test_pass
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_gitops_check_managed_surface_tests
fi
