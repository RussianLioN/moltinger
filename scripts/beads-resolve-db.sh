#!/usr/bin/env bash
set -euo pipefail

BEADS_RESOLVE_SCHEMA="beads-dispatch/v1"
BEADS_RESOLVE_DECISION=""
BEADS_RESOLVE_CONTEXT=""
BEADS_RESOLVE_REPO_ROOT=""
BEADS_RESOLVE_CANONICAL_ROOT=""
BEADS_RESOLVE_DB_PATH=""
BEADS_RESOLVE_MESSAGE=""
BEADS_RESOLVE_RECOVERY_HINT=""
BEADS_RESOLVE_ROOT_CLEANUP_NOTICE=""
BEADS_RESOLVE_EXIT_CODE=0
BEADS_RESOLVE_LAST_BD_OUTPUT=""
BEADS_RESOLVE_LAST_BD_RC=0
BEADS_RESOLVE_LAST_BD_TIMED_OUT="false"
BEADS_RESOLVE_RUNTIME_PROBE_STATE="not_run"

beads_resolve_usage() {
  cat <<'EOF'
Usage:
  scripts/beads-resolve-db.sh [--repo <path>] [--format <human|env>] [--] [bd args...]
  scripts/beads-resolve-db.sh localize [--repo <path>] [--format <human|env>]

Description:
  Resolve whether plain `bd` can safely use the current worktree-local tracker,
  should pass through unchanged, or must fail closed before a root fallback.
  The `localize` subcommand materializes a local beads.db from the current
  worktree's tracked `.beads/issues.jsonl`.

  When `.beads/pilot-mode.json` or `.beads/cutover-mode.json` exists in a
  dedicated worktree, legacy-only operator paths such as `bd sync` fail
  closed and must be replaced by the active migration review surface.
EOF
}

beads_resolve_reset() {
  BEADS_RESOLVE_DECISION=""
  BEADS_RESOLVE_CONTEXT=""
  BEADS_RESOLVE_REPO_ROOT=""
  BEADS_RESOLVE_CANONICAL_ROOT=""
  BEADS_RESOLVE_DB_PATH=""
  BEADS_RESOLVE_MESSAGE=""
  BEADS_RESOLVE_RECOVERY_HINT=""
  BEADS_RESOLVE_ROOT_CLEANUP_NOTICE=""
  BEADS_RESOLVE_EXIT_CODE=0
}

beads_resolve_die() {
  echo "[beads-resolve-db] $*" >&2
  exit 2
}

beads_localize_notice() {
  local message="$1"
  if [[ "${BEADS_LOCALIZE_FORMAT:-human}" == "env" ]]; then
    printf 'result=%q\n' "${message}"
  else
    printf '%s\n' "${message}"
  fi
}

beads_resolve_normalize_path() {
  local input_path="$1"
  local base_path="${2:-$PWD}"
  local probe_path=""
  local suffix=""
  local next_probe=""

  if [[ -z "${input_path}" ]]; then
    return 1
  fi

  if [[ "${input_path}" == /* ]]; then
    probe_path="${input_path}"
    while [[ ! -e "${probe_path}" ]]; do
      next_probe="$(dirname "${probe_path}")"
      if [[ "${next_probe}" == "${probe_path}" ]]; then
        return 1
      fi
      suffix="/$(basename "${probe_path}")${suffix}"
      probe_path="${next_probe}"
    done

    if [[ ! -d "${probe_path}" ]]; then
      suffix="/$(basename "${probe_path}")${suffix}"
      probe_path="$(dirname "${probe_path}")"
    fi

    (
      cd "${probe_path}"
      printf '%s%s\n' "$(pwd -P)" "${suffix}"
    )
    return 0
  fi

  probe_path="${base_path}/${input_path}"
  beads_resolve_normalize_path "${probe_path}"
}

beads_resolve_git() {
  env \
    -u GIT_DIR \
    -u GIT_WORK_TREE \
    -u GIT_COMMON_DIR \
    -u GIT_NAMESPACE \
    -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_PREFIX \
    -u GIT_CEILING_DIRECTORIES \
    -u GIT_DISCOVERY_ACROSS_FILESYSTEM \
    git "$@"
}

beads_resolve_find_git_marker_root() {
  local probe_path="${1:-$PWD}"
  local cursor=""
  local next_cursor=""

  cursor="$(beads_resolve_normalize_path "${probe_path}")" || return 1
  if [[ ! -d "${cursor}" ]]; then
    cursor="$(dirname "${cursor}")"
  fi

  while [[ -n "${cursor}" ]]; do
    if [[ -e "${cursor}/.git" ]]; then
      printf '%s\n' "${cursor}"
      return 0
    fi

    if [[ "${cursor}" == "/" ]]; then
      break
    fi

    next_cursor="$(dirname "${cursor}")"
    if [[ "${next_cursor}" == "${cursor}" ]]; then
      break
    fi
    cursor="${next_cursor}"
  done

  return 1
}

beads_resolve_gitdir_path() {
  local repo_root="$1"
  local marker_path="${repo_root}/.git"
  local gitdir_value=""

  if [[ -d "${marker_path}" ]]; then
    beads_resolve_normalize_path "${marker_path}"
    return 0
  fi

  if [[ ! -f "${marker_path}" ]]; then
    return 1
  fi

  gitdir_value="$(sed -n '1s/^gitdir: //p' "${marker_path}")"
  [[ -n "${gitdir_value}" ]] || return 1

  beads_resolve_normalize_path "${gitdir_value}" "${repo_root}"
}

beads_resolve_canonical_root_from_gitdir() {
  local repo_root="$1"
  local gitdir_path=""
  local common_dir_rel=""
  local common_dir=""

  gitdir_path="$(beads_resolve_gitdir_path "${repo_root}")" || return 1

  if [[ -d "${repo_root}/.git" ]]; then
    printf '%s\n' "${repo_root}"
    return 0
  fi

  if [[ -f "${gitdir_path}/commondir" ]]; then
    common_dir_rel="$(<"${gitdir_path}/commondir")"
    [[ -n "${common_dir_rel}" ]] || return 1
    common_dir="$(beads_resolve_normalize_path "${common_dir_rel}" "${gitdir_path}")" || return 1
  else
    common_dir="${gitdir_path}"
  fi

  if [[ "$(basename "${common_dir}")" == ".git" ]]; then
    (
      cd "${common_dir}"
      cd ..
      pwd -P
    )
    return 0
  fi

  if [[ "$(basename "$(dirname "${common_dir}")")" == "worktrees" ]]; then
    (
      cd "${common_dir}"
      cd ../..
      cd ..
      pwd -P
    )
    return 0
  fi

  return 1
}

beads_resolve_repo_root() {
  local probe_path="${1:-$PWD}"
  local repo_root=""

  repo_root="$(beads_resolve_git -C "${probe_path}" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "${repo_root}" ]]; then
    printf '%s\n' "${repo_root}"
    return 0
  fi

  beads_resolve_find_git_marker_root "${probe_path}" || true
}

beads_resolve_canonical_root() {
  local repo_root="$1"
  local common_dir=""

  common_dir="$(beads_resolve_git -C "${repo_root}" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "${common_dir}" ]]; then
    beads_resolve_canonical_root_from_gitdir "${repo_root}"
    return $?
  fi

  (
    cd "${repo_root}"
    cd "${common_dir}"
    cd ..
    pwd -P
  )
}

beads_resolve_is_global_passthrough() {
  local first_arg="${1:-}"

  case "${first_arg}" in
    ""|-h|--help|help|-V|--version|version|completion|onboard)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

beads_resolve_is_explicit_troubleshooting() {
  local arg=""

  for arg in "$@"; do
    case "${arg}" in
      --db|--db=*|--no-db)
        return 0
        ;;
    esac
  done

  return 1
}

beads_resolve_is_runtime_repair_command() {
  local command=""

  beads_resolve_extract_command "$@"
  command="${BEADS_RESOLVE_COMMAND}"

  case "${command}" in
    bootstrap|doctor|dolt|init|backup)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

beads_resolve_requests_readonly_mode() {
  local arg=""

  for arg in "$@"; do
    if [[ "${arg}" == "--readonly" ]]; then
      return 0
    fi
  done

  return 1
}

beads_resolve_extract_command() {
  local -a args=("$@")
  local index=0
  local arg=""

  BEADS_RESOLVE_COMMAND=""
  BEADS_RESOLVE_SUBCOMMAND=""

  while [[ "${index}" -lt "${#args[@]}" ]]; do
    arg="${args[$index]}"
    case "${arg}" in
      --)
        ((index += 1))
        break
        ;;
      --actor|--lock-timeout|--db)
        ((index += 2))
        continue
        ;;
      --actor=*|--lock-timeout=*|--db=*|--allow-stale|--json|--no-auto-flush|--no-auto-import|--no-daemon|--no-db|--profile|--readonly|--sandbox|-h|--help|-q|--quiet|-v|--verbose|-V|--version)
        ((index += 1))
        continue
        ;;
      -*)
        ((index += 1))
        continue
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ "${index}" -lt "${#args[@]}" ]]; then
    BEADS_RESOLVE_COMMAND="${args[$index]}"
    if [[ $((index + 1)) -lt "${#args[@]}" ]]; then
      BEADS_RESOLVE_SUBCOMMAND="${args[$((index + 1))]}"
    fi
  fi
}

beads_resolve_pilot_mode_file() {
  local repo_root="$1"
  printf '%s/.beads/pilot-mode.json\n' "${repo_root}"
}

beads_resolve_pilot_mode_enabled() {
  local repo_root="$1"
  [[ -f "$(beads_resolve_pilot_mode_file "${repo_root}")" ]]
}

beads_resolve_cutover_mode_file() {
  local repo_root="$1"
  printf '%s/.beads/cutover-mode.json\n' "${repo_root}"
}

beads_resolve_cutover_mode_enabled() {
  local repo_root="$1"
  [[ -f "$(beads_resolve_cutover_mode_file "${repo_root}")" ]]
}

beads_resolve_active_migration_mode() {
  local repo_root="$1"

  if beads_resolve_cutover_mode_enabled "${repo_root}"; then
    printf 'cutover\n'
    return 0
  fi

  if beads_resolve_pilot_mode_enabled "${repo_root}"; then
    printf 'pilot\n'
    return 0
  fi

  return 1
}

beads_resolve_migration_review_command() {
  local migration_mode="$1"

  case "${migration_mode}" in
    cutover)
      printf './scripts/beads-dolt-rollout.sh verify --worktree .\n'
      ;;
    pilot)
      printf './scripts/beads-dolt-pilot.sh review\n'
      ;;
    *)
      return 1
      ;;
  esac
}

beads_resolve_has_local_runtime() {
  local beads_dir="$1"
  local db_path="${beads_dir}/beads.db"
  local dolt_dir="${beads_dir}/dolt"
  local db_entry=""

  if [[ -f "${db_path}" || -L "${db_path}" ]]; then
    return 0
  fi

  if [[ -d "${dolt_dir}/beads" || -d "${dolt_dir}/beads/.dolt" ]]; then
    return 0
  fi

  if [[ -d "${db_path}" ]]; then
    db_entry="$(find "${db_path}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
    [[ -n "${db_entry}" ]] && return 0
  fi

  return 1
}

beads_resolve_has_runtime_shell() {
  local beads_dir="$1"
  local db_path="${beads_dir}/beads.db"

  if [[ -d "${beads_dir}/dolt" || -f "${beads_dir}/metadata.json" || -f "${beads_dir}/dolt-server.port" || -f "${beads_dir}/dolt-server.pid" ]]; then
    return 0
  fi

  if [[ -d "${db_path}" ]]; then
    return 0
  fi

  return 1
}

beads_resolve_is_repo_local_wrapper_candidate() {
  local candidate_path="$1"
  local candidate_dir=""
  local candidate_repo_root=""

  [[ -n "${candidate_path}" ]] || return 1
  [[ "$(basename "${candidate_path}")" == "bd" ]] || return 1

  candidate_dir="$(dirname "${candidate_path}")"
  [[ "$(basename "${candidate_dir}")" == "bin" ]] || return 1

  candidate_repo_root="$(cd "${candidate_dir}/.." && pwd -P 2>/dev/null || true)"
  [[ -n "${candidate_repo_root}" ]] || return 1
  [[ -f "${candidate_repo_root}/scripts/beads-resolve-db.sh" ]]
}

beads_resolve_is_migration_legacy_command() {
  local command=""

  beads_resolve_extract_command "$@"
  command="${BEADS_RESOLVE_COMMAND}"

  case "${command}" in
    sync)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

beads_resolve_is_canonical_root_read_only_command() {
  local command=""
  local subcommand=""

  beads_resolve_extract_command "$@"
  command="${BEADS_RESOLVE_COMMAND}"
  subcommand="${BEADS_RESOLVE_SUBCOMMAND}"

  case "${command}" in
    ""|activity|blocked|children|completion|count|diff|doctor|export|find-duplicates|graph|help|history|human|info|list|onboard|orphans|prime|query|quickstart|ready|search|show|stale|state|status|types|version|where)
      return 0
      ;;
    backend)
      [[ "${subcommand}" == "show" ]]
      return
      ;;
    branch)
      [[ "${subcommand}" == "list" ]]
      return
      ;;
    dep)
      [[ "${subcommand}" == "cycles" ]]
      return
      ;;
    worktree)
      [[ "${subcommand}" == "list" ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

beads_resolve_extract_worktree_remove_target() {
  local -a args=("$@")
  local index=0
  local arg=""

  while [[ "${index}" -lt "${#args[@]}" ]]; do
    arg="${args[$index]}"
    case "${arg}" in
      --)
        ((index += 1))
        break
        ;;
      --actor|--lock-timeout|--db)
        ((index += 2))
        continue
        ;;
      --actor=*|--lock-timeout=*|--db=*|--allow-stale|--json|--no-auto-flush|--no-auto-import|--no-daemon|--no-db|--profile|--readonly|--sandbox|-h|--help|-q|--quiet|-v|--verbose|-V|--version)
        ((index += 1))
        continue
        ;;
      -*)
        ((index += 1))
        continue
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ "${args[$index]:-}" != "worktree" || "${args[$((index + 1))]:-}" != "remove" ]]; then
    return 1
  fi

  printf '%s\n' "${args[$((index + 2))]:-}"
}

beads_resolve_is_canonical_root_cleanup_admin_command() {
  local repo_root="$1"
  local canonical_root="$2"
  shift 2

  local target_arg=""
  local normalized_target=""
  local line=""
  local current_path=""
  local candidate_path=""

  target_arg="$(beads_resolve_extract_worktree_remove_target "$@")" || return 1
  [[ -n "${target_arg}" ]] || return 1

  normalized_target="$(beads_resolve_normalize_path "${target_arg}" "${repo_root}" 2>/dev/null || true)"
  [[ -n "${normalized_target}" ]] || return 1
  [[ "${normalized_target}" != "${canonical_root}" ]] || return 1

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      worktree\ *)
        current_path="$(beads_resolve_normalize_path "${line#worktree }" "/" 2>/dev/null || true)"
        ;;
      "")
        if [[ -n "${current_path}" && "${current_path}" == "${normalized_target}" ]]; then
          return 0
        fi
        current_path=""
        ;;
    esac
  done < <(beads_resolve_git -C "${repo_root}" worktree list --porcelain 2>/dev/null)

  if [[ -n "${current_path}" && "${current_path}" == "${normalized_target}" ]]; then
    return 0
  fi

  return 1
}

beads_resolve_set_decision() {
  local decision="$1"
  local context="$2"
  local exit_code="$3"
  local message="${4:-}"
  local recovery_hint="${5:-}"
  local root_cleanup_notice="${6:-}"

  BEADS_RESOLVE_DECISION="${decision}"
  BEADS_RESOLVE_CONTEXT="${context}"
  BEADS_RESOLVE_EXIT_CODE="${exit_code}"
  BEADS_RESOLVE_MESSAGE="${message}"
  BEADS_RESOLVE_RECOVERY_HINT="${recovery_hint}"
  BEADS_RESOLVE_ROOT_CLEANUP_NOTICE="${root_cleanup_notice}"
}

beads_resolve_dispatch() {
  local current_dir="${1:-$PWD}"
  shift || true

  local repo_root=""
  local canonical_root=""
  local beads_dir=""
  local config_path=""
  local issues_path=""
  local db_path=""
  local dolt_dir=""
  local redirect_path=""
  local redirect_target=""
  local root_db_path=""
  local has_local_runtime="false"
  local has_runtime_shell="false"
  local recovery_hint=""
  local runtime_probe_state="not_run"
  local runtime_recovery_hint=""
  local runtime_repair_detail=""
  local root_cleanup_notice=""
  local migration_mode=""
  local migration_review_command=""

  beads_resolve_reset

  repo_root="$(beads_resolve_repo_root "${current_dir}")"
  if [[ -z "${repo_root}" ]]; then
    beads_resolve_set_decision "pass_through_non_repo" "non_repo" 0
    return 0
  fi

  canonical_root="$(beads_resolve_canonical_root "${repo_root}")"
  if [[ -z "${canonical_root}" ]]; then
    beads_resolve_set_decision \
      "block_unresolved_ownership" \
      "unknown" \
      25 \
      "bd: could not determine the canonical git worktree for this repository." \
      "Re-enter the repository from a valid git worktree and retry."
    return 0
  fi

  BEADS_RESOLVE_REPO_ROOT="${repo_root}"
  BEADS_RESOLVE_CANONICAL_ROOT="${canonical_root}"

  if beads_resolve_is_global_passthrough "$@"; then
    beads_resolve_set_decision "pass_through_global" "global" 0
    return 0
  fi

  if beads_resolve_is_explicit_troubleshooting "$@"; then
    beads_resolve_set_decision "allow_explicit_troubleshooting" "explicit" 0
    return 0
  fi

  migration_mode="$(beads_resolve_active_migration_mode "${repo_root}" 2>/dev/null || true)"
  if [[ -n "${migration_mode}" ]]; then
    migration_review_command="$(beads_resolve_migration_review_command "${migration_mode}" 2>/dev/null || true)"
  fi

  if beads_resolve_is_migration_legacy_command "$@"; then
    if [[ -n "${migration_mode}" ]]; then
      beads_resolve_set_decision \
        "block_pilot_legacy_command" \
        "dedicated_worktree" \
        27 \
        "bd: ${migration_mode} mode is enabled in ${repo_root}, so legacy-only commands such as ${BEADS_RESOLVE_COMMAND} are blocked." \
        "Use ${migration_review_command:-./scripts/beads-dolt-pilot.sh review} for the active migration review surface, and keep JSONL export/sync out of the everyday operator path."
      return 0
    fi

    beads_resolve_set_decision \
      "block_deprecated_sync" \
      "repo_local" \
      28 \
      "bd: 'sync' is retired in this repository's Beads workflow." \
      "Use bd status for local inspection, and use bd dolt push / bd dolt pull only when this worktree is configured with a Dolt remote."
    return 0
  fi

  if [[ "${repo_root}" == "${canonical_root}" ]]; then
    if beads_resolve_requests_readonly_mode "$@" || beads_resolve_is_canonical_root_read_only_command "$@"; then
      beads_resolve_set_decision "pass_through_root_readonly" "canonical_root" 0
      return 0
    fi

    if beads_resolve_is_canonical_root_cleanup_admin_command "${repo_root}" "${canonical_root}" "$@"; then
      beads_resolve_set_decision "pass_through_root_cleanup_admin" "canonical_root" 0
      return 0
    fi

    beads_resolve_set_decision \
      "block_root_mutation" \
      "canonical_root" \
      26 \
      "bd: mutating canonical-root tracker commands are blocked by default in ${repo_root}." \
      "For intentional canonical-root admin/troubleshooting work only, rerun with an explicit target such as: bd --db $(printf '%q' "${repo_root}/.beads/beads.db") <command>"
    return 0
  fi

  beads_dir="${repo_root}/.beads"
  config_path="${beads_dir}/config.yaml"
  issues_path="${beads_dir}/issues.jsonl"
  db_path="${beads_dir}/beads.db"
  dolt_dir="${beads_dir}/dolt"
  redirect_path="${beads_dir}/redirect"
  root_db_path="${canonical_root}/.beads/beads.db"
  recovery_hint="cd $(printf '%q' "${repo_root}") && ./scripts/beads-worktree-localize.sh --path ."
  if [[ -f "${config_path}" && ! -f "${issues_path}" ]]; then
    recovery_hint="cd $(printf '%q' "${repo_root}") && /usr/local/bin/bd doctor --json && ./scripts/beads-worktree-localize.sh --path ."
  fi
  if beads_resolve_has_local_runtime "${beads_dir}"; then
    has_local_runtime="true"
  fi
  if beads_resolve_has_runtime_shell "${beads_dir}"; then
    has_runtime_shell="true"
  fi
  if [[ "${has_local_runtime}" == "true" ]]; then
    beads_resolve_probe_local_runtime_health "${repo_root}" || true
    runtime_probe_state="${BEADS_RESOLVE_RUNTIME_PROBE_STATE:-not_run}"
  fi
  if [[ -f "${issues_path}" ]]; then
    runtime_recovery_hint="cd $(printf '%q' "${repo_root}") && ./scripts/beads-worktree-localize.sh --path ."
    runtime_repair_detail="Repair the local runtime in place from the tracked local foundation."
  else
    runtime_recovery_hint="cd $(printf '%q' "${repo_root}") && /usr/local/bin/bd doctor --json && ./scripts/beads-worktree-localize.sh --path ."
    runtime_repair_detail="Tracked .beads/issues.jsonl is retired here; quarantine the stale runtime shell, rerun bootstrap, and import the newest compatibility issues backup instead of restoring tracked JSONL."
  fi

  if [[ -f "${redirect_path}" ]]; then
    redirect_target="$(cat "${redirect_path}")"
    if [[ -n "${redirect_target}" ]]; then
      root_cleanup_notice="Residual canonical-root cleanup may still be required, but it is a separate follow-up from this local ownership fix."
    fi
    beads_resolve_set_decision \
      "block_legacy_redirect" \
      "dedicated_worktree" \
      23 \
      "bd: legacy Beads redirect metadata is still present at ${redirect_path}. Shared redirect ownership is disabled for dedicated worktrees." \
      "${recovery_hint}" \
      "${root_cleanup_notice}"
    return 0
  fi

  if [[ ! -f "${config_path}" ]]; then
    if [[ -f "${root_db_path}" ]]; then
      beads_resolve_set_decision \
        "block_root_fallback" \
        "dedicated_worktree" \
        24 \
        "bd: local Beads foundation is incomplete in ${repo_root}, and falling back to the canonical root tracker is blocked." \
        "${recovery_hint}" \
        "Residual canonical-root cleanup must be handled separately; this command will not repair root state."
      return 0
    fi

    beads_resolve_set_decision \
      "block_missing_foundation" \
      "dedicated_worktree" \
      25 \
      "bd: local Beads foundation is incomplete in ${repo_root}. Required files: .beads/config.yaml and .beads/issues.jsonl." \
      "${recovery_hint}"
    return 0
  fi

  if [[ "${runtime_probe_state}" == "unhealthy" ]]; then
    if beads_resolve_is_runtime_repair_command "$@"; then
      beads_resolve_set_decision "allow_explicit_troubleshooting" "runtime_repair" 0
      return 0
    fi

    beads_resolve_set_decision \
      "block_missing_foundation" \
      "$( [[ ! -f "${issues_path}" ]] && printf '%s' "runtime_only_worktree" || printf '%s' "dedicated_worktree" )" \
      25 \
      "bd: local Beads runtime exists in ${repo_root}, but plain bd cannot read it safely yet. ${runtime_repair_detail}" \
      "${runtime_recovery_hint}"
    return 0
  fi

  if [[ "${has_local_runtime}" != "true" && "${has_runtime_shell}" == "true" ]]; then
    if beads_resolve_is_runtime_repair_command "$@"; then
      beads_resolve_set_decision "allow_explicit_troubleshooting" "runtime_repair" 0
      return 0
    fi

    beads_resolve_set_decision \
      "block_missing_foundation" \
      "$( [[ ! -f "${issues_path}" ]] && printf '%s' "runtime_only_worktree" || printf '%s' "dedicated_worktree" )" \
      25 \
      "bd: local Dolt-backed Beads runtime is incomplete in ${repo_root}. A runtime shell exists, but the named 'beads' database is not materialized yet. ${runtime_repair_detail}" \
      "${runtime_recovery_hint}"
    return 0
  fi

  if [[ -f "${config_path}" && "${has_local_runtime}" == "true" && ! -f "${issues_path}" ]]; then
    BEADS_RESOLVE_DB_PATH="${db_path}"
    beads_resolve_set_decision \
      "execute_local" \
      "$( [[ -n "${migration_mode}" ]] && printf '%s' "${migration_mode}_worktree" || printf '%s' "runtime_only_worktree" )" \
      0
    return 0
  fi

  if [[ -f "${config_path}" && ! -f "${issues_path}" ]]; then
    if [[ -f "${root_db_path}" ]]; then
      beads_resolve_set_decision \
        "block_root_fallback" \
        "runtime_only_worktree" \
        24 \
        "bd: local Dolt-backed Beads runtime is incomplete in ${repo_root}, and falling back to the canonical root tracker is blocked." \
        "${recovery_hint}" \
        "Tracked .beads/issues.jsonl is retired in this state; repair the local runtime instead of restoring JSONL."
      return 0
    fi

    beads_resolve_set_decision \
      "block_missing_foundation" \
      "runtime_only_worktree" \
      25 \
      "bd: local Dolt-backed Beads runtime is incomplete in ${repo_root}. Tracked .beads/issues.jsonl is retired here; repair the local runtime instead of restoring JSONL." \
      "${recovery_hint}"
    return 0
  fi

  if [[ ! -f "${issues_path}" ]]; then
    if [[ -f "${root_db_path}" ]]; then
      beads_resolve_set_decision \
        "block_root_fallback" \
        "dedicated_worktree" \
        24 \
        "bd: local Beads foundation is incomplete in ${repo_root}, and falling back to the canonical root tracker is blocked." \
        "${recovery_hint}" \
        "Residual canonical-root cleanup must be handled separately; this command will not repair root state."
      return 0
    fi

    beads_resolve_set_decision \
      "block_missing_foundation" \
      "dedicated_worktree" \
      25 \
      "bd: local Beads foundation is incomplete in ${repo_root}. Required files: .beads/config.yaml and .beads/issues.jsonl." \
      "${recovery_hint}"
    return 0
  fi

  BEADS_RESOLVE_DB_PATH="${db_path}"
  beads_resolve_set_decision "execute_local" "dedicated_worktree" 0
}

beads_resolve_find_system_bd() {
  local self_path="$1"
  local path_dir=""
  local candidate=""
  local self_real=""
  local candidate_real=""
  local old_ifs="${IFS}"

  self_real="$(beads_resolve_normalize_path "${self_path}")"

  IFS=':'
  for path_dir in ${PATH}; do
    [[ -n "${path_dir}" ]] || path_dir="."
    candidate="${path_dir%/}/bd"
    if [[ ! -x "${candidate}" ]]; then
      continue
    fi

    candidate_real="$(beads_resolve_normalize_path "${candidate}")"
    if [[ "${candidate_real}" == "${self_real}" ]]; then
      continue
    fi

    if beads_resolve_is_repo_local_wrapper_candidate "${candidate_real}"; then
      continue
    fi

    printf '%s\n' "${candidate}"
    IFS="${old_ifs}"
    return 0
  done
  IFS="${old_ifs}"

  return 1
}

beads_resolve_run_system_bd_probe() {
  local repo_root="$1"
  local capture_stderr="$2"
  shift 2

  local timeout_seconds="${BEADS_RESOLVE_BD_TIMEOUT_SECONDS:-8}"
  local command_path=""
  local stdout_file=""
  local stderr_file=""
  local timed_out_file=""
  local command_pid=""
  local watchdog_pid=""
  local rc=0
  local output=""

  if [[ -z "${repo_root}" || ! -d "${repo_root}" ]]; then
    return 1
  fi

  command_path="$(beads_resolve_find_system_bd "${repo_root}/bin/bd")" || return 1

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  timed_out_file="$(mktemp)"

  (
    cd "${repo_root}"
    "${command_path}" "$@" >"${stdout_file}" 2>"${stderr_file}"
  ) &
  command_pid=$!

  (
    sleep "${timeout_seconds}"
    if kill -0 "${command_pid}" 2>/dev/null; then
      printf 'true\n' >"${timed_out_file}"
      kill -TERM "${command_pid}" 2>/dev/null || true
      sleep 1
      kill -KILL "${command_pid}" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  set +e
  wait "${command_pid}"
  rc=$?
  set -e

  kill "${watchdog_pid}" 2>/dev/null || true
  wait "${watchdog_pid}" 2>/dev/null || true

  BEADS_RESOLVE_LAST_BD_OUTPUT="$(cat "${stdout_file}")"
  if [[ "${capture_stderr}" == "true" ]]; then
    output="$(cat "${stderr_file}")"
    if [[ -n "${output}" ]]; then
      if [[ -n "${BEADS_RESOLVE_LAST_BD_OUTPUT}" ]]; then
        BEADS_RESOLVE_LAST_BD_OUTPUT+=$'\n'
      fi
      BEADS_RESOLVE_LAST_BD_OUTPUT+="${output}"
    fi
  fi

  BEADS_RESOLVE_LAST_BD_TIMED_OUT="false"
  BEADS_RESOLVE_LAST_BD_RC="${rc}"
  if [[ -s "${timed_out_file}" ]]; then
    BEADS_RESOLVE_LAST_BD_TIMED_OUT="true"
    BEADS_RESOLVE_LAST_BD_RC=124
  fi

  rm -f "${stdout_file}" "${stderr_file}" "${timed_out_file}"
  return 0
}

beads_resolve_probe_local_runtime_health() {
  local repo_root="$1"

  BEADS_RESOLVE_RUNTIME_PROBE_STATE="not_run"
  BEADS_RESOLVE_LAST_BD_OUTPUT=""
  BEADS_RESOLVE_LAST_BD_RC=0
  BEADS_RESOLVE_LAST_BD_TIMED_OUT="false"

  if ! beads_resolve_run_system_bd_probe "${repo_root}" true status; then
    BEADS_RESOLVE_RUNTIME_PROBE_STATE="unavailable"
    return 1
  fi

  if [[ "${BEADS_RESOLVE_LAST_BD_TIMED_OUT}" == "true" ]]; then
    BEADS_RESOLVE_RUNTIME_PROBE_STATE="unavailable"
    return 0
  fi

  if [[ "${BEADS_RESOLVE_LAST_BD_RC}" -eq 0 ]]; then
    BEADS_RESOLVE_RUNTIME_PROBE_STATE="healthy"
  else
    BEADS_RESOLVE_RUNTIME_PROBE_STATE="unhealthy"
  fi

  return 0
}

beads_resolve_render_env() {
  printf 'schema=%q\n' "${BEADS_RESOLVE_SCHEMA}"
  printf 'decision=%q\n' "${BEADS_RESOLVE_DECISION}"
  printf 'context=%q\n' "${BEADS_RESOLVE_CONTEXT}"
  printf 'repo_root=%q\n' "${BEADS_RESOLVE_REPO_ROOT:-}"
  printf 'canonical_root=%q\n' "${BEADS_RESOLVE_CANONICAL_ROOT:-}"
  printf 'db_path=%q\n' "${BEADS_RESOLVE_DB_PATH:-}"
  printf 'exit_code=%q\n' "${BEADS_RESOLVE_EXIT_CODE}"
  printf 'message=%q\n' "${BEADS_RESOLVE_MESSAGE:-}"
  printf 'recovery_hint=%q\n' "${BEADS_RESOLVE_RECOVERY_HINT:-}"
  printf 'root_cleanup_notice=%q\n' "${BEADS_RESOLVE_ROOT_CLEANUP_NOTICE:-}"
}

beads_resolve_render_human() {
  printf 'Decision: %s\n' "${BEADS_RESOLVE_DECISION}"
  printf 'Context: %s\n' "${BEADS_RESOLVE_CONTEXT}"
  if [[ -n "${BEADS_RESOLVE_REPO_ROOT}" ]]; then
    printf 'Repo Root: %s\n' "${BEADS_RESOLVE_REPO_ROOT}"
  fi
  if [[ -n "${BEADS_RESOLVE_CANONICAL_ROOT}" ]]; then
    printf 'Canonical Root: %s\n' "${BEADS_RESOLVE_CANONICAL_ROOT}"
  fi
  if [[ -n "${BEADS_RESOLVE_DB_PATH}" ]]; then
    printf 'DB Path: %s\n' "${BEADS_RESOLVE_DB_PATH}"
  fi
  if [[ -n "${BEADS_RESOLVE_MESSAGE}" ]]; then
    printf 'Message: %s\n' "${BEADS_RESOLVE_MESSAGE}"
  fi
  if [[ -n "${BEADS_RESOLVE_RECOVERY_HINT}" ]]; then
    printf 'Recovery: %s\n' "${BEADS_RESOLVE_RECOVERY_HINT}"
  fi
  if [[ -n "${BEADS_RESOLVE_ROOT_CLEANUP_NOTICE}" ]]; then
    printf 'Root Cleanup: %s\n' "${BEADS_RESOLVE_ROOT_CLEANUP_NOTICE}"
  fi
}

beads_localize_worktree() {
  local repo_root="$1"
  local output_format="$2"
  local current_db=""
  local current_dolt=""
  local current_redirect=""
  local current_config=""
  local current_issues=""
  local system_bd=""
  local timestamp=""
  local recovery_dir=""
  local recovery_path=""
  local artifact=""
  local has_local_runtime="false"
  local runtime_probe_state="not_run"
  local -a stale_runtime_artifacts=(
    "metadata.json"
    "interactions.jsonl"
    "dolt-server.lock"
    "dolt-server.log"
    "dolt-server.pid"
    "dolt-server.port"
  )

  BEADS_LOCALIZE_FORMAT="${output_format}"

  repo_root="$(beads_resolve_normalize_path "${repo_root}")"
  current_config="${repo_root}/.beads/config.yaml"
  current_issues="${repo_root}/.beads/issues.jsonl"
  current_db="${repo_root}/.beads/beads.db"
  current_dolt="${repo_root}/.beads/dolt"
  current_redirect="${repo_root}/.beads/redirect"

  if beads_resolve_has_local_runtime "${repo_root}/.beads"; then
    has_local_runtime="true"
    beads_resolve_probe_local_runtime_health "${repo_root}" || true
    runtime_probe_state="${BEADS_RESOLVE_RUNTIME_PROBE_STATE:-not_run}"
  fi

  if [[ -f "${current_config}" && "${has_local_runtime}" == "true" && "${runtime_probe_state}" != "unhealthy" && ! -f "${current_issues}" && ! -f "${current_redirect}" ]]; then
    if [[ "${output_format}" == "env" ]]; then
      printf 'result=%q\n' "post_migration_runtime_only"
      printf 'repo_root=%q\n' "${repo_root}"
      if [[ -e "${current_db}" ]]; then
        printf 'db_path=%q\n' "${current_db}"
      else
        printf 'db_path=%q\n' "${current_dolt}"
      fi
    else
      printf 'Tracked .beads/issues.jsonl is already retired; use the local Beads runtime in %s as the backlog source of truth.\n' "${repo_root}/.beads"
    fi
    return 0
  fi

  if [[ ! -f "${current_config}" || ! -f "${current_issues}" ]]; then
    beads_resolve_die "Cannot localize ${repo_root}: tracked .beads/config.yaml and .beads/issues.jsonl must exist locally first."
  fi

  if [[ "${has_local_runtime}" == "true" && "${runtime_probe_state}" != "unhealthy" && ! -f "${current_redirect}" ]]; then
    if [[ "${output_format}" == "env" ]]; then
      printf 'result=%q\n' "already_local"
      printf 'repo_root=%q\n' "${repo_root}"
      if [[ -e "${current_db}" ]]; then
        printf 'db_path=%q\n' "${current_db}"
      else
        printf 'db_path=%q\n' "${current_dolt}"
      fi
    else
      if [[ -e "${current_db}" ]]; then
        printf 'Local Beads DB already present at %s\n' "${current_db}"
      else
        printf 'Local Beads runtime already present at %s\n' "${current_dolt}"
      fi
    fi
    return 0
  fi

  system_bd="${BEADS_SYSTEM_BD:-}"
  if [[ -z "${system_bd}" ]]; then
    system_bd="$(beads_resolve_find_system_bd "${repo_root}/bin/bd")" || {
      beads_resolve_die "Could not find the system bd binary needed for localization."
    }
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  recovery_dir="${repo_root}/.beads/recovery"

  if [[ "${runtime_probe_state}" == "unhealthy" ]] || \
     ([[ ! -d "${current_dolt}/beads" && ! -d "${current_dolt}/beads/.dolt" ]] && \
      [[ -d "${current_dolt}" || -e "${repo_root}/.beads/metadata.json" || -e "${repo_root}/.beads/interactions.jsonl" ]]); then
    recovery_path="${recovery_dir}/runtime-pre-init-${timestamp}"
    mkdir -p "${recovery_path}"
    if [[ -d "${current_dolt}" ]]; then
      mv "${current_dolt}" "${recovery_path}/dolt"
    fi
    for artifact in "${stale_runtime_artifacts[@]}"; do
      if [[ -e "${repo_root}/.beads/${artifact}" ]]; then
        mv "${repo_root}/.beads/${artifact}" "${recovery_path}/${artifact}"
      fi
    done
  fi

  (
    cd "${repo_root}"
    "${system_bd}" bootstrap >/dev/null 2>&1
    "${system_bd}" --db "${current_db}" import "${current_issues}" >/dev/null 2>&1
  )
  rm -f "${current_redirect}"

  if [[ "${output_format}" == "env" ]]; then
    printf 'result=%q\n' "localized"
    printf 'repo_root=%q\n' "${repo_root}"
    printf 'db_path=%q\n' "${current_db}"
    if [[ -n "${recovery_path}" ]]; then
      printf 'backup_path=%q\n' "${recovery_path}"
    fi
    return 0
  fi

  printf 'Localized Beads state to the named runtime behind %s\n' "${current_db}"
  if [[ -n "${recovery_path}" ]]; then
    printf 'Backup: %s\n' "${recovery_path}"
  fi
}

beads_resolve_main() {
  local repo_override=""
  local output_format="human"
  local -a bd_args=()
  local localize_mode="false"

  if [[ "${1:-}" == "localize" ]]; then
    localize_mode="true"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo_override="${2:-}"
        [[ -n "${repo_override}" ]] || beads_resolve_die "--repo requires a value"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
        [[ -n "${output_format}" ]] || beads_resolve_die "--format requires a value"
        shift 2
        ;;
      --)
        shift
        bd_args=("$@")
        break
        ;;
      -h|--help)
        beads_resolve_usage
        exit 0
        ;;
      *)
        bd_args+=("$1")
        shift
        ;;
    esac
  done

  case "${output_format}" in
    human|env) ;;
    *)
      beads_resolve_die "Unsupported output format: ${output_format}"
      ;;
  esac

  if [[ -n "${repo_override}" ]]; then
    repo_override="$(beads_resolve_normalize_path "${repo_override}")"
  fi

  if [[ "${localize_mode}" == "true" ]]; then
    beads_localize_worktree "${repo_override:-$PWD}" "${output_format}"
    return 0
  fi

  beads_resolve_dispatch "${repo_override:-$PWD}" "${bd_args[@]}"

  if [[ "${output_format}" == "env" ]]; then
    beads_resolve_render_env
  else
    beads_resolve_render_human
  fi

  exit "${BEADS_RESOLVE_EXIT_CODE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  beads_resolve_main "$@"
fi
