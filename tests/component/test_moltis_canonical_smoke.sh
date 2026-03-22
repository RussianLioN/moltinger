#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

CANONICAL_SMOKE_SCRIPT="$PROJECT_ROOT/scripts/moltis-canonical-smoke.sh"

write_fake_docker() {
    local output_path="$1"
    cat > "$output_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    inspect)
        if [[ "${2:-}" == "--format" ]]; then
            printf 'healthy\n'
            exit 0
        fi
        ;;
    exec)
        shift
        container="${1:-}"
        shift || true
        if [[ "$container" == "moltis" && "${1:-}" == "moltis" && "${2:-}" == "auth" && "${3:-}" == "status" ]]; then
            printf 'openai-codex [valid 1h]\n'
            exit 0
        fi
        ;;
    restart)
        printf 'restart %s\n' "${2:-}" >> "${FAKE_DOCKER_LOG:?}"
        exit 0
        ;;
esac

printf 'unexpected docker invocation: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "$output_path"
}

write_fake_curl() {
    local output_path="$1"
    cat > "$output_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '200'
EOF
    chmod +x "$output_path"
}

write_fake_api_smoke() {
    local output_path="$1"
    cat > "$output_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'PROMPT=%s\n' "${1:-}"
    printf 'MOLTIS_URL=%s\n' "${MOLTIS_URL:-}"
    printf 'EXPECTED_PROVIDER=%s\n' "${EXPECTED_PROVIDER:-}"
    printf 'EXPECTED_MODEL=%s\n' "${EXPECTED_MODEL:-}"
    printf 'EXPECTED_REPLY_TEXT=%s\n' "${EXPECTED_REPLY_TEXT:-}"
    printf 'CHAT_WAIT_MS=%s\n' "${CHAT_WAIT_MS:-}"
    printf -- '---\n'
} >> "${FAKE_SMOKE_CALLS:?}"
EOF
    chmod +x "$output_path"
}

run_component_moltis_canonical_smoke_tests() {
    start_timer

    local tmp_dir fake_bin fake_docker fake_curl fake_api smoke_calls docker_log old_path
    tmp_dir="$(secure_temp_dir moltis-canonical-smoke)"
    fake_bin="$tmp_dir/bin"
    mkdir -p "$fake_bin"
    fake_docker="$fake_bin/docker"
    fake_curl="$fake_bin/curl"
    fake_api="$tmp_dir/fake-test-moltis-api.sh"
    smoke_calls="$tmp_dir/smoke-calls.log"
    docker_log="$tmp_dir/docker.log"

    write_fake_docker "$fake_docker"
    write_fake_curl "$fake_curl"
    write_fake_api_smoke "$fake_api"

    old_path="$PATH"
    export PATH="$fake_bin:$PATH"
    export FAKE_DOCKER_LOG="$docker_log"
    export FAKE_SMOKE_CALLS="$smoke_calls"

    test_start "component_moltis_canonical_smoke_forwards_expected_provider_contract"
    : > "$smoke_calls"
    : > "$docker_log"
    if ! MOLTIS_TEST_API_SCRIPT="$fake_api" CHAT_WAIT_MS=321 \
        bash "$CANONICAL_SMOKE_SCRIPT" --base-url http://localhost:13131 --container moltis > "$tmp_dir/initial.log"; then
        test_fail "Canonical smoke should succeed against the fake healthy runtime"
        PATH="$old_path"
        return
    fi

    if [[ "$(grep -c '^PROMPT=' "$smoke_calls")" != "1" ]] || \
       [[ -s "$docker_log" ]] || \
       ! grep -Fq 'PROMPT=Reply with exactly OK and nothing else.' "$smoke_calls" || \
       ! grep -Fq 'MOLTIS_URL=http://localhost:13131' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_PROVIDER=openai-codex' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_MODEL=openai-codex::gpt-5.4' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_REPLY_TEXT=OK' "$smoke_calls" || \
       ! grep -Fq 'CHAT_WAIT_MS=321' "$smoke_calls"; then
        test_fail "Canonical smoke must forward the tracked provider/model/reply contract into test-moltis-api.sh without restarting by default"
        PATH="$old_path"
        return
    fi
    test_pass

    test_start "component_moltis_canonical_smoke_restart_survival_repeats_proof"
    : > "$smoke_calls"
    : > "$docker_log"
    if ! MOLTIS_TEST_API_SCRIPT="$fake_api" \
        bash "$CANONICAL_SMOKE_SCRIPT" --base-url http://localhost:13131 --container moltis --restart-survival > "$tmp_dir/restart.log"; then
        test_fail "Canonical smoke should succeed when restart-survival is requested"
        PATH="$old_path"
        return
    fi

    if [[ "$(grep -c '^PROMPT=' "$smoke_calls")" != "2" ]] || \
       [[ "$(grep -c '^restart moltis$' "$docker_log")" != "1" ]]; then
        test_fail "Restart-survival proof must restart the target container once and rerun the canonical chat proof twice"
        PATH="$old_path"
        return
    fi
    test_pass

    PATH="$old_path"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_canonical_smoke_tests
fi
