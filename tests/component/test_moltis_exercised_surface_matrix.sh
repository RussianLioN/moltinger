#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SURFACE_MATRIX_SCRIPT="$PROJECT_ROOT/scripts/moltis-exercised-surface-matrix.sh"

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

run_component_moltis_exercised_surface_matrix_tests() {
    start_timer

    local tmp_dir fake_api smoke_calls
    tmp_dir="$(secure_temp_dir moltis-exercised-surface-matrix)"
    fake_api="$tmp_dir/fake-test-moltis-api.sh"
    smoke_calls="$tmp_dir/smoke-calls.log"

    write_fake_api_smoke "$fake_api"
    export FAKE_SMOKE_CALLS="$smoke_calls"

    test_start "component_moltis_exercised_surface_matrix_runs_browser_search_and_repo_context_contracts"
    : > "$smoke_calls"
    if ! MOLTIS_TEST_API_SCRIPT="$fake_api" CHAT_WAIT_MS=654 \
        bash "$SURFACE_MATRIX_SCRIPT" --base-url http://localhost:13131 >"$tmp_dir/output.log"; then
        test_fail "Exercised surface matrix should succeed against the fake smoke runner"
        return
    fi

    if [[ "$(grep -c '^PROMPT=' "$smoke_calls")" != "3" ]] || \
       ! grep -Fq 'PROMPT=Используй browser, открой https://docs.moltis.org/ и ответь только заголовком страницы.' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_REPLY_TEXT=Introduction - Moltis Documentation' "$smoke_calls" || \
       ! grep -Fq 'PROMPT=Используй search и найди официальный домен документации Moltis. Ответь только доменом.' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_REPLY_TEXT=docs.moltis.org' "$smoke_calls" || \
       ! grep -Fq 'PROMPT=Используй memory_search. В каком пути внутри runtime Moltis находится checkout репозитория? Ответь только одним путем.' "$smoke_calls" || \
       ! grep -Fq 'EXPECTED_REPLY_TEXT=/server' "$smoke_calls" || \
       [[ "$(grep -c '^EXPECTED_PROVIDER=openai-codex$' "$smoke_calls")" != "3" ]] || \
       [[ "$(grep -c '^EXPECTED_MODEL=openai-codex::gpt-5.4$' "$smoke_calls")" != "3" ]] || \
       [[ "$(grep -c '^CHAT_WAIT_MS=654$' "$smoke_calls")" != "3" ]]; then
        test_fail "Surface matrix must exercise browser/search/repo-context with the tracked provider/model contract"
        return
    fi
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_exercised_surface_matrix_tests
fi
