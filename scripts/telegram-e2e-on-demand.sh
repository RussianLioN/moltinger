#!/usr/bin/env bash
# On-demand Telegram remote UAT wrapper.
#
# Canonical use:
#   --mode authoritative
#   --secondary-diagnostics none|mtproto
#
# Exit codes:
#   0 - authoritative verdict passed
#   2 - precondition/config error
#   3 - authoritative verdict failed
#   4 - upstream/runtime error

set -euo pipefail

MODE="authoritative"
SECONDARY_DIAGNOSTICS="none"
MESSAGE=""
TIMEOUT_SEC=45
OUTPUT_PATH="telegram-e2e-result.json"
DEBUG_OUTPUT_PATH="${REMOTE_UAT_DEBUG_OUTPUT:-}"
VERBOSE=false
TRIGGER_SOURCE="${TRIGGER_SOURCE:-cli}"
TARGET_ENVIRONMENT="${TARGET_ENVIRONMENT:-production}"
OPERATOR_INTENT="${OPERATOR_INTENT:-post_deploy_verification}"
PRODUCTION_TRANSPORT_MODE="${PRODUCTION_TRANSPORT_MODE:-polling}"
AUTHORITATIVE_TARGET="${TELEGRAM_WEB_TARGET:-@moltinger_bot}"
AUTHORITATIVE_STATE="${TELEGRAM_WEB_STATE:-/opt/moltinger/data/.telegram-web-state.json}"
SHARED_TARGET_LOCK="${SHARED_TARGET_LOCK:-/tmp/moltinger-telegram-remote-uat.lock}"
SERIALIZE_SHARED_TARGET="${SERIALIZE_SHARED_TARGET:-true}"
MOLTIS_URL="${MOLTIS_URL:-http://localhost:13131}"
MOLTIS_PASSWORD_ENV="${MOLTIS_PASSWORD_ENV:-MOLTIS_PASSWORD}"
STATUS_EXPECTED_MODEL="${STATUS_EXPECTED_MODEL:-custom-zai-telegram-safe::glm-5}"
SKILLS_API_ATTEMPTS="${SKILLS_API_ATTEMPTS:-3}"
SKILLS_API_RETRY_DELAY_SECONDS="${SKILLS_API_RETRY_DELAY_SECONDS:-1}"

RUN_ID=""
STARTED_AT=""
FINISHED_AT=""
START_MS=0
DURATION_MS=0
RUN_STAGE="init"
VERDICT="failed"
AUTHORITATIVE_PATH="telegram_web"
TRANSPORT="telegram_web_user"
FAILURE_JSON='null'
ATTRIBUTION_JSON='{"attribution_confidence":"unknown"}'
DIAGNOSTIC_JSON='{}'
FALLBACK_JSON='{"requested":false,"path_used":null,"prerequisites_present":null,"outcome":"not_requested","decision_note":"Secondary diagnostics not requested."}'
RECOMMENDED_ACTION="Inspect the authoritative artifact and rerun after narrowing the root cause."
REDACTIONS_JSON='["telegram_session","telegram_api_hash","telegram_web_state_path","raw_logs"]'
ARTIFACT_STATUS="review_safe"

AUTHORITATIVE_RAW_JSON='null'
AUTHORITATIVE_STDERR=""
FALLBACK_RAW_JSON='null'
FALLBACK_STDERR=""

TMP_DIR=""
LOCK_FD=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_API_CACHE_STATUS="unset"
SKILLS_API_CACHE_JSON=""
SKILLS_API_CACHE_ERROR=""
SKILLS_API_CACHE_LOGIN_HTTP_CODE=""
SKILLS_API_CACHE_HTTP_CODE=""

usage() {
  cat <<'USAGE'
Usage: scripts/telegram-e2e-on-demand.sh [options]

Options:
  --mode authoritative|telegram_web|synthetic|real_user
                                    Execution mode (default: authoritative)
  --secondary-diagnostics none|mtproto
                                    Optional secondary diagnostics (default: none)
  --message "<text>"                Input message/command to send (required)
  --timeout-sec <int>               Timeout in seconds (default: 45)
  --output <path>                   Review-safe JSON output path (default: telegram-e2e-result.json)
  --debug-output <path>             Restricted debug bundle output path
  --target-environment <name>       Target environment label (default: production)
  --operator-intent <name>          Operator intent label (default: post_deploy_verification)
  --moltis-url <url>                Moltis base URL for synthetic compatibility mode
  --moltis-password-env <ENV>       Env var holding Moltis password for synthetic mode
  --verbose                         Enable verbose logs
  -h, --help                        Show this help message
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
  local sec ns
  sec="$(date +%s)"
  ns="$(date +%N 2>/dev/null || true)"
  if [[ "$ns" =~ ^[0-9]{1,9}$ ]]; then
    echo $(( sec * 1000 + 10#${ns:0:3} ))
    return 0
  fi
  echo $(( sec * 1000 ))
}

tail_sanitized() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo ""
    return 0
  fi

  tail -n 80 "$file_path" 2>/dev/null \
    | sed -E 's/(TELEGRAM_TEST_SESSION|TELEGRAM_TEST_API_HASH|TELEGRAM_TEST_API_ID|MOLTIS_PASSWORD|password|token|secret)=([^[:space:]]+)/\1=[redacted]/g' \
    | tr '\n' ' ' \
    | sed 's/[[:space:]]\+/ /g'
}

write_json_file() {
  local path="$1"
  local content="$2"
  local output_dir
  output_dir="$(dirname "$path")"
  mkdir -p "$output_dir" 2>/dev/null || true
  printf '%s\n' "$content" > "$path"
}

build_failure_json() {
  local code="$1"
  local stage_name="$2"
  local summary="$3"
  local actionability="$4"
  local fallback_relevant="$5"

  jq -cn \
    --arg code "$code" \
    --arg stage "$stage_name" \
    --arg summary "$summary" \
    --arg actionability "$actionability" \
    --argjson fallback_relevant "$fallback_relevant" \
    '{
      code: $code,
      stage: $stage,
      summary: $summary,
      actionability: $actionability,
      fallback_relevant: $fallback_relevant
    }'
}

sanitize_json_for_operator() {
  local input_json="${1:-"{}"}"
  jq -c '
    def scrub:
      walk(
        if type == "object" then
          with_entries(
            if (.key | test("(token|secret|session|api[_-]?hash|password|state_path)"; "i"))
            then .value = "[redacted]"
            else .
            end
          )
        else .
        end
      );
    scrub
  ' <<< "$input_json"
}

normalize_message_text() {
  printf '%s' "${1:-}" | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//'
}

reply_has_internal_activity() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    *"activity log"*|*"running:"*|*"searching memory"*|*"memory_search"*|*"thinking..."*|*"tool_call_started"*|*"tool_call_progress"*|*"mcp__"*)
      return 0
      ;;
  esac

  return 1
}

reply_has_internal_planning_leak() {
  local normalized
  normalized="$(normalize_message_text "${1:-}")"
  [[ -n "$normalized" ]] || return 1

  if printf '%s' "$normalized" | grep -Eiq 'пользователь просит|the user (is )?asking|у меня есть доступ к|i have access to|мне доступны|сначала найду|для начала найду|сейчас проверю|проверю источник|вернусь с ответом|вернусь с кратким планом|let me|checking|opening|looking up|((отлично|супер|окей|ладно)[!,.[:space:]]{0,12})?давай(те)? (получу|найду|изучу|посмотрю|открою|проверю|проанализирую|сделаю)|давай наконец(-то)?( это)? сделаю( правильно)?|хорошо,?[[:space:]]*(изучу|проверю|посмотрю|почитаю).{0,120}(документац|docs|documentation|manual|guide|инструкц)|начну с (поиска|анализа|изучения|просмотра)|наш[её]л официальный (репозиторий|документац)|github|полную документацию|чита(ю|ем).{0,80}(существующ(ий|его)|имеющ(ийся|егося)).{0,80}(навык|skill)|найд(у|ем).{0,80}(документац|docs|documentation|manual|guide|инструкц)|как пример|mcp__|mounted workspace|skill files|existing skills|существующ(ий|ие|его) навык|имеющ(егося|ийся) навы'; then
    return 0
  fi

  return 1
}

reply_has_host_path_leak() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    *"/home/moltis/.moltis/skills"*|*"/server/scripts/"*|*"/server/specs/"*)
      return 0
      ;;
  esac

  return 1
}

message_is_skill_create_query() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  if printf '%s' "$normalized" | grep -Eiq '(созда(й|йте|дим|ть|вать)|создать|создай|создадим|create|build|make).{0,40}(навык|skill)|(навык|skill).{0,24}(созда|create)'; then
    return 0
  fi

  return 1
}

message_is_skill_visibility_query() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  if message_is_skill_create_query "$normalized"; then
    return 1
  fi

  if printf '%s' "$normalized" | grep -Eiq '((что|какие|какой|покажи|показать|спис(ок|ать)|list|show|what).{0,40}(навык|skills?))|((навык|skills?).{0,40}(есть|имеются|видны|доступны|available|visible))|темплейт|template'; then
    return 0
  fi

  return 1
}

extract_requested_skill_name() {
  local normalized candidate
  normalized="$(normalize_message_text "${1:-}")"
  [[ -n "$normalized" ]] || return 1

  if [[ "$normalized" =~ (навык|skill)[[:space:]]*[\"\'\`\«]?([A-Za-z0-9._-]+) ]]; then
    candidate="${BASH_REMATCH[2]}"
    case "${candidate,,}" in
      новый|нового|новый|new|skill|skills|навык|навыки|template|темплейт)
        return 1
        ;;
    esac
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

reply_has_skill_false_negative() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  if printf '%s' "$normalized" | grep -Eiq '(/home/moltis/.moltis/skills|skills/? directory|директори(я|и) skills|каталог[[:space:]]+skills|папк(а|и).*/home/moltis/.moltis/skills).{0,120}(не существует|does not exist|missing|отсутствует|no such file or directory|не найден)'; then
    return 0
  fi

  if printf '%s' "$normalized" | grep -Eiq 'навыки.{0,40}(были удалены|ещ[её] не созданы)|skills.{0,40}(were deleted|not created yet)|по факту.{0,120}/home/moltis/.moltis/skills'; then
    return 0
  fi

  return 1
}

read_moltis_auth_password() {
  printf '%s' "${!MOLTIS_PASSWORD_ENV:-}"
}

moltis_login_session() {
  local cookie_file="$1"
  local login_url password login_payload login_code

  password="$(read_moltis_auth_password)"
  if [[ -z "$password" ]]; then
    SKILLS_API_CACHE_ERROR="missing_password_env:$MOLTIS_PASSWORD_ENV"
    SKILLS_API_CACHE_LOGIN_HTTP_CODE=""
    return 1
  fi

  login_url="${MOLTIS_URL%/}/api/auth/login"
  login_payload="$(jq -nc --arg password "$password" '{password:$password}')"
  login_code="$(
    curl -sS -o /dev/null -w '%{http_code}' \
      -c "$cookie_file" -b "$cookie_file" \
      -X POST "$login_url" \
      -H 'Content-Type: application/json' \
      -d "$login_payload" \
      --max-time 10 2>/dev/null || echo "000"
  )"
  SKILLS_API_CACHE_LOGIN_HTTP_CODE="${login_code:-000}"

  if [[ "$login_code" != "200" && "$login_code" != "302" ]]; then
    SKILLS_API_CACHE_ERROR="login_failed"
    return 1
  fi

  return 0
}

fetch_authenticated_skills_json() {
  if [[ "$SKILLS_API_CACHE_STATUS" == "success" ]]; then
    printf '%s' "$SKILLS_API_CACHE_JSON"
    return 0
  fi

  if [[ "$SKILLS_API_CACHE_STATUS" == "failed" ]]; then
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    SKILLS_API_CACHE_STATUS="failed"
    SKILLS_API_CACHE_ERROR="curl_missing"
    return 1
  fi

  local cookie_file response_file skills_api_url attempt http_code skills_json
  cookie_file="$TMP_DIR/moltis-skills-cookie.txt"
  response_file="$TMP_DIR/moltis-skills-response.json"
  skills_api_url="${MOLTIS_URL%/}/api/skills"

  if ! moltis_login_session "$cookie_file"; then
    SKILLS_API_CACHE_STATUS="failed"
    rm -f "$cookie_file" "$response_file"
    return 1
  fi

  for (( attempt = 1; attempt <= SKILLS_API_ATTEMPTS; attempt += 1 )); do
    http_code="$(
      curl -sS -b "$cookie_file" -c "$cookie_file" \
        "$skills_api_url" \
        -o "$response_file" \
        -w '%{http_code}' \
        --max-time 10 2>/dev/null || echo "000"
    )"
    SKILLS_API_CACHE_HTTP_CODE="${http_code:-000}"

    if [[ "$http_code" == "200" ]] && jq -e . "$response_file" >/dev/null 2>&1; then
      skills_json="$(jq -c . "$response_file")"
      SKILLS_API_CACHE_JSON="$skills_json"
      SKILLS_API_CACHE_STATUS="success"
      SKILLS_API_CACHE_ERROR=""
      rm -f "$cookie_file" "$response_file"
      printf '%s' "$skills_json"
      return 0
    fi

    if (( attempt < SKILLS_API_ATTEMPTS )); then
      sleep "$SKILLS_API_RETRY_DELAY_SECONDS"
    fi
  done

  SKILLS_API_CACHE_STATUS="failed"
  SKILLS_API_CACHE_ERROR="skills_api_unavailable"
  rm -f "$cookie_file" "$response_file"
  return 1
}

skills_json_has_skill_name() {
  local skill_name="$1"
  local skills_json="$2"

  jq -e --arg skill_name "$skill_name" '
    .skills[]? | select(.name == $skill_name)
  ' <<<"$skills_json" >/dev/null 2>&1
}

skills_json_has_any_skill_names() {
  local skills_json="$1"

  jq -e '
    [.skills[]?.name // empty] | length > 0
  ' <<<"$skills_json" >/dev/null 2>&1
}

reply_mentions_any_runtime_skill_name() {
  local reply_text="$1"
  local skills_json="$2"
  local normalized_reply skill_name normalized_skill_name

  normalized_reply="$(normalize_message_text "$reply_text" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized_reply" ]] || return 1

  while IFS= read -r skill_name; do
    [[ -n "$skill_name" ]] || continue
    normalized_skill_name="$(printf '%s' "$skill_name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$normalized_reply" == *"$normalized_skill_name"* ]]; then
      return 0
    fi
  done < <(jq -r '.skills[]?.name // empty' <<<"$skills_json" 2>/dev/null)

  return 1
}

runtime_skill_names_json() {
  local skills_json="$1"

  jq -c '[.skills[]?.name // empty]' <<<"$skills_json" 2>/dev/null
}

fail_skill_semantics_when_api_unavailable() {
  local normalized_message="$1"
  local reply_text="$2"

  VERDICT="failed"
  RUN_STAGE="semantic_review"
  FAILURE_JSON="$(build_failure_json "semantic_skills_api_unavailable" "$RUN_STAGE" "Authoritative skill verification could not authenticate or query live /api/skills" "operator" true)"
  DIAGNOSTIC_JSON="$(
    jq -cn \
      --arg message "$normalized_message" \
      --arg reply_text "$reply_text" \
      --arg error "$SKILLS_API_CACHE_ERROR" \
      --arg login_http_code "$SKILLS_API_CACHE_LOGIN_HTTP_CODE" \
      --arg skills_http_code "$SKILLS_API_CACHE_HTTP_CODE" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {
        semantic_review: {
          message: $message,
          observed_reply: $reply_text,
          failure: "semantic_skills_api_unavailable",
          skills_api_error: (if $error == "" then null else $error end),
          login_http_code: (if $login_http_code == "" then null else $login_http_code end),
          skills_http_code: (if $skills_http_code == "" then null else $skills_http_code end)
        }
      }'
  )"
  RECOMMENDED_ACTION="Restore authenticated live /api/skills verification for Telegram skill checks and rerun authoritative UAT."
}

message_is_codex_update_query() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    *"codex"*|*"кодекс"*)
      return 0
      ;;
  esac

  return 1
}

reply_has_codex_update_false_negative() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    *"путь к skill codex-update"*|*"skill codex-update"*|*"path to skill codex-update"*|*"каталога /home/moltis/.moltis/skills"*|*"directory /home/moltis/.moltis/skills"*)
      ;;
    *)
      return 1
      ;;
  esac

  case "$normalized" in
    *"не существует"*|*"does not exist"*|*"no such file or directory"*|*"тоже нет"*|*"is missing"*|*"не найден"*)
      return 0
      ;;
  esac

  return 1
}

reply_has_codex_update_remote_contract_violation() {
  local normalized
  normalized="$(normalize_message_text "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    *"make codex-update"*|*"запущу канонический runtime"*|*"запускаю канонический runtime"*|*"обновлю вашу локальную установку codex"*|*"обновлю локальную установку codex"*|*"обновлю ваш codex"*|*"смогу обновить ваш codex"*|*"удаленно обновлю ваш codex"*|*"удалённо обновлю ваш codex"*)
      return 0
      ;;
  esac

  return 1
}

reply_has_codex_update_state_memory_false_negative() {
  local normalized
  normalized="$(normalize_message_text "${1:-}")"
  [[ -n "$normalized" ]] || return 1

  case "$normalized" in
    *"в памяти не найдено"*|*"В памяти не найдено"*|*"не найдено в памяти"*|*"Не найдено в памяти"*|*"в памяти записи о последней известной версии не найдено"*|*"В памяти записи о последней известной версии не найдено"*|*"в памяти записи не найдено"*|*"В памяти записи не найдено"*|*"в памяти у меня не зафиксирована"*|*"В памяти у меня не зафиксирована"*|*"в базе у меня не зафиксирована"*|*"В базе у меня не зафиксирована"*|*"в базе не зафиксирована"*|*"В базе не зафиксирована"*|*"не вижу физически доступного содержимого skill"*|*"Не вижу физически доступного содержимого skill"*|*"не вижу физически доступного содержимого скил"*|*"Не вижу физически доступного содержимого скил"*|*"механизм отслеживания обновлений codex cli сейчас не в рабочем состоянии"*|*"Механизм отслеживания обновлений Codex CLI сейчас не в рабочем состоянии"*)
      return 0
      ;;
  esac

  return 1
}

write_report() {
  local debug_available="false"
  if [[ -n "$DEBUG_OUTPUT_PATH" ]]; then
    debug_available="true"
  fi

  local report_json
  report_json="$(
    jq -cn \
      --arg schema_version "remote_uat.v2" \
      --arg run_id "$RUN_ID" \
      --arg target_environment "$TARGET_ENVIRONMENT" \
      --arg trigger_source "$TRIGGER_SOURCE" \
      --arg authoritative_path "$AUTHORITATIVE_PATH" \
      --arg started_at "$STARTED_AT" \
      --arg finished_at "$FINISHED_AT" \
      --arg verdict "$VERDICT" \
      --arg stage "$RUN_STAGE" \
      --arg production_transport_mode "$PRODUCTION_TRANSPORT_MODE" \
      --arg operator_intent "$OPERATOR_INTENT" \
      --arg message "$MESSAGE" \
      --arg transport "$TRANSPORT" \
      --arg artifact_status "$ARTIFACT_STATUS" \
      --arg recommended_action "$RECOMMENDED_ACTION" \
      --argjson duration_ms "$DURATION_MS" \
      --argjson failure "$FAILURE_JSON" \
      --argjson attribution_evidence "$ATTRIBUTION_JSON" \
      --argjson diagnostic_context "$DIAGNOSTIC_JSON" \
      --argjson redactions_applied "$REDACTIONS_JSON" \
      --argjson fallback_assessment "$FALLBACK_JSON" \
      --argjson debug_available "$debug_available" \
      '{
        schema_version: $schema_version,
        run: {
          run_id: $run_id,
          target_environment: $target_environment,
          trigger_source: $trigger_source,
          authoritative_path: $authoritative_path,
          started_at: $started_at,
          finished_at: $finished_at,
          duration_ms: $duration_ms,
          verdict: $verdict,
          stage: $stage,
          production_transport_mode: $production_transport_mode,
          operator_intent: $operator_intent,
          message: $message,
          transport: $transport
        },
        failure: $failure,
        attribution_evidence: $attribution_evidence,
        diagnostic_context: $diagnostic_context,
        fallback_assessment: $fallback_assessment,
        recommended_action: $recommended_action,
        artifact_status: $artifact_status,
        redactions_applied: $redactions_applied,
        debug_bundle: {available: $debug_available}
      }'
  )"

  write_json_file "$OUTPUT_PATH" "$report_json"
  log "Review-safe artifact written to $OUTPUT_PATH"
}

evaluate_authoritative_semantics() {
  if [[ "$VERDICT" != "passed" ]]; then
    return 0
  fi

  local normalized_message reply_text skill_query_skills_json requested_skill_name runtime_skill_names
  normalized_message="$(normalize_message_text "$MESSAGE")"
  reply_text="$(jq -r '.reply_text // empty' <<< "$AUTHORITATIVE_RAW_JSON" 2>/dev/null || true)"
  skill_query_skills_json=""
  requested_skill_name=""
  runtime_skill_names='[]'

  if reply_has_internal_activity "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_activity_leak" "$RUN_STAGE" "Authoritative Telegram reply exposed internal activity/tool-progress instead of a user-facing answer" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{observed_reply:$reply_text, failure:"semantic_activity_leak"}}')"
    RECOMMENDED_ACTION="Reconcile the active Telegram session/runtime so internal activity logs stop reaching the user-facing chat, then rerun the authoritative check."
    return 0
  fi

  if reply_has_internal_planning_leak "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_internal_planning_leak" "$RUN_STAGE" "Authoritative Telegram reply exposed internal tool inventory, capability disclosure, or planning instead of a user-facing answer" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{observed_reply:$reply_text, failure:"semantic_internal_planning_leak"}}')"
    RECOMMENDED_ACTION="Tighten the Telegram-safe lane so internal planning/tool inventory never reaches the user-facing chat, then rerun authoritative UAT."
    return 0
  fi

  local pre_send_activity_leak
  pre_send_activity_leak="$(
    jq -r '.attribution_evidence.last_pre_send_activity.messages[]?.text // empty' <<< "$AUTHORITATIVE_RAW_JSON" 2>/dev/null \
      | while IFS= read -r line; do
          if reply_has_internal_activity "$line"; then
            printf '%s\n' "$line"
            break
          fi
        done
  )"

  if [[ -n "$pre_send_activity_leak" ]]; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_pre_send_activity_leak" "$RUN_STAGE" "Authoritative Telegram chat already contained a recent internal activity/tool-progress leak before the probe send" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg activity_text "$pre_send_activity_leak" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{recent_invalid_incoming:$activity_text, failure:"semantic_pre_send_activity_leak"}}')"
    RECOMMENDED_ACTION="Clear or reconcile the contaminated Telegram chat/session and rerun authoritative UAT only after the last invalid incoming activity message is gone."
    return 0
  fi

  local pre_send_internal_planning_leak
  pre_send_internal_planning_leak="$(
    jq -r '.attribution_evidence.last_pre_send_activity.messages[]?.text // empty' <<< "$AUTHORITATIVE_RAW_JSON" 2>/dev/null \
      | while IFS= read -r line; do
          if reply_has_internal_planning_leak "$line"; then
            printf '%s\n' "$line"
            break
          fi
        done
  )"

  if [[ -n "$pre_send_internal_planning_leak" ]]; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_pre_send_internal_planning_leak" "$RUN_STAGE" "Authoritative Telegram chat already contained a recent internal planning/tool-inventory leak before the probe send" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg planning_text "$pre_send_internal_planning_leak" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{recent_invalid_incoming:$planning_text, failure:"semantic_pre_send_internal_planning_leak"}}')"
    RECOMMENDED_ACTION="Clear or reconcile the contaminated Telegram chat/session and rerun authoritative UAT only after the last invalid incoming planning leak is gone."
    return 0
  fi

  if message_is_skill_visibility_query "$normalized_message" || message_is_skill_create_query "$normalized_message"; then
    if ! skill_query_skills_json="$(fetch_authenticated_skills_json)"; then
      fail_skill_semantics_when_api_unavailable "$normalized_message" "$reply_text"
      return 0
    fi
    runtime_skill_names="$(runtime_skill_names_json "$skill_query_skills_json")"
  fi

  if message_is_skill_visibility_query "$normalized_message" && reply_has_skill_false_negative "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_skill_visibility_false_negative" "$RUN_STAGE" "Authoritative skills reply treated sandbox-invisible filesystem state as proof that skills were absent" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg message "$normalized_message" \
      --argjson runtime_skill_names "$runtime_skill_names" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:$message, observed_reply:$reply_text, runtime_skill_names:$runtime_skill_names, failure:"semantic_skill_visibility_false_negative"}}')"
    RECOMMENDED_ACTION="Reconcile Telegram skill visibility so replies use live runtime /api/skills truth instead of sandbox filesystem guesses, then rerun authoritative UAT."
    return 0
  fi

  if message_is_skill_visibility_query "$normalized_message" \
    && skills_json_has_any_skill_names "$skill_query_skills_json" \
    && ! reply_mentions_any_runtime_skill_name "$reply_text" "$skill_query_skills_json"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_skill_visibility_mismatch" "$RUN_STAGE" "Authoritative skills reply did not mention any live runtime skill names returned by /api/skills" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg message "$normalized_message" \
      --argjson runtime_skill_names "$runtime_skill_names" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:$message, observed_reply:$reply_text, runtime_skill_names:$runtime_skill_names, failure:"semantic_skill_visibility_mismatch"}}')"
    RECOMMENDED_ACTION="Reconcile Telegram skill visibility replies with live /api/skills output and rerun authoritative UAT."
    return 0
  fi

  if message_is_skill_create_query "$normalized_message"; then
    requested_skill_name="$(extract_requested_skill_name "$normalized_message" || true)"

    if reply_has_skill_false_negative "$reply_text"; then
      VERDICT="failed"
      RUN_STAGE="semantic_review"
      FAILURE_JSON="$(build_failure_json "semantic_skill_create_false_negative" "$RUN_STAGE" "Authoritative skill-creation reply fell back to filesystem absence reasoning instead of runtime skill-tool truth" "operator" true)"
      DIAGNOSTIC_JSON="$(jq -cn \
        --arg reply_text "$reply_text" \
        --arg message "$normalized_message" \
        --arg requested_skill_name "$requested_skill_name" \
        --argjson runtime_skill_names "$runtime_skill_names" \
        --argjson base "$DIAGNOSTIC_JSON" \
        '$base + {semantic_review:{message:$message, observed_reply:$reply_text, requested_skill_name:(if $requested_skill_name == "" then null else $requested_skill_name end), runtime_skill_names:$runtime_skill_names, failure:"semantic_skill_create_false_negative"}}')"
      RECOMMENDED_ACTION="Reconcile Telegram skill creation so it relies on dedicated skill tools and live runtime truth instead of filesystem probing, then rerun authoritative UAT."
      return 0
    fi

    if [[ -n "$requested_skill_name" ]] && ! skills_json_has_skill_name "$requested_skill_name" "$skill_query_skills_json"; then
      VERDICT="failed"
      RUN_STAGE="semantic_review"
      FAILURE_JSON="$(build_failure_json "semantic_skill_create_not_persisted" "$RUN_STAGE" "Authoritative skill-creation reply completed but the requested skill is still missing from live /api/skills" "operator" true)"
      DIAGNOSTIC_JSON="$(jq -cn \
        --arg reply_text "$reply_text" \
        --arg message "$normalized_message" \
        --arg requested_skill_name "$requested_skill_name" \
        --argjson runtime_skill_names "$runtime_skill_names" \
        --argjson base "$DIAGNOSTIC_JSON" \
        '$base + {semantic_review:{message:$message, observed_reply:$reply_text, requested_skill_name:$requested_skill_name, runtime_skill_names:$runtime_skill_names, failure:"semantic_skill_create_not_persisted"}}')"
      RECOMMENDED_ACTION="Rerun Telegram skill creation only after the requested skill appears in live /api/skills, then verify the final user-facing reply again."
      return 0
    fi
  fi

  if message_is_codex_update_query "$normalized_message" && reply_has_codex_update_false_negative "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_codex_update_false_negative" "$RUN_STAGE" "Authoritative Codex update reply treated sandbox-invisible host paths as proof that the live skill was missing" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg message "$normalized_message" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:$message, observed_reply:$reply_text, failure:"semantic_codex_update_false_negative"}}')"
    RECOMMENDED_ACTION="Reconcile the Telegram prompt/skill contract so codex-update availability is not disproven via sandbox-invisible host paths, then rerun authoritative UAT."
    return 0
  fi

  if message_is_codex_update_query "$normalized_message" && reply_has_codex_update_remote_contract_violation "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_codex_update_remote_contract_violation" "$RUN_STAGE" "Authoritative Codex update reply promised operator-only runtime execution or local-machine update behavior on a remote user-facing surface" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg message "$normalized_message" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:$message, observed_reply:$reply_text, failure:"semantic_codex_update_remote_contract_violation"}}')"
    RECOMMENDED_ACTION="Reconcile the remote codex-update contract so Telegram stays advisory-only and does not promise operator-only runtime execution, then rerun authoritative UAT."
    return 0
  fi

  if message_is_codex_update_query "$normalized_message" && reply_has_codex_update_state_memory_false_negative "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_codex_update_state_memory_false_negative" "$RUN_STAGE" "Authoritative Codex update reply treated chat memory or generic unavailable text as proof that codex-update runtime state was absent" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg message "$normalized_message" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:$message, observed_reply:$reply_text, failure:"semantic_codex_update_state_memory_false_negative"}}')"
    RECOMMENDED_ACTION="Reconcile codex-update state queries so they read runtime state helper truth instead of memory-search fallbacks, then rerun authoritative UAT."
    return 0
  fi

  if reply_has_host_path_leak "$reply_text"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_host_path_leak" "$RUN_STAGE" "Authoritative Telegram reply exposed internal host filesystem or repo runtime paths to the user-facing chat" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{observed_reply:$reply_text, failure:"semantic_host_path_leak"}}')"
    RECOMMENDED_ACTION="Remove host-path and repo-runtime details from user-facing Telegram replies and rerun authoritative UAT."
    return 0
fi

  if [[ "$normalized_message" != "/status" ]]; then
    return 0
  fi

  local verification_gate_re
  verification_gate_re='verification code|enter the verification code'

  if printf '%s' "$reply_text" | grep -Eiq "$verification_gate_re"; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "verification_gate_reply" "$RUN_STAGE" "Authoritative /status reply hit a verification gate and is not comparable to the allowlisted operator path" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg expected_model "$STATUS_EXPECTED_MODEL" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:"/status", expected_model:$expected_model, observed_reply:$reply_text, failure:"verification_gate_reply"}}')"
    RECOMMENDED_ACTION="Reconcile Telegram allowlist/session state and rerun authoritative /status after removing the verification gate."
    return 0
  fi

  if [[ -n "$STATUS_EXPECTED_MODEL" ]] && [[ "$reply_text" != *"$STATUS_EXPECTED_MODEL"* ]]; then
    VERDICT="failed"
    RUN_STAGE="semantic_review"
    FAILURE_JSON="$(build_failure_json "semantic_status_mismatch" "$RUN_STAGE" "Authoritative /status reply was attributable but did not mention the canonical model contract" "operator" true)"
    DIAGNOSTIC_JSON="$(jq -cn \
      --arg reply_text "$reply_text" \
      --arg expected_model "$STATUS_EXPECTED_MODEL" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {semantic_review:{message:"/status", expected_model:$expected_model, observed_reply:$reply_text, failure:"semantic_status_mismatch"}}')"
    RECOMMENDED_ACTION="Reset or reconcile the active session/runtime and rerun authoritative /status until the reply itself mentions the canonical model."
  fi
}

write_debug_bundle() {
  if [[ -z "$DEBUG_OUTPUT_PATH" ]]; then
    return 0
  fi

  local debug_json
  debug_json="$(
    jq -cn \
      --arg run_id "$RUN_ID" \
      --arg authoritative_stderr "$AUTHORITATIVE_STDERR" \
      --arg fallback_stderr "$FALLBACK_STDERR" \
      --argjson authoritative_raw "$AUTHORITATIVE_RAW_JSON" \
      --argjson fallback_raw "$FALLBACK_RAW_JSON" \
      '{
        run_id: $run_id,
        authoritative_raw: $authoritative_raw,
        authoritative_stderr_tail: (if $authoritative_stderr == "" then null else $authoritative_stderr end),
        fallback_raw: $fallback_raw,
        fallback_stderr_tail: (if $fallback_stderr == "" then null else $fallback_stderr end)
      }'
  )"

  write_json_file "$DEBUG_OUTPUT_PATH" "$debug_json"
  log "Restricted debug bundle written to $DEBUG_OUTPUT_PATH"
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
  write_debug_bundle
  exit "$exit_code"
}

precondition_fail() {
  local summary="$1"
  local stage_name="${2:-$RUN_STAGE}"
  local code="${3:-environment_precondition}"
  local actionability="${4:-operator}"
  local fallback_relevant="${5:-true}"
  FAILURE_JSON="$(build_failure_json "$code" "$stage_name" "$summary" "$actionability" "$fallback_relevant")"
  VERDICT="failed"
  RUN_STAGE="$stage_name"
  RECOMMENDED_ACTION="$(jq -r '.recommended_action // "Restore the missing prerequisites and rerun the authoritative check."' <<< "$AUTHORITATIVE_RAW_JSON" 2>/dev/null || true)"
  if [[ -z "$RECOMMENDED_ACTION" || "$RECOMMENDED_ACTION" == "null" ]]; then
    RECOMMENDED_ACTION="Restore the missing prerequisites and rerun the authoritative check."
  fi
  finish_with_status 2
}

upstream_fail() {
  local summary="$1"
  local stage_name="${2:-$RUN_STAGE}"
  local code="${3:-environment_precondition}"
  local actionability="${4:-engineering}"
  local fallback_relevant="${5:-true}"
  FAILURE_JSON="$(build_failure_json "$code" "$stage_name" "$summary" "$actionability" "$fallback_relevant")"
  VERDICT="failed"
  RUN_STAGE="$stage_name"
  RECOMMENDED_ACTION="Inspect restricted debug evidence and rerun after narrowing the root cause."
  finish_with_status 4
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="${2:-}"
        shift 2
        ;;
      --secondary-diagnostics)
        SECONDARY_DIAGNOSTICS="${2:-}"
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
      --debug-output)
        DEBUG_OUTPUT_PATH="${2:-}"
        shift 2
        ;;
      --target-environment)
        TARGET_ENVIRONMENT="${2:-}"
        shift 2
        ;;
      --operator-intent)
        OPERATOR_INTENT="${2:-}"
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
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 2
  fi

  if [[ -z "${MESSAGE// }" ]]; then
    precondition_fail "--message must be non-empty" "init"
  fi

  if ! [[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_SEC" -le 0 ]]; then
    precondition_fail "--timeout-sec must be a positive integer" "init"
  fi

  case "$MODE" in
    authoritative|telegram_web|synthetic|real_user)
      ;;
    *)
      precondition_fail "--mode must be authoritative, telegram_web, synthetic, or real_user" "init"
      ;;
  esac

  case "$SECONDARY_DIAGNOSTICS" in
    none|mtproto)
      ;;
    *)
      precondition_fail "--secondary-diagnostics must be none or mtproto" "init"
      ;;
  esac
}

init_runtime() {
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  STARTED_AT="$(now_iso)"
  START_MS="$(now_ms)"
  TMP_DIR="$(mktemp -d)"
  trap 'cleanup_runtime' EXIT
}

cleanup_runtime() {
  if [[ -n "$LOCK_FD" ]]; then
    eval "exec ${LOCK_FD}>&-"
    LOCK_FD=""
  fi
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

acquire_shared_target_lock() {
  if [[ "$SERIALIZE_SHARED_TARGET" != "true" ]]; then
    return 0
  fi

  if command -v flock >/dev/null 2>&1; then
    exec {LOCK_FD}>"$SHARED_TARGET_LOCK"
    if ! flock -n "$LOCK_FD"; then
      FAILURE_JSON="$(build_failure_json "environment_precondition" "init" "Another authoritative remote UAT run is already in progress" "operator" false)"
      DIAGNOSTIC_JSON="$(jq -cn --arg lock_file "$SHARED_TARGET_LOCK" '{lock_file:$lock_file, serialization:"flock"}')"
      RECOMMENDED_ACTION="Wait for the current authoritative run to finish and rerun the check."
      VERDICT="failed"
      RUN_STAGE="init"
      finish_with_status 2
    fi
    return 0
  fi

  local lock_dir="${SHARED_TARGET_LOCK}.d"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    FAILURE_JSON="$(build_failure_json "environment_precondition" "init" "Another authoritative remote UAT run is already in progress" "operator" false)"
    DIAGNOSTIC_JSON="$(jq -cn --arg lock_dir "$lock_dir" '{lock_dir:$lock_dir, serialization:"mkdir"}')"
    RECOMMENDED_ACTION="Wait for the current authoritative run to finish and rerun the check."
    VERDICT="failed"
    RUN_STAGE="init"
    finish_with_status 2
  fi
  trap 'rmdir "'"$lock_dir"'" 2>/dev/null || true; cleanup_runtime' EXIT
}

capture_helper_json() {
  local helper_output_file="$1"
  local helper_error_file="$2"
  local raw_var_name="$3"
  local stderr_var_name="$4"

  if jq -e . "$helper_output_file" >/dev/null 2>&1; then
    printf -v "$raw_var_name" '%s' "$(jq -c . "$helper_output_file")"
  else
    printf -v "$raw_var_name" '%s' 'null'
  fi

  printf -v "$stderr_var_name" '%s' "$(tail_sanitized "$helper_error_file")"
}

normalize_from_authoritative_helper() {
  local helper_json="$1"
  local helper_context
  helper_context="$(jq -c '.diagnostic_context // {}' <<< "$helper_json")"
  helper_context="$(sanitize_json_for_operator "$helper_context")"
  RUN_STAGE="$(jq -r '.stage // "unknown"' <<< "$helper_json")"
  ATTRIBUTION_JSON="$(jq -c '.attribution_evidence // {attribution_confidence:"unknown"}' <<< "$helper_json")"
  DIAGNOSTIC_JSON="$(
    jq -cn \
      --arg target "$AUTHORITATIVE_TARGET" \
      --arg state_file "$(basename "$AUTHORITATIVE_STATE")" \
      --argjson helper_context "$helper_context" \
      --argjson helper "$helper_json" \
      '$helper_context + {
        target: $target,
        state_file: $state_file
      } + (if $helper.hint then {hint:$helper.hint} else {} end)'
  )"
  RECOMMENDED_ACTION="$(jq -r '.recommended_action // empty' <<< "$helper_json")"
  if [[ -z "$RECOMMENDED_ACTION" ]]; then
    RECOMMENDED_ACTION="Inspect the authoritative artifact and rerun after narrowing the root cause."
  fi

  if [[ "$(jq -r '.ok' <<< "$helper_json")" == "true" ]]; then
    VERDICT="passed"
    FAILURE_JSON='null'
    return 0
  fi

  VERDICT="failed"
  if jq -e '.failure | type == "object"' <<< "$helper_json" >/dev/null 2>&1; then
    FAILURE_JSON="$(jq -c '.failure' <<< "$helper_json")"
  else
    FAILURE_JSON="$(build_failure_json "environment_precondition" "$RUN_STAGE" "Authoritative Telegram Web probe failed without a normalized failure object" "engineering" true)"
  fi
}

run_authoritative_telegram_web() {
  acquire_shared_target_lock
  RUN_STAGE="login"
  AUTHORITATIVE_PATH="telegram_web"
  TRANSPORT="telegram_web_user"

  if ! command -v node >/dev/null 2>&1; then
    DIAGNOSTIC_JSON='{"reason":"node_missing"}'
    precondition_fail "node is required for Telegram Web authoritative mode" "login"
  fi

  local helper_script="$SCRIPT_DIR/telegram-web-user-monitor.sh"
  if [[ ! -f "$helper_script" ]]; then
    DIAGNOSTIC_JSON='{"reason":"telegram_web_monitor_missing"}'
    upstream_fail "Telegram Web monitor script is missing" "login"
  fi

  local helper_output_file="$TMP_DIR/telegram-web-result.json"
  local helper_error_file="$TMP_DIR/telegram-web-error.log"
  local helper_debug="false"
  if [[ -n "$DEBUG_OUTPUT_PATH" || "$VERBOSE" == "true" ]]; then
    helper_debug="true"
  fi

  set +e
  TELEGRAM_WEB_TARGET="$AUTHORITATIVE_TARGET" \
  TELEGRAM_WEB_STATE="$AUTHORITATIVE_STATE" \
  TELEGRAM_WEB_MESSAGE="$MESSAGE" \
  TELEGRAM_WEB_TIMEOUT_SECONDS="$TIMEOUT_SEC" \
  TELEGRAM_WEB_DEBUG="$helper_debug" \
  "$helper_script" >"$helper_output_file" 2>"$helper_error_file"
  local helper_exit=$?
  set -e

  capture_helper_json "$helper_output_file" "$helper_error_file" AUTHORITATIVE_RAW_JSON AUTHORITATIVE_STDERR

  if ! jq -e . "$helper_output_file" >/dev/null 2>&1; then
    DIAGNOSTIC_JSON="$(jq -cn --arg stderr "$AUTHORITATIVE_STDERR" '{helper_stderr:$stderr, helper_exit_code:"invalid_json"}')"
    upstream_fail "Telegram Web authoritative probe returned invalid JSON" "login" "environment_precondition"
  fi

  normalize_from_authoritative_helper "$AUTHORITATIVE_RAW_JSON"

  DIAGNOSTIC_JSON="$(
    jq -cn \
      --arg transport "$TRANSPORT" \
      --argjson helper_exit "$helper_exit" \
      --argjson base "$DIAGNOSTIC_JSON" \
      '$base + {transport:$transport, helper_exit_code:$helper_exit}'
  )"
}

run_synthetic_compat() {
  AUTHORITATIVE_PATH="synthetic_api"
  TRANSPORT="moltis_api_chat"
  RUN_STAGE="auth"

  if ! command -v curl >/dev/null 2>&1; then
    DIAGNOSTIC_JSON='{"reason":"curl_missing"}'
    precondition_fail "curl is required for synthetic mode" "auth"
  fi

  local password
  password="${!MOLTIS_PASSWORD_ENV:-}"
  if [[ -z "$password" ]]; then
    DIAGNOSTIC_JSON="$(jq -cn --arg env_name "$MOLTIS_PASSWORD_ENV" '{missing_env:$env_name}')"
    precondition_fail "Environment variable for Moltis password is empty" "auth"
  fi

  local cookie_file="$TMP_DIR/moltis-cookie.txt"
  local login_response_file="$TMP_DIR/login-response.json"
  local send_response_file="$TMP_DIR/send-response.json"
  local poll_response_file="$TMP_DIR/poll-response.json"

  local login_code
  login_code="$(curl -sS -c "$cookie_file" -b "$cookie_file" \
    -X POST "$MOLTIS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg pw "$password" '{password:$pw}')" \
    -o "$login_response_file" \
    -w "%{http_code}" || true)"
  login_code="${login_code:-000}"

  if [[ "$login_code" != "200" && "$login_code" != "302" ]]; then
    DIAGNOSTIC_JSON="$(jq -cn --arg login_http_code "$login_code" '{login_http_code:$login_http_code}')"
    upstream_fail "Synthetic Moltis authentication failed" "auth" "environment_precondition"
  fi

  RUN_STAGE="send"
  local send_code
  send_code="$(curl -sS -b "$cookie_file" \
    -X POST "$MOLTIS_URL/api/v1/chat" \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg msg "$MESSAGE" '{message:$msg}')" \
    -o "$send_response_file" \
    -w "%{http_code}" || true)"
  send_code="${send_code:-000}"

  if [[ "$send_code" != "200" && "$send_code" != "202" ]]; then
    FAILURE_JSON="$(build_failure_json "send_failure" "send" "Synthetic chat send failed" "engineering" true)"
    DIAGNOSTIC_JSON="$(jq -cn --arg login_http_code "$login_code" --arg send_http_code "$send_code" '{login_http_code:$login_http_code, send_http_code:$send_http_code}')"
    RECOMMENDED_ACTION="Inspect the synthetic API chat path and rerun after fixing the upstream error."
    VERDICT="failed"
    finish_with_status 4
  fi

  RUN_STAGE="wait_reply"
  local observed=""
  local attempt=0
  local elapsed=0
  while [[ $elapsed -lt $TIMEOUT_SEC && -z "$observed" ]]; do
    attempt=$((attempt + 1))
    sleep 1
    local poll_code
    poll_code="$(curl -sS -b "$cookie_file" -X GET "$MOLTIS_URL/api/v1/chat" -o "$poll_response_file" -w "%{http_code}" || true)"
    poll_code="${poll_code:-000}"
    if [[ "$poll_code" == "200" || "$poll_code" == "202" ]]; then
      local poll_body
      poll_body="$(cat "$poll_response_file" 2>/dev/null || true)"
      if [[ -n "$(printf '%s' "$poll_body" | tr -d '[:space:]')" ]]; then
        observed="$poll_body"
      fi
    fi
    elapsed=$((elapsed + 1))
  done

  ATTRIBUTION_JSON='{"attribution_confidence":"n/a"}'
  if [[ -z "$observed" ]]; then
    FAILURE_JSON="$(build_failure_json "bot_no_response" "wait_reply" "Synthetic path did not observe a response before timeout" "engineering" true)"
    DIAGNOSTIC_JSON="$(jq -cn --arg login_http_code "$login_code" --arg send_http_code "$send_code" --argjson poll_attempts "$attempt" '{login_http_code:$login_http_code, send_http_code:$send_http_code, poll_attempts:$poll_attempts}')"
    RECOMMENDED_ACTION="Inspect the synthetic API polling path and rerun after restoring the response contract."
    VERDICT="failed"
    finish_with_status 3
  fi

  DIAGNOSTIC_JSON="$(jq -cn --arg observed_response "$observed" --argjson poll_attempts "$attempt" '{observed_response:$observed_response, poll_attempts:$poll_attempts}')"
  RECOMMENDED_ACTION="Synthetic compatibility path passed."
  VERDICT="passed"
  FAILURE_JSON='null'
}

run_real_user_compat() {
  AUTHORITATIVE_PATH="telegram_mtproto"
  TRANSPORT="telegram_mtproto_real_user"
  RUN_STAGE="send"

  if ! command -v python3 >/dev/null 2>&1; then
    DIAGNOSTIC_JSON='{"reason":"python3_missing"}'
    precondition_fail "python3 is required for real_user mode" "send"
  fi

  local helper_script="$SCRIPT_DIR/telegram-real-user-e2e.py"
  if [[ ! -f "$helper_script" ]]; then
    DIAGNOSTIC_JSON='{"reason":"telegram_real_user_helper_missing"}'
    upstream_fail "real_user helper script is missing" "send"
  fi

  local helper_output_file="$TMP_DIR/real-user-result.json"
  local helper_error_file="$TMP_DIR/real-user-error.log"
  local bot_username="${TELEGRAM_TEST_BOT_USERNAME:-@moltinger_bot}"
  local helper_args=(
    "$helper_script"
    --bot-username "$bot_username"
    --message "$MESSAGE"
    --timeout-sec "$TIMEOUT_SEC"
  )
  if [[ "$VERBOSE" == "true" ]]; then
    helper_args+=(--verbose)
  fi

  set +e
  python3 "${helper_args[@]}" >"$helper_output_file" 2>"$helper_error_file"
  local helper_exit=$?
  set -e

  capture_helper_json "$helper_output_file" "$helper_error_file" AUTHORITATIVE_RAW_JSON AUTHORITATIVE_STDERR

  if ! jq -e . "$helper_output_file" >/dev/null 2>&1; then
    DIAGNOSTIC_JSON="$(jq -cn --arg stderr "$AUTHORITATIVE_STDERR" '{helper_stderr:$stderr}')"
    upstream_fail "real_user helper returned invalid JSON" "send"
  fi

  RUN_STAGE="$(jq -r '.context.stage // "wait_reply"' "$helper_output_file")"
  DIAGNOSTIC_JSON="$(jq -c '.context // {}' "$helper_output_file")"
  ATTRIBUTION_JSON='{"attribution_confidence":"n/a"}'

  local helper_status
  helper_status="$(jq -r '.status // "upstream_failed"' "$helper_output_file")"
  local error_message
  error_message="$(jq -r '.error_message // empty' "$helper_output_file")"
  local observed_response
  observed_response="$(jq -r '.observed_response // empty' "$helper_output_file")"
  DIAGNOSTIC_JSON="$(sanitize_json_for_operator "$DIAGNOSTIC_JSON")"

  case "$helper_status" in
    completed)
      VERDICT="passed"
      FAILURE_JSON='null'
      DIAGNOSTIC_JSON="$(jq -cn --arg observed_response "$observed_response" --argjson helper_exit "$helper_exit" --argjson context "$DIAGNOSTIC_JSON" '$context + {observed_response:$observed_response, helper_exit_code:$helper_exit}')"
      RECOMMENDED_ACTION="MTProto compatibility path passed."
      ;;
    timeout)
      VERDICT="failed"
      FAILURE_JSON="$(build_failure_json "bot_no_response" "wait_reply" "MTProto helper timed out waiting for a reply" "operator" true)"
      RECOMMENDED_ACTION="Inspect bot response health and rerun after restoring reply delivery."
      finish_with_status 3
      ;;
    precondition_failed)
      VERDICT="failed"
      FAILURE_JSON="$(build_failure_json "environment_precondition" "send" "${error_message:-MTProto prerequisites are missing}" "operator" true)"
      RECOMMENDED_ACTION="Restore MTProto prerequisites and rerun if secondary diagnostics are still needed."
      finish_with_status 2
      ;;
    *)
      VERDICT="failed"
      FAILURE_JSON="$(build_failure_json "environment_precondition" "send" "${error_message:-Unexpected MTProto helper failure}" "engineering" true)"
      RECOMMENDED_ACTION="Inspect restricted debug evidence and rerun after narrowing the MTProto failure."
      finish_with_status 4
      ;;
  esac
}

evaluate_secondary_mtproto() {
  if [[ "$SECONDARY_DIAGNOSTICS" != "mtproto" ]]; then
    FALLBACK_JSON='{"requested":false,"path_used":null,"prerequisites_present":null,"outcome":"not_requested","decision_note":"Secondary diagnostics not requested."}'
    return 0
  fi

  local prerequisites_present="true"
  local missing=()
  local key
  for key in TELEGRAM_TEST_API_ID TELEGRAM_TEST_API_HASH TELEGRAM_TEST_SESSION; do
    if [[ -z "${!key:-}" ]]; then
      prerequisites_present="false"
      missing+=("$key")
    fi
  done

  if [[ "$prerequisites_present" != "true" ]]; then
    local missing_json
    missing_json="$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)"
    FALLBACK_JSON="$(jq -cn \
      --argjson missing "$missing_json" \
      '{
        requested: true,
        path_used: "mtproto",
        prerequisites_present: false,
        outcome: "unavailable",
        decision_note: "MTProto fallback prerequisites are absent on this target.",
        missing_prerequisites: $missing
      }')"
    return 0
  fi

  local helper_script="$SCRIPT_DIR/telegram-real-user-e2e.py"
  local helper_output_file="$TMP_DIR/fallback-real-user-result.json"
  local helper_error_file="$TMP_DIR/fallback-real-user-error.log"
  local bot_username="${TELEGRAM_TEST_BOT_USERNAME:-@moltinger_bot}"
  local helper_args=(
    "$helper_script"
    --bot-username "$bot_username"
    --message "$MESSAGE"
    --timeout-sec "$TIMEOUT_SEC"
  )
  if [[ "$VERBOSE" == "true" ]]; then
    helper_args+=(--verbose)
  fi

  set +e
  python3 "${helper_args[@]}" >"$helper_output_file" 2>"$helper_error_file"
  local helper_exit=$?
  set -e

  capture_helper_json "$helper_output_file" "$helper_error_file" FALLBACK_RAW_JSON FALLBACK_STDERR

  if ! jq -e . "$helper_output_file" >/dev/null 2>&1; then
    FALLBACK_JSON="$(jq -cn \
      --arg stderr "$FALLBACK_STDERR" \
      '{
        requested: true,
        path_used: "mtproto",
        prerequisites_present: true,
        outcome: "failed",
        decision_note: "MTProto fallback returned invalid JSON.",
        helper_stderr: (if $stderr == "" then null else $stderr end)
      }')"
    return 0
  fi

  FALLBACK_JSON="$(
    jq -cn \
      --argjson helper "$(jq -c . "$helper_output_file")" \
      --argjson helper_exit "$helper_exit" \
      '{
        requested: true,
        path_used: "mtproto",
        prerequisites_present: true,
        outcome: ($helper.status // "unknown"),
        comparable_to_authoritative:
          (if (($helper.status // "") == "completed") and (($helper.observed_response // "") | test("verification code|enter the verification code"; "i"))
           then false
           else true
           end),
        observed_verification_gate:
          (if (($helper.observed_response // "") | test("verification code|enter the verification code"; "i"))
           then true
           else false
           end),
        decision_note:
          (if (($helper.status // "") == "completed") and (($helper.observed_response // "") | test("verification code|enter the verification code"; "i"))
           then "Secondary MTProto diagnostics reached the bot but hit the verification-code gate. This usually means TELEGRAM_TEST_SESSION belongs to a different or non-allowlisted test user, so the result is not directly comparable to the authoritative Telegram Web account."
           elif ($helper.status // "") == "completed"
           then "Secondary MTProto diagnostics succeeded; Telegram Web remains authoritative but fallback may help isolate UI-only issues."
           elif ($helper.status // "") == "timeout"
           then "Secondary MTProto diagnostics also missed a reply; investigate deployed bot/runtime before enabling fallback."
           elif ($helper.status // "") == "precondition_failed"
           then "Secondary MTProto diagnostics could not run because prerequisites were incomplete."
           else "Secondary MTProto diagnostics failed unexpectedly; keep Telegram Web authoritative and inspect the fallback helper."
           end),
        helper_exit_code: $helper_exit,
        helper_status: ($helper.status // null),
        helper_error_code: ($helper.error_code // null),
        helper_error_message: ($helper.error_message // null)
      }'
  )"
}

main() {
  parse_args "$@"
  init_runtime
  validate_args

  case "$MODE" in
    authoritative|telegram_web)
      run_authoritative_telegram_web
      evaluate_authoritative_semantics
      if [[ "$VERDICT" == "failed" ]]; then
        evaluate_secondary_mtproto
        finish_with_status 3
      fi
      evaluate_secondary_mtproto
      finish_with_status 0
      ;;
    synthetic)
      run_synthetic_compat
      finish_with_status 0
      ;;
    real_user)
      run_real_user_compat
      finish_with_status 0
      ;;
  esac
}

main "$@"
