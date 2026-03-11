#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install/bootstrap.sh --target <host-project> [--adapter claude-code|codex-cli|opencode] [--with-speckit]
EOF
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
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
      echo "[bootstrap] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "${target}" ]] || { usage >&2; exit 2; }
[[ -d "${target}" ]] || { echo "[bootstrap] target not found: ${target}" >&2; exit 2; }

mkdir -p "${target}"
cp -R "${repo_root}/core/." "${target}/"

if [[ -n "${adapter}" ]]; then
  [[ -d "${repo_root}/adapters/${adapter}" ]] || { echo "[bootstrap] adapter not found: ${adapter}" >&2; exit 2; }
  cp -R "${repo_root}/adapters/${adapter}/." "${target}/"
fi

if [[ "${with_speckit}" == "true" ]]; then
  mkdir -p "${target}/bridge"
  cp -R "${repo_root}/bridge/speckit" "${target}/bridge/"
fi

echo "[bootstrap] installed portable core into ${target}"
if [[ -n "${adapter}" ]]; then
  echo "[bootstrap] installed adapter ${adapter}"
fi
if [[ "${with_speckit}" == "true" ]]; then
  echo "[bootstrap] installed Speckit bridge"
fi
