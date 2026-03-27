#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

copy_hook_assets() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.githooks" "${repo_dir}/scripts"
    cp "${PROJECT_ROOT}/.githooks/_repo-local-path.sh" "${repo_dir}/.githooks/_repo-local-path.sh"
    cp "${PROJECT_ROOT}/.githooks/post-checkout" "${repo_dir}/.githooks/post-checkout"
    cp "${PROJECT_ROOT}/.githooks/post-merge" "${repo_dir}/.githooks/post-merge"
    chmod +x \
        "${repo_dir}/.githooks/_repo-local-path.sh" \
        "${repo_dir}/.githooks/post-checkout" \
        "${repo_dir}/.githooks/post-merge"
}

write_fake_localize_script() {
    local repo_dir="$1"

    cat > "${repo_dir}/scripts/beads-worktree-localize.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

target_path=""
output_format="human"
check_only="false"
bootstrap_source="__unset__"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      target_path="${2:-}"
      shift 2
      ;;
    --format)
      output_format="${2:-}"
      shift 2
      ;;
    --check)
      check_only="true"
      shift
      ;;
    --bootstrap-source)
      bootstrap_source="${2:-}"
      if [[ -z "${bootstrap_source}" ]]; then
        echo "[fake-localize] --bootstrap-source requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${check_only}" == "true" && "${output_format}" == "env" ]]; then
  printf 'schema=%q\n' "beads-localize/v1"
  printf 'worktree=%q\n' "${target_path}"
  printf 'state=%q\n' "partial_foundation"
  printf 'action=%q\n' "rebuild_local_foundation"
  printf 'db_path=%q\n' "${target_path}/.beads/dolt"
  printf 'message=%q\n' "fixture"
  printf 'notice=%q\n' ""
  printf 'bootstrap_source=%q\n' ""
  exit 0
fi

if [[ "${bootstrap_source}" == "__unset__" ]]; then
  echo "[fake-localize] expected --bootstrap-source on the mutation call" >&2
  exit 2
fi

printf 'applied bootstrap_source=%s\n' "${bootstrap_source}"
EOF

    cat > "${repo_dir}/scripts/git-topology-registry.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

    chmod +x \
        "${repo_dir}/scripts/beads-worktree-localize.sh" \
        "${repo_dir}/scripts/git-topology-registry.sh"
}

prepare_hook_fixture_repo() {
    local fixture_root="$1"
    local repo_dir=""

    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "hook-fixture")"
    copy_hook_assets "${repo_dir}"
    write_fake_localize_script "${repo_dir}"

    (
        cd "${repo_dir}"
        git config core.hooksPath .githooks
    )

    printf '%s\n' "${repo_dir}"
}

assert_not_contains_text() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if printf '%s\n' "${haystack}" | rg -q --fixed-strings -- "${needle}"; then
        test_fail "${message}"
    fi
}

run_hook_script() {
    local repo_dir="$1"
    local hook_name="$2"

    (
        cd "${repo_dir}"
        "./.githooks/${hook_name}" 2>&1
    )
}

test_post_checkout_hook_preserves_requested_bootstrap_source() {
    test_start "beads_git_hooks_post_checkout_preserves_requested_bootstrap_source"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/beads-git-hooks-unit.XXXXXX)"
    repo_dir="$(prepare_hook_fixture_repo "${fixture_root}")"

    output="$(
        set +e
        run_hook_script "${repo_dir}" "post-checkout"
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${rc}" "Post-checkout hook should stay non-blocking when helper env output includes bootstrap_source=''"
    assert_contains "${output}" 'applied bootstrap_source=origin/main' "Post-checkout hook should preserve its requested bootstrap source after eval"
    assert_not_contains_text "${output}" '--bootstrap-source requires a value' "Post-checkout hook must not clobber bootstrap_source from helper env output"

    rm -rf "${fixture_root}"
    test_pass
}

test_post_merge_hook_preserves_requested_bootstrap_source() {
    test_start "beads_git_hooks_post_merge_preserves_requested_bootstrap_source"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/beads-git-hooks-unit.XXXXXX)"
    repo_dir="$(prepare_hook_fixture_repo "${fixture_root}")"

    output="$(
        set +e
        run_hook_script "${repo_dir}" "post-merge"
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${rc}" "Post-merge hook should stay non-blocking when helper env output includes bootstrap_source=''"
    assert_contains "${output}" 'applied bootstrap_source=origin/main' "Post-merge hook should preserve its requested bootstrap source after eval"
    assert_not_contains_text "${output}" '--bootstrap-source requires a value' "Post-merge hook must not clobber bootstrap_source from helper env output"

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "${OUTPUT_JSON}" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Beads Git Hook Unit Tests"
        echo "========================================="
        echo ""
    fi

    test_post_checkout_hook_preserves_requested_bootstrap_source
    test_post_merge_hook_preserves_requested_bootstrap_source
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
