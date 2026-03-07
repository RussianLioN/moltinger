#!/usr/bin/env bash
# On-demand Telegram/Moltis E2E harness (manual verdict mode)
#
# Exit codes:
#   0 - completed with report
#   2 - precondition/config error
#   3 - timeout/no observed response
#   4 - upstream/auth error

set -euo pipefail

MODE=""
MESSAGE=""
TIMEOUT_SEC=30
OUTPUT_PATH="telegram-e2e-result.json"
MOLTIS_URL="http://localhost:13131"
MOLTIS_PASSWORD_ENV="MOLTIS_PASSWORD"
VERBOSE=false
TRIGGER_SOURCE="${TRIGGER_SOURCE:-cli}"

RUN_ID=""
STARTED_AT=""
FINISHED_AT=""
START_MS=0
DURATION_MS=0
TRANSPORT=""
OBSERVED_RESPONSE=""
STATUS=""
ERROR_CODE=""
ERROR_MESSAGE=""
CONTEXT_JSON='{}'

TMP_DIR=""
COOKIE_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/telegram-e2e-on-demand.sh [options]

Options:
  --mode synthetic|real_user      Execution mode (required)
  --message "<text>"             Input message for the run (required)
  --timeout-sec <int>             Timeout in seconds (default: 30)
  --output <path>                 Report output path (default: telegram-e2e-result.json)
  --moltis-url <url>              Moltis base URL (default: http://localhost:13131)
  --moltis-password-env <ENV>     Env var name that holds Moltis password (default: MOLTIS_PASSWORD)
  --verbose                       Enable verbose logs
  -h, --help                      Show this help message
USAGE
}

log() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[telegram-e2e] $*" >&2
  fi
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_ms() {
  local sec ns ms
  sec="$(date +%s)"
  ns="$(date +%N 2>/dev/null || true)"

  if [[ "$ns" =~ ^[0-9]{1,9}$ ]]; then
    ms=$(( sec * 1000 + 10#${ns:0:3} ))
    echo "$ms"
    return 0
  fi

  # macOS BSD date does not support %N.
  echo "$(( sec * 1000 ))"
}

is_meaningful_payload() {
  local payload="$1"
  local trimmed
  trimmed="$(echo "$payload" | tr -d '[:space:]')"

  if [[ -z "$trimmed" ]]; then
    return 1
  fi

  case "$trimmed" in
    null|"null"|{}|[]|""|"{}"|"[]")
      return 1
      ;;
  esac

  return 0
}

write_report() {
  local output_dir
  output_dir="$(dirname "$OUTPUT_PATH")"

  mkdir -p "$output_dir" 2>/dev/null || true

  jq -n \
    --arg run_id "$RUN_ID" \
    --arg mode "$MODE" \
    --arg trigger_source "$TRIGGER_SOURCE" \
    --arg message "$MESSAGE" \
    --arg started_at "$STARTED_AT" \
    --arg finished_at "$FINISHED_AT" \
    --argjson duration_ms "$DURATION_MS" \
    --arg transport "$TRANSPORT" \
    --arg observed_response "$OBSERVED_RESPONSE" \
    --arg status "$STATUS" \
    --arg error_code "$ERROR_CODE" \
    --arg error_message "$ERROR_MESSAGE" \
    --argjson context "$CONTEXT_JSON" \
    '{
      run_id: $run_id,
      mode: $mode,
      trigger_source: $trigger_source,
      message: $message,
      started_at: $started_at,
      finished_at: $finished_at,
      duration_ms: $duration_ms,
      transport: $transport,
      observed_response: (if $observed_response == "" then null else $observed_response end),
      status: $status,
      error_code: (if $error_code == "" then null else $error_code end),
      error_message: (if $error_message == "" then null else $error_message end),
      context: $context
    }' > "$OUTPUT_PATH"

  log "Report written: $OUTPUT_PATH"
}

finish_with_status() {
  local exit_code="$1"
  local finished_ms
  finished_ms="$(now_ms)"
  FINISHED_AT="$(now_iso)"
  if [[ "$START_MS" =~ ^[0-9]+$ ]] && [[ "$finished_ms" =~ ^[0-9]+$ ]]; then
    DURATION_MS=$(( finished_ms - START_MS ))
    if [[ "$DURATION_MS" -lt 0 ]]; then
      DURATION_MS=0
    fi
  else
    DURATION_MS=0
  fi

  write_report
  exit "$exit_code"
}

precondition_fail() {
  ERROR_CODE="precondition"
  ERROR_MESSAGE="$1"
  STATUS="precondition_failed"
  finish_with_status 2
}

upstream_fail() {
  ERROR_CODE="upstream"
  ERROR_MESSAGE="$1"
  STATUS="upstream_failed"
  finish_with_status 4
}

timeout_fail() {
  ERROR_CODE="timeout"
  ERROR_MESSAGE="$1"
  STATUS="timeout"
  finish_with_status 3
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="${2:-}"
        shift 2
        ;;
      --message)
        MESSAGE="${2:-}"
        shift 2
        ;;
      --timeout-sec)
        TIMEOUT_SEC="${2:-}"
        shift 2
        ;;
      --output)
        OUTPUT_PATH="${2:-}"
        shift 2
        ;;
      --moltis-url)
        MOLTIS_URL="${2:-}"
        shift 2
        ;;
      --moltis-password-env)
        MOLTIS_PASSWORD_ENV="${2:-}"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 2
        ;;
    esac
  done
}

validate_args() {
  if ! command -v curl >/dev/null 2>&1; then
    precondition_fail "curl is required"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    precondition_fail "jq is required"
  fi

  if [[ -z "$MODE" ]]; then
    precondition_fail "--mode is required"
  fi

  if [[ "$MODE" != "synthetic" && "$MODE" != "real_user" ]]; then
    precondition_fail "--mode must be synthetic or real_user"
  fi

  if [[ -z "${MESSAGE// }" ]]; then
    precondition_fail "--message must be non-empty"
  fi

  if ! [[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_SEC" -le 0 ]]; then
    precondition_fail "--timeout-sec must be a positive integer"
  fi
}

init_runtime() {
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  STARTED_AT="$(now_iso)"
  START_MS="$(now_ms)"

  TMP_DIR="$(mktemp -d)"
  COOKIE_FILE="$TMP_DIR/moltis-cookie.txt"

  trap 'rm -rf "$TMP_DIR"' EXIT
}

run_real_user() {
  TRANSPORT="telegram_mtproto_real_user"

  if ! command -v python3 >/dev/null 2>&1; then
    CONTEXT_JSON='{"notes":["python3 is required for real_user mode"]}'
    precondition_fail "python3 is required for real_user mode"
  fi

  local required_vars=(
    TELEGRAM_TEST_API_ID
    TELEGRAM_TEST_API_HASH
    TELEGRAM_TEST_SESSION
  )

  local missing=()
  local key
  for key in "${required_vars[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      missing+=("$key")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    local missing_json
    missing_json="$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)"
    CONTEXT_JSON="$(jq -cn \
      --argjson missing "$missing_json" \
      --arg hint1 "Set TELEGRAM_TEST_API_ID, TELEGRAM_TEST_API_HASH, TELEGRAM_TEST_SESSION" \
      --arg hint2 "Generate TELEGRAM_TEST_SESSION once via Telegram OTP bootstrap" \
      '{missing_prerequisites:$missing, action_hints:[$hint1,$hint2]}')"
    precondition_fail "Missing required TELEGRAM_TEST_* prerequisites for real_user mode"
  fi

  local helper_script="$SCRIPT_DIR/telegram-real-user-e2e.py"
  if [[ ! -f "$helper_script" ]]; then
    CONTEXT_JSON='{"notes":["real_user helper script not found"]}'
    upstream_fail "real_user helper script is missing"
  fi

  local helper_output_file="$TMP_DIR/real-user-result.json"
  local helper_error_file="$TMP_DIR/real-user-error.log"
  local bot_username="${TELEGRAM_TEST_BOT_USERNAME:-@moltinger_bot}"
  local helper_args=(
    "$helper_script"
    --api-id "${TELEGRAM_TEST_API_ID}"
    --api-hash "${TELEGRAM_TEST_API_HASH}"
    --session "${TELEGRAM_TEST_SESSION}"
    --bot-username "$bot_username"
    --message "$MESSAGE"
    --timeout-sec "$TIMEOUT_SEC"
  )
  if [[ "$VERBOSE" == "true" ]]; then
    helper_args+=(--verbose)
  fi

  set +e
  python3 "${helper_args[@]}" > "$helper_output_file" 2> "$helper_error_file"
  local helper_exit=$?
  set -e

  if ! jq -e . "$helper_output_file" >/dev/null 2>&1; then
    local helper_stderr
    helper_stderr="$(tail -n 50 "$helper_error_file" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    CONTEXT_JSON="$(jq -cn --arg stderr "$helper_stderr" '{helper_stderr:$stderr}')"
    upstream_fail "real_user helper returned invalid JSON"
  fi

  TRANSPORT="$(jq -r '.transport // "telegram_mtproto_real_user"' "$helper_output_file")"
  OBSERVED_RESPONSE="$(jq -r '.observed_response // ""' "$helper_output_file")"
  STATUS="$(jq -r '.status // "upstream_failed"' "$helper_output_file")"
  ERROR_CODE="$(jq -r '.error_code // ""' "$helper_output_file")"
  ERROR_MESSAGE="$(jq -r '.error_message // ""' "$helper_output_file")"
  CONTEXT_JSON="$(jq -c --argjson helper_exit "$helper_exit" '(.context // {}) + {helper_exit_code:$helper_exit}' "$helper_output_file")"

  case "$STATUS" in
    completed)
      finish_with_status 0
      ;;
    timeout)
      finish_with_status 3
      ;;
    precondition_failed)
      finish_with_status 2
      ;;
    upstream_failed)
      finish_with_status 4
      ;;
    *)
      ERROR_CODE="upstream"
      if [[ -z "$ERROR_MESSAGE" ]]; then
        ERROR_MESSAGE="Unexpected real_user status from helper: $STATUS"
      fi
      STATUS="upstream_failed"
      finish_with_status 4
      ;;
  esac
}

run_synthetic() {
  TRANSPORT="moltis_api_chat"

  local password
  password="${!MOLTIS_PASSWORD_ENV:-}"
  if [[ -z "$password" ]]; then
    CONTEXT_JSON='{"notes":["missing Moltis password env"]}'
    precondition_fail "Environment variable ${MOLTIS_PASSWORD_ENV} is empty"
  fi

  local login_response_file="$TMP_DIR/login-response.json"
  local send_response_file="$TMP_DIR/send-response.json"
  local poll_response_file="$TMP_DIR/poll-response.json"

  log "Authenticating against $MOLTIS_URL/api/auth/login"
  local login_code
  login_code="$(curl -sS -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MOLTIS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg pw "$password" '{password:$pw}')" \
    -o "$login_response_file" \
    -w "%{http_code}" || true)"
  login_code="${login_code:-000}"

  if [[ "$login_code" != "200" && "$login_code" != "302" ]]; then
    CONTEXT_JSON="$(jq -cn --arg login_http_code "$login_code" '{login_http_code:$login_http_code}')"
    upstream_fail "Moltis authentication failed (HTTP ${login_code})"
  fi

  log "Sending message to $MOLTIS_URL/api/v1/chat"
  local send_code
  send_code="$(curl -sS -b "$COOKIE_FILE" \
    -X POST "$MOLTIS_URL/api/v1/chat" \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg msg "$MESSAGE" '{message:$msg}')" \
    -o "$send_response_file" \
    -w "%{http_code}" || true)"
  send_code="${send_code:-000}"

  local send_body
  send_body="$(cat "$send_response_file" 2>/dev/null || true)"

  if [[ "$send_code" != "200" && "$send_code" != "202" ]]; then
    CONTEXT_JSON="$(jq -cn \
      --arg login_http_code "$login_code" \
      --arg send_http_code "$send_code" \
      '{login_http_code:$login_http_code, send_http_code:$send_http_code}')"
    upstream_fail "Moltis chat send failed (HTTP ${send_code})"
  fi

  local observed=""
  if is_meaningful_payload "$send_body"; then
    observed="$send_body"
  fi

  local attempt=0
  local elapsed=0
  while [[ $elapsed -lt $TIMEOUT_SEC && -z "$observed" ]]; do
    attempt=$((attempt + 1))
    sleep 1

    local poll_code
    poll_code="$(curl -sS -b "$COOKIE_FILE" \
      -X GET "$MOLTIS_URL/api/v1/chat" \
      -o "$poll_response_file" \
      -w "%{http_code}" || true)"
    poll_code="${poll_code:-000}"

    local poll_body
    poll_body="$(cat "$poll_response_file" 2>/dev/null || true)"

    if [[ "$poll_code" == "200" || "$poll_code" == "202" ]]; then
      if is_meaningful_payload "$poll_body"; then
        observed="$poll_body"
      fi
    fi

    elapsed=$((elapsed + 1))
  done

  CONTEXT_JSON="$(jq -cn \
    --arg login_http_code "$login_code" \
    --arg send_http_code "$send_code" \
    --argjson poll_attempts "$attempt" \
    '{login_http_code:$login_http_code, send_http_code:$send_http_code, poll_attempts:$poll_attempts}')"

  if [[ -z "$observed" ]]; then
    timeout_fail "No observed response before timeout"
  fi

  OBSERVED_RESPONSE="$observed"
  STATUS="completed"
  finish_with_status 0
}

main() {
  parse_args "$@"
  init_runtime
  validate_args

  case "$MODE" in
    synthetic)
      run_synthetic
      ;;
    real_user)
      run_real_user
      ;;
    *)
      precondition_fail "Unsupported mode"
      ;;
  esac
}

main "$@"
