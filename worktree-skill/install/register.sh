#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install/register.sh --target <host-project> --adapter <claude-code|codex-cli|opencode>
EOF
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
target=""
adapter=""

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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[register] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "${target}" && -n "${adapter}" ]] || { usage >&2; exit 2; }

case "${adapter}" in
  claude-code)
    echo "[register] Claude Code usually requires only file placement. Verify host discovery manually."
    ;;
  codex-cli)
    "${repo_root}/adapters/codex-cli/install/sync-to-codex.sh" --install --source-root "${target}"
    ;;
  opencode)
    echo "[register] Follow ${repo_root}/adapters/opencode/register-example.md for host-specific registration."
    ;;
  *)
    echo "[register] unsupported adapter: ${adapter}" >&2
    exit 2
    ;;
esac
