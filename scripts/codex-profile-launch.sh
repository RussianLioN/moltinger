#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/codex-profile-launch.sh <profile> [prompt]

Profiles:
  research   Read-only investigative session
  docs       Docs and knowledge updates
  runtime    Config, workflow, and operational code changes
  assets     .ai/.claude asset work
  review     Non-interactive codex review against CODEX_BASE_BRANCH
  hotfix     Bounded hotfix session

Environment:
  CODEX_MODEL        Override model (default: gpt-5.4)
  CODEX_BASE_BRANCH  Override review base branch (default: main)

Notes:
  This launcher configures local Codex CLI behavior only.
  It does not change the Moltis runtime provider stack or GitHub workflow models.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROFILE="$1"
shift

MODEL="${CODEX_MODEL:-gpt-5.4}"
BASE_BRANCH="${CODEX_BASE_BRANCH:-main}"

if [[ -d "${REPO_ROOT}/bin" ]]; then
  export PATH="${REPO_ROOT}/bin:${PATH}"
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH" >&2
  exit 1
fi

case "${PROFILE}" in
  research)
    exec codex -m "${MODEL}" -C "${REPO_ROOT}" -s read-only -a never "$@"
    ;;
  docs)
    exec codex -m "${MODEL}" -C "${REPO_ROOT}" -s workspace-write -a on-request "$@"
    ;;
  runtime)
    exec codex -m "${MODEL}" -C "${REPO_ROOT}" -s workspace-write -a on-request "$@"
    ;;
  assets)
    exec codex -m "${MODEL}" -C "${REPO_ROOT}" -s workspace-write -a on-request "$@"
    ;;
  hotfix)
    exec codex -m "${MODEL}" -C "${REPO_ROOT}" -s workspace-write -a on-request "$@"
    ;;
  review)
    exec codex review -c "model=\"${MODEL}\"" --base "${BASE_BRANCH}" "$@"
    ;;
  *)
    echo "Unknown profile: ${PROFILE}" >&2
    usage >&2
    exit 2
    ;;
esac
