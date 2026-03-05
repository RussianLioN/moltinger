#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/sync-agent-instructions.sh --write   # regenerate AGENTS.md
  ./scripts/sync-agent-instructions.sh --check   # verify AGENTS.md is up to date
EOF
}

mode="${1:---write}"
if [[ "${mode}" != "--write" && "${mode}" != "--check" ]]; then
  usage
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

shared="${repo_root}/.ai/instructions/shared-core.md"
codex="${repo_root}/.ai/instructions/codex-adapter.md"
target="${repo_root}/AGENTS.md"

for f in "${shared}" "${codex}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing source file: ${f}" >&2
    exit 1
  fi
done

tmp="$(mktemp)"
cleanup() {
  rm -f "${tmp}"
}
trap cleanup EXIT

{
  cat <<'EOF'
# Agent Instructions

> GENERATED FILE. DO NOT EDIT DIRECTLY.
> Source: `.ai/instructions/shared-core.md` + `.ai/instructions/codex-adapter.md`
> Regenerate with: `./scripts/sync-agent-instructions.sh --write`

EOF
  cat "${shared}"
  echo
  cat "${codex}"
} > "${tmp}"

if [[ "${mode}" == "--check" ]]; then
  if [[ ! -f "${target}" ]]; then
    echo "AGENTS.md is missing. Run --write." >&2
    exit 1
  fi

  if cmp -s "${tmp}" "${target}"; then
    echo "AGENTS.md is up to date."
    exit 0
  fi

  echo "AGENTS.md is out of date. Run ./scripts/sync-agent-instructions.sh --write" >&2
  diff -u "${target}" "${tmp}" || true
  exit 1
fi

mv "${tmp}" "${target}"
trap - EXIT
echo "Updated ${target}"
