#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sync-to-codex.sh --install [--source-root <host-project>]
  sync-to-codex.sh --check [--source-root <host-project>]
EOF
}

mode="${1:---install}"
shift || true

source_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-root)
      source_root="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[sync-to-codex] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${mode}" != "--install" && "${mode}" != "--check" ]]; then
  usage >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
adapter_root="$(cd -- "${script_dir}/.." && pwd)"
repo_root="$(cd -- "${adapter_root}/../.." && pwd)"
source_root="${source_root:-${repo_root}}"
dest_root="${CODEX_HOME:-$HOME/.codex}/skills/worktree-skill-codex"

mkdir -p "${dest_root}"

required_sources=(
  "${source_root}/.claude/commands/worktree.md"
  "${source_root}/.claude/commands/session-summary.md"
  "${source_root}/.claude/commands/git-topology.md"
)

for path in "${required_sources[@]}"; do
  [[ -f "${path}" ]] || { echo "[sync-to-codex] missing required source: ${path}" >&2; exit 1; }
done

if [[ "${mode}" == "--check" ]]; then
  for file in worktree.md session-summary.md git-topology.md; do
    [[ -f "${dest_root}/${file}" ]] || { echo "[sync-to-codex] missing bridged file: ${dest_root}/${file}" >&2; exit 1; }
  done
  echo "[sync-to-codex] Codex bridge files are present in ${dest_root}"
  exit 0
fi

cp "${source_root}/.claude/commands/worktree.md" "${dest_root}/worktree.md"
cp "${source_root}/.claude/commands/session-summary.md" "${dest_root}/session-summary.md"
cp "${source_root}/.claude/commands/git-topology.md" "${dest_root}/git-topology.md"

echo "[sync-to-codex] installed worktree-skill bridge files into ${dest_root}"
echo "[sync-to-codex] restart Codex if the client caches skill discovery."
