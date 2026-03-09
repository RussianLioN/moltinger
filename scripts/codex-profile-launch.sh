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
  CODEX_UPDATE_LAUNCH_ALERT     Print launch-time Codex update banner (default: 1)
  CODEX_UPDATE_LAUNCH_TELEGRAM  Send Telegram delivery check at launch when configured (default: 0)
  CODEX_UPDATE_DELIVERY_TELEGRAM_CHAT_ID  Telegram chat id for launch-time delivery
  CODEX_UPDATE_DELIVERY_SCRIPT  Override the delivery script path (test/debug use)
  CODEX_UPDATE_LAUNCH_TELEGRAM_SEND_SCRIPT  Override the Telegram transport script used at launch

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
DELIVERY_ALERT_ENABLED="${CODEX_UPDATE_LAUNCH_ALERT:-1}"
DELIVERY_TELEGRAM_ENABLED="${CODEX_UPDATE_LAUNCH_TELEGRAM:-0}"
DELIVERY_TELEGRAM_CHAT_ID="${CODEX_UPDATE_DELIVERY_TELEGRAM_CHAT_ID:-}"
DELIVERY_SCRIPT="${CODEX_UPDATE_DELIVERY_SCRIPT:-${REPO_ROOT}/scripts/codex-cli-update-delivery.sh}"
DELIVERY_TELEGRAM_SEND_SCRIPT="${CODEX_UPDATE_LAUNCH_TELEGRAM_SEND_SCRIPT:-${REPO_ROOT}/scripts/telegram-bot-send-remote.sh}"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH" >&2
  exit 1
fi

show_delivery_alert() {
  local enabled="$1"
  local summary=""

  case "$enabled" in
    0|false|FALSE|no|NO|off|OFF)
      return 0
      ;;
  esac

  if [[ ! -f "$DELIVERY_SCRIPT" ]]; then
    return 0
  fi

  if summary="$(bash "$DELIVERY_SCRIPT" --surface launcher --stdout summary 2>/dev/null)"; then
    if [[ -n "$summary" ]]; then
      printf '%s\n' "$summary"
      printf '\n'
    fi
  fi
}

send_delivery_telegram() {
  local enabled="$1"
  local chat_id="$2"
  local send_script="$3"

  case "$enabled" in
    0|false|FALSE|no|NO|off|OFF)
      return 0
      ;;
  esac

  if [[ ! -f "$DELIVERY_SCRIPT" || -z "$chat_id" || ! -f "$send_script" ]]; then
    return 0
  fi

  (
    bash "$DELIVERY_SCRIPT" \
      --surface telegram \
      --telegram-enabled \
      --telegram-chat-id "$chat_id" \
      --telegram-send-script "$send_script" \
      --stdout none >/dev/null 2>&1 || true
  ) &
}

show_delivery_alert "$DELIVERY_ALERT_ENABLED"
send_delivery_telegram "$DELIVERY_TELEGRAM_ENABLED" "$DELIVERY_TELEGRAM_CHAT_ID" "$DELIVERY_TELEGRAM_SEND_SCRIPT"

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
