#!/bin/bash
# Unit tests for deterministic Phase A worktree creation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

WORKTREE_PHASE_A_SCRIPT="$PROJECT_ROOT/scripts/worktree-phase-a.sh"

create_fake_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--no-daemon" ]]; then
  shift
fi

db_path=""
if [[ "${1:-}" == "--db" ]]; then
  db_path="${2:-}"
  shift 2
fi

if [[ -n "${FAKE_BD_CALL_LOG:-}" ]]; then
  printf '%s\n' "${1:-}" >> "${FAKE_BD_CALL_LOG}"
fi

if [[ "${1:-}" == "info" ]]; then
  if [[ -n "${FAKE_BD_INFO_SLEEP_SECONDS:-}" ]]; then
    sleep "${FAKE_BD_INFO_SLEEP_SECONDS}"
  fi
  if [[ -n "${db_path}" ]]; then
    mkdir -p "$(dirname "${db_path}")"
    : > "${db_path}"
  fi
  if [[ -e ".beads/dolt/beads/.fake-broken" ]]; then
    printf 'simulated broken named db\n' >&2
    exit 1
  fi
  if [[ -n "${FAKE_BD_INFO_STDOUT:-}" ]]; then
    printf '%s\n' "${FAKE_BD_INFO_STDOUT}"
  fi
  if [[ -n "${FAKE_BD_INFO_STDERR:-}" ]]; then
    printf '%s\n' "${FAKE_BD_INFO_STDERR}" >&2
  fi
  exit "${FAKE_BD_INFO_RC:-0}"
fi

if [[ "${1:-}" == "import" ]]; then
  import_source="${2:-}"
  mkdir -p .beads/dolt/beads/.dolt
  rm -f .beads/dolt/beads/.fake-broken
  : > .beads/last-touched
  if [[ -n "${import_source}" && -f "${import_source}" ]]; then
    cp "${import_source}" .beads/last-import.jsonl
  fi
  exit 0
fi

if [[ "${1:-}" == "export" ]]; then
  output_path=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output)
        output_path="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "${FAKE_BD_EXPORT_MODE:-success}" != "success" ]]; then
    printf 'simulated export failure\n' >&2
    exit 1
  fi

  [[ -n "${output_path}" ]] || {
    printf 'missing export output path\n' >&2
    exit 1
  }

  if [[ -n "${FAKE_BD_EXPORT_SOURCE_FILE:-}" && -f "${FAKE_BD_EXPORT_SOURCE_FILE}" ]]; then
    cp "${FAKE_BD_EXPORT_SOURCE_FILE}" "${output_path}"
  else
    cp .beads/issues.jsonl "${output_path}"
  fi
  exit 0
fi

if [[ "${1:-}" == "status" ]]; then
  if [[ -n "${FAKE_BD_STATUS_SLEEP_SECONDS:-}" ]]; then
    sleep "${FAKE_BD_STATUS_SLEEP_SECONDS}"
  fi
  if [[ -n "${FAKE_BD_STATUS_STDOUT:-}" ]]; then
    printf '%s\n' "${FAKE_BD_STATUS_STDOUT}"
  fi
  if [[ -n "${FAKE_BD_STATUS_STDERR:-}" ]]; then
    printf '%s\n' "${FAKE_BD_STATUS_STDERR}" >&2
  fi
  if [[ -e ".beads/dolt/beads/.fake-broken" ]]; then
    printf 'simulated broken named db\n' >&2
    exit 1
  fi
  exit "${FAKE_BD_STATUS_RC:-0}"
fi

if [[ "${1:-}" == "show" ]]; then
  issue_id="${2:-}"
  source_file=".beads/last-import.jsonl"
  if [[ ! -f "${source_file}" ]]; then
    source_file=".beads/issues.jsonl"
  fi
  if [[ -n "${issue_id}" ]] && [[ -f "${source_file}" ]] && grep -Fq "\"id\":\"${issue_id}\"" "${source_file}"; then
    grep -F "\"id\":\"${issue_id}\"" "${source_file}"
    exit 0
  fi
  printf 'issue not found\n' >&2
  exit 1
fi

if [[ "${1:-}" == "list" ]]; then
  if [[ -n "${BEADS_DB:-}" ]]; then
    mkdir -p "$(dirname "${BEADS_DB}")"
    : > "${BEADS_DB}"
  fi
  exit 0
fi

if [[ "${1:-}" == "bootstrap" ]]; then
  if [[ "${FAKE_BD_BOOTSTRAP_MODE:-success}" != "success" ]]; then
    printf 'simulated bootstrap failure\n' >&2
    exit 1
  fi

  mkdir -p .beads/dolt/beads/.dolt
  printf '{"role":"maintainer"}\n' > .beads/metadata.json
  exit 0
fi

printf 'unsupported fake bd invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

run_phase_a_create() {
    local fake_bin="$1"
    shift
    PATH="${fake_bin}:$PATH" "$WORKTREE_PHASE_A_SCRIPT" create-from-base "$@"
}

assert_file_missing() {
    local path="$1"
    local message="$2"
    if [[ -e "$path" ]]; then
        test_fail "$message (unexpected path: $path)"
    fi
}

seed_unhealthy_named_runtime_fixture() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads/dolt/beads/.dolt"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    printf '{"role":"maintainer"}\n' > "${repo_dir}/.beads/metadata.json"
    : > "${repo_dir}/.beads/dolt/beads/.fake-broken"
}

test_phase_a_create_from_base_anchors_new_branch_to_main() {
    test_start "worktree_phase_a_create_from_base_anchors_new_branch_to_main"

    local fixture_root repo_dir fake_bin target_path base_sha branch_sha worktree_sha output
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-clean-start"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track beads state" >/dev/null
    )

    (
        cd "${repo_dir}"
        git switch -c uat/source-line >/dev/null
        printf 'source\n' > source.txt
        git add source.txt
        git commit -m "fixture: source line" >/dev/null
    )

    output="$(run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/clean-start \
        --path "$target_path" \
        --format env)"

    base_sha="$(git -C "$repo_dir" rev-parse main)"
    branch_sha="$(git -C "$repo_dir" rev-parse feat/clean-start)"
    worktree_sha="$(git -C "$target_path" rev-parse HEAD)"

    assert_contains "$output" 'schema=worktree-phase-a/v1' "Phase A create should expose its env schema"
    assert_contains "$output" 'result=created_from_base' "Phase A create should report successful base-anchored creation"
    assert_eq "$base_sha" "$branch_sha" "New branch should be created exactly at canonical main"
    assert_eq "$base_sha" "$worktree_sha" "New worktree HEAD should match canonical main"
    assert_file_missing "${target_path}/.beads/redirect" "Phase A create should not leave redirect metadata in the new worktree"
    if [[ ! -d "${target_path}/.beads/dolt/beads/.dolt" ]]; then
        test_fail "Phase A create should bootstrap a named local Beads runtime in the new worktree"
    fi
    if [[ ! -f "${target_path}/.beads/last-touched" ]]; then
        test_fail "Phase A create should import the tracked issues into the new runtime"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_imports_live_canonical_export() {
    test_start "worktree_phase_a_create_imports_live_canonical_export"

    local fixture_root repo_dir fake_bin target_path canonical_export output call_log import_count
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-live-export"
    canonical_export="${fixture_root}/canonical-live-export.jsonl"
    call_log="${fixture_root}/phase-a-live-export.calls"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"tracked fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track stale issues foundation" >/dev/null
    )

    cat > "${canonical_export}" <<'EOF'
{"id":"molt-1","title":"tracked fixture"}
{"id":"molt-2","title":"live canonical issue"}
EOF

    output="$(FAKE_BD_CALL_LOG="${call_log}" FAKE_BD_EXPORT_SOURCE_FILE="${canonical_export}" run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/live-export \
        --path "$target_path" \
        --format env)"

    assert_contains "$output" 'result=created_from_base' "Phase A should still succeed with a canonical export import step"
    if [[ ! -f "${target_path}/.beads/last-import.jsonl" ]]; then
        test_fail "Phase A should record the live canonical export as the final import source"
    fi
    assert_contains "$(cat "${target_path}/.beads/last-import.jsonl")" '"id":"molt-2"' "Phase A must import the live canonical export, not just the tracked issues snapshot"
    if ! (
        cd "${target_path}"
        PATH="${fake_bin}:$PATH" bd show molt-2 >/dev/null
    ); then
        test_fail "Phase A should make the newly exported canonical issue visible in the fresh worktree without manual import repair"
    fi
    import_count="$(grep -c '^import$' "${call_log}" || true)"
    assert_eq "1" "${import_count}" "Phase A should import the canonical backlog exactly once after runtime prep"

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_blocks_existing_branch_on_wrong_base() {
    test_start "worktree_phase_a_create_blocks_existing_branch_on_wrong_base"

    local fixture_root repo_dir fake_bin target_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-drifted-start"

    (
        cd "${repo_dir}"
        git switch -c feat/drifted >/dev/null
        printf 'drift\n' > drift.txt
        git add drift.txt
        git commit -m "fixture: drifted branch" >/dev/null
        git switch main >/dev/null
    )

    output="$(
        set +e
        run_phase_a_create "$fake_bin" \
            --canonical-root "$repo_dir" \
            --base-ref main \
            --branch feat/drifted \
            --path "$target_path" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Existing drifted branch should block Phase A create"
    assert_contains "$output" "Existing branch 'feat/drifted' is not aligned to main" "Blocked Phase A should explain the base mismatch"
    assert_file_missing "$target_path" "Blocked Phase A should not create a worktree"

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_bootstraps_runtime_shell_when_named_db_missing() {
    test_start "worktree_phase_a_create_bootstraps_runtime_shell_when_named_db_missing"

    local fixture_root repo_dir fake_bin target_path output
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-bootstrap-runtime"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    printf '{"role":"maintainer"}\n' > "${repo_dir}/.beads/metadata.json"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl .beads/metadata.json
        git commit -m "fixture: track broken dolt runtime shell" >/dev/null
    )

    output="$(run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/bootstrap-runtime \
        --path "$target_path" \
        --format env)"

    assert_contains "$output" 'result=created_from_base' "Phase A should still succeed after bootstrap repair"
    if [[ ! -d "${target_path}/.beads/dolt/beads/.dolt" ]]; then
        test_fail "Phase A should materialize the named beads DB when bootstrap repair is required"
    fi
    if [[ ! -f "${target_path}/.beads/metadata.json" ]]; then
        test_fail "Phase A should leave bootstrap metadata in place after runtime repair"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_repairs_runtime_only_state_without_tracked_issues() {
    test_start "worktree_phase_a_create_repairs_runtime_only_state_without_tracked_issues"

    local fixture_root repo_dir fake_bin target_path canonical_export output
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-runtime-only"
    canonical_export="${fixture_root}/canonical-runtime-only-export.jsonl"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml
        git commit -m "fixture: track runtime-only local foundation" >/dev/null
    )

    cat > "${canonical_export}" <<'EOF'
{"id":"molt-1","title":"live runtime issue"}
EOF

    output="$(FAKE_BD_EXPORT_SOURCE_FILE="${canonical_export}" run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/runtime-only \
        --path "$target_path" \
        --format env)"

    assert_contains "$output" 'result=created_from_base' "Phase A should succeed for runtime-only post-migration state"
    if [[ ! -d "${target_path}/.beads/dolt/beads/.dolt" ]]; then
        test_fail "Phase A should materialize a named local runtime even when tracked issues are already retired"
    fi
    if [[ -f "${target_path}/.beads/issues.jsonl" ]]; then
        test_fail "Phase A should not recreate tracked issues.jsonl for runtime-only post-migration state"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_rebuilds_unhealthy_named_runtime() {
    test_start "worktree_phase_a_create_rebuilds_unhealthy_named_runtime"

    local fixture_root repo_dir fake_bin target_path output
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-unhealthy-runtime"

    mkdir -p "${repo_dir}/.beads"
    seed_unhealthy_named_runtime_fixture "${repo_dir}"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl .beads/metadata.json .beads/dolt/beads/.fake-broken
        git commit -m "fixture: track unhealthy named runtime" >/dev/null
    )

    output="$(run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/unhealthy-runtime \
        --path "$target_path" \
        --format env)"

    assert_contains "$output" 'result=created_from_base' "Phase A should still succeed after rebuilding an unhealthy named runtime"
    if [[ ! -f "${target_path}/.beads/last-touched" ]]; then
        test_fail "Phase A should reimport tracked issues after unhealthy runtime repair"
    fi
    if [[ -e "${target_path}/.beads/dolt/beads/.fake-broken" ]]; then
        test_fail "Phase A should not leave the unhealthy named runtime marker behind"
    fi
    if ! find "${target_path}/.beads/recovery" -maxdepth 2 -type d -name 'runtime-pre-init-*' | grep -q .; then
        test_fail "Phase A should quarantine the unhealthy runtime before rebuilding it"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_accepts_info_probe_when_status_probe_is_noisy() {
    test_start "worktree_phase_a_create_accepts_info_probe_when_status_probe_is_noisy"

    local fixture_root repo_dir fake_bin target_path output
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-noisy-status"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: tracked local foundation for noisy status probe" >/dev/null
    )

    output="$(FAKE_BD_STATUS_RC="1" \
        FAKE_BD_STATUS_STDERR='failed to get statistics: dial tcp 127.0.0.1:12345: connect: connection refused' \
        FAKE_BD_INFO_STDOUT='Beads Database Information' \
        run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/noisy-status \
        --path "$target_path" \
        --format env)"

    assert_contains "$output" 'result=created_from_base' "Phase A should trust a successful info probe even when status is noisy"
    if [[ ! -f "${target_path}/.beads/last-import.jsonl" && ! -f "${target_path}/.beads/last-touched" ]]; then
        test_fail "Phase A should still finish the canonical import path when status probing is noisy"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_falls_back_to_status_when_info_probe_times_out() {
    test_start "worktree_phase_a_create_falls_back_to_status_when_info_probe_times_out"

    local fixture_root repo_dir fake_bin target_path output call_log info_line status_line
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-info-timeout"
    call_log="${fixture_root}/phase-a-info-timeout.calls"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: tracked local foundation for info-timeout fallback" >/dev/null
    )

    output="$(BEADS_RESOLVE_BD_TIMEOUT_SECONDS="1" \
        FAKE_BD_CALL_LOG="${call_log}" \
        FAKE_BD_INFO_SLEEP_SECONDS="2" \
        FAKE_BD_STATUS_STDOUT='ok' \
        run_phase_a_create "$fake_bin" \
        --canonical-root "$repo_dir" \
        --base-ref main \
        --branch feat/info-timeout \
        --path "$target_path" \
        --format env)"

    assert_contains "$output" 'result=created_from_base' "Phase A should fall back to status when info probing times out"
    info_line="$(grep -n '^info$' "${call_log}" | head -1 | cut -d: -f1)"
    status_line="$(grep -n '^status$' "${call_log}" | head -1 | cut -d: -f1)"
    if [[ -z "${info_line}" || -z "${status_line}" ]]; then
        test_fail "Phase A timeout fallback should probe both info and status"
        return
    fi
    if (( info_line >= status_line )); then
        test_fail "Phase A timeout fallback should try info before status"
        return
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_blocks_when_runtime_bootstrap_does_not_repair() {
    test_start "worktree_phase_a_create_blocks_when_runtime_bootstrap_does_not_repair"

    local fixture_root repo_dir fake_bin target_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-bootstrap-runtime-fail"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    printf '{"role":"maintainer"}\n' > "${repo_dir}/.beads/metadata.json"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl .beads/metadata.json
        git commit -m "fixture: track unrepaired dolt runtime shell" >/dev/null
    )

    output="$(
        set +e
        FAKE_BD_BOOTSTRAP_MODE="fail" run_phase_a_create "$fake_bin" \
            --canonical-root "$repo_dir" \
            --base-ref main \
            --branch feat/bootstrap-runtime-fail \
            --path "$target_path" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Phase A must fail closed when runtime bootstrap does not repair the new worktree"
    assert_contains "$output" "named 'beads' database is not materialized yet" "Phase A must surface the runtime bootstrap blocker explicitly"

    rm -rf "$fixture_root"
    test_pass
}

test_phase_a_create_blocks_when_canonical_export_fails() {
    test_start "worktree_phase_a_create_blocks_when_canonical_export_fails"

    local fixture_root repo_dir fake_bin target_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-phase-a-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    target_path="${fixture_root}/moltinger-export-fail"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "molt"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"molt-1","title":"fixture"}\n' > "${repo_dir}/.beads/issues.jsonl"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl
        git commit -m "fixture: track export failure baseline" >/dev/null
    )

    output="$(
        set +e
        FAKE_BD_EXPORT_MODE="fail" run_phase_a_create "$fake_bin" \
            --canonical-root "$repo_dir" \
            --base-ref main \
            --branch feat/export-fail \
            --path "$target_path" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Phase A must fail closed when canonical backlog export fails"
    assert_contains "$output" "could not export the live canonical Beads backlog" "Phase A must explain the canonical export blocker"
    assert_file_missing "$target_path" "Phase A should not create a worktree when canonical export fails"

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Worktree Phase A Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$WORKTREE_PHASE_A_SCRIPT" ]]; then
        test_fail "Worktree Phase A script missing or not executable: $WORKTREE_PHASE_A_SCRIPT"
        generate_report
        return 1
    fi

    test_phase_a_create_from_base_anchors_new_branch_to_main
    test_phase_a_create_blocks_existing_branch_on_wrong_base
    test_phase_a_create_bootstraps_runtime_shell_when_named_db_missing
    test_phase_a_create_imports_live_canonical_export
    test_phase_a_create_repairs_runtime_only_state_without_tracked_issues
    test_phase_a_create_rebuilds_unhealthy_named_runtime
    test_phase_a_create_accepts_info_probe_when_status_probe_is_noisy
    test_phase_a_create_falls_back_to_status_when_info_probe_times_out
    test_phase_a_create_blocks_when_runtime_bootstrap_does_not_repair
    test_phase_a_create_blocks_when_canonical_export_fails
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
