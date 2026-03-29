#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/moltis-repo-skills-sync.sh"

setup_component_moltis_repo_skills_sync() {
    require_commands_or_skip bash mktemp sort cp mv rm || return 2
    return 0
}

run_component_moltis_repo_skills_sync_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_repo_skills_sync
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local fixture_root source_root target_root manifest_path
    fixture_root="$(secure_temp_dir moltis-repo-skills-sync)"
    source_root="$fixture_root/source"
    target_root="$fixture_root/target"
    manifest_path="$fixture_root/manifest.txt"

    mkdir -p "$source_root/codex-update" "$source_root/telegram-learner" "$source_root/ignored-dir"
    mkdir -p "$target_root/legacy-skill" "$target_root/manual-skill"

    cat >"$source_root/codex-update/SKILL.md" <<'EOF'
---
name: codex-update
description: test
---
EOF
    printf 'helper\n' >"$source_root/codex-update/helper.txt"

    cat >"$source_root/telegram-learner/SKILL.md" <<'EOF'
---
name: telegram-learner
description: test
---
EOF

    printf 'not-a-skill\n' >"$source_root/ignored-dir/readme.txt"
    printf 'old\n' >"$target_root/legacy-skill/SKILL.md"
    printf 'keep-me\n' >"$target_root/manual-skill/SKILL.md"
    printf 'legacy-skill\n' >"$manifest_path"

    test_start "component_moltis_repo_skills_sync_copies_repo_managed_skills_and_sidecars"
    bash "$SYNC_SCRIPT" \
        --source-root "$source_root" \
        --target-root "$target_root" \
        --manifest "$manifest_path"
    assert_file_exists "$target_root/codex-update/SKILL.md" "Repo-managed codex-update skill should be installed into runtime target"
    assert_file_exists "$target_root/codex-update/helper.txt" "Repo-managed sidecar files should be copied together with SKILL.md"
    assert_file_exists "$target_root/telegram-learner/SKILL.md" "Every repo skill with SKILL.md should be installed"
    if [[ -e "$target_root/ignored-dir" ]]; then
        test_fail "Directories without SKILL.md must not be treated as runtime skills"
    fi
    assert_file_exists "$manifest_path" "Sync should leave a manifest of repo-managed installed skills"
    assert_contains "$(cat "$manifest_path")" "codex-update" "Manifest should record installed repo-managed skills"
    assert_contains "$(cat "$manifest_path")" "telegram-learner" "Manifest should list every repo-managed skill"
    test_pass

    test_start "component_moltis_repo_skills_sync_removes_only_previous_repo_managed_skills"
    if [[ -e "$target_root/legacy-skill" ]]; then
        test_fail "Stale repo-managed runtime skill should be removed when it disappears from source root"
    fi
    assert_file_exists "$target_root/manual-skill/SKILL.md" "Sync must preserve runtime skills that are not listed in the repo-managed manifest"
    test_pass

    test_start "component_moltis_repo_skills_sync_can_prune_unmanaged_runtime_skills_when_requested"
    mkdir -p "$target_root/manual-skill"
    printf 'keep-me\n' >"$target_root/manual-skill/SKILL.md"
    MOLTIS_RUNTIME_SKILLS_PRUNE_UNMANAGED=1 bash "$SYNC_SCRIPT" \
        --source-root "$source_root" \
        --target-root "$target_root" \
        --manifest "$manifest_path"
    if [[ -e "$target_root/manual-skill" ]]; then
        test_fail "Strict managed mode should remove runtime skills that are not present in the repo source root"
    fi
    assert_file_exists "$target_root/codex-update/SKILL.md" "Strict managed mode must keep repo-managed skills installed"
    test_pass

    local auto_fixture_root auto_source_root auto_target_root auto_manifest_path
    auto_fixture_root="$(secure_temp_dir moltis-repo-skills-sync-auto-manifest)"
    auto_source_root="$auto_fixture_root/source"
    auto_target_root="$auto_fixture_root/runtime-skills"
    auto_manifest_path="$auto_fixture_root/.repo-managed-skills.txt"

    mkdir -p "$auto_source_root/codex-update"
    cat >"$auto_source_root/codex-update/SKILL.md" <<'EOF'
---
name: codex-update
description: test
---
EOF

    test_start "component_moltis_repo_skills_sync_derives_manifest_from_target_root_when_not_explicit"
    bash "$SYNC_SCRIPT" \
        --source-root "$auto_source_root" \
        --target-root "$auto_target_root"
    assert_file_exists "$auto_manifest_path" "Sync should derive a stable manifest path next to the runtime target root when --manifest is omitted"
    assert_contains "$(cat "$auto_manifest_path")" "codex-update" "Derived manifest should still record repo-managed installed skills"
    test_pass

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_repo_skills_sync_tests
fi
