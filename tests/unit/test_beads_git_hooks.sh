#!/bin/bash
# Unit tests for Beads git hook bootstrap-source handling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

POST_CHECKOUT_HOOK="$PROJECT_ROOT/.githooks/post-checkout"
POST_MERGE_HOOK="$PROJECT_ROOT/.githooks/post-merge"
REPO_LOCAL_PATH_HOOK="$PROJECT_ROOT/.githooks/_repo-local-path.sh"

create_hook_fixture_repo() {
    local fixture_root="$1"
    local repo_dir="${fixture_root}/repo"

    mkdir -p "${repo_dir}/.githooks" "${repo_dir}/scripts"
    (
        cd "${repo_dir}"
        git init -b main >/dev/null
        git config user.name "Test User"
        git config user.email "test@example.com"
        git config core.hooksPath .githooks
        printf 'fixture\n' > README.md
        git add README.md
        git commit -m "fixture: init" >/dev/null
    )

    cp "${POST_CHECKOUT_HOOK}" "${repo_dir}/.githooks/post-checkout"
    cp "${POST_MERGE_HOOK}" "${repo_dir}/.githooks/post-merge"
    cp "${REPO_LOCAL_PATH_HOOK}" "${repo_dir}/.githooks/_repo-local-path.sh"

    cat > "${repo_dir}/scripts/git-topology-registry.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
    chmod +x "${repo_dir}/scripts/git-topology-registry.sh"

    cat > "${repo_dir}/scripts/beads-worktree-localize.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${HOOK_ARG_LOG:-}"
check_mode="false"
format_mode="human"
bootstrap_source=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      shift 2
      ;;
    --check)
      check_mode="true"
      shift
      ;;
    --format)
      format_mode="${2:-}"
      shift 2
      ;;
    --bootstrap-source)
      bootstrap_source="${2:-}"
      if [[ -z "${bootstrap_source}" ]]; then
        printf '[beads-worktree-localize] --bootstrap-source requires a value\n' >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${check_mode}" == "true" && "${format_mode}" == "env" ]]; then
  printf "state=%q\n" "bootstrap_required"
  printf "action=%q\n" "bootstrap_and_localize"
  printf "bootstrap_source=%q\n" ""
  exit 0
fi

if [[ -n "${log_file}" ]]; then
  printf '%s\n' "${bootstrap_source}" >> "${log_file}"
fi

printf 'localized\n'
EOF
    chmod +x "${repo_dir}/scripts/beads-worktree-localize.sh"
    chmod +x "${repo_dir}/.githooks/post-checkout" "${repo_dir}/.githooks/post-merge" "${repo_dir}/.githooks/_repo-local-path.sh"

    printf '%s\n' "${repo_dir}"
}

run_hook_script() {
    local repo_dir="$1"
    local hook_name="$2"
    local log_file="$3"

    (
        cd "${repo_dir}"
        HOOK_ARG_LOG="${log_file}" "./.githooks/${hook_name}" >/tmp/"${hook_name}".out 2>/tmp/"${hook_name}".err
    )
}

test_hooks_preserve_requested_bootstrap_source_after_env_eval() {
    test_start "hooks_preserve_requested_bootstrap_source_after_env_eval"

    local fixture_root repo_dir log_file
    fixture_root="$(mktemp -d /tmp/beads-hook-unit.XXXXXX)"
    repo_dir="$(create_hook_fixture_repo "${fixture_root}")"
    log_file="${fixture_root}/hook-args.log"
    : > "${log_file}"

    run_hook_script "${repo_dir}" "post-checkout" "${log_file}"
    run_hook_script "${repo_dir}" "post-merge" "${log_file}"

    assert_contains "$(cat "${log_file}")" "origin/main" "Hooks must preserve the requested bootstrap source even when env output exports bootstrap_source=''"

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Beads Git Hooks Unit Tests"
        echo "========================================="
        echo ""
    fi

    test_hooks_preserve_requested_bootstrap_source_after_env_eval
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
