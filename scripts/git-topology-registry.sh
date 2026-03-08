#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/git-topology-registry.sh refresh [--write-doc]
  scripts/git-topology-registry.sh check
  scripts/git-topology-registry.sh status
  scripts/git-topology-registry.sh doctor [--prune] [--write-doc]

Description:
  Owner script for the sanitized git topology registry and reviewed intent sidecar.
  Phase 1 provides the command skeleton and shared path discovery only.
EOF
}

action=""
write_doc=false
prune=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    refresh|check|status|doctor)
      if [[ -n "${action}" ]]; then
        echo "[git-topology-registry] Multiple actions provided." >&2
        usage >&2
        exit 2
      fi
      action="$1"
      shift
      ;;
    --write-doc)
      write_doc=true
      shift
      ;;
    --prune)
      prune=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[git-topology-registry] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${action}" ]]; then
  usage >&2
  exit 2
fi

git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${git_root}" ]]; then
  echo "[git-topology-registry] Not inside a git repository." >&2
  exit 2
fi

git_common_dir="$(git rev-parse --git-common-dir)"
state_dir="${git_common_dir}/topology-registry"
state_file="${state_dir}/health.env"
intent_file="${git_root}/docs/GIT-TOPOLOGY-INTENT.yaml"
registry_doc="${git_root}/docs/GIT-TOPOLOGY-REGISTRY.md"

print_context() {
  echo "repo_root=${git_root}"
  echo "git_common_dir=${git_common_dir}"
  echo "intent_file=${intent_file}"
  echo "registry_doc=${registry_doc}"
  echo "state_file=${state_file}"
}

ensure_state_dir() {
  mkdir -p "${state_dir}"
}

not_implemented() {
  local feature="$1"
  echo "[git-topology-registry] ${feature} is not implemented yet." >&2
  echo "[git-topology-registry] Phase 1 skeleton only; finish T006-T010 next." >&2
  exit 3
}

case "${action}" in
  status)
    print_context
    if [[ -f "${state_file}" ]]; then
      cat "${state_file}"
    else
      echo "status=unconfigured"
      echo "message=topology registry has not written health state yet"
    fi
    ;;
  refresh)
    ensure_state_dir
    if [[ "${write_doc}" == "true" ]]; then
      not_implemented "refresh --write-doc"
    fi
    not_implemented "refresh"
    ;;
  check)
    not_implemented "check"
    ;;
  doctor)
    ensure_state_dir
    if [[ "${prune}" == "true" ]]; then
      echo "[git-topology-registry] doctor will support --prune after Phase 2." >&2
    fi
    if [[ "${write_doc}" == "true" ]]; then
      echo "[git-topology-registry] doctor will support --write-doc after Phase 2." >&2
    fi
    not_implemented "doctor"
    ;;
esac
