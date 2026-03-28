#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

seed_beads_audit_tools() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/scripts" "${repo_dir}/bin"
    cp "${PROJECT_ROOT}/bin/bd" "${repo_dir}/bin/bd"
    cp "${PROJECT_ROOT}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-resolve-db.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-localize.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-audit.sh" "${repo_dir}/scripts/beads-worktree-audit.sh"
    chmod +x \
        "${repo_dir}/bin/bd" \
        "${repo_dir}/scripts/beads-resolve-db.sh" \
        "${repo_dir}/scripts/beads-worktree-localize.sh" \
        "${repo_dir}/scripts/beads-worktree-audit.sh"
}

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
  exit 0
fi

if [[ "${args[0]:-}" == "import" ]]; then
  mkdir -p ".beads/dolt/beads/.dolt"
  : > ".beads/last-touched"
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
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
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

seed_post_migration_runtime_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads"
    : > "${worktree_dir}/.beads/beads.db"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
}

seed_broken_post_migration_runtime_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads/dolt/.dolt"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
}

run_audit() {
    local worktree_dir="$1"
    local fake_bin="$2"
    shift 2

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" ./scripts/beads-worktree-audit.sh "$@"
    )
}

test_audit_blocks_canonical_root_when_legacy_redirect_exists() {
    test_start "audit_blocks_canonical_root_when_legacy_redirect_exists"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-worktree-audit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_beads_audit_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-legacy"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/legacy-localize" "main"
    seed_local_beads_foundation "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_audit "${repo_dir}" "${fake_bin}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "${rc}" "Canonical root audit should fail closed on legacy redirect siblings"
    assert_contains "${output}" "migratable_legacy" "Audit should classify the sibling redirect state explicitly"
    assert_contains "${output}" "${worktree_path}" "Audit should identify the offending worktree path"

    rm -rf "${fixture_root}"
    test_pass
}

test_audit_apply_safe_localizes_redirected_sibling() {
    test_start "audit_apply_safe_localizes_redirected_sibling"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/beads-worktree-audit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_beads_audit_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-legacy"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/legacy-localize" "main"
    seed_local_beads_foundation "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_audit "${repo_dir}" "${fake_bin}" --apply-safe --bootstrap-source main)"

    if [[ -f "${worktree_path}/.beads/redirect" ]]; then
        test_fail "Safe apply should remove redirect metadata from migratable siblings"
    fi
    if [[ ! -d "${worktree_path}/.beads/dolt/beads/.dolt" || ! -f "${worktree_path}/.beads/last-touched" ]]; then
        test_fail "Safe apply should materialize a named local Beads runtime for migratable siblings"
    fi
    assert_contains "${output}" "Actions: 1" "Audit should report one localization action"

    rm -rf "${fixture_root}"
    test_pass
}

test_audit_apply_safe_bootstraps_damaged_sibling() {
    test_start "audit_apply_safe_bootstraps_damaged_sibling"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/beads-worktree-audit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_beads_audit_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    printf 'export PATH="${repo_root}/bin:${PATH}"\n' > "${repo_dir}/.envrc"
    (
        cd "${repo_dir}"
        git add -A -- .beads .envrc bin scripts
        git commit -m "fixture: seed bootstrap foundation" >/dev/null
        git push origin main >/dev/null
    )
    worktree_path="${fixture_root}/moltinger-damaged"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/damaged-localize" "main"
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

    output="$(run_audit "${repo_dir}" "${fake_bin}" --apply-safe)"

    if [[ -f "${worktree_path}/.beads/redirect" ]]; then
        test_fail "Safe apply should remove redirect metadata from bootstrap-repair siblings"
    fi
    if [[ ! -d "${worktree_path}/.beads/dolt/beads/.dolt" || ! -f "${worktree_path}/.beads/last-touched" ]]; then
        test_fail "Safe apply should materialize a named local Beads runtime for bootstrap-repair siblings"
    fi
    if [[ ! -f "${worktree_path}/bin/bd" || ! -f "${worktree_path}/scripts/beads-resolve-db.sh" ]]; then
        test_fail "Safe apply should restore the plain bd toolchain for bootstrap-repair siblings"
    fi
    assert_contains "${output}" "Actions: 1" "Audit should report one localization action for bootstrap-repair siblings"
    assert_contains "${output}" "state=current action=localized path=" "Audit should report the sibling as localized after bootstrap repair"
    assert_contains "${output}" "moltinger-damaged" "Audit output should identify the repaired bootstrap sibling"

    rm -rf "${fixture_root}"
    test_pass
}

test_audit_skips_enforcement_in_non_canonical_worktree() {
    test_start "audit_skips_enforcement_in_non_canonical_worktree"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/beads-worktree-audit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_beads_audit_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-safe"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/safe" "main"
    seed_local_beads_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        cd "${worktree_path}"
        PATH="${repo_dir}/bin:${fake_bin}:$PATH" "${repo_dir}/scripts/beads-worktree-audit.sh" --repo "${worktree_path}"
    )"

    assert_contains "${output}" "Mode: non_canonical" "Non-canonical worktrees should not enforce sibling ownership globally"

    rm -rf "${fixture_root}"
    test_pass
}

test_audit_treats_post_migration_runtime_only_sibling_as_ok() {
    test_start "audit_treats_post_migration_runtime_only_sibling_as_ok"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-worktree-audit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_beads_audit_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-post-migration-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/post-migration-runtime" "main"
    seed_post_migration_runtime_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_audit "${repo_dir}" "${fake_bin}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${rc}" "Canonical root audit must not fail on the post-migration runtime-only sibling state"
    assert_contains "${output}" "state=post_migration_runtime_only" "Audit must classify the sibling as the post-migration runtime-only state"
    assert_contains "${output}" "action=none" "Audit must avoid suggesting localization for the runtime-only state"
    assert_contains "${output}" "moltinger-post-migration-runtime" "Audit output must still identify the sibling worktree"

    rm -rf "${fixture_root}"
    test_pass
}

test_audit_warns_for_runtime_bootstrap_required_runtime_only_sibling() {
    test_start "audit_warns_for_runtime_bootstrap_required_runtime_only_sibling"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-worktree-audit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    seed_beads_audit_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-broken-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/broken-runtime" "main"
    seed_broken_post_migration_runtime_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_audit "${repo_dir}" "${fake_bin}" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "${rc}" "Ownership audit must not fail closed when the sibling already has local ownership but needs runtime bootstrap"
    assert_contains "${output}" "Warnings: 1" "Audit should surface the runtime repair issue as a warning"
    assert_contains "${output}" "state=runtime_bootstrap_required" "Audit must classify broken runtime-only siblings explicitly"
    assert_contains "${output}" "action=runtime_repair" "Audit must distinguish runtime repair from ownership localization"
    assert_contains "${output}" "/usr/local/bin/bd doctor --json && ./scripts/beads-worktree-localize.sh --path ." "Audit must point runtime-only siblings to the sanctioned runtime repair helper"

    rm -rf "${fixture_root}"
    test_pass
}

run_test_beads_worktree_audit() {
    start_timer
    test_audit_blocks_canonical_root_when_legacy_redirect_exists
    test_audit_apply_safe_localizes_redirected_sibling
    test_audit_apply_safe_bootstraps_damaged_sibling
    test_audit_skips_enforcement_in_non_canonical_worktree
    test_audit_treats_post_migration_runtime_only_sibling_as_ok
    test_audit_warns_for_runtime_bootstrap_required_runtime_only_sibling
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_test_beads_worktree_audit
fi
