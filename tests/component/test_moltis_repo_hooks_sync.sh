#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/moltis-repo-hooks-sync.sh"

setup_component_moltis_repo_hooks_sync() {
    require_commands_or_skip bash mktemp sort cp mv rm || return 2
    return 0
}

run_component_moltis_repo_hooks_sync_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_repo_hooks_sync
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local fixture_root source_root target_root manifest_path
    fixture_root="$(secure_temp_dir moltis-repo-hooks-sync)"
    source_root="$fixture_root/source"
    target_root="$fixture_root/target"
    manifest_path="$fixture_root/manifest.txt"

    mkdir -p "$source_root/telegram-safe-llm-guard" "$source_root/observer-hook" "$source_root/ignored-dir"
    mkdir -p "$target_root/legacy-hook" "$target_root/manual-hook"

    cat >"$source_root/telegram-safe-llm-guard/HOOK.md" <<'EOF'
+++
name = "telegram-safe-llm-guard"
+++
EOF
    printf 'helper\n' >"$source_root/telegram-safe-llm-guard/readme.txt"

    cat >"$source_root/observer-hook/HOOK.md" <<'EOF'
+++
name = "observer-hook"
+++
EOF

    printf 'not-a-hook\n' >"$source_root/ignored-dir/readme.txt"
    printf 'old\n' >"$target_root/legacy-hook/HOOK.md"
    printf 'keep-me\n' >"$target_root/manual-hook/HOOK.md"
    printf 'legacy-hook\n' >"$manifest_path"

    test_start "component_moltis_repo_hooks_sync_copies_repo_managed_hooks_and_sidecars"
    bash "$SYNC_SCRIPT" \
        --source-root "$source_root" \
        --target-root "$target_root" \
        --manifest "$manifest_path"
    assert_file_exists "$target_root/telegram-safe-llm-guard/HOOK.md" "Repo-managed telegram-safe hook should be installed into runtime target"
    assert_file_exists "$target_root/telegram-safe-llm-guard/readme.txt" "Repo-managed hook sidecar files should be copied together with HOOK.md"
    assert_file_exists "$target_root/observer-hook/HOOK.md" "Every repo hook with HOOK.md should be installed"
    if [[ -e "$target_root/ignored-dir" ]]; then
        test_fail "Directories without HOOK.md must not be treated as runtime hooks"
    fi
    assert_file_exists "$manifest_path" "Sync should leave a manifest of repo-managed installed hooks"
    assert_contains "$(cat "$manifest_path")" "telegram-safe-llm-guard" "Manifest should record installed repo-managed hooks"
    assert_contains "$(cat "$manifest_path")" "observer-hook" "Manifest should list every repo-managed hook"
    test_pass

    test_start "component_moltis_repo_hooks_sync_removes_only_previous_repo_managed_hooks"
    if [[ -e "$target_root/legacy-hook" ]]; then
        test_fail "Stale repo-managed runtime hook should be removed when it disappears from source root"
    fi
    assert_file_exists "$target_root/manual-hook/HOOK.md" "Sync must preserve runtime hooks that are not listed in the repo-managed manifest"
    test_pass

    test_start "component_moltis_repo_hooks_sync_can_prune_unmanaged_runtime_hooks_when_requested"
    mkdir -p "$target_root/manual-hook"
    printf 'keep-me\n' >"$target_root/manual-hook/HOOK.md"
    MOLTIS_RUNTIME_HOOKS_PRUNE_UNMANAGED=1 bash "$SYNC_SCRIPT" \
        --source-root "$source_root" \
        --target-root "$target_root" \
        --manifest "$manifest_path"
    if [[ -e "$target_root/manual-hook" ]]; then
        test_fail "Strict managed mode should remove runtime hooks that are not present in the repo source root"
    fi
    assert_file_exists "$target_root/telegram-safe-llm-guard/HOOK.md" "Strict managed mode must keep repo-managed hooks installed"
    test_pass

    local auto_fixture_root auto_source_root auto_target_root auto_manifest_path
    auto_fixture_root="$(secure_temp_dir moltis-repo-hooks-sync-auto-manifest)"
    auto_source_root="$auto_fixture_root/source"
    auto_target_root="$auto_fixture_root/runtime-hooks"
    auto_manifest_path="$auto_fixture_root/.repo-managed-hooks.txt"

    mkdir -p "$auto_source_root/telegram-safe-llm-guard"
    cat >"$auto_source_root/telegram-safe-llm-guard/HOOK.md" <<'EOF'
+++
name = "telegram-safe-llm-guard"
+++
EOF

    test_start "component_moltis_repo_hooks_sync_derives_manifest_from_target_root_when_not_explicit"
    bash "$SYNC_SCRIPT" \
        --source-root "$auto_source_root" \
        --target-root "$auto_target_root"
    assert_file_exists "$auto_manifest_path" "Sync should derive a stable manifest path next to the runtime target root when --manifest is omitted"
    assert_contains "$(cat "$auto_manifest_path")" "telegram-safe-llm-guard" "Derived manifest should still record repo-managed installed hooks"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_repo_hooks_sync_tests
fi
