#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/worktree-skill-ready.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

"${repo_root}/install/bootstrap.sh" --target "${tmpdir}" --adapter claude-code --with-speckit >/dev/null
"${repo_root}/install/verify.sh" --target "${tmpdir}" --adapter claude-code --with-speckit >/dev/null

test -f "${tmpdir}/.claude/commands/worktree.md"
test -f "${tmpdir}/scripts/worktree-ready.sh"
test -d "${tmpdir}/bridge/speckit"

echo "ok - portable bootstrap and verify flow works"
