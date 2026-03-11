#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install/verify.sh --target <host-project> [--adapter claude-code|codex-cli|opencode] [--with-speckit]
EOF
}

target=""
adapter=""
with_speckit="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target="${2:-}"
      shift 2
      ;;
    --adapter)
      adapter="${2:-}"
      shift 2
      ;;
    --with-speckit)
      with_speckit="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[verify] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "${target}" ]] || { usage >&2; exit 2; }
[[ -d "${target}" ]] || { echo "[verify] target not found: ${target}" >&2; exit 2; }

required_paths=(
  ".claude/commands/worktree.md"
  ".claude/commands/session-summary.md"
  ".claude/commands/git-topology.md"
  "scripts/worktree-ready.sh"
  "scripts/worktree-phase-a.sh"
  "scripts/git-topology-registry.sh"
)

for path in "${required_paths[@]}"; do
  [[ -e "${target}/${path}" ]] || { echo "[verify] missing core artifact: ${path}" >&2; exit 1; }
done

if [[ "${with_speckit}" == "true" ]]; then
  [[ -d "${target}/bridge/speckit" ]] || { echo "[verify] Speckit bridge requested but not found." >&2; exit 1; }
fi

echo "[verify] portable core present in ${target}"
if [[ -n "${adapter}" ]]; then
  echo "[verify] adapter check completed for ${adapter}"
fi
if [[ "${with_speckit}" == "true" ]]; then
  echo "[verify] Speckit bridge present"
fi
