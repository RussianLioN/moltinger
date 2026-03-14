#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/beads-normalize-issues-jsonl.sh"

seed_noncanonical_issues_file() {
    local issues_path="$1"

    cat > "$issues_path" <<'EOF'
{"id":"demo-1","title":"Seed issue","status":"open","dependencies":[{"issue_id":"demo-1","depends_on_id":"demo-blocked","type":"blocks","created_at":"2026-03-14T11:00:00+03:00","created_by":"tester"},{"issue_id":"demo-1","depends_on_id":"demo-parent","type":"parent-child","created_at":"2026-03-14T10:00:00+03:00","created_by":"tester"}]}
EOF
}

test_normalize_reorders_dependencies_deterministically() {
    test_start "beads_normalize_reorders_dependencies_deterministically"

    local fixture_root issues_path first_type second_type
    fixture_root="$(mktemp -d /tmp/beads-normalize-unit.XXXXXX)"
    issues_path="${fixture_root}/issues.jsonl"

    seed_noncanonical_issues_file "${issues_path}"
    "${NORMALIZE_SCRIPT}" --path "${issues_path}" >/dev/null

    first_type="$(jq -r '.dependencies[0].type' "${issues_path}")"
    second_type="$(jq -r '.dependencies[1].type' "${issues_path}")"

    assert_eq "parent-child" "${first_type}" "Normalization must place parent-child before later block dependencies"
    assert_eq "blocks" "${second_type}" "Normalization must keep the block dependency after the parent-child dependency"

    rm -rf "${fixture_root}"
    test_pass
}

test_check_mode_detects_and_clears_noncanonical_order() {
    test_start "beads_normalize_check_mode_detects_and_clears_noncanonical_order"

    local fixture_root issues_path output rc post_output post_rc
    fixture_root="$(mktemp -d /tmp/beads-normalize-unit.XXXXXX)"
    issues_path="${fixture_root}/issues.jsonl"

    seed_noncanonical_issues_file "${issues_path}"

    output="$(
        set +e
        "${NORMALIZE_SCRIPT}" --check --path "${issues_path}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "${rc}" "Check mode must fail when dependency order is non-canonical"
    assert_contains "${output}" "Non-canonical dependency order" "Check mode must explain why it failed"

    "${NORMALIZE_SCRIPT}" --path "${issues_path}" >/dev/null

    post_output="$(
        set +e
        "${NORMALIZE_SCRIPT}" --check --path "${issues_path}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    post_rc="$(printf '%s\n' "${post_output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${post_rc}" "Check mode must pass after normalization"

    rm -rf "${fixture_root}"
    test_pass
}

test_normalize_preserves_non_dependency_escape_sequences() {
    test_start "beads_normalize_preserves_non_dependency_escape_sequences"

    local fixture_root issues_path line
    fixture_root="$(mktemp -d /tmp/beads-normalize-unit.XXXXXX)"
    issues_path="${fixture_root}/issues.jsonl"

    cat > "${issues_path}" <<'EOF'
{"id":"demo-2","title":"Escaped demo","description":"Keep \\u003e and \\u0026 exactly as-is","dependencies":[{"issue_id":"demo-2","depends_on_id":"demo-blocked","type":"blocks","created_at":"2026-03-14T11:00:00+03:00","created_by":"tester"},{"issue_id":"demo-2","depends_on_id":"demo-parent","type":"parent-child","created_at":"2026-03-14T10:00:00+03:00","created_by":"tester"}]}
EOF

    "${NORMALIZE_SCRIPT}" --path "${issues_path}" >/dev/null
    line="$(cat "${issues_path}")"

    assert_contains "${line}" '\\u003e' "Normalization must preserve escaped non-dependency text outside the dependencies array"
    assert_contains "${line}" '\\u0026' "Normalization must preserve escaped ampersand text outside the dependencies array"

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ ! -x "${NORMALIZE_SCRIPT}" ]]; then
        test_fail "Normalizer script missing or not executable: ${NORMALIZE_SCRIPT}"
        generate_report
        return 1
    fi

    test_normalize_reorders_dependencies_deterministically
    test_check_mode_detects_and_clears_noncanonical_order
    test_normalize_preserves_non_dependency_escape_sequences
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
