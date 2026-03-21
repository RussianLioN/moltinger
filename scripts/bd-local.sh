#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

fail() {
  printf 'bd-local: %s\n' "$1" >&2
  exit "${2:-1}"
}

if [[ -z "${repo_root}" ]]; then
  fail "run this command from inside a git worktree" 2
fi

# shellcheck source=scripts/beads-resolve-db.sh
source "${repo_root}/scripts/beads-resolve-db.sh"

repo_bd_path="${repo_root}/bin/bd"
self_path="${script_dir}/bd-local.sh"
system_bd="${BEADS_SYSTEM_BD:-}"

resolve_system_bd() {
  if [[ -n "${system_bd}" ]]; then
    printf '%s\n' "${system_bd}"
    return 0
  fi

  if system_bd="$(beads_resolve_find_system_bd "${repo_bd_path:-${self_path}}" 2>/dev/null)"; then
    printf '%s\n' "${system_bd}"
    return 0
  fi

  if system_bd="$(command -v bd 2>/dev/null || true)"; then
    printf '%s\n' "${system_bd}"
    return 0
  fi

  return 1
}

beads_resolve_dispatch "${repo_root}" "$@"

case "${BEADS_RESOLVE_DECISION}" in
  execute_local)
    export BEADS_DB="${BEADS_RESOLVE_DB_PATH}"
    if [[ -x "${repo_bd_path}" ]]; then
      exec "${repo_bd_path}" "$@"
    fi
    system_bd="$(resolve_system_bd)" || fail "could not locate a bd binary to execute the resolved local runtime" 1
    exec "${system_bd}" --db "${BEADS_RESOLVE_DB_PATH}" "$@"
    ;;
  pass_through_non_repo|pass_through_root_readonly|pass_through_global|allow_explicit_troubleshooting)
    if [[ -x "${repo_bd_path}" ]]; then
      exec "${repo_bd_path}" "$@"
    fi
    system_bd="$(resolve_system_bd)" || fail "could not locate a bd binary to execute the command" 1
    exec "${system_bd}" "$@"
    ;;
  block_legacy_redirect|block_missing_foundation|block_pilot_legacy_command|block_root_fallback|block_root_mutation|block_unresolved_ownership)
    printf '%s\n' "${BEADS_RESOLVE_MESSAGE}" >&2
    if [[ -n "${BEADS_RESOLVE_RECOVERY_HINT}" ]]; then
      printf 'Recovery: %s\n' "${BEADS_RESOLVE_RECOVERY_HINT}" >&2
    fi
    if [[ -n "${BEADS_RESOLVE_ROOT_CLEANUP_NOTICE}" ]]; then
      printf 'Note: %s\n' "${BEADS_RESOLVE_ROOT_CLEANUP_NOTICE}" >&2
    fi
    exit "${BEADS_RESOLVE_EXIT_CODE:-1}"
    ;;
  *)
    fail "unsupported resolution state '${BEADS_RESOLVE_DECISION}'" 1
    ;;
esac
