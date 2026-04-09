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
WATCHER_REPORT_HELPER="${PROJECT_ROOT}/scripts/codex-cli-upstream-watcher-report.py"
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
TELEGRAM_CONSENT_ENABLED="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ENABLED:-false}"
TELEGRAM_CONSENT_WINDOW_HOURS="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_WINDOW_HOURS:-72}"
TELEGRAM_CONSENT_ROUTER_ENABLED="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CONSENT_ROUTER_ENABLED:-false}"
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
  --telegram-consent-disabled    Legacy compatibility no-op; старый consent UX уже выведен из эксплуатации
  --telegram-consent-window-hours N Legacy compatibility no-op
  --telegram-consent-router-disabled Legacy compatibility no-op
  --telegram-consent-store-script PATH Legacy compatibility no-op
  --telegram-consent-store-dir PATH Legacy compatibility no-op
  --telegram-updates-file PATH   Legacy compatibility no-op
  --telegram-allow-getupdates    Legacy compatibility no-op; old Bot API polling path retired
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

    if [[ "$TELEGRAM_CONSENT_ENABLED" == "true" || "$TELEGRAM_CONSENT_ROUTER_ENABLED" == "true" || "$TELEGRAM_ALLOW_GETUPDATES" == "true" || "$TELEGRAM_COMMAND_HOOK_READY" == "true" ]]; then
        add_warning "Interactive Telegram consent UX retired in watcher: official Moltis docs keep Telegram without interactive components, and MessageReceived/Command hooks stay read-only. Watcher sends only one-way alerts."
    fi
    TELEGRAM_CONSENT_ENABLED="false"
    TELEGRAM_CONSENT_ROUTER_ENABLED="false"
    TELEGRAM_ALLOW_GETUPDATES="false"
    TELEGRAM_COMMAND_HOOK_READY="false"

    if [[ "$ADVISOR_BRIDGE_ENABLED" == "true" ]]; then
        advisor_bridge_path="$(build_advisor_bridge "$release_source_path" "$issue_source_path" || true)"
    fi

    if [[ ! -f "$WATCHER_REPORT_HELPER" ]]; then
        printf 'Не найден helper рендеринга watcher report: %s\n' "$WATCHER_REPORT_HELPER" >&2
        exit 2
    fi

    python3 "$WATCHER_REPORT_HELPER" \
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
        > "$REPORT_PATH"

    local alert_action alert_text alert_reply_markup telegram_output send_code resolved_reply_to alert_message_id
    alert_action="$(jq -r '.automation.alert.action // "skip"' "$REPORT_PATH")"
    if [[ "$alert_action" == "send" ]]; then
        alert_text="$(jq -r '.automation.alert.text // ""' "$REPORT_PATH")"
        alert_reply_markup="$(jq -r '.automation.alert.reply_markup_json // ""' "$REPORT_PATH")"
        if [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            patch_report_alert_failure "не найден или не исполняем telegram sender script: ${TELEGRAM_SEND_SCRIPT}"
        elif [[ -z "$resolved_chat_id" ]]; then
            patch_report_alert_failure "не удалось определить telegram chat id"
        fi
        if [[ "$alert_action" == "send" && -x "$TELEGRAM_SEND_SCRIPT" && -n "$resolved_chat_id" ]]; then
            set +e
            telegram_output="$(run_telegram_sender "$resolved_chat_id" "$alert_text" "" "$alert_reply_markup" 2>&1)"
            send_code=$?
            set -e
            if [[ $send_code -eq 0 ]]; then
                alert_message_id="$(printf '%s' "$telegram_output" | jq -r '.result.message_id // ""' 2>/dev/null || true)"
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
