#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

PROFILE_SCRIPT="$PROJECT_ROOT/scripts/moltis-codex-update-profile.sh"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/codex-update-skill"

setup_component_moltis_codex_update_profile() {
    require_commands_or_skip jq python3 || return 2
    return 0
}

run_component_moltis_codex_update_profile_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_component_moltis_codex_update_profile
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    local output work_dir invalid_file exit_code

    test_start "component_moltis_codex_update_profile_validate_accepts_stable_profile_contract"
    output="$(bash "$PROFILE_SCRIPT" validate --file "$FIXTURE_DIR/project-profile-basic.json" --json)"
    assert_eq "true" "$(jq -r '.ok' <<<"$output")" "validate should accept the basic fixture"
    assert_eq "moltinger-default" "$(jq -r '.profile_id' <<<"$output")" "validate should return the normalized profile id"
    test_pass

    test_start "component_moltis_codex_update_profile_load_returns_normalized_profile_payload"
    output="$(bash "$PROFILE_SCRIPT" load --file "$FIXTURE_DIR/project-profile-basic.json" --json)"
    assert_eq "true" "$(jq -r '.ok' <<<"$output")" "load should succeed for a valid profile"
    assert_eq "Moltinger" "$(jq -r '.profile.project_name' <<<"$output")" "load should expose normalized project name"
    assert_eq "Проверить worktree-процессы Moltinger" "$(jq -r '.profile.relevance_rules[0].title_ru' <<<"$output")" "load should preserve normalized rule titles"
    assert_contains "$(jq -r '.profile.relevance_rules[0].rationale_ru' <<<"$output")" "Проект" "load should preserve Russian rationale"
    assert_eq "doc-topology-review" "$(jq -r '.profile.relevance_rules[0].recommendation_template_id' <<<"$output")" "load should preserve template linkage"
    assert_eq "Сверить обновление Codex CLI с профилем проекта Moltinger" "$(jq -r '.profile.fallback_recommendation.title_ru' <<<"$output")" "load should expose fallback recommendation contract"
    test_pass

    test_start "component_moltis_codex_update_profile_rejects_invalid_profile_shape"
    work_dir="$(secure_temp_dir moltis-codex-update-profile-invalid)"
    invalid_file="$work_dir/invalid-profile.json"
    cat > "$invalid_file" <<'JSON'
{"schema_version":"wrong","profile_id":"","project_name":"","traits":[],"relevance_rules":[]}
JSON
    set +e
    output="$(bash "$PROFILE_SCRIPT" validate --file "$invalid_file" --json)"
    exit_code=$?
    set -e
    if [[ $exit_code -eq 0 ]]; then
        test_fail "validate should fail for an invalid profile"
    else
        assert_contains "$output" "schema_version" "Invalid profile output should explain contract violations"
        test_pass
    fi

    test_start "component_moltis_codex_update_profile_rejects_missing_template_reference"
    invalid_file="$work_dir/invalid-template-ref.json"
    cat > "$invalid_file" <<'JSON'
{
  "schema_version": "codex-update-project-profile/v1",
  "profile_id": "broken",
  "project_name": "Broken",
  "traits": ["docs"],
  "relevance_rules": [
    {
      "id": "rule-1",
      "keywords": ["resume"],
      "title_ru": "Проверить resume",
      "rationale_ru": "Нужно проверить resume guidance.",
      "next_steps_ru": ["Сверить changelog."],
      "recommendation_template_id": "missing-template"
    }
  ],
  "recommendation_templates": []
}
JSON
    set +e
    output="$(bash "$PROFILE_SCRIPT" validate --file "$invalid_file" --json)"
    exit_code=$?
    set -e
    if [[ $exit_code -eq 0 ]]; then
        test_fail "validate should fail for an unknown recommendation template reference"
    else
        assert_contains "$output" "recommendation_template_id" "Invalid template linkage should be reported"
        test_pass
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_moltis_codex_update_profile_tests
fi
