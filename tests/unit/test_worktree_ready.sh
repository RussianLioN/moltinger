#!/bin/bash
# Unit tests for worktree-ready helper planning and one-shot UX.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

WORKTREE_READY_SCRIPT="$PROJECT_ROOT/scripts/worktree-ready.sh"

create_fake_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "worktree" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  payload="${BD_WORKTREE_LIST_JSON:-[]}"
  if [[ "${BD_WORKTREE_LIST_FILTER_MISSING:-0}" == "1" ]]; then
    filtered_lines=()
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      line_path="$(printf '%s\n' "${line}" | jq -r '.path // empty')"
      if [[ -z "${line_path}" || -e "${line_path}" ]]; then
        filtered_lines+=("${line}")
      fi
    done < <(printf '%s\n' "${payload}" | jq -c '.[]')

    if [[ "${#filtered_lines[@]}" -eq 0 ]]; then
      payload='[]'
    else
      payload="$(printf '%s\n' "${filtered_lines[@]}" | jq -s '.')"
    fi
  fi
  printf '%s\n' "${payload}"
  exit 0
fi

if [[ "${1:-}" == "worktree" && "${2:-}" == "remove" ]]; then
  target_path="${3:-}"
  if [[ "${BD_WORKTREE_REMOVE_CANONICALIZE:-0}" == "1" && -d "${target_path}" ]]; then
    target_path="$(cd "${target_path}" && pwd -P)"
  fi
  if [[ -n "${BD_WORKTREE_REMOVE_STDOUT:-}" ]]; then
    printf '%s\n' "${BD_WORKTREE_REMOVE_STDOUT}"
  fi
  if [[ -n "${BD_WORKTREE_REMOVE_STDERR:-}" ]]; then
    printf '%s\n' "${BD_WORKTREE_REMOVE_STDERR}" >&2
  fi
  if [[ "${BD_WORKTREE_REMOVE_NOOP:-0}" != "1" && -n "${target_path}" ]]; then
    git worktree remove "${target_path}" >/dev/null 2>&1 || true
  fi
  exit "${BD_WORKTREE_REMOVE_RC:-0}"
fi

if [[ "${1:-}" == "list" && "${2:-}" == "--all" && "${3:-}" == "--json" ]]; then
  printf '%s\n' "${BD_LIST_ALL_JSON:-[]}"
  exit 0
fi

if [[ "${1:-}" == "show" && "${3:-}" == "--json" ]]; then
  if [[ -n "${BD_SHOW_JSON_MAP:-}" ]]; then
    printf '%s\n' "${BD_SHOW_JSON_MAP}" | jq -c --arg issue "${2:-}" '.[$issue] // empty'
    exit 0
  fi
  printf '%s\n' "${BD_SHOW_JSON:-[]}"
  exit 0
fi

if [[ "${1:-}" == "status" ]]; then
  if [[ -n "${BD_STATUS_SLEEP_SECONDS:-}" ]]; then
    sleep "${BD_STATUS_SLEEP_SECONDS}"
  fi
  if [[ -n "${BD_STATUS_STDOUT:-}" ]]; then
    printf '%s\n' "${BD_STATUS_STDOUT}"
  fi
  if [[ -n "${BD_STATUS_STDERR:-}" ]]; then
    printf '%s\n' "${BD_STATUS_STDERR}" >&2
  fi
  exit "${BD_STATUS_RC:-0}"
fi

if [[ "${1:-}" == "doctor" && "${2:-}" == "--json" ]]; then
  if [[ -n "${BD_DOCTOR_SLEEP_SECONDS:-}" ]]; then
    sleep "${BD_DOCTOR_SLEEP_SECONDS}"
  fi
  printf '%s\n' "${BD_DOCTOR_STDOUT:-{\"checks\":[],\"overall_ok\":true}}"
  exit "${BD_DOCTOR_RC:-0}"
fi

printf 'unsupported fake bd invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

create_fake_gh_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/gh-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit "${GH_AUTH_RC:-0}"
fi

if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
  if [[ -n "${GH_EXPECT_CWD:-}" && "${PWD}" != "${GH_EXPECT_CWD}" ]]; then
    printf 'unexpected gh cwd: %s\n' "${PWD}" >&2
    exit 97
  fi
  printf '%s\n' "${GH_REPO_VIEW_JSON:-{\"defaultBranchRef\":{\"name\":\"main\"},\"deleteBranchOnMerge\":false,\"nameWithOwner\":\"example/repo\"}}"
  exit "${GH_REPO_VIEW_RC:-0}"
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  if [[ -n "${GH_EXPECT_CWD:-}" && "${PWD}" != "${GH_EXPECT_CWD}" ]]; then
    printf 'unexpected gh cwd: %s\n' "${PWD}" >&2
    exit 97
  fi
  printf '%s\n' "${GH_PR_LIST_JSON:-[]}"
  exit "${GH_PR_LIST_RC:-0}"
fi

if [[ "${1:-}" == "api" && "${2:-}" == "-X" && "${3:-}" == "DELETE" ]]; then
  if [[ -n "${GH_EXPECT_CWD:-}" && "${PWD}" != "${GH_EXPECT_CWD}" ]]; then
    printf 'unexpected gh cwd: %s\n' "${PWD}" >&2
    exit 97
  fi
  if [[ -n "${GH_EXPECT_API_DELETE_ROUTE:-}" && "${4:-}" != "${GH_EXPECT_API_DELETE_ROUTE}" ]]; then
    printf 'unexpected gh api route: %s\n' "${4:-}" >&2
    exit 98
  fi
  if [[ -n "${GH_API_STDOUT:-}" ]]; then
    printf '%s\n' "${GH_API_STDOUT}"
  fi
  if [[ -n "${GH_API_STDERR:-}" ]]; then
    printf '%s\n' "${GH_API_STDERR}" >&2
  fi
  if [[ -n "${GH_API_DELETE_GIT_DIR:-}" && -n "${GH_API_DELETE_REF:-}" ]]; then
    git --git-dir "${GH_API_DELETE_GIT_DIR}" update-ref -d "${GH_API_DELETE_REF}" >/dev/null 2>&1 || true
  fi
  exit "${GH_API_RC:-0}"
fi

if [[ "${1:-}" == "api" && -n "${2:-}" ]]; then
  if [[ -n "${GH_EXPECT_CWD:-}" && "${PWD}" != "${GH_EXPECT_CWD}" ]]; then
    printf 'unexpected gh cwd: %s\n' "${PWD}" >&2
    exit 97
  fi
  if [[ -n "${GH_EXPECT_API_GET_ROUTE:-}" && "${2:-}" != "${GH_EXPECT_API_GET_ROUTE}" ]]; then
    printf 'unexpected gh api route: %s\n' "${2:-}" >&2
    exit 99
  fi
  if [[ -n "${GH_API_GET_STDOUT:-}" ]]; then
    printf '%s\n' "${GH_API_GET_STDOUT}"
  fi
  if [[ -n "${GH_API_GET_STDERR:-}" ]]; then
    printf '%s\n' "${GH_API_GET_STDERR}" >&2
  fi
  exit "${GH_API_GET_RC:-0}"
fi

printf 'unsupported fake gh invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/gh"

    printf '%s\n' "${fake_bin}"
}

run_worktree_plan() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" plan --repo "$repo_dir" "$@"
}

run_worktree_attach() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" "$@"
}

run_worktree_create() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" "$@"
}

run_worktree_doctor() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" doctor --repo "$repo_dir" "$@"
}

run_worktree_finish() {
    local repo_dir="$1"
    local fake_bin="$2"
    shift 2

    PATH="${fake_bin}:$PATH" "$WORKTREE_READY_SCRIPT" finish --repo "$repo_dir" "$@"
}

run_worktree_cleanup() {
    local repo_dir="$1"
    local path_prefix="$2"
    shift 2

    PATH="${path_prefix}:$PATH" "$WORKTREE_READY_SCRIPT" cleanup --repo "$repo_dir" "$@"
}

create_fake_direnv_permission_denied_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/direnv-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/direnv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "export" && "${2:-}" == "json" ]]; then
  printf 'direnv: error open /Users/test/.local/share/direnv/allow/demo: operation not permitted\n' >&2
  exit 1
fi

printf 'unsupported fake direnv invocation\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/direnv"

    printf '%s\n' "${fake_bin}"
}

create_failing_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/failing-bd-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'simulated bd failure\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

create_fake_uname_darwin_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/uname-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-s" || "$#" -eq 0 ]]; then
  printf 'Darwin\n'
  exit 0
fi

/usr/bin/uname "$@"
EOF
    chmod +x "${fake_bin}/uname"

    printf '%s\n' "${fake_bin}"
}

create_fake_osascript_success_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/osascript-success-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
    chmod +x "${fake_bin}/osascript"

    printf '%s\n' "${fake_bin}"
}

create_fake_osascript_failure_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/osascript-failure-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'simulated osascript failure\n' >&2
exit 1
EOF
    chmod +x "${fake_bin}/osascript"

    printf '%s\n' "${fake_bin}"
}

create_fake_codex_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/codex-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
    chmod +x "${fake_bin}/codex"

    printf '%s\n' "${fake_bin}"
}

seed_fake_guard_script() {
    local worktree_dir="$1"
    local raw_status="${2:-ok}"

    mkdir -p "${worktree_dir}/scripts"
    cat > "${worktree_dir}/scripts/git-session-guard.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "--status" ]]; then
  printf 'status=%s\n' "${raw_status}"
  exit 0
fi

if [[ "\${1:-}" == "--refresh" ]]; then
  printf 'status=ok\n'
  exit 0
fi

printf 'unsupported guard invocation\n' >&2
exit 1
EOF
    chmod +x "${worktree_dir}/scripts/git-session-guard.sh"
}

seed_fake_local_beads_runtime() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    : > "${worktree_dir}/.beads/beads.db"
}

seed_fake_beads_issues() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads"
cat > "${repo_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"molt-2","title":"Implement Codex CLI update monitor from Speckit seed","description":"Create the dedicated feature branch/worktree and run the Speckit workflow using docs/plans/codex-cli-update-monitoring-speckit-seed.md and docs/research/codex-cli-update-monitoring-2026-03-09.md as inputs."}
{"id":"moltinger-dmi","title":"Controlled Telegram webhook rollout"}
EOF
}

seed_fake_issue_artifacts() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/docs/plans" "${repo_dir}/docs/research"
    printf '# seed\n' > "${repo_dir}/docs/plans/codex-cli-update-monitoring-speckit-seed.md"
    printf '# research\n' > "${repo_dir}/docs/research/codex-cli-update-monitoring-2026-03-09.md"
    printf '# research index\n' > "${repo_dir}/docs/research/README.md"
}

seed_fake_ambiguous_beads_issues() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads"
cat > "${repo_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"molt","title":"Broad umbrella epic"}
{"id":"molt-2","title":"Implement Codex CLI update monitor from Speckit seed"}
EOF
}

seed_fake_topology_registry_script() {
    local repo_dir="$1"
    local raw_status="${2:-stale}"

    mkdir -p "${repo_dir}/scripts"
    cat > "${repo_dir}/scripts/git-topology-registry.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "check" ]]; then
  printf 'status=%s\n' "${raw_status}"
  if [[ "${raw_status}" == "stale" ]]; then
    printf "Dispatch the shared publish flow via: scripts/git-topology-registry.sh publish\n"
    exit 1
  fi
  exit 0
fi

printf 'unsupported fake topology invocation\n' >&2
exit 1
EOF
    chmod +x "${repo_dir}/scripts/git-topology-registry.sh"
}

test_plan_creates_clean_slug_without_issue() {
    test_start "worktree_ready_plan_creates_clean_slug_without_issue"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening)"

    assert_contains "$output" 'Branch: feat/remote-uat-hardening' "Slug-only plan should derive a clean feature branch"
    assert_contains "$output" 'Preview: ../moltinger-remote-uat-hardening' "Slug-only plan should derive a clean sibling worktree path"
    assert_contains "$output" 'Decision: create_clean' "Slug-only plan should choose clean creation when there are no collisions"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_normalizes_issue_short_in_worktree_path() {
    test_start "worktree_ready_plan_normalizes_issue_short_in_worktree_path"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --issue moltinger-dmi --slug telegram-webhook-rollout)"

    assert_contains "$output" 'Branch: feat/moltinger-dmi-telegram-webhook-rollout' "Issue-aware plan should keep the full issue id in the branch name"
    assert_contains "$output" 'Preview: ../moltinger-dmi-telegram-webhook-rollout' "Issue-aware plan should strip the repo prefix from the worktree suffix"
    assert_contains "$output" 'Decision: create_clean' "Issue-aware plan should stay clean when no collisions exist"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_derives_numeric_branch_for_explicit_speckit_request() {
    test_start "worktree_ready_plan_derives_numeric_branch_for_explicit_speckit_request"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug codex-update-monitor --speckit)"

    assert_contains "$output" 'Branch: 001-codex-update-monitor' "Explicit Speckit planning should allocate a numeric feature branch"
    assert_contains "$output" 'Preview: ../moltinger-001-codex-update-monitor' "Explicit Speckit planning should derive a numeric sibling worktree path"
    assert_contains "$output" 'Decision: create_clean' "Explicit Speckit planning should stay on the clean-create path when no collisions exist"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_reuses_existing_numeric_branch_for_speckit_issue() {
    test_start "worktree_ready_plan_reuses_existing_numeric_branch_for_speckit_issue"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    seed_fake_beads_issues "$repo_dir"
    git_topology_fixture_add_local_branch "$repo_dir" "007-codex-update-monitor" "main"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --issue molt-2 --slug codex-update-monitor)"

    assert_contains "$output" 'Branch: 007-codex-update-monitor' "Speckit-linked issue planning should reuse the exact numeric branch when it already exists"
    assert_contains "$output" 'Preview: ../moltinger-007-codex-update-monitor' "Speckit-linked issue planning should show the numeric sibling worktree path"
    assert_contains "$output" 'Decision: attach_existing_branch' "Existing exact numeric branch should attach instead of generating a legacy feat branch"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_reuses_existing_attached_worktree() {
    test_start "worktree_ready_plan_reuses_existing_attached_worktree"

    local fixture_root repo_dir fake_bin output existing_path
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening)"

    assert_contains "$output" 'Decision: reuse_existing' "Exact attached branch should be reused instead of duplicated"
    assert_contains "$output" "$existing_path" "Plan should point to the existing worktree path"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_reports_clean_preview_for_existing_feature_branch() {
    test_start "worktree_ready_attach_reports_clean_preview_for_existing_feature_branch"

    local fixture_root repo_dir fake_bin output existing_path
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"

    output="$(run_worktree_attach "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --handoff manual)"

    assert_contains "$output" 'Preview: ../moltinger-remote-uat-hardening' "Attach flow should reuse the normalized sibling preview for feature branches"
    assert_contains "$output" "$existing_path" "Attach flow should report the already-attached worktree path"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_attaches_existing_local_branch() {
    test_start "worktree_ready_plan_attaches_existing_local_branch"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening" "main"

    output="$(run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening)"

    assert_contains "$output" 'Decision: attach_existing_branch' "Existing unattached local branch should switch the plan into attach mode"
    assert_contains "$output" 'Question: A local branch already exists for this request.' "Attach plan should explain why creation is not the default"

    rm -rf "$fixture_root"
    test_pass
}

test_plan_asks_once_when_similar_branch_exists() {
    test_start "worktree_ready_plan_asks_once_when_similar_branch_exists"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening-v2" "main"

    output="$(
        set +e
        run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "10" "$rc" "Similar branch names should now return the clarification exit code"
    assert_contains "$output" 'Decision: needs_clarification' "Similar branch names should trigger one clarification instead of silent duplication"
    assert_contains "$output" 'clean worktree' "Clarification question should keep the clean-new option explicit"
    assert_contains "$output" 'feat/remote-uat-hardening-v2' "Clarification output should include the strongest similar candidate"

    rm -rf "$fixture_root"
    test_pass
}

test_create_treats_direnv_permission_denied_as_needs_env_approval() {
    test_start "worktree_ready_create_treats_direnv_permission_denied_as_needs_env_approval"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-remote-uat-hardening"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/remote-uat-hardening --path "$probe_dir"
    )"

    assert_contains "$output" 'Status: needs_env_approval' "Permission-denied direnv probe should still guide the user through env approval"
    assert_contains "$output" 'direnv allow' "Permission-denied direnv probe should suggest the safe recovery step"
    assert_contains "$output" '```bash' "Manual handoff should render a fenced bash block for copy-paste"
    assert_contains "$output" "cd ${probe_dir}" "Manual handoff bash block should include the target worktree path"
    assert_contains "$output" 'codex' "Manual handoff bash block should end with the Codex launch command"

    rm -rf "$fixture_root"
    test_pass
}

test_create_env_format_emits_handoff_boundary_contract() {
    test_start "worktree_ready_create_env_format_emits_handoff_boundary_contract"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-remote-uat-hardening"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/remote-uat-hardening --path "$probe_dir" --format env
    )"

    assert_contains "$output" 'schema=worktree-handoff/v1' "Create env output should expose the handoff schema"
    assert_contains "$output" 'phase=create' "Create env output should declare the create phase"
    assert_contains "$output" 'boundary=stop_after_create' "Create env output should declare the hard handoff boundary"
    assert_contains "$output" 'final_state=handoff_needs_env_approval' "Blocked env approval should map to the env-approval final state"
    assert_contains "$output" 'approval_required=true' "Blocked env approval should require approval explicitly"
    assert_contains "$output" 'handoff_mode=manual' "Default handoff mode should remain manual"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_env_format_emits_handoff_boundary_contract() {
    test_start "worktree_ready_attach_env_format_emits_handoff_boundary_contract"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin existing_path output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    printf 'export DEMO=1\n' > "${existing_path}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" --branch feat/remote-uat-hardening --format env
    )"

    assert_contains "$output" 'schema=worktree-handoff/v1' "Attach env output should expose the handoff schema"
    assert_contains "$output" 'phase=attach' "Attach env output should declare the attach phase"
    assert_contains "$output" 'boundary=stop_after_attach' "Attach env output should declare the hard attach handoff boundary"
    assert_contains "$output" 'final_state=handoff_needs_env_approval' "Attach env output should map blocked env approval to the env-approval final state"
    assert_contains "$output" 'approval_required=true' "Attach env output should require approval explicitly when direnv is blocked"
    assert_contains "$output" 'handoff_mode=manual' "Attach env output should keep manual handoff as the default"

    rm -rf "$fixture_root"
    test_pass
}

test_create_uses_explicit_pending_summary() {
    test_start "worktree_ready_create_uses_explicit_pending_summary"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-openclaw-control-plane"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/openclaw-control-plane --path "$probe_dir" \
          --pending-summary "Start Speckit for the OpenClaw Control Plane epic in the target worktree."
    )"

    assert_contains "$output" 'Pending: Start Speckit for the OpenClaw Control Plane epic in the target worktree.' "Explicit downstream intent should replace the generic pending handoff text"
    assert_contains "$output" '```text' "Explicit downstream intent should append the advisory Phase B text block"
    assert_contains "$output" 'Phase B only.' "Explicit downstream intent should use the fixed Phase B seed prompt header"
    assert_contains "$output" 'Task: Start Speckit for the OpenClaw Control Plane epic in the target worktree.' "Phase B seed prompt should preserve the exact downstream task"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/openclaw-control-plane --path "$probe_dir" \
          --pending-summary "Start Speckit for the OpenClaw Control Plane epic in the target worktree." --format env
    )"

    assert_contains "$output" 'pending=Start\ Speckit\ for\ the\ OpenClaw\ Control\ Plane\ epic\ in\ the\ target\ worktree.' "Env contract should preserve explicit pending handoff intent"

    rm -rf "$fixture_root"
    test_pass
}

test_create_preserves_separate_phase_b_seed_payload() {
    test_start "worktree_ready_create_preserves_separate_phase_b_seed_payload"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output phase_b_seed
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-openclaw-control-plane"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"
    phase_b_seed=$'Feature Description: Create a feature for hardening the command-worktree Phase A / Phase B boundary and manual handoff contract.\nConstraints: do not deploy; do not weaken the stop-after-handoff boundary.\nDefaults: manual handoff remains default; explicit codex/terminal launch remains opt-in only.'

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/openclaw-control-plane --path "$probe_dir" \
          --pending-summary "Start Speckit for the OpenClaw Control Plane epic in the target worktree." \
          --phase-b-seed-payload "$phase_b_seed"
    )"

    assert_contains "$output" 'Pending: Start Speckit for the OpenClaw Control Plane epic in the target worktree.' "Short pending summary should remain a distinct quick-scan field"
    assert_contains "$output" 'Phase B Seed Payload (deferred, not executed).' "Human handoff should render a separate richer deferred payload block"
    assert_contains "$output" 'Payload:' "Richer payload block should clearly mark the payload body"
    assert_contains "$output" 'Feature Description: Create a feature for hardening the command-worktree Phase A / Phase B boundary and manual handoff contract.' "Richer payload block should preserve the exact feature description"
    assert_contains "$output" 'Constraints: do not deploy; do not weaken the stop-after-handoff boundary.' "Richer payload block should preserve critical constraints"
    assert_contains "$output" 'Defaults: manual handoff remains default; explicit codex/terminal launch remains opt-in only.' "Richer payload block should preserve default handoff rules"
    assert_contains "$output" 'Phase A is complete. Do not repeat worktree setup in the originating session.' "Richer payload block should restate the stop boundary"
    if [[ "$output" == *'Phase B only.'* ]]; then
        test_fail "Rich handoff payload should replace the short Phase B only block instead of rendering both"
    fi

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/openclaw-control-plane --path "$probe_dir" \
          --pending-summary "Start Speckit for the OpenClaw Control Plane epic in the target worktree." \
          --phase-b-seed-payload "$phase_b_seed" --format env
    )"

    assert_contains "$output" 'pending=Start\ Speckit\ for\ the\ OpenClaw\ Control\ Plane\ epic\ in\ the\ target\ worktree.' "Env contract should keep the short pending summary separate"
    assert_contains "$output" "phase_b_seed_payload=\$'Feature Description: Create a feature for hardening the command-worktree" "Env contract should expose the richer payload in a separate field"
    assert_contains "$output" 'Constraints: do not deploy; do not weaken the stop-after-handoff boundary.' "Env contract should preserve constraints inside the richer payload"
    assert_contains "$output" 'Defaults: manual handoff remains default; explicit codex/terminal launch remains opt-in only.' "Env contract should preserve defaults inside the richer payload"

    rm -rf "$fixture_root"
    test_pass
}

test_create_infers_issue_from_issue_aware_branch_name() {
    test_start "worktree_ready_create_infers_issue_from_issue_aware_branch_name"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-molt-2-codex-update-monitor-new"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"
    seed_fake_beads_issues "${repo_dir}"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/molt-2-codex-update-monitor-new --path "$probe_dir"
    )"

    assert_contains "$output" 'Issue: molt-2' "Issue-aware branch names should infer the Beads issue id in human handoff output"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/molt-2-codex-update-monitor-new --path "$probe_dir" --format env
    )"

    assert_contains "$output" 'issue=molt-2' "Issue-aware branch names should infer the Beads issue id in env handoff output"

    rm -rf "$fixture_root"
    test_pass
}

test_create_returns_issue_na_when_branch_mapping_is_ambiguous() {
    test_start "worktree_ready_create_returns_issue_na_when_branch_mapping_is_ambiguous"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-molt-2-codex-update-monitor-new"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"
    seed_fake_ambiguous_beads_issues "${repo_dir}"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/molt-2-codex-update-monitor-new --path "$probe_dir"
    )"

    assert_contains "$output" 'Issue: n/a' "Ambiguous branch-to-issue mappings should fall back to Issue: n/a in human output"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/molt-2-codex-update-monitor-new --path "$probe_dir" --format env
    )"

    assert_contains "$output" 'issue=n/a' "Ambiguous branch-to-issue mappings should fall back to n/a in env output"

    rm -rf "$fixture_root"
    test_pass
}

test_create_surfaces_source_only_issue_artifacts_when_target_lacks_them() {
    test_start "worktree_ready_create_surfaces_source_only_issue_artifacts_when_target_lacks_them"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin probe_dir output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-molt-2-codex-update-monitor-new"
    mkdir -p "${probe_dir}"
    printf 'export DEMO=1\n' > "${probe_dir}/.envrc"
    seed_fake_beads_issues "${repo_dir}"
    seed_fake_issue_artifacts "${repo_dir}"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/molt-2-codex-update-monitor-new --path "$probe_dir"
    )"

    assert_contains "$output" 'Issue Title: Implement Codex CLI update monitor from Speckit seed' "Handoff should include the resolved issue title when available"
    assert_contains "$output" 'Issue Artifacts:' "Handoff should enumerate issue-linked repo artifacts"
    assert_contains "$output" 'docs/plans/codex-cli-update-monitoring-speckit-seed.md [source only; missing in target]' "Missing seed docs should be called out as source-only context"
    assert_contains "$output" "Issue 'molt-2' is not present in target worktree Beads state" "Handoff should explain why local bd lookups will fail in the target worktree"
    assert_contains "$output" "Issue artifact 'docs/research/codex-cli-update-monitoring-2026-03-09.md' is not present in the target worktree." "Handoff should warn when issue artifacts are absent from the target worktree"
    assert_contains "$output" 'Bootstrap Source: origin/main' "Bootstrap handoff should prefer the current branch upstream as the source ref"
    assert_contains "$output" 'Bootstrap Files:' "Bootstrap handoff should enumerate the files that need to be imported"
    assert_contains "$output" '.beads/issues.jsonl' "Bootstrap handoff should include the Beads issue state file"
    assert_contains "$output" 'docs/research/README.md' "Bootstrap handoff should include the research index when research artifacts are source-only"
    assert_contains "$output" 'git checkout origin/main -- .beads/issues.jsonl docs/plans/codex-cli-update-monitoring-speckit-seed.md docs/research/codex-cli-update-monitoring-2026-03-09.md docs/research/README.md' "Manual handoff should include an exact bootstrap import command before launch"

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" create --repo "$repo_dir" --branch feat/molt-2-codex-update-monitor-new --path "$probe_dir" --format env
    )"

    assert_contains "$output" 'issue_title=Implement\ Codex\ CLI\ update\ monitor\ from\ Speckit\ seed' "Env handoff should preserve the issue title"
    assert_contains "$output" 'issue_artifact_count=2' "Env handoff should enumerate linked issue artifacts"
    assert_contains "$output" 'bootstrap_source=origin/main' "Env handoff should expose the source ref for bootstrap imports"
    assert_contains "$output" 'bootstrap_file_count=4' "Env handoff should enumerate the bootstrap files needed in the target worktree"

    rm -rf "$fixture_root"
    test_pass
}

test_create_without_existing_worktree_points_to_phase_a_executor() {
    test_start "worktree_ready_create_without_existing_worktree_points_to_phase_a_executor"

    local fixture_root repo_dir canonical_repo_dir fake_bd_bin probe_dir output rc expected_create_command
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    canonical_repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    probe_dir="${fixture_root}/moltinger-main-034-moltis-skill-discovery-and-telegram-leak-regressions"
    expected_create_command="scripts/worktree-phase-a.sh create-from-base --canonical-root ${canonical_repo_dir} --base-ref main --branch 034-moltis-skill-discovery-and-telegram-leak-regressions --path ${probe_dir}"

    output="$(
        set +e
        run_worktree_create "$repo_dir" "$fake_bd_bin" --branch 034-moltis-skill-discovery-and-telegram-leak-regressions --path "$probe_dir" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Create helper should return the blocked action-required exit code when no worktree exists yet"
    assert_contains "$output" 'Status: action_required' "Create helper should block when the target worktree has not been allocated yet"
    assert_contains "$output" 'worktree-ready create is a post-Phase-A handoff helper; it does not allocate the branch or git worktree by itself.' "Create helper should explain the Phase A boundary explicitly"
    assert_contains "$output" "$expected_create_command" "Create helper should route missing-worktree cases to the exact Phase A executor command"
    if [[ "$output" == *'Retry the managed worktree flow from the invoking worktree after fixing the reported prerequisites'* ]]; then
        test_fail "Create helper should not fall back to the old generic retry guidance when no worktree exists yet"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_branch_only_suppresses_already_attached_warning() {
    test_start "worktree_ready_doctor_branch_only_suppresses_already_attached_warning"

    local fixture_root repo_dir fake_bin output existing_path rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"

    output="$(
        set +e
        run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Branch-only doctor should still block when the fixture is genuinely missing guard and Beads state"
    assert_contains "$output" "Worktree: ${existing_path}" "Doctor should report the discovered attached worktree path"
    assert_contains "$output" 'Status: action_required' "Doctor should still surface actionable diagnostics when prerequisites are genuinely missing"
    if [[ "$output" == *"already attached at"* ]]; then
        test_fail "Branch-only doctor should not emit the false already-attached warning"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_accepts_local_beads_state() {
    test_start "worktree_ready_doctor_accepts_local_beads_state"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    seed_fake_local_beads_runtime "${existing_path}"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_STATUS_STDOUT="ok" \
        run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Doctor should accept a local Beads worktree as ready"
    assert_contains "$output" "Worktree: ${existing_path}" "Doctor should report the discovered attached worktree path"
    assert_contains "$output" 'Status: ready_for_codex' "Local Beads ownership plus an OK guard should be considered ready"
    assert_contains "$output" 'Beads: local' "Doctor should surface local Beads ownership explicitly"
    assert_contains "$output" 'Beads Runtime: healthy' "Doctor should prove local runtime health separately from ownership state"
    if [[ "$output" == *"./scripts/beads-worktree-localize.sh --path ."* ]]; then
        test_fail "Doctor should not route already-local Beads ownership through the localization helper"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_blocks_runtime_bootstrap_required_when_external_state_says_local() {
    test_start "worktree_ready_doctor_blocks_runtime_bootstrap_required_when_external_state_says_local"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json doctor_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-broken-runtime-doctor"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/broken-runtime-doctor" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    mkdir -p "${existing_path}/.beads/dolt/.dolt"
    cat > "${existing_path}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${existing_path}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed"}
EOF
    bd_json="$(printf '[{"name":"broken-runtime-doctor","path":"%s","branch":"feat/broken-runtime-doctor","beads_state":"local"}]\n' "${existing_path}")"
    doctor_json='{"checks":[{"name":"Metadata Config","status":"error","message":"metadata.json is missing"},{"name":"Database","status":"error","message":"Unable to open database","detail":"database \"beads\" not found"}],"overall_ok":false}'

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_STATUS_RC="1" \
        BD_STATUS_STDERR='database "beads" not found' \
        BD_DOCTOR_STDOUT="${doctor_json}" \
        run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/broken-runtime-doctor 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Doctor must fail closed when ownership says local but runtime still needs bootstrap"
    assert_contains "$output" 'Beads: local' "Doctor should preserve ownership discovery separately from runtime health"
    assert_contains "$output" 'Beads Runtime: runtime_bootstrap_required' "Doctor must surface runtime bootstrap repair as the real blocker"
    assert_contains "$output" '/usr/local/bin/bd doctor --json' "Doctor must route broken local runtimes through the official runtime diagnostic path"
    assert_contains "$output" './scripts/beads-worktree-localize.sh --path .' "Doctor must route broken local runtimes through the managed runtime repair helper"
    if [[ "$output" == *"./scripts/git-session-guard.sh --refresh"* ]]; then
        test_fail "Doctor should not prioritize guard refresh ahead of a broken local runtime"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_does_not_block_on_beads_probe_unavailable() {
    test_start "worktree_ready_doctor_does_not_block_on_beads_probe_unavailable"

    local fixture_root repo_dir failing_bd_bin existing_path restricted_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    failing_bd_bin="$(create_failing_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    printf 'export DEMO=1\n' > "${existing_path}/.envrc"
    restricted_path="${failing_bd_bin}:/usr/bin:/bin"

    output="$(
        set +e
        PATH="${restricted_path}" "$WORKTREE_READY_SCRIPT" doctor --repo "$repo_dir" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Doctor should not hard-fail solely because the Beads probe is unavailable"
    assert_contains "$output" 'Status: created' "Unavailable probes should degrade readiness instead of blocking the worktree"
    assert_contains "$output" 'Beads worktree state could not be probed from this session.' "Doctor should explain that the Beads probe itself failed"
    assert_contains "$output" 'Install direnv or launch the session from an environment where direnv is available' "Doctor should emit a viable env recovery step when direnv is unavailable"
    if [[ "$output" == *"bd worktree list"* ]]; then
        test_fail "Doctor should not suggest bd worktree list when the Beads probe itself is unavailable"
    fi
    if [[ "$output" == *"direnv status"* ]]; then
        test_fail "Doctor should not suggest direnv status when direnv is unavailable"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_missing_guard_script_does_not_suggest_refresh() {
    test_start "worktree_ready_doctor_missing_guard_script_does_not_suggest_refresh"

    local fixture_root repo_dir fake_bin existing_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"

    output="$(
        set +e
        run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Missing guard script should still block doctor when the target lacks required readiness state"
    assert_contains "$output" "inspect scripts/git-session-guard.sh availability" "Doctor should suggest inspecting the missing guard script, not refreshing it"
    if [[ "$output" == *"./scripts/git-session-guard.sh --refresh"* ]]; then
        test_fail "Doctor should not suggest refreshing a guard script that is not present"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_missing_worktree_routes_back_to_managed_attach() {
    test_start "worktree_ready_doctor_missing_worktree_routes_back_to_managed_attach"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening" "main"

    output="$(
        set +e
        run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Missing worktree should still block doctor"
    assert_contains "$output" "Use command-worktree attach feat/remote-uat-hardening from the invoking worktree" "Doctor should route missing-worktree recovery back to the managed attach flow"
    if [[ "$output" == *"bd worktree create"* ]]; then
        test_fail "Doctor should not suggest raw bd worktree create for an existing unattached branch"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_missing_beads_state_routes_to_localize_helper() {
    test_start "worktree_ready_doctor_missing_beads_state_routes_to_localize_helper"

    local fixture_root repo_dir fake_bin existing_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-beads-localize"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/beads-localize" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "$existing_path" "ok"

    output="$(
        set +e
        run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/beads-localize 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Missing Beads ownership should still block doctor"
    assert_contains "$output" "./scripts/beads-worktree-localize.sh --path ." "Doctor should route dedicated-worktree Beads recovery through the managed localization helper"
    if [[ "$output" == *"bd worktree create"* ]]; then
        test_fail "Doctor should not suggest raw bd worktree create for Beads ownership recovery"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_doctor_stale_topology_remains_warning_not_blocker() {
    test_start "worktree_ready_doctor_stale_topology_remains_warning_not_blocker"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    seed_fake_local_beads_runtime "${existing_path}"
    seed_fake_topology_registry_script "${repo_dir}" "stale"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_doctor "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Stale topology should remain non-blocking for ordinary doctor"
    assert_contains "$output" 'Status: ready_for_codex' "Ordinary doctor should remain ready when stale topology is the only issue"
    assert_contains "$output" 'Topology: stale' "Ordinary doctor should surface stale topology explicitly"
    assert_contains "$output" 'scripts/git-topology-registry.sh publish' "Ordinary doctor should defer topology publication to the shared publish flow"
    if [[ "$output" == *'refresh --write-doc'* ]]; then
        test_fail "Ordinary doctor should not suggest auto-publishing topology from the current branch"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_finish_returns_issue_na_when_branch_mapping_is_ambiguous() {
    test_start "worktree_ready_finish_returns_issue_na_when_branch_mapping_is_ambiguous"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-molt-2-codex-update-monitor-new"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/molt-2-codex-update-monitor-new" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    seed_fake_local_beads_runtime "${existing_path}"
    seed_fake_ambiguous_beads_issues "${repo_dir}"
    bd_json="$(printf '[{"name":"molt-2-codex-update-monitor-new","path":"%s","branch":"feat/molt-2-codex-update-monitor-new","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_finish "$repo_dir" "$fake_bin" --branch feat/molt-2-codex-update-monitor-new 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Ambiguous issue mapping should not block ordinary finish"
    assert_contains "$output" 'Issue: n/a' "Ambiguous finish mappings should fall back to Issue: n/a"
    assert_contains "$output" 'Status: finish_ready' "Ordinary finish should remain ready when ambiguity only affects close resolution"
    assert_contains "$output" 'Phase: finish' "Finish helper should report the finish phase explicitly"
    assert_contains "$output" 'Boundary: stop_before_finish' "Finish helper should stop before executing finish mutations"
    assert_contains "$output" 'Close: skip' "Issue: n/a should skip bd close in ordinary finish output"
    assert_contains "$output" 'bd preflight --check' "Finish helper should render the ordinary finish preflight command"
    if [[ "$output" == *'Close: bd close '* ]]; then
        test_fail "Ambiguous ordinary finish should not render a bd close command"
    fi
    if [[ "$output" == *"./scripts/beads-worktree-localize.sh --path ."* ]]; then
        test_fail "Ordinary finish should not route already-local Beads ownership through the localization helper"
    fi

    output="$(
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_finish "$repo_dir" "$fake_bin" --branch feat/molt-2-codex-update-monitor-new --format env
    )"

    assert_contains "$output" 'issue=n/a' "Finish env output should expose Issue: n/a when branch mapping is ambiguous"
    assert_contains "$output" 'close_action=skip' "Finish env output should expose skip-close behavior for Issue: n/a"

    rm -rf "$fixture_root"
    test_pass
}

test_finish_blocks_runtime_bootstrap_required_when_external_state_says_local() {
    test_start "worktree_ready_finish_blocks_runtime_bootstrap_required_when_external_state_says_local"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json doctor_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-broken-runtime-finish"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/broken-runtime-finish" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    mkdir -p "${existing_path}/.beads/dolt/.dolt"
    cat > "${existing_path}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${existing_path}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed"}
EOF
    bd_json="$(printf '[{"name":"broken-runtime-finish","path":"%s","branch":"feat/broken-runtime-finish","beads_state":"local"}]\n' "${existing_path}")"
    doctor_json='{"checks":[{"name":"Metadata Config","status":"error","message":"metadata.json is missing"},{"name":"Database","status":"error","message":"Unable to open database","detail":"database \"beads\" not found"}],"overall_ok":false}'

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_STATUS_RC="1" \
        BD_STATUS_STDERR='database "beads" not found' \
        BD_DOCTOR_STDOUT="${doctor_json}" \
        run_worktree_finish "$repo_dir" "$fake_bin" --branch feat/broken-runtime-finish 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Finish must fail closed when the local runtime still needs bootstrap"
    assert_contains "$output" 'Beads Runtime: runtime_bootstrap_required' "Finish must surface runtime health separately from ownership"
    assert_contains "$output" '/usr/local/bin/bd doctor --json' "Finish must point operators at the canonical runtime diagnostic path"
    assert_contains "$output" './scripts/beads-worktree-localize.sh --path .' "Finish must require the managed runtime repair helper before ordinary finish commands"
    if [[ "$output" == *'bd preflight --check'* ]]; then
        test_fail "Finish should stop before preflight/commit commands when the runtime itself is broken"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_finish_stale_topology_remains_warning_not_blocker() {
    test_start "worktree_ready_finish_stale_topology_remains_warning_not_blocker"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    seed_fake_guard_script "${existing_path}" "ok"
    seed_fake_local_beads_runtime "${existing_path}"
    seed_fake_topology_registry_script "${repo_dir}" "stale"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_finish "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Stale topology should remain non-blocking for ordinary finish"
    assert_contains "$output" 'Status: finish_ready' "Ordinary finish should stay ready when stale topology is the only issue"
    assert_contains "$output" 'Phase: finish' "Ordinary finish should render the finish phase"
    assert_contains "$output" 'Final State: finish_ready' "Ordinary finish should keep a ready final state when topology is merely stale"
    assert_contains "$output" 'Topology: stale' "Ordinary finish should surface stale topology explicitly"
    assert_contains "$output" 'scripts/git-topology-registry.sh publish' "Ordinary finish should defer topology publication to the shared publish flow"
    if [[ "$output" == *'refresh --write-doc'* ]]; then
        test_fail "Ordinary finish should not suggest auto-publishing topology from the current branch"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_plan_needs_clarification_returns_exit_code_10() {
    test_start "worktree_ready_plan_needs_clarification_returns_exit_code_10"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    git_topology_fixture_add_local_branch "$repo_dir" "feat/remote-uat-hardening-v2" "main"

    output="$(
        set +e
        run_worktree_plan "$repo_dir" "$fake_bin" --slug remote-uat-hardening --format env 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "10" "$rc" "Ambiguous plan output should return the clarification exit code"
    assert_contains "$output" 'schema=worktree-plan/v1' "Plan env output should expose the planning schema"
    assert_contains "$output" 'decision=needs_clarification' "Plan env output should preserve the clarification decision"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_missing_branch_returns_blocked_missing_branch() {
    test_start "worktree_ready_attach_missing_branch_returns_blocked_missing_branch"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"

    output="$(
        set +e
        run_worktree_attach "$repo_dir" "$fake_bin" --branch feat/missing-line --format env 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "22" "$rc" "Missing existing branch should return the blocked-missing-branch exit code"
    assert_contains "$output" 'final_state=blocked_missing_branch' "Missing existing branch should map to the blocked missing branch final state"
    assert_contains "$output" 'repair_command=Create\ or\ fetch\ the\ branch' "Missing existing branch should emit an exact repair command"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_preserves_separate_phase_b_seed_payload() {
    test_start "worktree_ready_attach_preserves_separate_phase_b_seed_payload"

    local fixture_root repo_dir fake_bd_bin fake_direnv_bin existing_path output phase_b_seed
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_direnv_bin="$(create_fake_direnv_permission_denied_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    printf 'export DEMO=1\n' > "${existing_path}/.envrc"
    phase_b_seed=$'Feature Description: Continue the deferred review only from the attached worktree.\nConstraints: do not continue in the originating session.\nDefaults: manual handoff remains default.'

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" --branch feat/remote-uat-hardening \
          --pending-summary "Continue the deferred review from the attached worktree." \
          --phase-b-seed-payload "$phase_b_seed"
    )"

    assert_contains "$output" 'Boundary: stop_after_attach' "Attach handoff should preserve the attach boundary in human output"
    assert_contains "$output" 'Pending: Continue the deferred review from the attached worktree.' "Attach handoff should keep the concise pending summary"
    assert_contains "$output" 'Phase B Seed Payload (deferred, not executed).' "Attach handoff should render a separate richer deferred payload block"
    assert_contains "$output" 'Payload:' "Attach handoff should clearly mark the payload body"
    assert_contains "$output" 'Constraints: do not continue in the originating session.' "Attach handoff should preserve critical downstream constraints"
    assert_contains "$output" 'Defaults: manual handoff remains default.' "Attach handoff should preserve default handoff rules"
    assert_contains "$output" 'Phase A is complete. Do not repeat worktree setup in the originating session.' "Attach handoff should restate the stop boundary"
    if [[ "$output" == *'Phase B only.'* ]]; then
        test_fail "Attach rich handoff payload should replace the short Phase B only block instead of rendering both"
    fi

    output="$(
        PATH="${fake_direnv_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" --branch feat/remote-uat-hardening \
          --pending-summary "Continue the deferred review from the attached worktree." \
          --phase-b-seed-payload "$phase_b_seed" --format env
    )"

    assert_contains "$output" 'boundary=stop_after_attach' "Attach env output should preserve the attach boundary"
    assert_contains "$output" 'pending=Continue\ the\ deferred\ review\ from\ the\ attached\ worktree.' "Attach env contract should keep the short pending summary separate"
    assert_contains "$output" "phase_b_seed_payload=\$'Feature Description: Continue the deferred review only from the attached worktree." "Attach env contract should expose the richer payload in a separate field"
    assert_contains "$output" 'Constraints: do not continue in the originating session.' "Attach env contract should preserve critical constraints"
    assert_contains "$output" 'Defaults: manual handoff remains default.' "Attach env contract should preserve default handoff rules"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_terminal_handoff_launches_and_stops_at_handoff() {
    test_start "worktree_ready_attach_terminal_handoff_launches_and_stops_at_handoff"

    local fixture_root repo_dir fake_bd_bin fake_uname_bin fake_osascript_bin existing_path output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_uname_bin="$(create_fake_uname_darwin_bin "$fixture_root")"
    fake_osascript_bin="$(create_fake_osascript_success_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"

    output="$(
        WORKTREE_READY_DRY_RUN=1 \
        PATH="${fake_osascript_bin}:${fake_uname_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" --branch feat/remote-uat-hardening --handoff terminal --format env
    )"

    assert_contains "$output" 'boundary=stop_after_attach' "Automatic terminal handoff should preserve the attach stop boundary"
    assert_contains "$output" 'requested_handoff=terminal' "Env contract should preserve the explicit terminal handoff request"
    assert_contains "$output" 'handoff_mode=terminal' "Successful terminal handoff should keep the requested automatic handoff mode"
    assert_contains "$output" 'final_state=handoff_launched' "Successful automatic terminal handoff should report the launched handoff final state"
    if [[ "$output" != *"launch_command="*"osascript"* ]]; then
        test_fail "Successful automatic terminal handoff should expose the osascript launch command"
    fi
    assert_contains "$output" 'Dry-run\ mode\ enabled\;\ handoff\ command\ was\ not\ executed.' "Dry-run success path should still stop at the launched-handoff boundary"

    rm -rf "$fixture_root"
    test_pass
}

test_attach_codex_handoff_falls_back_to_manual_boundary() {
    test_start "worktree_ready_attach_codex_handoff_falls_back_to_manual_boundary"

    local fixture_root repo_dir fake_bd_bin fake_uname_bin fake_osascript_bin fake_codex_bin existing_path output
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_uname_bin="$(create_fake_uname_darwin_bin "$fixture_root")"
    fake_osascript_bin="$(create_fake_osascript_failure_bin "$fixture_root")"
    fake_codex_bin="$(create_fake_codex_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"

    output="$(
        PATH="${fake_osascript_bin}:${fake_codex_bin}:${fake_uname_bin}:${fake_bd_bin}:$PATH" \
        "$WORKTREE_READY_SCRIPT" attach --repo "$repo_dir" --branch feat/remote-uat-hardening --handoff codex --format env
    )"

    assert_contains "$output" 'boundary=stop_after_attach' "Automatic codex fallback should preserve the attach stop boundary"
    assert_contains "$output" 'requested_handoff=codex' "Fallback env contract should preserve the explicit codex handoff request"
    assert_contains "$output" 'handoff_mode=manual' "Failed automatic codex handoff should fall back to manual mode"
    assert_contains "$output" 'final_state=handoff_ready' "Failed automatic codex handoff should degrade to a manual-ready final state"
    assert_contains "$output" 'next_1=cd\ ' "Fallback should restore manual next-step commands instead of pretending the launch succeeded"
    assert_contains "$output" 'next_2=export\ PATH=' "Fallback should restore the plain bd bootstrap step before launching codex"
    assert_contains "$output" 'next_3=codex' "Fallback should keep the exact manual codex next step after bootstrap"
    assert_contains "$output" 'Automatic\ codex\ handoff\ failed.\ Falling\ back\ to\ manual\ steps.' "Fallback should be explicit in the warning stream"
    if [[ "$output" != *"Launch command:"*"osascript"* ]]; then
        test_fail "Fallback should expose the failed launch command for debugging"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_removes_linked_worktree_without_branch_delete() {
    test_start "worktree_ready_cleanup_removes_linked_worktree_without_branch_delete"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --format env 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup without branch deletion should succeed for a managed linked worktree"
    assert_contains "$output" 'schema=worktree-cleanup/v1' "Cleanup env output should expose the cleanup schema"
    assert_contains "$output" 'status=cleanup_complete' "Cleanup env output should report cleanup_complete on success"
    assert_contains "$output" 'worktree_action=removed' "Cleanup should mark the linked worktree as removed"
    assert_contains "$output" 'local_branch_action=not_requested' "Cleanup without --delete-branch should not touch local branches"
    assert_contains "$output" 'remote_branch_action=not_requested' "Cleanup without --delete-branch should not touch remote branches"
    if [[ -d "${existing_path}" ]]; then
        test_fail "Cleanup should remove the linked worktree directory"
    fi
    if git -C "$repo_dir" worktree list --porcelain | rg -q 'feat/remote-uat-hardening'; then
        test_fail "Cleanup should remove the linked worktree entry from git worktree list"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_prunes_stale_missing_worktree_entry() {
    test_start "worktree_ready_cleanup_prunes_stale_missing_worktree_entry"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    rm -rf "$existing_path"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should prune stale missing worktree entries"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should stay complete after pruning a stale entry"
    assert_contains "$output" 'Worktree Action: pruned' "Cleanup should report pruned when stale admin state was removed"
    if git -C "$repo_dir" worktree list --porcelain | rg -q 'feat/remote-uat-hardening'; then
        test_fail "Cleanup should prune the stale git worktree entry"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_delete_branch_uses_git_ancestor_proof() {
    test_start "worktree_ready_cleanup_delete_branch_uses_git_ancestor_proof"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should delete local and remote branch when git ancestry proves the branch is merged"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should complete once branch deletion succeeds"
    assert_contains "$output" 'Merge Check: git_ancestor_remote' "Cleanup should record refreshed remote ancestry as the merge proof"
    assert_contains "$output" 'Local Branch Action: deleted' "Cleanup should delete the local branch after worktree removal"
    assert_contains "$output" 'Remote Branch Action: deleted' "Cleanup should delete the remote branch after merge proof"
    if git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the local branch after delete-branch success"
    fi
    if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the remote branch after delete-branch success"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_uses_git_remove_fallback_for_false_unpushed_guard() {
    test_start "worktree_ready_cleanup_uses_git_remove_fallback_for_false_unpushed_guard"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git merge --no-ff feat/remote-uat-hardening -m "fixture: merge feature branch" >/dev/null
        git push origin main >/dev/null
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_WORKTREE_LIST_FILTER_MISSING=1 \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should recover when bd falsely reports unpushed commits for a merged clean worktree"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should complete after the direct git fallback removes the worktree"
    assert_contains "$output" 'Worktree Action: removed' "Cleanup should report the worktree as removed after the fallback"
    assert_contains "$output" 'Merge Check: git_ancestor_remote' "Cleanup should still require authoritative refreshed remote proof before using the fallback"
    assert_contains "$output" 'git worktree remove fallback succeeded' "Cleanup should explain that the direct git fallback was used"
    if [[ -d "$existing_path" ]]; then
        test_fail "Cleanup should remove the worktree directory after the fallback succeeds"
    fi
    if git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the local branch after the fallback succeeds"
    fi
    if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the remote branch after the fallback succeeds"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_does_not_bypass_false_unpushed_guard_without_merge_proof() {
    test_start "worktree_ready_cleanup_does_not_bypass_false_unpushed_guard_without_merge_proof"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup must stay blocked when bd reports unpushed commits and merged proof is missing"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should stay blocked when the fallback cannot establish merged proof"
    assert_contains "$output" 'Worktree Action: blocked' "Cleanup should not remove the worktree when the branch is not merged"
    assert_contains "$output" 'bd worktree remove failed' "Cleanup should preserve the original bd failure context when no safe fallback exists"
    if [[ ! -d "$existing_path" ]]; then
        test_fail "Cleanup must preserve the worktree when merged proof is missing"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the local branch when merged proof is missing"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the remote branch when merged proof is missing"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_does_not_bypass_false_unpushed_guard_for_dirty_worktree() {
    test_start "worktree_ready_cleanup_does_not_bypass_false_unpushed_guard_for_dirty_worktree"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git merge --no-ff feat/remote-uat-hardening -m "fixture: merge feature branch" >/dev/null
        git push origin main >/dev/null
    )
    (
        cd "$existing_path"
        printf 'dirty\n' > dirty.txt
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup must stay blocked when the worktree is dirty even if the branch is merged"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should stay blocked for a dirty worktree"
    assert_contains "$output" 'Worktree Action: blocked' "Cleanup should not remove a dirty worktree through the fallback path"
    assert_contains "$output" 'bd worktree remove failed' "Cleanup should preserve the bd failure context when the fallback is disallowed"
    if [[ ! -d "$existing_path" ]]; then
        test_fail "Cleanup must preserve the dirty worktree when the fallback is disallowed"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the local branch for a dirty worktree"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the remote branch for a dirty worktree"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_blocks_conflicting_path_and_branch_arguments() {
    test_start "worktree_ready_cleanup_blocks_conflicting_path_and_branch_arguments"

    local fixture_root repo_dir fake_bin path_worktree branch_worktree output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    path_worktree="${fixture_root}/moltinger-path-target"
    branch_worktree="${fixture_root}/moltinger-branch-target"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$path_worktree" "feat/path-target" "main"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$branch_worktree" "feat/branch-target" "main"
    path_worktree="$(cd "$path_worktree" && pwd -P)"
    branch_worktree="$(cd "$branch_worktree" && pwd -P)"
    (
        cd "$branch_worktree"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: branch target commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/branch-target >/dev/null
        git merge --no-ff feat/branch-target -m "fixture: merge branch target" >/dev/null
        git push origin main >/dev/null
    )
    bd_json="$(printf '[{"name":"path-target","path":"%s","branch":"feat/path-target","beads_state":"local"},{"name":"branch-target","path":"%s","branch":"feat/branch-target","beads_state":"local"}]\n' "${path_worktree}" "${branch_worktree}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --path "$path_worktree" --branch feat/branch-target --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup must fail closed when --path and --branch resolve to different worktrees"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should report cleanup_blocked for conflicting target arguments"
    assert_contains "$output" 'Cleanup arguments conflict' "Cleanup should explain the path/branch mismatch"
    if [[ ! -d "$path_worktree" ]]; then
        test_fail "Cleanup must not remove the worktree selected by --path when arguments conflict"
    fi
    if [[ ! -d "$branch_worktree" ]]; then
        test_fail "Cleanup must not touch the unrelated branch worktree when arguments conflict"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/branch-target; then
        test_fail "Cleanup must preserve the branch selected by the conflicting --branch argument"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/branch-target; then
        test_fail "Cleanup must preserve the remote branch selected by the conflicting --branch argument"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_accepts_alias_path_when_branch_matches_same_worktree() {
    test_start "worktree_ready_cleanup_accepts_alias_path_when_branch_matches_same_worktree"

    local fixture_root repo_dir fake_bin path_worktree alias_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    path_worktree="${fixture_root}/moltinger-path-target"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$path_worktree" "feat/path-target" "main"
    path_worktree="$(cd "$path_worktree" && pwd -P)"
    alias_path="${fixture_root}/moltinger-path-target-alias"
    ln -s "$path_worktree" "$alias_path"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON='[]' \
        BD_WORKTREE_REMOVE_CANONICALIZE=1 \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --path "$alias_path" --branch feat/path-target 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should accept an alias path when it resolves to the same worktree as the requested branch"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should complete when alias path and branch identify the same worktree"
    if [[ -d "$path_worktree" ]]; then
        test_fail "Cleanup should remove the real worktree even when the request uses an alias path"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_refreshes_remote_refs_before_using_local_merge_proof() {
    test_start "worktree_ready_cleanup_refreshes_remote_refs_before_using_local_merge_proof"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json second_clone
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git merge --no-ff feat/remote-uat-hardening -m "fixture: merge feature branch" >/dev/null
        git push origin main >/dev/null
    )
    second_clone="${fixture_root}/moltinger-second-clone"
    git clone "${fixture_root}/moltinger.git" "$second_clone" >/dev/null 2>&1
    (
        cd "$second_clone"
        git checkout feat/remote-uat-hardening >/dev/null 2>&1
        printf 'late\n' > late.txt
        git add late.txt
        git commit -m "fixture: late remote branch commit" >/dev/null
        git push origin feat/remote-uat-hardening >/dev/null
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup must block when a refreshed remote branch moved ahead and is no longer merged"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should stay blocked after refreshing remote refs reveals a live ahead branch"
    assert_contains "$output" 'Merge Check: not_merged' "Cleanup should refuse to trust stale local merge proof once the remote branch has moved"
    if [[ ! -d "$existing_path" ]]; then
        test_fail "Cleanup must preserve the worktree when the refreshed remote branch is not merged"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the local branch when the refreshed remote branch is not merged"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the refreshed remote-tracking branch when the remote branch moved ahead"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_uses_local_stale_proof_for_worktree_fallback_when_refresh_fails() {
    test_start "worktree_ready_cleanup_uses_local_stale_proof_for_worktree_fallback_when_refresh_fails"

    local fixture_root repo_dir fake_bin existing_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git merge --no-ff feat/remote-uat-hardening -m "fixture: merge feature branch" >/dev/null
        git push origin main >/dev/null
        git remote set-url origin "${fixture_root}/missing-origin.git"
    )

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="$(printf '[{\"name\":\"remote-uat-hardening\",\"path\":\"%s\",\"branch\":\"feat/remote-uat-hardening\",\"beads_state\":\"local\"}]\n' "${existing_path}")" \
        BD_WORKTREE_LIST_FILTER_MISSING=1 \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should allow git fallback worktree removal when only remote refresh is unavailable"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should still complete when no branch deletion was requested"
    assert_contains "$output" 'Merge Check: git_ancestor_local_stale' "Cleanup should record the degraded local-only merge proof for worktree fallback"
    assert_contains "$output" 'Remote ref refresh failed; using local merged ancestry only' "Cleanup should explain why it trusted local ancestry"
    if [[ -d "$existing_path" ]]; then
        test_fail "Cleanup should remove the worktree directory when local stale proof authorizes the fallback"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the local branch when only the worktree fallback is authorized"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the stale remote-tracking ref when branch deletion was not requested"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_delete_branch_uses_github_fallback_when_git_is_ambiguous() {
    test_start "worktree_ready_cleanup_delete_branch_uses_github_fallback_when_git_is_ambiguous"

    local fixture_root repo_dir fake_bd_bin fake_gh_bin existing_path output rc bd_json head_sha
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_gh_bin="$(create_fake_gh_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
    )
    head_sha="$(git -C "$repo_dir" rev-parse refs/remotes/origin/feat/remote-uat-hardening)"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        cd "$fixture_root"
        set +e
        WORKTREE_READY_ASSUME_GITHUB_ORIGIN=1 \
        GH_EXPECT_CWD="${repo_dir}" \
        GH_REPO_VIEW_JSON='{"defaultBranchRef":{"name":"main"},"deleteBranchOnMerge":false}' \
        GH_PR_LIST_JSON="$(printf '[{"number":103,"state":"MERGED","mergedAt":"2026-03-26T19:35:17Z","headRefName":"feat/remote-uat-hardening","headRefOid":"%s","baseRefName":"main","isCrossRepository":false,"url":"https://github.com/example/repo/pull/103","title":"Fixture merged PR"}]\n' "${head_sha}")" \
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        run_worktree_cleanup "$repo_dir" "${fake_gh_bin}:${fake_bd_bin}" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should allow branch deletion when GitHub merged-PR metadata proves merge safety"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should complete when GitHub fallback proves merge safety"
    assert_contains "$output" 'Merge Check: github_pr_merged' "Cleanup should record GitHub PR metadata as the merge proof"
    assert_contains "$output" 'Local Branch Action: deleted' "Cleanup should still delete the local branch after GitHub merge proof"
    assert_contains "$output" 'Remote Branch Action: deleted' "Cleanup should delete the remote branch after GitHub merge proof"

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_delete_branch_uses_github_api_remote_delete_fallback() {
    test_start "worktree_ready_cleanup_delete_branch_uses_github_api_remote_delete_fallback"

    local fixture_root repo_dir fake_bd_bin fake_gh_bin existing_path output rc bd_json head_sha origin_dir
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    origin_dir="${fixture_root}/moltinger.git"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_gh_bin="$(create_fake_gh_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git remote set-url origin "${fixture_root}/missing-origin.git"
    )
    head_sha="$(git -C "$repo_dir" rev-parse refs/remotes/origin/feat/remote-uat-hardening)"
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        cd "$fixture_root"
        set +e
        WORKTREE_READY_ASSUME_GITHUB_ORIGIN=1 \
        GH_EXPECT_CWD="${repo_dir}" \
        GH_EXPECT_API_DELETE_ROUTE="repos/example/repo/git/refs/heads/feat%2Fremote-uat-hardening" \
        GH_EXPECT_API_GET_ROUTE="repos/example/repo/git/ref/heads/feat%2Fremote-uat-hardening" \
        GH_API_GET_STDOUT="$(printf '{"object":{"sha":"%s"}}\n' "${head_sha}")" \
        GH_REPO_VIEW_JSON='{"defaultBranchRef":{"name":"main"},"deleteBranchOnMerge":false,"nameWithOwner":"example/repo"}' \
        GH_PR_LIST_JSON="$(printf '[{"number":111,"state":"MERGED","mergedAt":"2026-03-27T20:30:28Z","headRefName":"feat/remote-uat-hardening","headRefOid":"%s","baseRefName":"main","isCrossRepository":false,"url":"https://github.com/example/repo/pull/111","title":"Fixture merged PR"}]\n' "${head_sha}")" \
        GH_API_DELETE_GIT_DIR="${origin_dir}" \
        GH_API_DELETE_REF="refs/heads/feat/remote-uat-hardening" \
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        run_worktree_cleanup "$repo_dir" "${fake_gh_bin}:${fake_bd_bin}" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "0" "$rc" "Cleanup should recover remote deletion through GitHub API fallback when git push --delete fails"
    assert_contains "$output" 'Status: cleanup_complete' "Cleanup should stay complete after GitHub API remote-delete fallback"
    assert_contains "$output" 'Merge Check: github_pr_merged' "Cleanup should still rely on the merged PR proof before deleting remotely"
    assert_contains "$output" 'Remote Branch Action: deleted' "Cleanup should report the remote branch as deleted after API fallback"
    assert_contains "$output" "GitHub API fallback deleted remote branch 'feat/remote-uat-hardening'" "Cleanup should report that the API fallback path was used"
    if git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup should still delete the local branch when remote delete falls back to GitHub API"
    fi
    if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the local remote-tracking ref after GitHub API fallback"
    fi
    if git --git-dir "$origin_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the actual remote branch after GitHub API fallback"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_blocks_branch_delete_when_only_local_stale_proof_exists() {
    test_start "worktree_ready_cleanup_blocks_branch_delete_when_only_local_stale_proof_exists"

    local fixture_root repo_dir fake_bin existing_path output rc
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git merge --no-ff feat/remote-uat-hardening -m "fixture: merge feature branch" >/dev/null
        git push origin main >/dev/null
        git remote set-url origin "${fixture_root}/missing-origin.git"
    )

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="$(printf '[{\"name\":\"remote-uat-hardening\",\"path\":\"%s\",\"branch\":\"feat/remote-uat-hardening\",\"beads_state\":\"local\"}]\n' "${existing_path}")" \
        BD_WORKTREE_LIST_FILTER_MISSING=1 \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup must not delete branches when only stale local proof is available"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should stay blocked when branch deletion still lacks authoritative remote proof"
    assert_contains "$output" 'Worktree Action: removed' "Cleanup may still remove the worktree through the local-only fallback"
    assert_contains "$output" 'Local Branch Action: deleted' "Cleanup should still delete the local branch when local merged ancestry proves that step is safe"
    assert_contains "$output" 'Remote Branch Action: blocked' "Cleanup should preserve the remote branch when refresh proof is unavailable"
    assert_contains "$output" 'Merge Check: remote_refresh_failed' "Cleanup should report the remote-refresh failure for the branch-delete phase"
    if [[ -d "$existing_path" ]]; then
        test_fail "Cleanup should still remove the worktree directory before branch deletion blocks"
    fi
    if git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup should remove the local branch when local merged ancestry proves that step is safe"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the remote-tracking ref when authoritative branch-delete proof is unavailable"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_blocks_when_git_fallback_leaves_beads_metadata_stale() {
    test_start "worktree_ready_cleanup_blocks_when_git_fallback_leaves_beads_metadata_stale"

    local fixture_root repo_dir fake_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    fake_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
        git merge --no-ff feat/remote-uat-hardening -m "fixture: merge feature branch" >/dev/null
        git push origin main >/dev/null
    )
    bd_json="$(printf '[{\"name\":\"remote-uat-hardening\",\"path\":\"%s\",\"branch\":\"feat/remote-uat-hardening\",\"beads_state\":\"local\"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        BD_WORKTREE_REMOVE_NOOP=1 \
        BD_WORKTREE_REMOVE_RC=23 \
        BD_WORKTREE_REMOVE_STDERR='safety check failed: worktree has unpushed commits. Use --force to skip safety checks.' \
        run_worktree_cleanup "$repo_dir" "$fake_bin" --branch feat/remote-uat-hardening 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup should fail closed when git fallback removed the worktree but Beads metadata still reports it"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should stay blocked until Beads metadata is reconciled"
    assert_contains "$output" 'Worktree Action: removed' "Cleanup should report the physical worktree removal even when metadata reconciliation is pending"
    assert_contains "$output" 'Beads still reports' "Cleanup should explain the Beads reconciliation blocker"
    assert_contains "$output" 'Repair Command: cd ' "Cleanup should expose a repair command for Beads reconciliation"
    if [[ -d "$existing_path" ]]; then
        test_fail "Cleanup should still remove the worktree directory before blocking on Beads reconciliation"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the local branch while Beads reconciliation remains blocked"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the remote branch while Beads reconciliation remains blocked"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_blocks_branch_delete_without_merge_proof() {
    test_start "worktree_ready_cleanup_blocks_branch_delete_without_merge_proof"

    local fixture_root repo_dir fake_bd_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        BD_WORKTREE_LIST_JSON="${bd_json}" run_worktree_cleanup "$repo_dir" "$fake_bd_bin" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup should block branch deletion when no safe merge proof exists"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should report cleanup_blocked when branch deletion remains unsafe"
    assert_contains "$output" 'Remote Branch Action: blocked' "Cleanup should keep the remote branch intact when merged proof is missing"
    assert_contains "$output" 'Merge Check: not_merged' "Cleanup should record the failed merge proof state"
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the local branch when safe delete proof is missing"
    fi
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the remote branch when safe delete proof is missing"
    fi

    rm -rf "$fixture_root"
    test_pass
}

test_cleanup_blocks_remote_delete_when_github_fallback_is_unavailable() {
    test_start "worktree_ready_cleanup_blocks_remote_delete_when_github_fallback_is_unavailable"

    local fixture_root repo_dir fake_bd_bin fake_gh_bin existing_path output rc bd_json
    fixture_root="$(mktemp -d /tmp/worktree-ready-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    fake_bd_bin="$(create_fake_bd_bin "$fixture_root")"
    fake_gh_bin="$(create_fake_gh_bin "$fixture_root")"
    existing_path="${fixture_root}/moltinger-remote-uat-hardening"
    git_topology_fixture_add_worktree_branch_from "$repo_dir" "$existing_path" "feat/remote-uat-hardening" "main"
    existing_path="$(cd "$existing_path" && pwd -P)"
    (
        cd "$existing_path"
        printf 'feature\n' > feature.txt
        git add feature.txt
        git commit -m "fixture: feature branch commit" >/dev/null
    )
    (
        cd "$repo_dir"
        git push -u origin feat/remote-uat-hardening >/dev/null
    )
    bd_json="$(printf '[{"name":"remote-uat-hardening","path":"%s","branch":"feat/remote-uat-hardening","beads_state":"local"}]\n' "${existing_path}")"

    output="$(
        set +e
        WORKTREE_READY_ASSUME_GITHUB_ORIGIN=1 \
        GH_AUTH_RC=1 \
        BD_WORKTREE_LIST_JSON="${bd_json}" \
        run_worktree_cleanup "$repo_dir" "${fake_gh_bin}:${fake_bd_bin}" --branch feat/remote-uat-hardening --delete-branch 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "$output" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "$rc" "Cleanup should block deletion when GitHub fallback cannot be authenticated"
    assert_contains "$output" 'Status: cleanup_blocked' "Cleanup should report cleanup_blocked when GitHub fallback is unavailable"
    assert_contains "$output" 'Merge Check: github_unavailable' "Cleanup should record the degraded GitHub proof state"
    assert_contains "$output" 'Remote Branch Action: blocked' "Cleanup should preserve the remote branch when GitHub fallback is unavailable"
    if ! git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/feat/remote-uat-hardening; then
        test_fail "Cleanup must preserve the remote branch when GitHub fallback is unavailable"
    fi

    rm -rf "$fixture_root"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Worktree Ready Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$WORKTREE_READY_SCRIPT" ]]; then
        test_fail "Worktree-ready helper missing or not executable: $WORKTREE_READY_SCRIPT"
        generate_report
        return 1
    fi

    test_plan_creates_clean_slug_without_issue
    test_plan_normalizes_issue_short_in_worktree_path
    test_plan_derives_numeric_branch_for_explicit_speckit_request
    test_plan_reuses_existing_numeric_branch_for_speckit_issue
    test_plan_reuses_existing_attached_worktree
    test_attach_reports_clean_preview_for_existing_feature_branch
    test_plan_attaches_existing_local_branch
    test_plan_asks_once_when_similar_branch_exists
    test_create_treats_direnv_permission_denied_as_needs_env_approval
    test_create_env_format_emits_handoff_boundary_contract
    test_attach_env_format_emits_handoff_boundary_contract
    test_create_uses_explicit_pending_summary
    test_create_preserves_separate_phase_b_seed_payload
    test_create_infers_issue_from_issue_aware_branch_name
    test_create_returns_issue_na_when_branch_mapping_is_ambiguous
    test_create_surfaces_source_only_issue_artifacts_when_target_lacks_them
    test_create_without_existing_worktree_points_to_phase_a_executor
    test_doctor_branch_only_suppresses_already_attached_warning
    test_doctor_accepts_local_beads_state
    test_doctor_blocks_runtime_bootstrap_required_when_external_state_says_local
    test_doctor_does_not_block_on_beads_probe_unavailable
    test_doctor_missing_guard_script_does_not_suggest_refresh
    test_doctor_missing_worktree_routes_back_to_managed_attach
    test_doctor_missing_beads_state_routes_to_localize_helper
    test_doctor_stale_topology_remains_warning_not_blocker
    test_finish_returns_issue_na_when_branch_mapping_is_ambiguous
    test_finish_blocks_runtime_bootstrap_required_when_external_state_says_local
    test_finish_stale_topology_remains_warning_not_blocker
    test_cleanup_removes_linked_worktree_without_branch_delete
    test_cleanup_prunes_stale_missing_worktree_entry
    test_cleanup_delete_branch_uses_git_ancestor_proof
    test_cleanup_uses_git_remove_fallback_for_false_unpushed_guard
    test_cleanup_does_not_bypass_false_unpushed_guard_without_merge_proof
    test_cleanup_does_not_bypass_false_unpushed_guard_for_dirty_worktree
    test_cleanup_blocks_conflicting_path_and_branch_arguments
    test_cleanup_accepts_alias_path_when_branch_matches_same_worktree
    test_cleanup_refreshes_remote_refs_before_using_local_merge_proof
    test_cleanup_uses_local_stale_proof_for_worktree_fallback_when_refresh_fails
    test_cleanup_blocks_when_git_fallback_leaves_beads_metadata_stale
    test_cleanup_delete_branch_uses_github_fallback_when_git_is_ambiguous
    test_cleanup_delete_branch_uses_github_api_remote_delete_fallback
    test_cleanup_blocks_branch_delete_when_only_local_stale_proof_exists
    test_cleanup_blocks_branch_delete_without_merge_proof
    test_cleanup_blocks_remote_delete_when_github_fallback_is_unavailable
    test_plan_needs_clarification_returns_exit_code_10
    test_attach_missing_branch_returns_blocked_missing_branch
    test_attach_preserves_separate_phase_b_seed_payload
    test_attach_terminal_handoff_launches_and_stops_at_handoff
    test_attach_codex_handoff_falls_back_to_manual_boundary
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
