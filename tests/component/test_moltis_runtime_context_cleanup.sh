#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

CLEANUP_SCRIPT="$PROJECT_ROOT/scripts/moltis-runtime-context-cleanup.sh"

run_component_moltis_runtime_context_cleanup_tests() {
    start_timer

    local tmp_dir runtime_home
    tmp_dir="$(mktemp -d /tmp/moltis-runtime-context-cleanup.XXXXXX)"
    runtime_home="$tmp_dir/runtime-home"

    mkdir -p \
        "$runtime_home/oauth-runtime-test-config-v1" \
        "$runtime_home/oauth-runtime-test-data-v1" \
        "$runtime_home/oauth-config" \
        "$runtime_home/sessions" \
        "$runtime_home/memory"

    printf 'runtime test config\n' > "$runtime_home/oauth-runtime-test-config-v1/moltis.toml"
    printf 'runtime test data\n' > "$runtime_home/oauth-runtime-test-data-v1/logs.jsonl"
    printf 'runtime test backup\n' > "$runtime_home/oauth-config/moltis.toml.runtime-test.bak"
    printf 'real oauth token\n' > "$runtime_home/oauth-config/oauth_tokens.json"
    printf 'live session\n' > "$runtime_home/sessions/main.jsonl"
    printf 'knowledge\n' > "$runtime_home/memory/project-knowledge.md"

    test_start "component_runtime_context_cleanup_dry_run_reports_only_known_stale_artifacts"
    if ! bash "$CLEANUP_SCRIPT" --runtime-home "$runtime_home" > "$tmp_dir/dry-run.json"; then
        test_fail "Cleanup script dry-run failed on fixture runtime home"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ "$(jq -r '.mode' "$tmp_dir/dry-run.json")" != "dry-run" ]] || \
       [[ "$(jq -r '.candidate_count' "$tmp_dir/dry-run.json")" != "3" ]] || \
       [[ "$(jq -r '.removed_count' "$tmp_dir/dry-run.json")" != "0" ]] || \
       ! jq -e '.candidates[] | select(endswith("/oauth-runtime-test-config-v1"))' "$tmp_dir/dry-run.json" >/dev/null || \
       ! jq -e '.candidates[] | select(endswith("/oauth-runtime-test-data-v1"))' "$tmp_dir/dry-run.json" >/dev/null || \
       ! jq -e '.candidates[] | select(endswith("/oauth-config/moltis.toml.runtime-test.bak"))' "$tmp_dir/dry-run.json" >/dev/null || \
       [[ ! -d "$runtime_home/oauth-runtime-test-config-v1" ]] || \
       [[ ! -d "$runtime_home/oauth-runtime-test-data-v1" ]] || \
       [[ ! -f "$runtime_home/oauth-config/moltis.toml.runtime-test.bak" ]]; then
        test_fail "Dry-run must report only the allowlisted stale runtime-test artifacts without deleting them"
        rm -rf "$tmp_dir"
        return
    fi
    test_pass

    test_start "component_runtime_context_cleanup_apply_removes_only_allowlisted_stale_artifacts"
    if ! bash "$CLEANUP_SCRIPT" --runtime-home "$runtime_home" --apply > "$tmp_dir/apply.json"; then
        test_fail "Cleanup script apply mode failed on fixture runtime home"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ "$(jq -r '.mode' "$tmp_dir/apply.json")" != "apply" ]] || \
       [[ "$(jq -r '.removed_count' "$tmp_dir/apply.json")" != "3" ]] || \
       [[ -e "$runtime_home/oauth-runtime-test-config-v1" ]] || \
       [[ -e "$runtime_home/oauth-runtime-test-data-v1" ]] || \
       [[ -e "$runtime_home/oauth-config/moltis.toml.runtime-test.bak" ]] || \
       [[ ! -f "$runtime_home/oauth-config/oauth_tokens.json" ]] || \
       [[ ! -f "$runtime_home/sessions/main.jsonl" ]] || \
       [[ ! -f "$runtime_home/memory/project-knowledge.md" ]]; then
        test_fail "Apply mode must delete only stale runtime-test artifacts and keep active runtime state"
        rm -rf "$tmp_dir"
        return
    fi
    test_pass

    rm -rf "$tmp_dir"
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_runtime_context_cleanup_tests
fi
