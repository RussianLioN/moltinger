#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_RELEASE_URL="https://developers.openai.com/codex/changelog"
DEFAULT_ISSUE_SIGNALS_URL="https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"
DEFAULT_STATE_FILE="${PROJECT_ROOT}/.tmp/current/codex-cli-upstream-watcher-state.json"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"
DEFAULT_MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/codex-cli-update-monitor.sh"
DEFAULT_ADVISOR_SCRIPT="${PROJECT_ROOT}/scripts/codex-cli-update-advisor.sh"
DEFAULT_CONSENT_STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-telegram-consent-store.sh"
DEFAULT_CONSENT_STORE_DIR="${PROJECT_ROOT}/.tmp/current/codex-telegram-consent-store"

MODE="${CODEX_UPSTREAM_WATCHER_MODE:-manual}"
STATE_FILE="${CODEX_UPSTREAM_WATCHER_STATE_FILE:-${DEFAULT_STATE_FILE}}"
JSON_OUT=""
SUMMARY_OUT=""
ADVISORY_EVENT_OUT="${CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT:-}"
STDOUT_FORMAT="summary"

RELEASE_FILE="${CODEX_UPSTREAM_WATCHER_RELEASE_FILE:-}"
RELEASE_URL="${CODEX_UPSTREAM_WATCHER_RELEASE_URL:-${DEFAULT_RELEASE_URL}}"
INCLUDE_ISSUE_SIGNALS=false
ISSUE_SIGNALS_FILE="${CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_FILE:-}"
ISSUE_SIGNALS_URL="${CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_URL:-${DEFAULT_ISSUE_SIGNALS_URL}}"
MAX_RELEASES="${CODEX_UPSTREAM_WATCHER_MAX_RELEASES:-3}"

DELIVERY_MODE="${CODEX_UPSTREAM_WATCHER_DELIVERY_MODE:-immediate}"
DIGEST_WINDOW_HOURS="${CODEX_UPSTREAM_WATCHER_DIGEST_WINDOW_HOURS:-24}"
DIGEST_MAX_ITEMS="${CODEX_UPSTREAM_WATCHER_DIGEST_MAX_ITEMS:-3}"

ADVISOR_BRIDGE_ENABLED="${CODEX_UPSTREAM_WATCHER_ADVISOR_BRIDGE_ENABLED:-true}"
MONITOR_SCRIPT="${CODEX_UPSTREAM_WATCHER_MONITOR_SCRIPT:-${DEFAULT_MONITOR_SCRIPT}}"
ADVISOR_SCRIPT="${CODEX_UPSTREAM_WATCHER_ADVISOR_SCRIPT:-${DEFAULT_ADVISOR_SCRIPT}}"

TELEGRAM_ENABLED="${CODEX_UPSTREAM_WATCHER_TELEGRAM_ENABLED:-false}"
TELEGRAM_CHAT_ID="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENV_FILE="${CODEX_UPSTREAM_WATCHER_TELEGRAM_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
TELEGRAM_SILENT=false
TELEGRAM_SEND_SCRIPT="${CODEX_UPSTREAM_WATCHER_TELEGRAM_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"
TELEGRAM_CONSENT_ENABLED="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ENABLED:-true}"
TELEGRAM_CONSENT_WINDOW_HOURS="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_WINDOW_HOURS:-72}"
TELEGRAM_CONSENT_ROUTER_ENABLED="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ROUTER_ENABLED:-true}"
TELEGRAM_CONSENT_STORE_SCRIPT="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_STORE_SCRIPT:-${DEFAULT_CONSENT_STORE_SCRIPT}}"
TELEGRAM_CONSENT_STORE_DIR="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_STORE_DIR:-${DEFAULT_CONSENT_STORE_DIR}}"
TELEGRAM_UPDATES_FILE="${CODEX_UPSTREAM_WATCHER_TELEGRAM_UPDATES_FILE:-}"
TELEGRAM_ALLOW_GETUPDATES="${CODEX_UPSTREAM_WATCHER_TELEGRAM_ALLOW_GETUPDATES:-false}"
TELEGRAM_COMMAND_HOOK_READY="${CODEX_UPSTREAM_WATCHER_TELEGRAM_COMMAND_HOOK_READY:-false}"

TEMP_DIR=""
REPORT_PATH=""
SUMMARY_PATH=""
FETCH_SOURCE_ID=""

declare -a WARNINGS=()

usage() {
    cat <<'USAGE'
Usage: codex-cli-upstream-watcher.sh [options]

Проверяет официальный upstream Codex CLI, присваивает уровни важности,
умеет собирать дайджест, готовит bridge к advisor-слою проекта и при
необходимости готовит нормализованный advisory event для Moltis-native
Telegram flow.

Options:
  --mode MODE                    Режим: manual|scheduler (по умолчанию: manual)
  --state-file PATH              Файл состояния watcher-а
  --json-out PATH                Куда записать JSON-отчёт
  --summary-out PATH             Куда записать человекочитаемый summary
  --advisory-event-out PATH      Куда записать нормализованный advisory event для Moltis
  --stdout MODE                  Вывод в stdout: summary|json|none (по умолчанию: summary)
  --release-file PATH            Читать основной changelog из локального файла
  --release-url URL              Читать основной changelog по URL
  --max-releases N               Сколько последних релизов анализировать
  --include-issue-signals        Подключить advisory issue signals
  --issue-signals-file PATH      Читать issue signals из локального JSON-файла
  --issue-signals-url URL        Читать issue signals по URL
  --delivery-mode MODE           Режим доставки: immediate|digest
  --digest-window-hours N        Через сколько часов отправлять накопленный дайджест
  --digest-max-items N           Сколько новых событий накапливать до принудительной отправки дайджеста
  --advisor-bridge-disabled      Не строить практические рекомендации через advisor bridge
  --telegram-enabled             Включить Telegram-доставку для scheduler-режима
  --telegram-chat-id ID          Явно указать Telegram chat id
  --telegram-env-file PATH       Env-файл для Telegram sender-а и чтения ответов
  --telegram-silent              Отправлять Telegram тихо, без звука
  --telegram-send-script PATH    Путь к telegram sender script
  --telegram-consent-disabled    Не спрашивать о практических рекомендациях в Telegram
  --telegram-consent-window-hours N Сколько часов ждать ответ пользователя в Telegram
  --telegram-consent-router-disabled Выключить authoritative consent router и отправлять только one-way alert
  --telegram-consent-store-script PATH Путь к consent store helper
  --telegram-consent-store-dir PATH Директория shared consent store
  --telegram-updates-file PATH   Читать ответы Telegram из локального JSON-файла
  --telegram-allow-getupdates    Разрешить live-чтение ответов через Bot API getUpdates
  -h, --help                     Показать эту справку

Environment overrides:
  CODEX_UPSTREAM_WATCHER_MODE
  CODEX_UPSTREAM_WATCHER_STATE_FILE
  CODEX_UPSTREAM_WATCHER_ADVISORY_EVENT_OUT
  CODEX_UPSTREAM_WATCHER_RELEASE_FILE
  CODEX_UPSTREAM_WATCHER_RELEASE_URL
  CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_FILE
  CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_URL
  CODEX_UPSTREAM_WATCHER_MAX_RELEASES
  CODEX_UPSTREAM_WATCHER_DELIVERY_MODE
  CODEX_UPSTREAM_WATCHER_DIGEST_WINDOW_HOURS
  CODEX_UPSTREAM_WATCHER_DIGEST_MAX_ITEMS
  CODEX_UPSTREAM_WATCHER_ADVISOR_BRIDGE_ENABLED
  CODEX_UPSTREAM_WATCHER_TELEGRAM_ENABLED
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID
  CODEX_UPSTREAM_WATCHER_TELEGRAM_ENV_FILE
  CODEX_UPSTREAM_WATCHER_TELEGRAM_SEND_SCRIPT
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ENABLED
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_WINDOW_HOURS
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ROUTER_ENABLED
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_STORE_SCRIPT
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_STORE_DIR
  CODEX_UPSTREAM_WATCHER_TELEGRAM_UPDATES_FILE
  CODEX_UPSTREAM_WATCHER_TELEGRAM_ALLOW_GETUPDATES
  CODEX_UPSTREAM_WATCHER_TELEGRAM_COMMAND_HOOK_READY
USAGE
}

cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

add_warning() {
    WARNINGS+=("$1")
}

require_command() {
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        printf 'Не найдена обязательная зависимость: %s\n' "$name" >&2
        exit 2
    fi
}

ensure_parent_dir() {
    mkdir -p "$(dirname "$1")"
}

normalize_bool() {
    case "${1:-}" in
        true|1|yes|on)
            printf 'true\n'
            ;;
        false|0|no|off|'')
            printf 'false\n'
            ;;
        *)
            printf 'Некорректное boolean-значение: %s\n' "$1" >&2
            exit 2
            ;;
    esac
}

strip_wrapping_quotes() {
    local value="${1:-}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
    fi
    if [[ "$value" == \'*\' && "$value" == *\' ]]; then
        value="${value#\'}"
        value="${value%\'}"
    fi
    printf '%s\n' "$value"
}

read_env_value() {
    local env_file="$1"
    local key="$2"
    local value=""

    [[ -f "$env_file" ]] || return 1
    value="$(sed -n "s/^${key}=//p" "$env_file" | head -n 1)"
    [[ -n "$value" ]] || return 1
    strip_wrapping_quotes "$value"
}

resolve_telegram_chat_id() {
    local env_file="$1"
    local configured first_user

    if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
        printf '%s\n' "$TELEGRAM_CHAT_ID"
        return 0
    fi

    if [[ -n "$env_file" && -f "$env_file" ]]; then
        configured="$(read_env_value "$env_file" "CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID" || true)"
        if [[ -n "$configured" ]]; then
            printf '%s\n' "$configured"
            return 0
        fi

        configured="$(read_env_value "$env_file" "TELEGRAM_ALLOWED_USERS" || true)"
        if [[ -n "$configured" ]]; then
            configured="${configured//,/ }"
            for first_user in $configured; do
                if [[ -n "$first_user" ]]; then
                    printf '%s\n' "$first_user"
                    return 0
                fi
            done
        fi
    fi

    return 1
}

resolve_telegram_token() {
    local env_file="$1"
    local configured=""

    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        printf '%s\n' "${TELEGRAM_BOT_TOKEN}"
        return 0
    fi

    if [[ -n "$env_file" && -f "$env_file" ]]; then
        configured="$(read_env_value "$env_file" "TELEGRAM_BOT_TOKEN" || true)"
        if [[ -n "$configured" ]]; then
            printf '%s\n' "$configured"
            return 0
        fi
    fi

    return 1
}

fetch_source() {
    local kind="$1"
    local file_arg="$2"
    local url_arg="$3"
    local default_url="$4"
    local target="$5"

    if [[ -n "$file_arg" ]]; then
        FETCH_SOURCE_ID="file:${file_arg}"
        if [[ -f "$file_arg" ]]; then
            cp "$file_arg" "$target"
            return 0
        fi
        add_warning "Не найден файл источника (${kind}): ${file_arg}"
        return 1
    fi

    local source_url="${url_arg:-$default_url}"
    if [[ -z "$source_url" ]]; then
        add_warning "Для источника ${kind} не настроен URL"
        return 1
    fi

    FETCH_SOURCE_ID="url:${source_url}"
    require_command curl
    if curl -fsSL --connect-timeout 20 --max-time 60 "$source_url" -o "$target" 2>/dev/null; then
        return 0
    fi

    add_warning "Не удалось получить источник ${kind}: ${source_url}"
    return 1
}

state_has_pending_consent() {
    local state_file="$1"
    [[ -f "$state_file" ]] || return 1
    jq -e '.pending_consent.status? == "pending" or .pending_consent.status? == "accepted"' "$state_file" >/dev/null 2>&1
}

state_next_update_offset() {
    local state_file="$1"
    if [[ ! -f "$state_file" ]]; then
        printf '0\n'
        return 0
    fi
    jq -r '((.last_update_id // 0) | tonumber) + 1' "$state_file" 2>/dev/null || printf '0\n'
}

fetch_telegram_updates() {
    local target="$1"
    local offset="$2"
    local token="" webhook_info="" webhook_url=""

    if [[ -n "$TELEGRAM_UPDATES_FILE" ]]; then
        if [[ -f "$TELEGRAM_UPDATES_FILE" ]]; then
            cp "$TELEGRAM_UPDATES_FILE" "$target"
            return 0
        fi
        add_warning "Не найден файл с ответами Telegram: ${TELEGRAM_UPDATES_FILE}"
        return 1
    fi

    if [[ "$TELEGRAM_ALLOW_GETUPDATES" != "true" ]]; then
        add_warning "Live-чтение ответов Telegram отключено по умолчанию; включайте его только в безопасном режиме через --telegram-allow-getupdates."
        return 1
    fi

    token="$(resolve_telegram_token "$TELEGRAM_ENV_FILE" || true)"
    if [[ -z "$token" ]]; then
        add_warning "Не удалось определить TELEGRAM_BOT_TOKEN для чтения ответов пользователя."
        return 1
    fi

    require_command curl
    require_command jq

    webhook_info="$(curl -fsSL --connect-timeout 20 --max-time 60 \
        "https://api.telegram.org/bot${token}/getWebhookInfo" 2>/dev/null || true)"
    if [[ -z "$webhook_info" ]] || ! jq -e '.ok == true' >/dev/null 2>&1 <<<"$webhook_info"; then
        add_warning "Не удалось безопасно проверить режим Telegram webhook перед чтением ответов пользователя."
        return 1
    fi

    webhook_url="$(jq -r '.result.url // ""' <<<"$webhook_info")"
    if [[ -n "$webhook_url" ]]; then
        add_warning "У бота активен webhook; watcher не использует getUpdates, чтобы не ломать текущий режим доставки."
        return 1
    fi

    if curl -fsSL --connect-timeout 20 --max-time 60 \
        -G \
        --data-urlencode "offset=${offset}" \
        --data-urlencode "timeout=0" \
        "https://api.telegram.org/bot${token}/getUpdates" \
        -o "$target" 2>/dev/null; then
        return 0
    fi

    add_warning "Не удалось получить ответы пользователя через Telegram Bot API."
    return 1
}

build_advisor_bridge() {
    local release_source_path="$1"
    local issue_source_path="$2"
    local monitor_report advisor_report bridge_dir

    if [[ "$ADVISOR_BRIDGE_ENABLED" != "true" ]]; then
        return 1
    fi

    if [[ ! -f "$release_source_path" ]]; then
        add_warning "Advisor bridge пропущен: основной upstream-источник недоступен."
        return 1
    fi

    if [[ ! -f "$MONITOR_SCRIPT" || ! -f "$ADVISOR_SCRIPT" ]]; then
        add_warning "Advisor bridge пропущен: не найдены monitor/advisor scripts."
        return 1
    fi

    bridge_dir="${TEMP_DIR}/advisor-bridge"
    mkdir -p "$bridge_dir"
    monitor_report="${bridge_dir}/monitor-report.json"
    advisor_report="${bridge_dir}/advisor-report.json"

    local -a monitor_cmd=(
        bash "$MONITOR_SCRIPT"
        --json-out "$monitor_report"
        --summary-out "${bridge_dir}/monitor-summary.md"
        --stdout none
        --issue-action none
        --local-version 0.0.0
        --release-file "$release_source_path"
    )

    if [[ "$INCLUDE_ISSUE_SIGNALS" == "true" && -f "$issue_source_path" ]]; then
        monitor_cmd+=(--include-issue-signals --issue-signals-file "$issue_source_path")
    fi

    if ! "${monitor_cmd[@]}" >/dev/null 2>&1; then
        add_warning "Advisor bridge пропущен: не удалось построить промежуточный monitor report."
        return 1
    fi

    local -a advisor_cmd=(
        bash "$ADVISOR_SCRIPT"
        --monitor-report "$monitor_report"
        --json-out "$advisor_report"
        --summary-out "${bridge_dir}/advisor-summary.md"
        --stdout none
        --issue-action none
    )

    if ! "${advisor_cmd[@]}" >/dev/null 2>&1; then
        add_warning "Advisor bridge пропущен: не удалось построить advisor report."
        return 1
    fi

    printf '%s\n' "$advisor_report"
}

render_summary() {
    jq -r '
      def ru_status(value):
        if value == "new" then "новое"
        elif value == "known" then "уже известно"
        elif value == "investigate" then "нужно проверить"
        elif value == "unavailable" then "недоступно"
        elif value == "deliver" then "отправить"
        elif value == "suppress" then "не отправлять повторно"
        elif value == "retry" then "повторить позже"
        elif value == "queued" then "ждёт отправки в дайджесте"
        elif value == "ok" then "доступно"
        elif value == "ready" then "готово"
        elif value == "accepted" then "пользователь согласился"
        elif value == "declined" then "пользователь отказался"
        elif value == "pending" then "ждём ответ"
        elif value == "sent" then "отправлено"
        elif value == "expired" then "время ожидания истекло"
        elif value == "failed" then "ошибка"
        elif value == "info" then "обычная"
        elif value == "important" then "высокая"
        elif value == "critical" then "критическая"
        elif value == "digest" then "дайджест"
        elif value == "immediate" then "сразу"
        elif value == "delivered" then "доставлено"
        elif value == "suppressed" then "подавлено"
        elif value == "unknown" then "неизвестно"
        else value
        end;
      def ru_source_name(value):
        if value == "codex-changelog" then "официальная лента изменений Codex CLI"
        elif value == "codex-advisory-issues" then "дополнительные сигналы из тикетов Codex CLI"
        else value
        end;
      def fmt_list(items):
        if (items | length) == 0 then "- нет"
        else items[] | "- \(.)"
        end;
      def fmt_source(source):
        [
          "- \(ru_source_name(source.name)): \(ru_status(source.status))",
          (if (source.url // "") != "" then "  ссылка: \(source.url)" else empty end),
          (if (source.notes | length) > 0 then "  заметки:" else empty end),
          (source.notes[]? | "    - \(.)")
        ];
      [
        "# Монитор обновлений Codex CLI",
        "",
        "- Проверено: \(.checked_at)",
        "- Последняя версия из официального источника: \(.snapshot.latest_version)",
        "- Состояние: \(ru_status(.snapshot.release_status))",
        "- Важность: \(ru_status(.severity.level))",
        "- Решение: \(ru_status(.decision.status))",
        "- Почему: \(.decision.reason)",
        "- Режим доставки: \(ru_status(.decision.delivery_mode))",
        "- Telegram включён: \(if .telegram_target.enabled then "да" else "нет" end)",
        (if (.telegram_target.chat_id // "") != "" then "- Идентификатор чата Telegram: \(.telegram_target.chat_id)" else empty end),
        "",
        "## Что изменилось простыми словами",
        (fmt_list(.snapshot.highlight_explanations)),
        "",
        "## Что умеет этот режим",
        (fmt_list(.feature_explanation)),
        "",
        "## Практические рекомендации для проекта",
        "- Статус: \(ru_status(.advisor_bridge.status))",
        "- Коротко: \(.advisor_bridge.summary)",
        "- Приоритеты:",
        (fmt_list(.advisor_bridge.top_priorities)),
        "",
        "## Дайджест и follow-up",
        "- Дайджест: \(ru_status(.followup.digest.mode))",
        "- В очереди дайджеста: \(.followup.digest.pending_count)",
        (if (.followup.digest.next_send_after // "") != "" then "- Следующая возможная отправка дайджеста: \(.followup.digest.next_send_after)" else empty end),
        "- Согласие на рекомендации: \(ru_status(.followup.consent.status))",
        "- Почему: \(.followup.consent.reason)",
        (if (.followup.consent.expires_at // "") != "" then "- Ответ ждём до: \(.followup.consent.expires_at)" else empty end),
        "",
        "## Источники",
        (fmt_source(.snapshot.primary_source)),
        (if (.snapshot.advisory_sources | length) > 0 then "" else empty end),
        (.snapshot.advisory_sources[]? | fmt_source(.)),
        "",
        "## Заметки watcher-а",
        (fmt_list(.notes)),
        "",
        "## Сохранённое состояние",
        "- Последний статус: \(ru_status(.state.last_status))",
        (if (.state.last_seen_fingerprint // "") != "" then "- Последний увиденный отпечаток состояния: \(.state.last_seen_fingerprint)" else empty end),
        (if (.state.last_delivered_fingerprint // "") != "" then "- Последний доставленный отпечаток состояния: \(.state.last_delivered_fingerprint)" else empty end),
        (if (.state.last_checked_at // "") != "" then "- Последняя проверка: \(.state.last_checked_at)" else empty end)
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

build_advisory_event() {
    jq '
      def unique_strings:
        reduce .[] as $item ([]; if ($item | type) == "string" and ($item | length) > 0 and (index($item) | not) then . + [$item] else . end);
      def recommendation_status:
        if .advisor_bridge.status == "ready" and ((.advisor_bridge.practical_recommendations // []) | length) > 0 then "ready"
        elif .advisor_bridge.status == "ready" then "deferred"
        else "unavailable"
        end;
      def impacted_surfaces:
        [ .advisor_bridge.practical_recommendations[]?.impacted_paths[]? ] | unique_strings;
      def links:
        (
          [
            {
              title: "Официальный changelog Codex CLI",
              url: .snapshot.primary_source.url
            }
          ]
          + [
            .snapshot.advisory_items[]?
            | select((.url // "") != "")
            | {
                title: (.title // ("Advisory issue " + (.id // "unknown"))),
                url: .url
              }
          ]
        )
        | map(select((.url // "") != ""));
      def recommendation_items:
        [
          .advisor_bridge.practical_recommendations[]?
          | {
              title_ru: .title,
              priority: .priority,
              rationale_ru: .rationale,
              impacted_surfaces: (.impacted_paths // []),
              next_steps_ru: (.next_steps // [])
            }
        ];
      (recommendation_status) as $recommendation_status
      | {
          schema_version: "codex-advisory-event/v1",
          event_id: ("codex-advisory-" + .fingerprint),
          created_at: .checked_at,
          source: "codex-cli-upstream-watcher",
          upstream_fingerprint: .fingerprint,
          latest_version: .snapshot.latest_version,
          severity: .severity.level,
          summary_ru: ("Обновление Codex CLI: версия " + .snapshot.latest_version),
          why_it_matters_ru: .severity.reason,
          highlights_ru: (
            if (.snapshot.highlight_explanations | length) > 0
            then .snapshot.highlight_explanations[:4]
            else ["В официальной ленте появилось изменение; подробности сохранены в полном отчёте."]
            end
          ),
          recommendation_status: $recommendation_status,
          interactive_followup_eligible: ($recommendation_status == "ready"),
          operator_notes_ru: (.notes // []),
          recommendation_payload: (
            if $recommendation_status == "unavailable" then null
            else {
              headline_ru: "Практические рекомендации для проекта",
              summary_ru: .advisor_bridge.summary,
              priority_checks: (.advisor_bridge.top_priorities // []),
              impacted_surfaces: impacted_surfaces,
              raw_reference_path: "scripts/codex-cli-update-advisor.sh",
              items: recommendation_items
            }
            end
          ),
          links: links
        }
    ' "$REPORT_PATH"
}

attach_advisory_event_to_report() {
    local event_file="${TEMP_DIR}/advisory-event.json"
    build_advisory_event > "$event_file"
    jq --slurpfile event "$event_file" '.advisory_event = $event[0]' "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

run_telegram_sender() {
    local chat_id="$1"
    local text="$2"
    local reply_to="${3:-}"
    local reply_markup_json="${4:-}"
    local -a cmd=(
        "$TELEGRAM_SEND_SCRIPT"
        --chat-id "$chat_id"
        --text "$text"
        --json
    )

    if [[ "$TELEGRAM_SILENT" == "true" ]]; then
        cmd+=(--disable-notification)
    fi

    if [[ -n "$reply_to" ]]; then
        cmd+=(--reply-to "$reply_to")
    fi

    if [[ -n "$reply_markup_json" ]]; then
        cmd+=(--reply-markup-json "$reply_markup_json")
    fi

    if [[ -n "$TELEGRAM_ENV_FILE" ]]; then
        MOLTIS_ENV_FILE="$TELEGRAM_ENV_FILE" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

persist_authoritative_consent_request() {
    [[ "$TELEGRAM_CONSENT_ROUTER_ENABLED" == "true" ]] || return 0
    [[ -x "$TELEGRAM_CONSENT_STORE_SCRIPT" ]] || return 1

    local pending_state_path record_path record_file
    pending_state_path="$(jq -r '.followup.consent.pending_state.request_id // ""' "$REPORT_PATH")"
    [[ -n "$pending_state_path" ]] || return 0

    ensure_parent_dir "${TELEGRAM_CONSENT_STORE_DIR}/placeholder"
    record_file="${TEMP_DIR}/consent-record.json"

    jq '
        .followup.consent.pending_state as $pending |
        .advisor_bridge as $advisor |
        {
            request: {
                request_id: $pending.request_id,
                source: "codex_upstream_watcher",
                fingerprint: $pending.fingerprint,
                chat_id: $pending.chat_id,
                question_message_id: null,
                created_at: $pending.asked_at,
                expires_at: $pending.expires_at,
                status: "pending",
                action_token: $pending.action_token,
                question_text: $pending.question,
                delivery_mode: $pending.delivery_mode
            },
            recommendations: {
                summary: $advisor.summary,
                items: ($pending.recommendations // [])
            },
            decision: null,
            delivery: {
                status: "not_sent"
            },
            audit_notes: [
                "authoritative-router",
                "opened by watcher alert"
            ]
        }
    ' "$REPORT_PATH" > "$record_file"

    "$TELEGRAM_CONSENT_STORE_SCRIPT" \
        open \
        --store-dir "$TELEGRAM_CONSENT_STORE_DIR" \
        --record-file "$record_file" \
        --json >/dev/null
}

bind_authoritative_consent_message_id() {
    [[ "$TELEGRAM_CONSENT_ROUTER_ENABLED" == "true" ]] || return 0
    [[ -x "$TELEGRAM_CONSENT_STORE_SCRIPT" ]] || return 1

    local request_id="$1"
    local message_id="$2"
    [[ -n "$request_id" && -n "$message_id" ]] || return 0

    "$TELEGRAM_CONSENT_STORE_SCRIPT" \
        bind-message \
        --store-dir "$TELEGRAM_CONSENT_STORE_DIR" \
        --request-id "$request_id" \
        --message-id "$message_id" \
        --json >/dev/null
}

patch_report_alert_success() {
    local chat_id="$1"
    local message_id="$2"

    jq \
        --arg chat_id "$chat_id" \
        --arg message_id "$message_id" \
        '
        .notes += ["Telegram-уведомление успешно отправлено."] |
        .telegram_target.chat_id = $chat_id |
        .state.last_status = "delivered" |
        .state.last_delivered_fingerprint = (.automation.alert.delivered_fingerprints[-1] // .fingerprint) |
        .state.delivered_fingerprints = (((.state.delivered_fingerprints // []) + (.automation.alert.delivered_fingerprints // [])) | unique | .[-20:]) |
        .state.notes = (((.state.notes // []) + ["Telegram-уведомление доставлено в чат " + $chat_id + "."]) | .[-10:]) |
        .state.digest_pending = (
          [(.state.digest_pending // [])[] |
            select(.fingerprint as $fp | ((.automation.alert.delivered_fingerprints // []) | index($fp) | not))
          ]
        ) |
        (
          if .decision.delivery_mode == "digest" and (.automation.alert.delivered_fingerprints | length) > 0 then
            .state.last_digest_sent_at = .checked_at
          else
            .
          end
        ) |
        (
          if (.followup.consent.pending_state? != null) and (.automation.alert.consent_requested == true) then
            (
              if (.followup.consent.router_mode // "") == "authoritative" then
                .state.last_consent_request_id = .followup.consent.pending_state.request_id |
                .state |= del(.pending_consent) |
                .followup.consent.status = "pending" |
                .followup.consent.reason = "В Telegram отправлен запрос на рекомендации; дальнейший ответ принимает authoritative router."
              else
                .state.pending_consent = (
                  .followup.consent.pending_state +
                  (if $message_id == "" then {} else {message_id: ($message_id | tonumber)} end)
                ) |
                .followup.consent.status = "pending" |
                .followup.consent.reason = "В Telegram отправлен вопрос, нужны ли практические рекомендации."
              end
            )
          else
            .
          end
        )
        ' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

patch_report_alert_failure() {
    local failure_message="$1"

    jq \
        --arg failure_message "$failure_message" \
        '
        .decision.status = "retry" |
        .decision.reason = "Не удалось отправить Telegram-уведомление; повторите попытку позже." |
        .notes += ["Ошибка Telegram-доставки: " + $failure_message] |
        .state.last_status = "failed" |
        .state.notes = (((.state.notes // []) + ["Ошибка Telegram-доставки: " + $failure_message]) | .[-10:])
        ' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

patch_report_recommendations_success() {
    local chat_id="$1"

    jq \
        --arg chat_id "$chat_id" \
        '
        .notes += ["Практические рекомендации успешно отправлены в Telegram."] |
        .followup.consent.status = "sent" |
        .followup.consent.reason = "Пользователь согласился, рекомендации отправлены." |
        .state.last_status = "delivered" |
        .state.notes = (((.state.notes // []) + ["Практические рекомендации отправлены в чат " + $chat_id + "."]) | .[-10:]) |
        .state |= del(.pending_consent)
        ' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

patch_report_recommendations_failure() {
    local failure_message="$1"

    jq \
        --arg failure_message "$failure_message" \
        '
        .notes += ["Ошибка отправки практических рекомендаций: " + $failure_message] |
        .followup.consent.status = "accepted" |
        .followup.consent.reason = "Пользователь согласился, но отправка рекомендаций пока не удалась." |
        .state.last_status = "failed" |
        (
          if .state.pending_consent? != null then
            .state.pending_consent.status = "accepted" |
            .state.pending_consent.last_error = $failure_message
          else
            .
          end
        ) |
        .state.notes = (((.state.notes // []) + ["Ошибка отправки практических рекомендаций: " + $failure_message]) | .[-10:])
        ' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                MODE="${2:?missing value for --mode}"
                shift 2
                ;;
            --state-file)
                STATE_FILE="${2:?missing value for --state-file}"
                shift 2
                ;;
            --json-out)
                JSON_OUT="${2:?missing value for --json-out}"
                shift 2
                ;;
            --summary-out)
                SUMMARY_OUT="${2:?missing value for --summary-out}"
                shift 2
                ;;
            --advisory-event-out)
                ADVISORY_EVENT_OUT="${2:?missing value for --advisory-event-out}"
                shift 2
                ;;
            --stdout)
                STDOUT_FORMAT="${2:?missing value for --stdout}"
                shift 2
                ;;
            --release-file)
                RELEASE_FILE="${2:?missing value for --release-file}"
                shift 2
                ;;
            --release-url)
                RELEASE_URL="${2:?missing value for --release-url}"
                shift 2
                ;;
            --max-releases)
                MAX_RELEASES="${2:?missing value for --max-releases}"
                shift 2
                ;;
            --include-issue-signals)
                INCLUDE_ISSUE_SIGNALS=true
                shift
                ;;
            --issue-signals-file)
                ISSUE_SIGNALS_FILE="${2:?missing value for --issue-signals-file}"
                shift 2
                ;;
            --issue-signals-url)
                ISSUE_SIGNALS_URL="${2:?missing value for --issue-signals-url}"
                shift 2
                ;;
            --delivery-mode)
                DELIVERY_MODE="${2:?missing value for --delivery-mode}"
                shift 2
                ;;
            --digest-window-hours)
                DIGEST_WINDOW_HOURS="${2:?missing value for --digest-window-hours}"
                shift 2
                ;;
            --digest-max-items)
                DIGEST_MAX_ITEMS="${2:?missing value for --digest-max-items}"
                shift 2
                ;;
            --advisor-bridge-disabled)
                ADVISOR_BRIDGE_ENABLED=false
                shift
                ;;
            --telegram-enabled)
                TELEGRAM_ENABLED=true
                shift
                ;;
            --telegram-chat-id)
                TELEGRAM_CHAT_ID="${2:?missing value for --telegram-chat-id}"
                shift 2
                ;;
            --telegram-env-file)
                TELEGRAM_ENV_FILE="${2:?missing value for --telegram-env-file}"
                shift 2
                ;;
            --telegram-silent)
                TELEGRAM_SILENT=true
                shift
                ;;
            --telegram-send-script)
                TELEGRAM_SEND_SCRIPT="${2:?missing value for --telegram-send-script}"
                shift 2
                ;;
            --telegram-consent-disabled)
                TELEGRAM_CONSENT_ENABLED=false
                shift
                ;;
            --telegram-consent-window-hours)
                TELEGRAM_CONSENT_WINDOW_HOURS="${2:?missing value for --telegram-consent-window-hours}"
                shift 2
                ;;
            --telegram-consent-router-disabled)
                TELEGRAM_CONSENT_ROUTER_ENABLED=false
                shift
                ;;
            --telegram-consent-store-script)
                TELEGRAM_CONSENT_STORE_SCRIPT="${2:?missing value for --telegram-consent-store-script}"
                shift 2
                ;;
            --telegram-consent-store-dir)
                TELEGRAM_CONSENT_STORE_DIR="${2:?missing value for --telegram-consent-store-dir}"
                shift 2
                ;;
            --telegram-updates-file)
                TELEGRAM_UPDATES_FILE="${2:?missing value for --telegram-updates-file}"
                shift 2
                ;;
            --telegram-allow-getupdates)
                TELEGRAM_ALLOW_GETUPDATES=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown argument: %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done

    case "$MODE" in
        manual|scheduler) ;;
        *)
            printf 'Некорректное значение --mode: %s\n' "$MODE" >&2
            exit 2
            ;;
    esac

    case "$STDOUT_FORMAT" in
        summary|json|none) ;;
        *)
            printf 'Некорректное значение --stdout: %s\n' "$STDOUT_FORMAT" >&2
            exit 2
            ;;
    esac

    case "$DELIVERY_MODE" in
        immediate|digest) ;;
        *)
            printf 'Некорректное значение --delivery-mode: %s\n' "$DELIVERY_MODE" >&2
            exit 2
            ;;
    esac

    TELEGRAM_ENABLED="$(normalize_bool "$TELEGRAM_ENABLED")"
    ADVISOR_BRIDGE_ENABLED="$(normalize_bool "$ADVISOR_BRIDGE_ENABLED")"
    TELEGRAM_CONSENT_ENABLED="$(normalize_bool "$TELEGRAM_CONSENT_ENABLED")"
    TELEGRAM_ALLOW_GETUPDATES="$(normalize_bool "$TELEGRAM_ALLOW_GETUPDATES")"

    if ! [[ "$MAX_RELEASES" =~ ^[1-9][0-9]*$ ]]; then
        printf '--max-releases должен быть положительным целым числом\n' >&2
        exit 2
    fi

    if ! [[ "$DIGEST_WINDOW_HOURS" =~ ^[1-9][0-9]*$ ]]; then
        printf '--digest-window-hours должен быть положительным целым числом\n' >&2
        exit 2
    fi

    if ! [[ "$DIGEST_MAX_ITEMS" =~ ^[1-9][0-9]*$ ]]; then
        printf '--digest-max-items должен быть положительным целым числом\n' >&2
        exit 2
    fi

    if ! [[ "$TELEGRAM_CONSENT_WINDOW_HOURS" =~ ^[1-9][0-9]*$ ]]; then
        printf '--telegram-consent-window-hours должен быть положительным целым числом\n' >&2
        exit 2
    fi
}

main() {
    parse_args "$@"
    require_command jq
    require_command python3

    TEMP_DIR="$(mktemp -d)"
    REPORT_PATH="${TEMP_DIR}/report.json"
    SUMMARY_PATH="${TEMP_DIR}/summary.md"

    local release_source_path issue_source_path updates_source_path
    local release_source_id issue_source_id previous_chat_id resolved_chat_id advisor_bridge_path
    local telegram_consent_router_ready
    release_source_path="${TEMP_DIR}/release-source"
    issue_source_path="${TEMP_DIR}/issue-source"
    updates_source_path=""
    release_source_id=""
    issue_source_id=""
    previous_chat_id=""
    resolved_chat_id=""
    advisor_bridge_path=""
    telegram_consent_router_ready="false"

    fetch_source "release" "$RELEASE_FILE" "$RELEASE_URL" "$DEFAULT_RELEASE_URL" "$release_source_path" || true
    release_source_id="$FETCH_SOURCE_ID"

    if [[ "$INCLUDE_ISSUE_SIGNALS" == "true" ]]; then
        fetch_source "issue-signal" "$ISSUE_SIGNALS_FILE" "$ISSUE_SIGNALS_URL" "$DEFAULT_ISSUE_SIGNALS_URL" "$issue_source_path" || true
        issue_source_id="$FETCH_SOURCE_ID"
    fi

    if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
        resolved_chat_id="$(resolve_telegram_chat_id "$TELEGRAM_ENV_FILE" || true)"
        if [[ -z "$resolved_chat_id" ]]; then
            add_warning "Telegram включён, но chat id определить не удалось."
        fi
    fi

    if [[ "$TELEGRAM_CONSENT_ROUTER_ENABLED" == "true" && -x "$TELEGRAM_CONSENT_STORE_SCRIPT" ]]; then
        if [[ "$(basename "$TELEGRAM_SEND_SCRIPT")" == "telegram-bot-send-remote.sh" ]]; then
            add_warning "Consent follow-up отключён: watcher отправляет Telegram через remote sender, а authoritative router ожидает store на том же runtime. Для live follow-up запускайте watcher на Moltinger host."
        elif [[ "$TELEGRAM_COMMAND_HOOK_READY" != "true" ]]; then
            add_warning "Consent follow-up отключён: Moltis runtime пока не подтвердил, что Telegram-команды доходят до repo-managed router раньше generic-ответа. Watcher перейдёт в one-way alert режим."
        else
            telegram_consent_router_ready="true"
        fi
    elif [[ "$TELEGRAM_ENABLED" == "true" && "$TELEGRAM_CONSENT_ENABLED" == "true" && "$TELEGRAM_CONSENT_ROUTER_ENABLED" == "true" ]]; then
        add_warning "Authoritative consent router включён, но shared consent store helper сейчас недоступен; watcher перейдёт в one-way alert режим."
    fi

    if [[ "$ADVISOR_BRIDGE_ENABLED" == "true" ]]; then
        advisor_bridge_path="$(build_advisor_bridge "$release_source_path" "$issue_source_path" || true)"
    fi

    if [[ "$TELEGRAM_ENABLED" == "true" && "$TELEGRAM_CONSENT_ENABLED" == "true" && "$TELEGRAM_ALLOW_GETUPDATES" == "true" && "$telegram_consent_router_ready" != "true" && "$(state_has_pending_consent "$STATE_FILE"; printf '%s' "$?")" == "0" ]]; then
        local updates_path next_offset
        updates_path="${TEMP_DIR}/telegram-updates.json"
        next_offset="$(state_next_update_offset "$STATE_FILE")"
        if fetch_telegram_updates "$updates_path" "$next_offset"; then
            updates_source_path="$updates_path"
        fi
    fi

    python3 - \
        "$MODE" \
        "$STATE_FILE" \
        "$release_source_id" \
        "$RELEASE_URL" \
        "$release_source_path" \
        "$MAX_RELEASES" \
        "$INCLUDE_ISSUE_SIGNALS" \
        "$issue_source_id" \
        "$ISSUE_SIGNALS_URL" \
        "$issue_source_path" \
        "$TELEGRAM_ENABLED" \
        "$resolved_chat_id" \
        "$TELEGRAM_ENV_FILE" \
        "$TELEGRAM_SILENT" \
        "$DELIVERY_MODE" \
        "$DIGEST_WINDOW_HOURS" \
        "$DIGEST_MAX_ITEMS" \
        "$ADVISOR_BRIDGE_ENABLED" \
        "$advisor_bridge_path" \
        "$TELEGRAM_CONSENT_ENABLED" \
        "$TELEGRAM_CONSENT_WINDOW_HOURS" \
        "$TELEGRAM_CONSENT_ROUTER_ENABLED" \
        "$telegram_consent_router_ready" \
        "$TELEGRAM_ALLOW_GETUPDATES" \
        "$updates_source_path" \
        "$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s .)" \
        > "$REPORT_PATH" <<'PY'
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
from html.parser import HTMLParser

mode = sys.argv[1]
state_path = pathlib.Path(sys.argv[2])
release_source_id = sys.argv[3]
release_source_url = sys.argv[4]
release_source_path = pathlib.Path(sys.argv[5])
max_releases = int(sys.argv[6])
include_issue_signals = sys.argv[7] == "true"
issue_source_id = sys.argv[8]
issue_source_url = sys.argv[9]
issue_source_path = pathlib.Path(sys.argv[10])
telegram_enabled = sys.argv[11] == "true"
telegram_chat_id = sys.argv[12]
telegram_env_file = sys.argv[13]
telegram_silent = sys.argv[14] == "true"
delivery_mode = sys.argv[15]
digest_window_hours = int(sys.argv[16])
digest_max_items = int(sys.argv[17])
advisor_bridge_enabled = sys.argv[18] == "true"
advisor_bridge_path = pathlib.Path(sys.argv[19]) if sys.argv[19] else None
telegram_consent_enabled = sys.argv[20] == "true"
telegram_consent_window_hours = int(sys.argv[21])
telegram_consent_router_enabled = sys.argv[22] == "true"
telegram_consent_router_ready = sys.argv[23] == "true"
telegram_allow_getupdates = sys.argv[24] == "true"
updates_source_path = pathlib.Path(sys.argv[25]) if sys.argv[25] else None
warnings = json.loads(sys.argv[26])

checked_dt = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
checked_at = checked_dt.isoformat().replace("+00:00", "Z")


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div"}:
            self.parts.append("\n")

    def handle_data(self, data):
        stripped = data.strip()
        if stripped:
            self.parts.append(stripped)

    def text(self) -> str:
        text = "".join(self.parts)
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        return "\n".join(line for line in lines if line)


def compact_notes(notes: list[str], limit: int = 10) -> list[str]:
    cleaned = [note for note in notes if note]
    return cleaned[-limit:]


def unique_preserve(items: list[str], limit: int | None = None) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        value = str(item).strip()
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    if limit is not None:
        return result[-limit:]
    return result


def parse_datetime(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def load_state(path: pathlib.Path) -> tuple[dict, list[str]]:
    default = {
        "last_status": "unknown",
        "notes": [],
        "delivered_fingerprints": [],
        "digest_pending": [],
        "last_update_id": 0,
    }
    notes: list[str] = []
    if not path.is_file():
        return default, notes
    try:
        raw = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Не удалось разобрать файл состояния watcher-а: {exc}")
        return default, notes

    if not isinstance(raw, dict):
        notes.append("Файл состояния watcher-а не содержит JSON-объект и был проигнорирован.")
        return default, notes

    state = {
        "last_seen_fingerprint": str(raw.get("last_seen_fingerprint", "")).strip(),
        "last_delivered_fingerprint": str(raw.get("last_delivered_fingerprint", "")).strip(),
        "last_status": str(raw.get("last_status", "unknown")).strip() or "unknown",
        "last_checked_at": str(raw.get("last_checked_at", "")).strip(),
        "notes": [str(item).strip() for item in raw.get("notes", []) if str(item).strip()],
        "delivered_fingerprints": unique_preserve([str(item) for item in raw.get("delivered_fingerprints", [])], 20),
        "last_digest_sent_at": str(raw.get("last_digest_sent_at", "")).strip(),
        "last_update_id": int(raw.get("last_update_id", 0) or 0),
    }

    digest_pending = []
    for item in raw.get("digest_pending", []):
        if not isinstance(item, dict):
            continue
        fingerprint = str(item.get("fingerprint", "")).strip()
        version = str(item.get("version", "")).strip()
        checked = str(item.get("checked_at", "")).strip()
        headline = str(item.get("headline", "")).strip()
        severity = str(item.get("severity", "")).strip() or "info"
        explanations = [str(x).strip() for x in item.get("explanations", []) if str(x).strip()]
        if fingerprint and version and checked:
            digest_pending.append(
                {
                    "fingerprint": fingerprint,
                    "version": version,
                    "checked_at": checked,
                    "headline": headline or f"Вышла версия {version}.",
                    "severity": severity,
                    "explanations": explanations,
                }
            )
    state["digest_pending"] = digest_pending

    pending = raw.get("pending_consent")
    if isinstance(pending, dict):
        chat_id = str(pending.get("chat_id", "")).strip()
        fingerprint = str(pending.get("fingerprint", "")).strip()
        asked_at = str(pending.get("asked_at", "")).strip()
        if chat_id and fingerprint and asked_at:
            state["pending_consent"] = {
                "fingerprint": fingerprint,
                "chat_id": chat_id,
                "asked_at": asked_at,
                "expires_at": str(pending.get("expires_at", "")).strip(),
                "question": str(pending.get("question", "")).strip(),
                "summary": str(pending.get("summary", "")).strip(),
                "status": str(pending.get("status", "pending")).strip() or "pending",
                "message_id": int(pending.get("message_id", 0) or 0),
                "accepted_at": str(pending.get("accepted_at", "")).strip(),
                "last_error": str(pending.get("last_error", "")).strip(),
                "recommendations": [
                    {
                        "title": str(item.get("title", "")).strip(),
                        "rationale": str(item.get("rationale", "")).strip(),
                        "impacted_paths": [str(path).strip() for path in item.get("impacted_paths", []) if str(path).strip()],
                        "next_steps": [str(step).strip() for step in item.get("next_steps", []) if str(step).strip()],
                    }
                    for item in pending.get("recommendations", [])
                    if isinstance(item, dict)
                ],
            }

    return state, notes


def parse_release_source(raw: str, limit: int) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []

    if stripped[0] in "[{":
        data = json.loads(stripped)
        releases = data.get("releases", data if isinstance(data, list) else [])
        normalized = []
        for item in releases:
            changes = item.get("changes", [])
            normalized.append(
                {
                    "version": str(item.get("version", "")).strip(),
                    "published_at": str(item.get("published_at", "")).strip(),
                    "changes": [str(change).strip() for change in changes if str(change).strip()],
                }
            )
        return [item for item in normalized if item["version"]][:limit]

    parser = TextExtractor()
    parser.feed(stripped)
    text = parser.text()
    lines = text.splitlines()

    releases: list[dict] = []
    current = None
    pending_date = ""
    version_pattern = re.compile(r"Codex CLI(?: Release:)?\s*(\d+\.\d+\.\d+)")
    date_pattern = re.compile(r"^\d{4}-\d{2}-\d{2}$")

    for line in lines:
        if date_pattern.match(line):
            pending_date = line
            continue

        match = version_pattern.search(line)
        if match:
            if current:
                releases.append(current)
            current = {
                "version": match.group(1),
                "published_at": pending_date,
                "changes": [],
            }
            pending_date = ""
            continue

        if current is None:
            continue

        if line.lower() in {"new features", "bug fixes", "documentation", "fixes", "improvements"}:
            continue
        if line == "Changelog":
            continue
        if re.search(r"\d+\.\d+\.\d+", line) and "Codex CLI" in line:
            continue
        if line:
            current["changes"].append(line)

    if current:
        releases.append(current)

    cleaned = []
    for item in releases[:limit]:
        deduped = unique_preserve(item["changes"])
        cleaned.append(
            {
                "version": item["version"],
                "published_at": item["published_at"],
                "changes": deduped,
            }
        )
    return cleaned


def parse_issue_signals(raw: str) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []
    data = json.loads(stripped)
    if isinstance(data, list):
        issues = data
    elif isinstance(data, dict):
        issues = data.get("issues", data.get("result", []))
    else:
        issues = []

    normalized = []
    for item in issues:
        if not isinstance(item, dict):
            continue
        if item.get("pull_request"):
            continue
        issue_id = item.get("id") or item.get("number")
        if issue_id is None:
            continue
        normalized.append(
            {
                "id": str(issue_id),
                "title": str(item.get("title", "")).strip(),
                "state": str(item.get("state", "unknown")).strip() or "unknown",
                "url": str(item.get("html_url", item.get("url", ""))).strip(),
            }
        )
    return normalized


def explain_change(change_text: str, advisory: bool = False) -> tuple[str, list[str], str]:
    text = change_text.lower()
    rules = [
        ("critical", ["breaking", "migration", "deprecated", "deprecation", "security", "vulnerability", "incompatible"], "Есть риск несовместимости или усиления требований безопасности; это стоит проверить до обновления.", ["breaking", "security"]),
        ("important", ["approval", "permission profile", "sandbox"], "Изменения затрагивают подтверждение действий и ограничения среды выполнения.", ["approval", "sandbox"]),
        ("important", ["worktree", "/new", "workspace"], "Изменения затрагивают работу с рабочими деревьями и отдельными ветками.", ["worktree"]),
        ("important", ["multi-agent", "multi agent", "resume", "session"], "Изменения затрагивают восстановление сессий и работу с несколькими агентами.", ["agents"]),
        ("important", ["js_repl", "js repl", "repl"], "Изменения затрагивают сценарии с js_repl и встроенными вычислениями.", ["js-repl"]),
        ("important", ["skill", "mcp", "plugin"], "Изменения затрагивают навыки, MCP-интеграции или связанный инструментальный слой.", ["skills", "mcp"]),
        ("info", ["docs", "documentation", "example"], "Обновились документы или примеры использования Codex CLI.", ["docs"]),
    ]

    for level, keywords, explanation, tags in rules:
        if any(keyword in text for keyword in keywords):
            if advisory and level == "info":
                return ("important", "Есть дополнительный сигнал из тикетов Codex CLI; его стоит проверить вместе с changelog.", ["advisory"])
            return level, explanation, tags

    if advisory:
        return ("important", "Есть дополнительный сигнал из тикетов Codex CLI; он не меняет вердикт сам по себе, но усиливает необходимость проверки.", ["advisory"])
    return ("info", "В официальной ленте появилось изменение; подробности сохранены в полном отчёте.", ["generic"])


def build_highlight_explanations(highlights: list[str], advisories: list[dict]) -> tuple[list[str], list[str], str]:
    explanations: list[str] = []
    tags: list[str] = []
    level_rank = {"info": 1, "important": 2, "critical": 3}
    strongest_level = "info"

    for change in highlights[:5]:
        level, explanation, change_tags = explain_change(change)
        explanations.append(explanation)
        tags.extend(change_tags)
        if level_rank[level] > level_rank[strongest_level]:
            strongest_level = level

    for item in advisories[:3]:
        level, explanation, change_tags = explain_change(item["title"], advisory=True)
        explanations.append(explanation)
        tags.extend(change_tags)
        if level_rank[level] > level_rank[strongest_level]:
            strongest_level = level

    explanations = unique_preserve(explanations, 5)
    tags = unique_preserve(tags, 10)
    return explanations, tags, strongest_level


def build_recent_releases(releases: list[dict], advisories: list[dict]) -> list[dict]:
    recent = []
    for index, item in enumerate(releases[:3]):
        explanations, _, strongest = build_highlight_explanations(item["changes"][:5], advisories if index == 0 else [])
        recent.append(
            {
                "version": item["version"],
                "published_at": item["published_at"],
                "change_count": len(item["changes"]),
                "headline": explanations[0] if explanations else f"Вышла версия {item['version']}.",
                "explanations": explanations,
                "severity": strongest,
            }
        )
    return recent


def build_severity(primary_status: str, advisories: list[dict], explanations: list[str], tags: list[str], latest_version: str) -> dict:
    if primary_status != "ok":
        return {
            "level": "investigate",
            "reason": "Нельзя честно оценить важность, пока официальный источник недоступен или сломан.",
        }
    if "breaking" in tags or "security" in tags:
        return {
            "level": "critical",
            "reason": f"Версия {latest_version} выглядит потенциально рискованной: есть признаки несовместимости, миграции или усиления ограничений.",
        }
    if any(tag in tags for tag in ["approval", "sandbox", "worktree", "agents", "js-repl", "advisory"]):
        return {
            "level": "important",
            "reason": f"Версия {latest_version} затрагивает рабочие сценарии, которые этот проект использует регулярно.",
        }
    if explanations:
        return {
            "level": "info",
            "reason": f"В версии {latest_version} есть новые возможности, но без явных признаков срочного риска.",
        }
    return {
        "level": "info",
        "reason": "Свежая версия найдена, но значимых деталей пока мало.",
    }


def build_fingerprint(latest_version: str, highlights: list[str], primary_status: str, advisories: list[dict]) -> str:
    payload = json.dumps(
        {
            "latest_version": latest_version,
            "highlights": highlights[:5],
            "primary_status": primary_status,
            "advisories": [item["id"] for item in advisories[:5]],
        },
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


SUGGESTION_LOCALIZATION = {
    "worktree-guidance": {
        "title": "Проверить правила работы с worktree и топологией веток",
        "rationale": "Новая версия Codex затрагивает сценарии с отдельными worktree, а этот проект активно их использует.",
        "next_steps": [
            "Сверить инструкции по worktree с текущим поведением Codex.",
            "Проверить вспомогательные команды и примеры переключения между ветками.",
        ],
    },
    "approval-profile-review": {
        "title": "Пересмотреть правила approval и sandbox",
        "rationale": "В проекте есть строгие границы по подтверждению действий и sandbox, поэтому обновление может менять ожидания оператора.",
        "next_steps": [
            "Проверить, не изменились ли правила подтверждения опасных действий.",
            "Сверить текущие launch/default-профили с новой версией Codex.",
        ],
    },
    "agent-delegation-review": {
        "title": "Освежить инструкции по мультиагентному режиму и resume-flow",
        "rationale": "Проект опирается на делегирование задач агентам и продолжение сессий, поэтому этот участок особенно чувствителен к изменениям Codex.",
        "next_steps": [
            "Проверить, как теперь ведут себя resume-сценарии и длинные сессии.",
            "Обновить инструкции по делегированию, если они начали расходиться с реальным поведением.",
        ],
    },
    "js-repl-guidance": {
        "title": "Обновить guidance по js_repl",
        "rationale": "В проекте js_repl используется как рабочий инструмент, и новая версия Codex может менять допустимые сценарии или ограничения.",
        "next_steps": [
            "Проверить актуальность примеров и caveats по js_repl.",
            "Уточнить ограничения, если появились новые edge cases.",
        ],
    },
    "skills-surface-review": {
        "title": "Проверить bridge навыков и MCP-интеграции",
        "rationale": "Изменения в навыках, MCP или bridge-слое могут затронуть локальные инструкции и генерацию skill-обвязок.",
        "next_steps": [
            "Проверить, что skill bridge и MCP guidance по-прежнему корректны.",
            "Обновить локальные правила, если поведение capabilities изменилось.",
        ],
    },
    "runbook-refresh": {
        "title": "Обновить runbook и пользовательские примеры",
        "rationale": "После обновления Codex чаще всего первыми устаревают рабочие инструкции и примеры запуска.",
        "next_steps": [
            "Сверить runbook с реальным поведением новой версии.",
            "Освежить примеры команд и последовательности действий.",
        ],
    },
    "investigate-gap": {
        "title": "Сначала разобраться с пробелом в данных monitor/advisor",
        "rationale": "Без надёжного входного сигнала нельзя безопасно давать точные проектные рекомендации.",
        "next_steps": [
            "Починить источник данных monitor/advisor.",
            "Повторно собрать надёжный отчёт перед изменением проектных инструкций.",
        ],
    },
    "codex-runtime-review": {
        "title": "Проверить runtime-guidance Codex для этого проекта",
        "rationale": "Найдены релевантные изменения, но они не попали в более узкий сценарий и требуют ручного разбора.",
        "next_steps": [
            "Посмотреть релевантные пункты changelog и решить, какие правила нужно обновить.",
        ],
    },
}


def localize_suggestion(item: dict) -> dict:
    suggestion_id = str(item.get("id", "")).strip()
    localized = SUGGESTION_LOCALIZATION.get(suggestion_id, {})
    return {
        "id": suggestion_id or "generic",
        "title": localized.get("title", "Проверить применимость изменений Codex к этому проекту"),
        "priority": str(item.get("priority", "medium")).strip() or "medium",
        "rationale": localized.get("rationale", "Есть upstream-изменения Codex, которые стоит соотнести с локальными правилами и процессами проекта."),
        "impacted_paths": [str(path).strip() for path in item.get("impacted_paths", []) if str(path).strip()],
        "next_steps": localized.get(
            "next_steps",
            [step for step in [str(step).strip() for step in item.get("next_steps", [])] if step] or ["Проверить затронутые инструкции и сценарии вручную."],
        ),
    }


def load_advisor_bridge(path: pathlib.Path | None) -> dict:
    if not advisor_bridge_enabled:
        return {
            "enabled": False,
            "status": "disabled",
            "summary": "Практические рекомендации отключены.",
            "top_priorities": [],
            "practical_recommendations": [],
            "notes": [],
            "question": "",
        }

    if path is None or not path.is_file():
        return {
            "enabled": True,
            "status": "unavailable",
            "summary": "Практические рекомендации пока недоступны: bridge к advisor-слою не собран.",
            "top_priorities": [],
            "practical_recommendations": [],
            "notes": ["Advisor bridge не смог подготовить отчёт."],
            "question": "",
        }

    try:
        raw = json.loads(path.read_text())
    except Exception as exc:
        return {
            "enabled": True,
            "status": "investigate",
            "summary": "Практические рекомендации пока недоступны: advisor report не разобрался.",
            "top_priorities": [],
            "practical_recommendations": [],
            "notes": [f"Не удалось разобрать advisor report: {exc}"],
            "question": "",
        }

    practical_recommendations = [
        localize_suggestion(item)
        for item in raw.get("project_change_suggestions", [])
        if isinstance(item, dict)
    ]
    top_priorities = [item["title"] for item in practical_recommendations[:3]]

    if practical_recommendations:
        summary = "Можно подготовить конкретные шаги для этого проекта и связать их с затронутыми файлами."
        status = "ready"
    else:
        summary = "Срочных проектных правок не найдено; можно ограничиться наблюдением за релизом."
        status = "ready"

    return {
        "enabled": True,
        "status": status,
        "summary": summary,
        "top_priorities": top_priorities,
        "practical_recommendations": practical_recommendations,
        "notes": [str(item).strip() for item in raw.get("implementation_brief", {}).get("notes", []) if str(item).strip()],
        "question": "Хотите получить практические рекомендации по применению этих новых возможностей в вашем проекте?",
    }


def parse_updates(path: pathlib.Path | None) -> tuple[list[dict], int, list[str]]:
    if path is None or not path.is_file():
        return [], 0, []
    try:
        raw = json.loads(path.read_text())
    except Exception as exc:
        return [], 0, [f"Не удалось разобрать ответы Telegram: {exc}"]

    if isinstance(raw, dict):
        updates = raw.get("result", raw.get("updates", []))
    elif isinstance(raw, list):
        updates = raw
    else:
        updates = []

    normalized = []
    max_update_id = 0
    for item in updates:
        if not isinstance(item, dict):
            continue
        update_id = int(item.get("update_id", 0) or 0)
        max_update_id = max(max_update_id, update_id)
        message = item.get("message") or item.get("edited_message") or {}
        if not isinstance(message, dict):
            continue
        chat = message.get("chat", {})
        reply_to = message.get("reply_to_message", {})
        normalized.append(
            {
                "update_id": update_id,
                "chat_id": str(chat.get("id", "")).strip(),
                "text": str(message.get("text", "")).strip(),
                "message_id": int(message.get("message_id", 0) or 0),
                "reply_to_message_id": int(reply_to.get("message_id", 0) or 0),
                "date": int(message.get("date", 0) or 0),
            }
        )
    return normalized, max_update_id, []


def classify_response(text: str) -> str:
    normalized = re.sub(r"[^a-zа-я0-9 ]+", " ", text.lower()).strip()
    yes_markers = {"да", "yes", "хочу", "давай", "нужно", "конечно", "получить"}
    no_markers = {"нет", "no", "не надо", "не нужно", "позже", "не сейчас"}

    if any(marker in normalized for marker in yes_markers):
        return "yes"
    if any(marker in normalized for marker in no_markers):
        return "no"
    return "unknown"


def build_recommendations_message(advisor_bridge: dict) -> str:
    lines = [
        "Практические рекомендации по внедрению в этом проекте",
        advisor_bridge["summary"],
    ]
    if advisor_bridge["practical_recommendations"]:
        lines.append("Что стоит сделать сначала:")
        for item in advisor_bridge["practical_recommendations"][:3]:
            lines.append(f"- {item['title']}: {item['rationale']}")
            for step in item["next_steps"][:2]:
                lines.append(f"  - {step}")
        impacted_paths = unique_preserve(
            [path for item in advisor_bridge["practical_recommendations"][:3] for path in item["impacted_paths"]],
            8,
        )
        if impacted_paths:
            lines.append("Где это вероятнее всего затронет проект:")
            for path in impacted_paths:
                lines.append(f"- {path}")
    else:
        lines.append("Сейчас достаточно просто держать релиз под наблюдением.")
    return "\n".join(lines)


def build_consent_request(
    fingerprint: str,
    chat_id: str,
    checked_at: str,
    checked_dt: dt.datetime,
    window_hours: int,
    advisor_bridge: dict,
) -> dict:
    seed = f"{fingerprint}:{chat_id}:{checked_at}"
    request_id = "req-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:8]
    action_token = "tok-" + hashlib.sha256((seed + ":token").encode("utf-8")).hexdigest()[:8]
    short_accept_command = "/codex_da"
    short_decline_command = "/codex_net"
    accept_command = f"/codex-followup accept {request_id} {action_token}"
    decline_command = f"/codex-followup decline {request_id} {action_token}"
    return {
        "request_id": request_id,
        "action_token": action_token,
        "fingerprint": fingerprint,
        "chat_id": chat_id,
        "asked_at": checked_at,
        "expires_at": (checked_dt + dt.timedelta(hours=window_hours)).isoformat().replace("+00:00", "Z"),
        "question": advisor_bridge["question"],
        "summary": advisor_bridge["summary"],
        "status": "pending",
        "delivery_mode": "command_keyboard",
        "router_mode": "authoritative",
        "command_alias_accept": short_accept_command,
        "command_alias_decline": short_decline_command,
        "command_accept": accept_command,
        "command_decline": decline_command,
        "callback_accept": f"codex-consent:accept:{request_id}:{action_token}",
        "callback_decline": f"codex-consent:decline:{request_id}:{action_token}",
        "reply_markup": {
            "keyboard": [
                [{"text": short_accept_command}],
                [{"text": short_decline_command}],
            ],
            "resize_keyboard": True,
            "one_time_keyboard": True,
            "input_field_placeholder": "Выберите: прислать рекомендации или не сейчас",
        },
        "recommendations": advisor_bridge["practical_recommendations"],
    }


def build_alert_message(
    latest_version: str,
    severity: dict,
    explanations: list[str],
    decision_reason: str,
    delivery_kind: str,
    digest_entries: list[dict],
    advisor_bridge: dict,
    ask_for_consent: bool,
    consent_request: dict | None,
) -> str:
    severity_label = {
        "info": "обычная",
        "important": "высокая",
        "critical": "критическая",
        "investigate": "нужно проверить",
    }.get(severity["level"], severity["level"])
    lines: list[str] = []
    if delivery_kind == "digest":
        lines.extend(
            [
                "Дайджест обновлений Codex CLI",
                f"Накоплено новых upstream-событий: {len(digest_entries)}",
                f"Самая свежая версия: {latest_version}",
                f"Важность: {severity_label}",
                f"Почему это важно: {decision_reason}",
                "Коротко по событиям:",
            ]
        )
        for item in digest_entries[:5]:
            lines.append(f"- {item['version']}: {item['headline']}")
    else:
        lines.extend(
            [
                "Обновление Codex CLI",
                f"Последняя версия из официального источника: {latest_version}",
                f"Важность: {severity_label}",
                f"Почему это важно: {severity['reason']}",
                "Простыми словами:",
            ]
        )
        for explanation in explanations[:4]:
            lines.append(f"- {explanation}")

    if advisor_bridge["status"] == "ready":
        lines.append("Что это может дать проекту:")
        lines.append(f"- {advisor_bridge['summary']}")

    if ask_for_consent and advisor_bridge["question"]:
        lines.append("")
        lines.append(advisor_bridge["question"])
        if consent_request is not None:
            lines.append("Нажмите одну из кнопок ниже.")
            lines.append("Если клавиатура не показалась, можно отправить короткую команду вручную:")
            lines.append(f"- {consent_request['command_alias_accept']} — прислать рекомендации")
            lines.append(f"- {consent_request['command_alias_decline']} — не присылать сейчас")
            lines.append("Если увидите сообщение о нескольких активных запросах, используйте резервную команду из этого уведомления:")
            lines.append(f"- {consent_request['command_accept']}")
            lines.append(f"- Код запроса: {consent_request['request_id']}")
        else:
            lines.append("Ответьте в этом чате: да или нет.")

    return "\n".join(lines)


previous_state, state_warnings = load_state(state_path)
notes = list(warnings) + state_warnings

primary_notes: list[str] = []
releases: list[dict] = []
primary_status = "unavailable"

if release_source_path.is_file():
    try:
        releases = parse_release_source(release_source_path.read_text(), max_releases)
        if releases:
            primary_status = "ok"
            primary_notes.append(f"Из основного источника разобрано релизов: {len(releases)}.")
        else:
            primary_status = "investigate"
            primary_notes.append("Основной источник прочитан, но релизы Codex CLI из него не разобрались.")
    except Exception as exc:
        primary_status = "investigate"
        primary_notes.append(f"Не удалось разобрать основной источник: {exc}")
else:
    primary_status = "unavailable"
    primary_notes.append("Не удалось получить основной источник.")

advisory_sources: list[dict] = []
advisory_items: list[dict] = []
if include_issue_signals:
    advisory_notes: list[str] = []
    advisory_status = "unavailable"
    if issue_source_path.is_file():
        try:
            advisory_items = parse_issue_signals(issue_source_path.read_text())
            advisory_status = "ok"
            advisory_notes.append(f"Проверено дополнительных сигналов из тикетов: {len(advisory_items)}.")
            if advisory_items:
                advisory_notes.append("Найдены дополнительные сигналы из тикетов; они усиливают контекст, но не меняют официальный вердикт сами по себе.")
        except Exception as exc:
            advisory_status = "investigate"
            advisory_notes.append(f"Не удалось разобрать advisory issue signals: {exc}")
    else:
        advisory_status = "unavailable"
        advisory_notes.append("Не удалось получить источник advisory issue signals.")

    advisory_sources.append(
        {
            "name": "codex-advisory-issues",
            "status": advisory_status,
            "url": issue_source_url,
            "notes": advisory_notes,
        }
    )

latest_version = releases[0]["version"] if releases else "unknown"
highlights = releases[0]["changes"][:5] if releases else []
if releases and not highlights:
    highlights = [f"Опубликован релиз {latest_version}."]

highlight_explanations, explanation_tags, _ = build_highlight_explanations(highlights, advisory_items)
recent_releases = build_recent_releases(releases, advisory_items)
severity = build_severity(primary_status, advisory_items, highlight_explanations, explanation_tags, latest_version)
fingerprint = build_fingerprint(latest_version, highlights, primary_status, advisory_items)

seen_matches = previous_state.get("last_seen_fingerprint", "") == fingerprint
delivered_fingerprints = previous_state.get("delivered_fingerprints", [])
delivered_matches = fingerprint in delivered_fingerprints or previous_state.get("last_delivered_fingerprint", "") == fingerprint
release_status = "unavailable"
if primary_status == "ok":
    release_status = "known" if seen_matches else "new"
elif primary_status == "investigate":
    release_status = "investigate"

advisor_bridge = load_advisor_bridge(advisor_bridge_path)
updates, max_update_id, update_notes = parse_updates(updates_source_path)
notes.extend(update_notes)

state = dict(previous_state)
state["notes"] = list(previous_state.get("notes", []))
state["last_checked_at"] = checked_at
state["last_update_id"] = max(previous_state.get("last_update_id", 0), max_update_id)
state["delivered_fingerprints"] = delivered_fingerprints
state["digest_pending"] = list(previous_state.get("digest_pending", []))

recommendations_action = {"action": "skip", "reason": "Пока нет подтверждённого согласия пользователя.", "text": "", "reply_to_message_id": 0}
consent_status = "disabled" if not telegram_consent_enabled else "none"
consent_reason = "Вопрос о практических рекомендациях не активирован."
consent_expires_at = ""

pending_consent = previous_state.get("pending_consent")
if telegram_consent_enabled:
    if telegram_consent_router_ready:
        state.pop("pending_consent", None)
        consent_status = "none"
        consent_reason = "Authoritative router готов принимать токенизированные ответы на новые уведомления."
    elif telegram_allow_getupdates:
        consent_status = "disabled"
        consent_reason = "Authoritative router недоступен; interactive follow-up отключён. Legacy polling разрешён только для уже существующих тестовых запросов."
        if pending_consent and isinstance(pending_consent, dict):
            consent_status = "none"
            consent_reason = "Legacy polling включён только для совместимости со старыми test-state запросами."
        else:
            state.pop("pending_consent", None)
    else:
        state.pop("pending_consent", None)
        consent_status = "disabled"
        if telegram_consent_router_enabled:
            consent_reason = "Authoritative router сейчас недоступен, поэтому уведомление будет one-way без вопроса о рекомендациях."
        else:
            consent_reason = "Authoritative router выключен, поэтому уведомление будет one-way без вопроса о рекомендациях."

    if (not telegram_consent_router_ready) and telegram_allow_getupdates and pending_consent and isinstance(pending_consent, dict):
            expires_at = parse_datetime(str(pending_consent.get("expires_at", "")))
            consent_expires_at = str(pending_consent.get("expires_at", "")).strip()
            if expires_at and checked_dt > expires_at:
                state.pop("pending_consent", None)
                consent_status = "expired"
                consent_reason = "Пользователь не ответил вовремя, окно ожидания закрыто."
            elif pending_consent.get("status") == "accepted":
                if advisor_bridge["status"] == "ready" and advisor_bridge["practical_recommendations"]:
                    recommendations_action = {
                        "action": "send",
                        "reason": "Пользователь уже согласился ранее, рекомендации ещё не были отправлены.",
                        "text": build_recommendations_message(advisor_bridge),
                        "reply_to_message_id": int(pending_consent.get("message_id", 0) or 0),
                    }
                    consent_status = "accepted"
                    consent_reason = "Пользователь уже согласился; нужно дослать рекомендации."
                    state["pending_consent"] = pending_consent
                else:
                    state.pop("pending_consent", None)
                    consent_status = "investigate"
                    consent_reason = "Пользователь согласился, но готовые рекомендации сейчас недоступны."
            else:
                asked_at = parse_datetime(str(pending_consent.get("asked_at", "")))
                response = "unknown"
                for item in sorted(updates, key=lambda value: (value["date"], value["update_id"])):
                    if item["chat_id"] != str(pending_consent.get("chat_id", "")):
                        continue
                    if asked_at is not None and item["date"] and dt.datetime.fromtimestamp(item["date"], tz=dt.timezone.utc) < asked_at:
                        continue
                    if pending_consent.get("message_id") and item["reply_to_message_id"] not in {0, int(pending_consent.get("message_id", 0))}:
                        if item["message_id"] <= int(pending_consent.get("message_id", 0)):
                            continue
                    parsed = classify_response(item["text"])
                    if parsed != "unknown":
                        response = parsed
                        break

                if response == "yes":
                    if advisor_bridge["status"] == "ready" and advisor_bridge["practical_recommendations"]:
                        updated_pending = dict(pending_consent)
                        updated_pending["status"] = "accepted"
                        updated_pending["accepted_at"] = checked_at
                        state["pending_consent"] = updated_pending
                        recommendations_action = {
                            "action": "send",
                            "reason": "Пользователь согласился получить практические рекомендации.",
                            "text": build_recommendations_message(advisor_bridge),
                            "reply_to_message_id": int(updated_pending.get("message_id", 0) or 0),
                        }
                        consent_status = "accepted"
                        consent_reason = "Пользователь согласился получить практические рекомендации."
                    else:
                        state.pop("pending_consent", None)
                        consent_status = "investigate"
                        consent_reason = "Пользователь согласился, но рекомендации пока не готовы."
                elif response == "no":
                    state.pop("pending_consent", None)
                    consent_status = "declined"
                    consent_reason = "Пользователь отказался от практических рекомендаций."
                else:
                    state["pending_consent"] = pending_consent
                    consent_status = "pending"
                    consent_reason = "Legacy polling ждёт ответ только для уже существующего тестового запроса."

decision_status = "investigate"
decision_reason = "Официальная лента изменений сейчас недоступна."
decision_changed = False
consent_request = None
alert_action = {"action": "skip", "kind": delivery_mode, "reason": "Отправка не требуется.", "text": "", "delivered_fingerprints": [], "consent_requested": False}

if primary_status == "investigate":
    decision_status = "investigate"
    decision_reason = "Официальная лента изменений вернула неполные или некорректные данные."
    state["last_status"] = "investigate"
elif primary_status == "unavailable":
    decision_status = "investigate"
    decision_reason = "Официальная лента изменений сейчас недоступна."
    state["last_status"] = "investigate"
else:
    decision_changed = not seen_matches
    state["last_seen_fingerprint"] = fingerprint

    consent_request = None
    ask_for_consent = (
        telegram_enabled
        and telegram_consent_enabled
        and telegram_consent_router_ready
        and advisor_bridge["status"] == "ready"
        and bool(advisor_bridge["practical_recommendations"])
        and "pending_consent" not in state
    )
    if ask_for_consent and telegram_chat_id:
        consent_request = build_consent_request(
            fingerprint,
            telegram_chat_id,
            checked_at,
            checked_dt,
            telegram_consent_window_hours,
            advisor_bridge,
        )

    current_digest_entry = {
        "fingerprint": fingerprint,
        "version": latest_version,
        "checked_at": checked_at,
        "headline": highlight_explanations[0] if highlight_explanations else f"Вышла версия {latest_version}.",
        "severity": severity["level"] if severity["level"] in {"info", "important", "critical"} else "info",
        "explanations": highlight_explanations,
    }

    if mode == "scheduler" and telegram_enabled:
        if delivery_mode == "digest" and severity["level"] != "critical":
            digest_pending = list(state.get("digest_pending", []))
            pending_fingerprints = {item["fingerprint"] for item in digest_pending}
            if not delivered_matches and fingerprint not in pending_fingerprints:
                digest_pending.append(current_digest_entry)
            state["digest_pending"] = digest_pending

            oldest = parse_datetime(digest_pending[0]["checked_at"]) if digest_pending else None
            digest_due = False
            next_send_after = ""
            if digest_pending and oldest is not None:
                due_dt = oldest + dt.timedelta(hours=digest_window_hours)
                next_send_after = due_dt.isoformat().replace("+00:00", "Z")
                if checked_dt >= due_dt:
                    digest_due = True
            if len(digest_pending) >= digest_max_items:
                digest_due = True

            if digest_due and digest_pending:
                decision_status = "deliver"
                decision_reason = "Накопленный дайджест готов к отправке и не будет спамить отдельными сообщениями."
                state["last_status"] = "queued"
                alert_action = {
                    "action": "send",
                    "kind": "digest",
                    "reason": decision_reason,
                    "text": build_alert_message(
                        latest_version,
                        severity,
                        highlight_explanations,
                        decision_reason,
                        "digest",
                        digest_pending,
                        advisor_bridge,
                        ask_for_consent,
                        consent_request,
                    ),
                    "delivered_fingerprints": [item["fingerprint"] for item in digest_pending],
                    "consent_requested": ask_for_consent,
                    "reply_markup_json": json.dumps(consent_request["reply_markup"], ensure_ascii=False) if consent_request else "",
                }
            elif delivered_matches and not digest_pending:
                decision_status = "suppress"
                decision_reason = "Это состояние уже было доставлено раньше."
                state["last_status"] = "suppressed"
            else:
                decision_status = "queued"
                decision_reason = "Новое upstream-событие добавлено в очередь дайджеста; отдельное сообщение сейчас не отправляется."
                state["last_status"] = "queued"
        else:
            if not telegram_chat_id:
                decision_status = "investigate"
                decision_reason = "Telegram включён, но chat id определить не удалось."
                state["last_status"] = "investigate"
            elif delivered_matches:
                decision_status = "suppress"
                decision_reason = "Это состояние уже было отправлено в Telegram."
                state["last_status"] = "suppressed"
            else:
                decision_status = "deliver"
                decision_reason = "Найдено новое upstream-состояние; его нужно отправить в Telegram."
                state["last_status"] = "queued"
                alert_action = {
                    "action": "send",
                    "kind": "immediate",
                    "reason": decision_reason,
                    "text": build_alert_message(
                        latest_version,
                        severity,
                        highlight_explanations,
                        decision_reason,
                        "immediate",
                        [current_digest_entry],
                        advisor_bridge,
                        ask_for_consent,
                        consent_request,
                    ),
                    "delivered_fingerprints": [fingerprint],
                    "consent_requested": ask_for_consent,
                    "reply_markup_json": json.dumps(consent_request["reply_markup"], ensure_ascii=False) if consent_request else "",
                }
    else:
        if seen_matches:
            decision_status = "suppress"
            decision_reason = "Это состояние уже встречалось раньше."
            state["last_status"] = "suppressed"
        else:
            decision_status = "deliver"
            decision_reason = "Найдено новое upstream-состояние."
            state["last_status"] = "delivered"

run_note = f"{checked_at}: {decision_status} ({decision_reason})"
state["notes"] = compact_notes(previous_state.get("notes", []) + [run_note])

feature_explanation = [
    "Уровень важности показывает, это обычное обновление, важное изменение рабочего процесса или потенциально рискованный релиз.",
    "Режим дайджеста собирает несколько upstream-событий в одно сообщение и уменьшает шум в Telegram.",
    "Практические рекомендации строятся через advisor-слой проекта и передаются в Moltis-native advisory flow.",
]

followup_digest = {
    "mode": delivery_mode,
    "pending_count": len(state.get("digest_pending", [])),
    "last_sent_at": str(state.get("last_digest_sent_at", "")).strip(),
    "pending_items": state.get("digest_pending", []),
}
if delivery_mode == "digest" and state.get("digest_pending"):
    oldest_pending = parse_datetime(state["digest_pending"][0]["checked_at"])
    if oldest_pending is not None:
        followup_digest["next_send_after"] = (oldest_pending + dt.timedelta(hours=digest_window_hours)).isoformat().replace("+00:00", "Z")

pending_consent_state = None
if (
    telegram_enabled
    and telegram_consent_enabled
    and alert_action["action"] == "send"
    and alert_action["consent_requested"]
):
    if consent_request is not None:
        pending_consent_state = consent_request
    else:
        pending_consent_state = {
            "fingerprint": fingerprint,
            "chat_id": telegram_chat_id,
            "asked_at": checked_at,
            "expires_at": (checked_dt + dt.timedelta(hours=telegram_consent_window_hours)).isoformat().replace("+00:00", "Z"),
            "question": advisor_bridge["question"],
            "summary": advisor_bridge["summary"],
            "status": "pending",
            "recommendations": advisor_bridge["practical_recommendations"],
        }
    consent_status = "pending"
    if telegram_consent_router_ready:
        consent_reason = "После уведомления пользователь сможет нажать кнопку или отправить токенизированную команду; authoritative router зафиксирует ответ."
    else:
        consent_reason = "Interactive follow-up сейчас недоступен; watcher отправит только one-way alert."
    consent_expires_at = pending_consent_state["expires_at"]
elif consent_status == "pending" and pending_consent:
    consent_expires_at = str(pending_consent.get("expires_at", "")).strip()

report = {
    "checked_at": checked_at,
    "feature_explanation": feature_explanation,
    "snapshot": {
        "latest_version": latest_version,
        "release_status": release_status,
        "primary_source": {
            "name": "codex-changelog",
            "status": primary_status,
            "url": release_source_url,
            "notes": primary_notes,
        },
        "advisory_sources": advisory_sources,
        "advisory_items": advisory_items,
        "highlights": highlights,
        "highlight_explanations": highlight_explanations,
        "recent_releases": recent_releases,
    },
    "fingerprint": fingerprint,
    "severity": severity,
    "decision": {
        "status": decision_status,
        "reason": decision_reason,
        "changed": decision_changed,
        "delivery_mode": delivery_mode,
    },
    "advisor_bridge": advisor_bridge,
    "telegram_target": {
        "enabled": telegram_enabled,
        "consent_enabled": telegram_consent_enabled,
        "consent_router_enabled": telegram_consent_router_enabled,
        "consent_router_ready": telegram_consent_router_ready,
    },
    "followup": {
        "digest": followup_digest,
        "consent": {
            "status": consent_status,
            "reason": consent_reason,
            "expires_at": consent_expires_at,
            "question": advisor_bridge["question"],
            "router_mode": ("authoritative" if telegram_consent_router_ready else ("legacy" if telegram_allow_getupdates else "one_way_only")),
            "pending_state": pending_consent_state,
        },
    },
    "automation": {
        "alert": alert_action,
        "recommendations": recommendations_action,
    },
    "state": state,
    "notes": compact_notes(
        notes
        + [f"Режим: {'ручной' if mode == 'manual' else 'по расписанию'}."]
        + [f"Режим доставки: {'сразу' if delivery_mode == 'immediate' else 'дайджест'}."]
        + ([f"Определён идентификатор чата Telegram: {telegram_chat_id}."] if telegram_chat_id else [])
        + ([f"Использован файл окружения Telegram: {telegram_env_file}."] if telegram_env_file else [])
    ),
}

if telegram_chat_id:
    report["telegram_target"]["chat_id"] = telegram_chat_id
if telegram_silent:
    report["telegram_target"]["silent"] = True
if telegram_env_file:
    report["telegram_target"]["env_file"] = telegram_env_file

print(json.dumps(report, indent=2))
PY

    local alert_action alert_text alert_reply_markup telegram_output send_code resolved_reply_to alert_message_id consent_request_id
    alert_action="$(jq -r '.automation.alert.action // "skip"' "$REPORT_PATH")"
    if [[ "$alert_action" == "send" ]]; then
        alert_text="$(jq -r '.automation.alert.text // ""' "$REPORT_PATH")"
        alert_reply_markup="$(jq -r '.automation.alert.reply_markup_json // ""' "$REPORT_PATH")"
        consent_request_id="$(jq -r '.followup.consent.pending_state.request_id // ""' "$REPORT_PATH")"
        if [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            patch_report_alert_failure "не найден или не исполняем telegram sender script: ${TELEGRAM_SEND_SCRIPT}"
        elif [[ -z "$resolved_chat_id" ]]; then
            patch_report_alert_failure "не удалось определить telegram chat id"
        else
            if [[ "$telegram_consent_router_ready" == "true" && -n "$consent_request_id" ]]; then
                set +e
                persist_authoritative_consent_request
                send_code=$?
                set -e
                if [[ $send_code -ne 0 ]]; then
                    patch_report_alert_failure "не удалось записать authoritative consent request в shared store"
                    alert_action="skip"
                fi
            fi
        fi
        if [[ "$alert_action" == "send" && -x "$TELEGRAM_SEND_SCRIPT" && -n "$resolved_chat_id" ]]; then
            set +e
            telegram_output="$(run_telegram_sender "$resolved_chat_id" "$alert_text" "" "$alert_reply_markup" 2>&1)"
            send_code=$?
            set -e
            if [[ $send_code -eq 0 ]]; then
                alert_message_id="$(printf '%s' "$telegram_output" | jq -r '.result.message_id // ""' 2>/dev/null || true)"
                if [[ "$telegram_consent_router_ready" == "true" && -n "$consent_request_id" && -n "$alert_message_id" ]]; then
                    bind_authoritative_consent_message_id "$consent_request_id" "$alert_message_id" || true
                fi
                patch_report_alert_success "$resolved_chat_id" "$alert_message_id"
            else
                patch_report_alert_failure "${telegram_output:-telegram sender exited with status ${send_code}}"
            fi
        fi
    fi

    local recommendations_action recommendations_text recommendations_reply_to
    recommendations_action="$(jq -r '.automation.recommendations.action // "skip"' "$REPORT_PATH")"
    if [[ "$recommendations_action" == "send" ]]; then
        recommendations_text="$(jq -r '.automation.recommendations.text // ""' "$REPORT_PATH")"
        recommendations_reply_to="$(jq -r '(.automation.recommendations.reply_to_message_id // 0) | tostring' "$REPORT_PATH")"
        if [[ "$recommendations_reply_to" == "0" ]]; then
            recommendations_reply_to=""
        fi
        if [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            patch_report_recommendations_failure "не найден или не исполняем telegram sender script: ${TELEGRAM_SEND_SCRIPT}"
        elif [[ -z "$resolved_chat_id" ]]; then
            patch_report_recommendations_failure "не удалось определить telegram chat id"
        else
            set +e
            telegram_output="$(run_telegram_sender "$resolved_chat_id" "$recommendations_text" "$recommendations_reply_to" 2>&1)"
            send_code=$?
            set -e
            if [[ $send_code -eq 0 ]]; then
                patch_report_recommendations_success "$resolved_chat_id"
            else
                patch_report_recommendations_failure "${telegram_output:-telegram sender exited with status ${send_code}}"
            fi
        fi
    fi

    ensure_parent_dir "$STATE_FILE"
    jq '.state' "$REPORT_PATH" > "$STATE_FILE"
    attach_advisory_event_to_report

    render_summary > "$SUMMARY_PATH"

    if [[ -n "$JSON_OUT" ]]; then
        ensure_parent_dir "$JSON_OUT"
        cp "$REPORT_PATH" "$JSON_OUT"
    fi

    if [[ -n "$SUMMARY_OUT" ]]; then
        ensure_parent_dir "$SUMMARY_OUT"
        cp "$SUMMARY_PATH" "$SUMMARY_OUT"
    fi

    if [[ -n "$ADVISORY_EVENT_OUT" ]]; then
        ensure_parent_dir "$ADVISORY_EVENT_OUT"
        jq '.advisory_event' "$REPORT_PATH" > "$ADVISORY_EVENT_OUT"
    fi

    case "$STDOUT_FORMAT" in
        summary)
            cat "$SUMMARY_PATH"
            ;;
        json)
            cat "$REPORT_PATH"
            ;;
        none)
            ;;
    esac
}

main "$@"
