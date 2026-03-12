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

beads_dir="${repo_root}/.beads"
config_path="${beads_dir}/config.yaml"
issues_path="${beads_dir}/issues.jsonl"
redirect_path="${beads_dir}/redirect"
local_db_path="${beads_dir}/beads.db"
repo_bd_path="${repo_root}/bin/bd"

if [[ -f "${redirect_path}" ]]; then
  fail "redirected Beads metadata detected at ${redirect_path}. Run ${script_dir}/beads-worktree-localize.sh first." 3
fi

missing=()
if [[ ! -f "${config_path}" ]]; then
  missing+=("${config_path}")
fi
if [[ ! -f "${issues_path}" ]]; then
  missing+=("${issues_path}")
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  fail "missing local Beads foundation files: ${missing[*]}. Use the managed worktree bootstrap or recover/localize this worktree before retrying." 4
fi

export BEADS_DB="${local_db_path}"
if [[ -x "${repo_bd_path}" ]]; then
  exec "${repo_bd_path}" "$@"
fi

exec bd "$@"
