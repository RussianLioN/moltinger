#!/bin/bash
# Unit tests for repo-local plain `bd` dispatch and Beads ownership localization.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

create_fake_system_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/system-bd-bin"

    mkdir -p "${fake_bin}"
cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

db_path=""
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      db_path="${2:-}"
      shift 2
      ;;
    --db=*)
      db_path="${1#--db=}"
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "${args[0]:-}" == "bootstrap" ]]; then
  mkdir -p ".beads/dolt/beads/.dolt"
  printf 'BOOTSTRAP_DB=beads\n'
  exit 0
fi

if [[ "${args[0]:-}" == "import" ]]; then
  mkdir -p ".beads/dolt/beads/.dolt"
  rm -f ".beads/dolt/beads/.fake-broken"
  : > ".beads/last-touched"
  printf 'IMPORTED=%s\n' "${args[1]:-}"
  exit 0
fi

if [[ "${args[0]:-}" == "status" ]]; then
  if [[ -e ".beads/dolt/beads/.fake-broken" ]]; then
    printf 'Error: failed to open database: failed to initialize schema: failed to run dolt migrations: dolt migration "uuid_primary_keys" failed: migrate events to UUID PK: check column type: Error 1105 (HY000): no root value found in session\n' >&2
    exit 1
  fi
  printf 'STATUS_OK\n'
  exit 0
fi

if [[ -n "${db_path}" ]]; then
  mkdir -p "$(dirname "${db_path}")"
  if [[ -d "${db_path}" ]]; then
    : > "${db_path}/.fake-db-touch"
  else
    : > "${db_path}"
  fi
fi

printf 'DB=%s\n' "${db_path}"
printf 'ARGS=%s\n' "${args[*]}"
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

create_fake_repo_local_bd_wrapper_bin() {
    local wrapper_root="$1"

    mkdir -p "${wrapper_root}/bin" "${wrapper_root}/scripts"
    cat > "${wrapper_root}/bin/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'WRONG_WRAPPER=%s\n' "$0"
exit 97
EOF
    chmod +x "${wrapper_root}/bin/bd"
    : > "${wrapper_root}/scripts/beads-resolve-db.sh"

    printf '%s\n' "${wrapper_root}/bin"
}

seed_repo_local_bd_tools() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/bin" "${repo_dir}/scripts"
    cp "${PROJECT_ROOT}/bin/bd" "${repo_dir}/bin/bd"
    cp "${PROJECT_ROOT}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-resolve-db.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-localize.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"
    chmod +x "${repo_dir}/bin/bd" "${repo_dir}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"

    (
        cd "${repo_dir}"
        git add bin/bd scripts/beads-resolve-db.sh scripts/beads-worktree-localize.sh
        git commit -m "fixture: seed repo-local bd tools" >/dev/null
    )
}

seed_local_beads_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${worktree_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed","status":"open","type":"task","priority":3}
EOF
}

seed_pilot_ready_dolt_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads/beads.db" "${worktree_dir}/.beads/dolt/beads/.dolt"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
}

seed_broken_runtime_only_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads/dolt/.dolt"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
}

seed_broken_runtime_shell_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads/dolt/.dolt"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${worktree_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed","status":"open","type":"task","priority":3}
EOF
}

seed_unhealthy_named_runtime_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads/dolt/beads/.dolt"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${worktree_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed","status":"open","type":"task","priority":3}
EOF
    : > "${worktree_dir}/.beads/metadata.json"
    : > "${worktree_dir}/.beads/dolt/beads/.fake-broken"
}

run_plain_bd() {
    local worktree_dir="$1"
    local fake_bin="$2"
    shift 2

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" bd "$@"
    )
}

run_plain_bd_with_path_prefix() {
    local worktree_dir="$1"
    local path_prefix="$2"
    shift 2

    (
        cd "${worktree_dir}"
        PATH="${path_prefix}:$PATH" bd "$@"
    )
}

run_localize() {
    local worktree_dir="$1"
    local fake_bin="$2"
    shift 2

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" ./scripts/beads-worktree-localize.sh "$@"
    )
}

canonicalize_path() {
    local target_path="$1"

    (
        cd "${target_path}"
        pwd -P
    )
}

assert_named_beads_runtime_present() {
    local worktree_path="$1"
    local message="$2"

    if [[ ! -d "${worktree_path}/.beads/dolt/beads/.dolt" ]]; then
        test_fail "${message} (missing named beads runtime)"
    fi
    if [[ ! -f "${worktree_path}/.beads/last-touched" ]]; then
        test_fail "${message} (missing import marker)"
    fi
}

assert_runtime_quarantine_present() {
    local worktree_path="$1"
    local message="$2"

    if ! find "${worktree_path}/.beads/recovery" -maxdepth 2 -type d -name 'runtime-pre-init-*' | grep -q .; then
        test_fail "${message} (missing runtime recovery backup)"
    fi
}

test_plain_bd_executes_against_worktree_local_db() {
    test_start "plain_bd_executes_against_worktree_local_db"

    local fixture_root repo_dir worktree_path fake_bin output expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-safe-worktree"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/safe-local" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" info)"

    assert_contains "${output}" "DB=${expected_db}" "Plain bd should pin the local worktree DB"
    assert_contains "${output}" "ARGS=info" "Plain bd should forward the original arguments"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_skips_sibling_repo_wrapper_when_finding_system_bd() {
    test_start "plain_bd_skips_sibling_repo_wrapper_when_finding_system_bd"

    local fixture_root repo_dir worktree_path fake_bin sibling_wrapper_bin output rc expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-safe-worktree"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/safe-local" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    sibling_wrapper_bin="$(create_fake_repo_local_bd_wrapper_bin "${fixture_root}/sibling-wrapper")"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(
        set +e
        run_plain_bd_with_path_prefix "${worktree_path}" "${worktree_path}/bin:${sibling_wrapper_bin}:${fake_bin}" info 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${rc}" "Plain bd should skip sibling repo-local wrappers while resolving the system bd"
    assert_contains "${output}" "DB=${expected_db}" "Plain bd should still pin the local worktree DB after skipping sibling wrappers"

    rm -rf "${fixture_root}"
    test_pass
}

test_canonical_root_plain_bd_allows_read_only_commands() {
    test_start "canonical_root_plain_bd_allows_read_only_commands"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_plain_bd "${repo_dir}" "${fake_bin}" info)"

    assert_contains "${output}" "DB=" "Canonical-root read-only commands should still pass through to bd"
    assert_contains "${output}" "ARGS=info" "Canonical-root read-only commands should preserve the original subcommand"

    rm -rf "${fixture_root}"
    test_pass
}

test_canonical_root_plain_bd_blocks_mutation_by_default() {
    test_start "canonical_root_plain_bd_blocks_mutation_by_default"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${repo_dir}" "${fake_bin}" update demo-1 --status in_progress 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "26" "${rc}" "Canonical-root mutating plain bd should fail closed by default"
    assert_contains "${output}" "mutating canonical-root tracker commands are blocked by default" "Blocked root mutation should explain the new policy"
    assert_contains "${output}" "bd --db" "Blocked root mutation should point to the explicit override path"

    rm -rf "${fixture_root}"
    test_pass
}

test_canonical_root_plain_bd_allows_explicit_root_db_override() {
    test_start "canonical_root_plain_bd_allows_explicit_root_db_override"

    local fixture_root repo_dir fake_bin output explicit_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    explicit_db="${repo_dir}/.beads/beads.db"

    output="$(run_plain_bd "${repo_dir}" "${fake_bin}" --db "${explicit_db}" update demo-1 --status in_progress)"

    assert_contains "${output}" "DB=${explicit_db}" "Explicit canonical-root DB override should be allowed"
    assert_contains "${output}" "ARGS=update demo-1 --status in_progress" "Explicit canonical-root DB override should preserve the mutating command"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_legacy_redirect() {
    test_start "plain_bd_blocks_legacy_redirect"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-legacy-worktree"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/legacy-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" update demo-1 --status in_progress 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "${rc}" "Legacy redirect should fail closed"
    assert_contains "${output}" "legacy Beads redirect metadata" "Blocked dispatch should explain the redirect failure"
    assert_contains "${output}" "beads-worktree-localize.sh" "Blocked dispatch should point to the localization helper"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_root_fallback_when_local_foundation_is_missing() {
    test_start "plain_bd_blocks_root_fallback_when_local_foundation_is_missing"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    : > "${repo_dir}/.beads/beads.db"
    worktree_path="${fixture_root}/moltinger-missing-local"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/missing-local" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" update demo-1 --status in_progress 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "24" "${rc}" "Missing local foundation in a dedicated worktree should block canonical-root fallback"
    assert_contains "${output}" "falling back to the canonical root tracker is blocked" "Blocked dispatch should name the root-fallback failure"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_allows_explicit_troubleshooting_flags() {
    test_start "plain_bd_allows_explicit_troubleshooting_flags"

    local fixture_root repo_dir worktree_path fake_bin output explicit_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-explicit-troubleshooting"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/explicit-troubleshooting" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    explicit_db="${fixture_root}/custom-explicit.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" --db "${explicit_db}" info)"

    assert_contains "${output}" "DB=${explicit_db}" "Explicit troubleshooting DB path should pass through unchanged"
    assert_contains "${output}" "ARGS=info" "Explicit troubleshooting should still forward the subcommand"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_allows_backend_show_for_pilot_ready_dolt_foundation() {
    test_start "plain_bd_allows_backend_show_for_pilot_ready_dolt_foundation"

    local fixture_root repo_dir worktree_path fake_bin output expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-pilot-ready"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/pilot-ready" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_pilot_ready_dolt_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" backend show)"

    assert_contains "${output}" "DB=${expected_db}" "Pilot-ready Dolt foundation should still resolve the local Beads runtime"
    assert_contains "${output}" "ARGS=backend show" "Pilot-ready backend show should pass through as a read-only runtime probe"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_allows_doctor_for_pilot_ready_dolt_foundation() {
    test_start "plain_bd_allows_doctor_for_pilot_ready_dolt_foundation"

    local fixture_root repo_dir worktree_path fake_bin output expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-pilot-ready-doctor"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/pilot-ready-doctor" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_pilot_ready_dolt_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" doctor --json)"

    assert_contains "${output}" "DB=${expected_db}" "Pilot-ready Dolt foundation should allow doctor against the local runtime"
    assert_contains "${output}" "ARGS=doctor --json" "Pilot-ready doctor should pass through as a read-only runtime probe"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_allows_mutation_for_post_migration_runtime_only_state() {
    test_start "plain_bd_allows_mutation_for_post_migration_runtime_only_state"

    local fixture_root repo_dir worktree_path fake_bin output expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-runtime-only-update"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/runtime-only-update" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_pilot_ready_dolt_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" update demo-1 --status in_progress)"

    assert_contains "${output}" "DB=${expected_db}" "Runtime-only post-migration worktrees must still execute local mutating commands without a pilot gate"
    assert_contains "${output}" "ARGS=update demo-1 --status in_progress" "Runtime-only post-migration worktrees must preserve ordinary mutating commands"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_deprecated_sync_with_modern_guidance() {
    test_start "plain_bd_blocks_deprecated_sync_with_modern_guidance"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-runtime-only-sync"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/runtime-only-sync" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_pilot_ready_dolt_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" sync 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "28" "${rc}" "Deprecated bd sync must fail with modern guidance instead of suggesting pilot mode"
    assert_contains "${output}" "'sync' is retired" "Deprecated bd sync must be described as a retired workflow"
    assert_contains "${output}" "bd dolt push / bd dolt pull" "Deprecated bd sync must point operators at the modern Dolt workflow"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_recognizes_post_migration_runtime_only_state() {
    test_start "localize_recognizes_post_migration_runtime_only_state"

    local fixture_root repo_dir worktree_path fake_bin output expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-post-migration-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/post-migration-runtime" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_pilot_ready_dolt_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(run_localize "${worktree_path}" "${fake_bin}" --check --path "${worktree_path}")"

    assert_contains "${output}" "State: post_migration_runtime_only" "Localization helper must recognize the runtime-only post-migration state"
    assert_contains "${output}" "Action: none" "Localization helper must not force a repair just because tracked JSONL is retired"
    assert_contains "${output}" "DB Path: ${expected_db}" "Localization helper must point operators to the local runtime path"
    assert_contains "${output}" "local Beads repair problem" "Localization helper must direct operators to repair language instead of backlog-loss language"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_broken_runtime_only_foundation_with_bootstrap_guidance() {
    test_start "plain_bd_blocks_broken_runtime_only_foundation_with_bootstrap_guidance"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-broken-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/broken-runtime" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_broken_runtime_only_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" status 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "25" "${rc}" "Runtime-only worktrees with a missing beads named DB must fail closed"
    assert_contains "${output}" "local Dolt-backed Beads runtime is incomplete" "Dispatch must classify the failure as runtime repair, not backlog loss"
    assert_contains "${output}" "Tracked .beads/issues.jsonl is retired here" "Dispatch must keep retired JSONL retired during runtime repair"
    assert_contains "${output}" "bd bootstrap" "Dispatch must point operators to the official bootstrap recovery path"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_reports_runtime_bootstrap_required_for_broken_runtime_only_state() {
    test_start "localize_reports_runtime_bootstrap_required_for_broken_runtime_only_state"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-broken-runtime-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/broken-runtime-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_broken_runtime_only_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_localize "${worktree_path}" "${fake_bin}" --check --path "${worktree_path}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "${rc}" "Localization helper must stop and report when a runtime-only worktree needs bootstrap repair"
    assert_contains "${output}" "State: runtime_bootstrap_required" "Localization helper must expose a dedicated runtime-bootstrap-required state"
    assert_contains "${output}" "bd bootstrap" "Localization helper must point operators to bootstrap recovery"
    assert_contains "${output}" "Do not restore JSONL" "Localization helper must preserve retired JSONL semantics during repair"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_broken_runtime_shell_with_localize_guidance() {
    test_start "plain_bd_blocks_broken_runtime_shell_with_localize_guidance"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-broken-runtime-shell"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/broken-runtime-shell" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_broken_runtime_shell_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" status 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "25" "${rc}" "Runtime shell without a named beads DB must fail closed even when tracked JSONL still exists"
    assert_contains "${output}" "named 'beads' database is not materialized yet" "Dispatch must describe the missing named DB explicitly"
    assert_contains "${output}" "beads-worktree-localize.sh --path" "Dispatch must point operators to localized runtime rebuild when tracked foundation exists"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_reports_runtime_bootstrap_required_for_broken_runtime_shell() {
    test_start "localize_reports_runtime_bootstrap_required_for_broken_runtime_shell"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-broken-runtime-shell-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/broken-runtime-shell-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_broken_runtime_shell_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_localize "${worktree_path}" "${fake_bin}" --check --path "${worktree_path}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "${rc}" "Localization helper must stop and report when a named DB is missing behind a Dolt runtime shell"
    assert_contains "${output}" "State: runtime_bootstrap_required" "Localization helper must expose runtime_bootstrap_required for broken runtime shells"
    assert_contains "${output}" "named 'beads' database is not materialized yet" "Localization helper must explain the named DB problem directly"
    assert_contains "${output}" "Runtime Repair Mode: rebuild_local_foundation" "Localization helper must expose the repairable rebuild mode for tracked foundation states"
    assert_contains "${output}" "beads-worktree-localize.sh --path ." "Localization helper must route broken runtime shells to the in-place rebuild helper"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_materializes_local_db_and_removes_redirect() {
    test_start "localize_materializes_local_db_and_removes_redirect"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_localize "${worktree_path}" "${fake_bin}" --path "${worktree_path}")"

    assert_contains "${output}" "State: current" "Localization should end in the current localized state"
    if [[ -f "${worktree_path}/.beads/redirect" ]]; then
        test_fail "Localization should remove legacy redirect metadata"
    fi
    assert_named_beads_runtime_present "${worktree_path}" "Localization should materialize the named local Beads runtime"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_bootstraps_missing_foundation_from_source_ref() {
    test_start "localize_bootstraps_missing_foundation_from_source_ref"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    printf 'export PATH="${repo_root}/bin:${PATH}"\n' > "${repo_dir}/.envrc"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl .envrc
        git commit -m "fixture: seed bootstrap foundation" >/dev/null
    )
    worktree_path="${fixture_root}/moltinger-bootstrap-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/bootstrap-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    rm -f \
        "${worktree_path}/.beads/config.yaml" \
        "${worktree_path}/.beads/issues.jsonl" \
        "${worktree_path}/bin/bd" \
        "${worktree_path}/scripts/beads-resolve-db.sh" \
        "${worktree_path}/scripts/beads-worktree-localize.sh" \
        "${worktree_path}/.envrc"
    mkdir -p "${worktree_path}/.beads"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        cd "${PROJECT_ROOT}"
        PATH="${PROJECT_ROOT}/bin:${fake_bin}:$PATH" ./scripts/beads-worktree-localize.sh --path "${worktree_path}" --bootstrap-source main
    )"

    assert_contains "${output}" "State: current" "Bootstrap localization should finish in the current localized state"
    assert_contains "${output}" "Bootstrap Source: main" "Bootstrap localization should report the source ref"
    if [[ -f "${worktree_path}/.beads/redirect" ]]; then
        test_fail "Bootstrap localization should remove legacy redirect metadata"
    fi
    if [[ ! -f "${worktree_path}/.beads/config.yaml" || ! -f "${worktree_path}/.beads/issues.jsonl" ]]; then
        test_fail "Bootstrap localization should restore the local Beads foundation"
    fi
    if [[ ! -f "${worktree_path}/bin/bd" || ! -f "${worktree_path}/scripts/beads-resolve-db.sh" ]]; then
        test_fail "Bootstrap localization should restore the plain bd toolchain"
    fi
    assert_named_beads_runtime_present "${worktree_path}" "Bootstrap localization should materialize the named local Beads runtime"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_repairs_stale_dolt_shell_by_rebuilding_local_runtime() {
    test_start "localize_repairs_stale_dolt_shell_by_rebuilding_local_runtime"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-stale-shell-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/stale-shell-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    mkdir -p "${worktree_path}/.beads/dolt/.dolt"
    : > "${worktree_path}/.beads/metadata.json"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_localize "${worktree_path}" "${fake_bin}" --path "${worktree_path}")"

    assert_contains "${output}" "State: current" "Localization should converge stale Dolt shells to a healthy localized state"
    assert_named_beads_runtime_present "${worktree_path}" "Localization should rebuild stale runtime shells in place"
    assert_runtime_quarantine_present "${worktree_path}" "Localization should preserve the stale runtime shell in recovery before rebuilding"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_unhealthy_named_runtime_with_localize_guidance() {
    test_start "plain_bd_blocks_unhealthy_named_runtime_with_localize_guidance"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-unhealthy-named-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/unhealthy-named-runtime" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_unhealthy_named_runtime_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" status 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "25" "${rc}" "Partially materialized named DBs must fail closed instead of passing through to plain bd"
    assert_contains "${output}" "plain bd cannot read it safely yet" "Dispatch must explain that the local runtime exists but is unhealthy"
    assert_contains "${output}" "beads-worktree-localize.sh --path" "Dispatch must route unhealthy named DBs through localized rebuild"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_rebuilds_unhealthy_named_runtime_in_place() {
    test_start "localize_rebuilds_unhealthy_named_runtime_in_place"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-unhealthy-runtime-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/unhealthy-runtime-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_unhealthy_named_runtime_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_localize "${worktree_path}" "${fake_bin}" --path "${worktree_path}")"

    assert_contains "${output}" "State: current" "Localization should converge unhealthy named DBs to a healthy localized state"
    assert_named_beads_runtime_present "${worktree_path}" "Localization should reimport the tracked backlog after unhealthy runtime repair"
    assert_runtime_quarantine_present "${worktree_path}" "Localization should quarantine the unhealthy runtime before rebuilding"
    if [[ -e "${worktree_path}/.beads/dolt/beads/.fake-broken" ]]; then
        test_fail "Localization should remove the unhealthy named DB marker during rebuild"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Plain bd Dispatch Unit Tests"
        echo "========================================="
        echo ""
    fi

    test_plain_bd_executes_against_worktree_local_db
    test_plain_bd_skips_sibling_repo_wrapper_when_finding_system_bd
    test_canonical_root_plain_bd_allows_read_only_commands
    test_canonical_root_plain_bd_blocks_mutation_by_default
    test_canonical_root_plain_bd_allows_explicit_root_db_override
    test_plain_bd_blocks_legacy_redirect
    test_plain_bd_blocks_root_fallback_when_local_foundation_is_missing
    test_plain_bd_allows_explicit_troubleshooting_flags
    test_plain_bd_allows_backend_show_for_pilot_ready_dolt_foundation
    test_plain_bd_allows_doctor_for_pilot_ready_dolt_foundation
    test_plain_bd_allows_mutation_for_post_migration_runtime_only_state
    test_plain_bd_blocks_deprecated_sync_with_modern_guidance
    test_localize_recognizes_post_migration_runtime_only_state
    test_plain_bd_blocks_broken_runtime_only_foundation_with_bootstrap_guidance
    test_localize_reports_runtime_bootstrap_required_for_broken_runtime_only_state
    test_plain_bd_blocks_broken_runtime_shell_with_localize_guidance
    test_localize_reports_runtime_bootstrap_required_for_broken_runtime_shell
    test_localize_materializes_local_db_and_removes_redirect
    test_localize_bootstraps_missing_foundation_from_source_ref
    test_localize_repairs_stale_dolt_shell_by_rebuilding_local_runtime
    test_plain_bd_blocks_unhealthy_named_runtime_with_localize_guidance
    test_localize_rebuilds_unhealthy_named_runtime_in_place
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
