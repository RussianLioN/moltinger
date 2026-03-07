#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/git-session-guard.sh [--check] [--hook <name>]
  scripts/git-session-guard.sh --refresh
  scripts/git-session-guard.sh --status

Description:
  Guard against accidental branch/worktree drift across parallel sessions.
  State is stored in the repository git dir and validated by git hooks.
EOF
}

action="check"
hook_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      action="check"
      shift
      ;;
    --refresh)
      action="refresh"
      shift
      ;;
    --status)
      action="status"
      shift
      ;;
    --hook)
      hook_name="${2:-}"
      if [[ -z "${hook_name}" ]]; then
        echo "[git-session-guard] --hook requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[git-session-guard] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "[git-session-guard] Not inside a git repository; skipping."
  exit 0
fi

state_file="$(git rev-parse --git-path session-guard.state)"

current_branch="$(git symbolic-ref --short -q HEAD || true)"
current_worktree="$(cd "${git_root}" && pwd -P)"
now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

expected_branch=""
expected_worktree=""
created_at=""
updated_at=""

load_state() {
  if [[ ! -f "${state_file}" ]]; then
    return 1
  fi

  while IFS='=' read -r key value; do
    case "${key}" in
      expected_branch) expected_branch="${value}" ;;
      expected_worktree) expected_worktree="${value}" ;;
      created_at) created_at="${value}" ;;
      updated_at) updated_at="${value}" ;;
    esac
  done < "${state_file}"

  return 0
}

write_state() {
  local created="$1"
  cat > "${state_file}" <<EOF
expected_branch=${current_branch}
expected_worktree=${current_worktree}
created_at=${created}
updated_at=${now_utc}
EOF
}

fail_guard() {
  local reason="$1"
  if [[ -n "${hook_name}" ]]; then
    echo "[git-session-guard] ${hook_name} blocked: ${reason}" >&2
  else
    echo "[git-session-guard] ${reason}" >&2
  fi

  echo "[git-session-guard] current: branch='${current_branch:-DETACHED}', worktree='${current_worktree}'" >&2
  echo "[git-session-guard] expected: branch='${expected_branch:-<unset>}', worktree='${expected_worktree:-<unset>}'" >&2
  echo "[git-session-guard] If this switch is intentional, run: scripts/git-session-guard.sh --refresh" >&2
  exit 1
}

if [[ "${action}" == "refresh" ]]; then
  if [[ -z "${current_branch}" ]]; then
    echo "[git-session-guard] Cannot refresh while HEAD is detached." >&2
    exit 1
  fi

  if load_state; then
    write_state "${created_at:-${now_utc}}"
    echo "[git-session-guard] Refreshed: ${current_branch} @ ${current_worktree}"
  else
    write_state "${now_utc}"
    echo "[git-session-guard] Initialized: ${current_branch} @ ${current_worktree}"
  fi
  exit 0
fi

if [[ "${action}" == "status" ]]; then
  if ! load_state; then
    echo "[git-session-guard] No guard state yet. Run: scripts/git-session-guard.sh --refresh"
    exit 0
  fi

  echo "state_file=${state_file}"
  echo "expected_branch=${expected_branch}"
  echo "expected_worktree=${expected_worktree}"
  echo "created_at=${created_at}"
  echo "updated_at=${updated_at}"
  echo "current_branch=${current_branch:-DETACHED}"
  echo "current_worktree=${current_worktree}"

  if [[ -z "${current_branch}" ]]; then
    echo "status=detached_head"
    exit 1
  fi

  if [[ "${current_branch}" != "${expected_branch}" || "${current_worktree}" != "${expected_worktree}" ]]; then
    echo "status=drift"
    exit 1
  fi

  echo "status=ok"
  exit 0
fi

# action=check
if [[ -z "${current_branch}" ]]; then
  fail_guard "Detached HEAD is not allowed for guarded sessions."
fi

if ! load_state; then
  write_state "${now_utc}"
  echo "[git-session-guard] Initialized guard state for '${current_branch}'."
  exit 0
fi

if [[ -z "${expected_branch}" || -z "${expected_worktree}" ]]; then
  fail_guard "Corrupted guard state."
fi

if [[ "${current_branch}" != "${expected_branch}" ]]; then
  fail_guard "Branch drift detected."
fi

if [[ "${current_worktree}" != "${expected_worktree}" ]]; then
  fail_guard "Worktree drift detected."
fi

exit 0
