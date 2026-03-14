#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_RELEASE_URL="https://developers.openai.com/codex/changelog"
DEFAULT_ISSUE_SIGNALS_URL="https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"
DEFAULT_STATE_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-update-state.sh"
DEFAULT_PROFILE_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-update-profile.sh"
DEFAULT_STATE_FILE="${PROJECT_ROOT}/.tmp/current/moltis-codex-update-state.json"
DEFAULT_AUDIT_DIR="${PROJECT_ROOT}/.tmp/current/moltis-codex-update-audit"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"

MODE="${MOLTIS_CODEX_UPDATE_MODE:-manual}"
STATE_SCRIPT="${MOLTIS_CODEX_UPDATE_STATE_SCRIPT:-${DEFAULT_STATE_SCRIPT}}"
PROFILE_SCRIPT="${MOLTIS_CODEX_UPDATE_PROFILE_SCRIPT:-${DEFAULT_PROFILE_SCRIPT}}"
STATE_FILE="${MOLTIS_CODEX_UPDATE_STATE_FILE:-${DEFAULT_STATE_FILE}}"
AUDIT_DIR="${MOLTIS_CODEX_UPDATE_AUDIT_DIR:-${DEFAULT_AUDIT_DIR}}"
RELEASE_FILE="${MOLTIS_CODEX_UPDATE_RELEASE_FILE:-}"
RELEASE_URL="${MOLTIS_CODEX_UPDATE_RELEASE_URL:-${DEFAULT_RELEASE_URL}}"
ISSUE_SIGNALS_FILE="${MOLTIS_CODEX_UPDATE_ISSUE_SIGNALS_FILE:-}"
ISSUE_SIGNALS_URL="${MOLTIS_CODEX_UPDATE_ISSUE_SIGNALS_URL:-${DEFAULT_ISSUE_SIGNALS_URL}}"
INCLUDE_ISSUE_SIGNALS=false
PROFILE_FILE="${MOLTIS_CODEX_UPDATE_PROFILE_FILE:-}"
MAX_RELEASES="${MOLTIS_CODEX_UPDATE_MAX_RELEASES:-3}"
TELEGRAM_ENABLED="${MOLTIS_CODEX_UPDATE_TELEGRAM_ENABLED:-false}"
TELEGRAM_CHAT_ID="${MOLTIS_CODEX_UPDATE_TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENV_FILE="${MOLTIS_CODEX_UPDATE_TELEGRAM_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
TELEGRAM_SEND_SCRIPT="${MOLTIS_CODEX_UPDATE_TELEGRAM_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"
TELEGRAM_SILENT="${MOLTIS_CODEX_UPDATE_TELEGRAM_SILENT:-false}"
JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"

TEMP_DIR=""
REPORT_PATH=""
SUMMARY_PATH=""
RELEASE_SOURCE_ID=""
ISSUE_SOURCE_ID=""

declare -a WARNINGS=()

usage() {
    cat <<'EOF'
Usage:
  moltis-codex-update-run.sh [options]

Canonical Moltis-native runtime for checking Codex CLI upstream updates.

Options:
  --mode MODE                  manual|scheduler (default: manual)
  --state-file PATH            Skill state file
  --state-script PATH          State helper script
  --profile-script PATH        Profile helper script
  --audit-dir PATH             Audit mirror directory for run records
  --release-file PATH          Read official changelog from local file
  --release-url URL            Read official changelog from URL
  --include-issue-signals      Enrich context with advisory issue signals
  --issue-signals-file PATH    Read issue signals from local JSON file
  --issue-signals-url URL      Read issue signals from URL
  --profile-file PATH          Optional project profile JSON
  --max-releases N             Number of recent releases to normalize
  --telegram-enabled           Enable Telegram delivery for scheduler mode
  --telegram-chat-id CHAT_ID   Override Telegram chat id
  --telegram-env-file PATH     Env file used by telegram sender
  --telegram-send-script PATH  Telegram sender helper
  --telegram-silent            Send scheduler alerts silently
  --json-out PATH              Write JSON report to PATH
  --summary-out PATH           Write human-readable summary to PATH
  --stdout MODE                summary|json|none (default: summary)
  -h, --help                   Show help
EOF
}

cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

add_warning() {
    WARNINGS+=("$1")
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required dependency: $1"
}

ensure_parent_dir() {
    mkdir -p "$(dirname "$1")"
}

strip_wrapping_quotes() {
    local value="$1"
    if [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]]; then
        value="${value:1:${#value}-2}"
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

normalize_bool() {
    case "${1:-false}" in
        1|true|TRUE|yes|YES|on|ON) printf 'true\n' ;;
        0|false|FALSE|no|NO|off|OFF|'') printf 'false\n' ;;
        *) fail "Invalid boolean value: $1" ;;
    esac
}

resolve_telegram_chat_id() {
    local env_file="$1"
    local configured="" first_user=""

    if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
        printf '%s\n' "$TELEGRAM_CHAT_ID"
        return 0
    fi

    if [[ -n "$env_file" && -f "$env_file" ]]; then
        configured="$(read_env_value "$env_file" "MOLTIS_CODEX_UPDATE_TELEGRAM_CHAT_ID" || true)"
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

run_telegram_sender() {
    local chat_id="$1"
    local text="$2"
    local -a cmd=(
        "$TELEGRAM_SEND_SCRIPT"
        --chat-id "$chat_id"
        --text "$text"
        --json
    )

    if [[ "$TELEGRAM_SILENT" == "true" ]]; then
        cmd+=(--disable-notification)
    fi

    if [[ -n "$TELEGRAM_ENV_FILE" ]]; then
        MOLTIS_ENV_FILE="$TELEGRAM_ENV_FILE" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

fetch_source() {
    local kind="$1"
    local file_arg="$2"
    local url_arg="$3"
    local default_url="$4"
    local target="$5"
    local source_ref="$6"

    if [[ -n "$file_arg" ]]; then
        printf -v "$source_ref" 'file:%s' "$file_arg"
        if [[ -f "$file_arg" ]]; then
            cp "$file_arg" "$target"
            return 0
        fi
        add_warning "Не найден локальный источник ${kind}: ${file_arg}"
        return 1
    fi

    local source_url="${url_arg:-$default_url}"
    if [[ -z "$source_url" ]]; then
        add_warning "Для источника ${kind} не задан URL"
        return 1
    fi

    printf -v "$source_ref" 'url:%s' "$source_url"
    require_command curl
    if curl -fsSL --connect-timeout 20 --max-time 60 "$source_url" -o "$target" 2>/dev/null; then
        return 0
    fi

    add_warning "Не удалось получить источник ${kind}: ${source_url}"
    return 1
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
            --state-script)
                STATE_SCRIPT="${2:?missing value for --state-script}"
                shift 2
                ;;
            --profile-script)
                PROFILE_SCRIPT="${2:?missing value for --profile-script}"
                shift 2
                ;;
            --audit-dir)
                AUDIT_DIR="${2:?missing value for --audit-dir}"
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
            --profile-file)
                PROFILE_FILE="${2:?missing value for --profile-file}"
                shift 2
                ;;
            --max-releases)
                MAX_RELEASES="${2:?missing value for --max-releases}"
                shift 2
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
            --telegram-send-script)
                TELEGRAM_SEND_SCRIPT="${2:?missing value for --telegram-send-script}"
                shift 2
                ;;
            --telegram-silent)
                TELEGRAM_SILENT=true
                shift
                ;;
            --json-out)
                JSON_OUT="${2:?missing value for --json-out}"
                shift 2
                ;;
            --summary-out)
                SUMMARY_OUT="${2:?missing value for --summary-out}"
                shift 2
                ;;
            --stdout)
                STDOUT_FORMAT="${2:?missing value for --stdout}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown argument: $1"
                ;;
        esac
    done

    case "$MODE" in
        manual|scheduler) ;;
        *) fail "Invalid --mode: $MODE" ;;
    esac

    case "$STDOUT_FORMAT" in
        summary|json|none) ;;
        *) fail "Invalid --stdout mode: $STDOUT_FORMAT" ;;
    esac

    [[ "$MAX_RELEASES" =~ ^[1-9][0-9]*$ ]] || fail "--max-releases must be a positive integer"
    TELEGRAM_ENABLED="$(normalize_bool "$TELEGRAM_ENABLED")"
    TELEGRAM_SILENT="$(normalize_bool "$TELEGRAM_SILENT")"
    [[ -x "$STATE_SCRIPT" ]] || fail "State helper not found or not executable: $STATE_SCRIPT"
    [[ -x "$PROFILE_SCRIPT" ]] || fail "Profile helper not found or not executable: $PROFILE_SCRIPT"
}

load_profile_json() {
    if [[ -z "$PROFILE_FILE" ]]; then
        printf '{"status":"not_requested","ok":true,"profile":null,"errors":[]}\n'
        return 0
    fi

    local output status=0
    set +e
    output="$("$PROFILE_SCRIPT" load --file "$PROFILE_FILE" --json 2>/dev/null)"
    status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        jq '. + {status: "loaded"}' <<<"$output"
    else
        jq -n \
            --arg profile_path "$PROFILE_FILE" \
            --argjson payload "${output:-null}" '
            {
              status: "invalid",
              ok: false,
              profile_path: $profile_path,
              errors: (
                if ($payload | type) == "object" and ($payload.errors? | type) == "array"
                then $payload.errors
                else ["Project profile validation failed."]
                end
              ),
              profile: null
            }
        '
    fi
}

render_telegram_alert() {
    jq -r '
      def fmt_list(items):
        if (items | length) == 0 then "- нет"
        else items[] | "- \(.)"
        end;
      def fmt_recs(items):
        if (items | length) == 0 then "- нет"
        else items[] | "- \(.title_ru): \(.rationale_ru)"
        end;
      [
        "Обновление Codex CLI",
        "Последняя upstream-версия: \(.snapshot.latest_version)",
        "Важность: \(.decision.severity_ru)",
        "Почему это важно: \(.decision.why_it_matters_ru)",
        "",
        "Простыми словами:",
        (fmt_list(.snapshot.highlights_ru)),
        "",
        "Что стоит сделать:",
        (fmt_recs(.recommendation_bundle.items[:2]))
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

render_summary() {
    jq -r '
      def fmt_list(items):
        if (items | length) == 0 then "- нет"
        else items[] | "- \(.)"
        end;
      def fmt_recs(items):
        if (items | length) == 0 then "- нет"
        else items[] | "- \(.title_ru): \(.rationale_ru)"
        end;
      [
        "# Навык Moltis: обновления Codex CLI",
        "",
        "- Проверено: \(.checked_at)",
        "- Режим: \(.run_mode)",
        "- Последняя upstream-версия: \(.snapshot.latest_version)",
        "- Статус upstream: \(.snapshot.release_status_ru)",
        "- Решение: \(.decision.decision_ru)",
        "- Почему: \(.decision.why_it_matters_ru)",
        "- Профиль проекта: \(.profile.status_ru)",
        "- Доставка: \(.delivery.status)",
        "- Пояснение доставки: \(.delivery.reason)",
        "",
        "## Что изменилось",
        (fmt_list(.snapshot.highlights_ru)),
        "",
        "## Практические рекомендации",
        (fmt_recs(.recommendation_bundle.items)),
        "",
        "## Заметки",
        (fmt_list(.notes))
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

persist_audit_mirror() {
    local run_id="$1"
    local audit_written_at="$2"
    local audit_record_path audit_summary_path state_final

    [[ -n "$AUDIT_DIR" ]] || fail "Audit directory must not be empty"
    ensure_parent_dir "${AUDIT_DIR}/placeholder"
    audit_record_path="${AUDIT_DIR}/${run_id}.json"
    audit_summary_path="${AUDIT_DIR}/${run_id}.summary.md"

    "$STATE_SCRIPT" mark-audit \
        --state-file "$STATE_FILE" \
        --audit-record "$audit_record_path" \
        --audit-summary "$audit_summary_path" \
        --audit-written-at "$audit_written_at" \
        --json >/dev/null

    state_final="$("$STATE_SCRIPT" get --state-file "$STATE_FILE" --json)"
    jq \
        --arg audit_dir "$AUDIT_DIR" \
        --arg audit_record "$audit_record_path" \
        --arg audit_summary "$audit_summary_path" \
        --arg audit_written_at "$audit_written_at" \
        --argjson state "$state_final" \
        '
        .state = $state |
        .audit = {
          dir: $audit_dir,
          record_path: $audit_record,
          summary_path: $audit_summary,
          written_at: $audit_written_at
        }
        ' "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"

    cp "$REPORT_PATH" "$audit_record_path"
    cp "$SUMMARY_PATH" "$audit_summary_path"
}

main() {
    parse_args "$@"
    require_command jq
    require_command python3

    TEMP_DIR="$(mktemp -d)"
    REPORT_PATH="${TEMP_DIR}/report.json"
    SUMMARY_PATH="${TEMP_DIR}/summary.md"

    local release_source_path issue_signals_path release_ok=false issue_ok=false
    local state_before profile_payload state_after decision fingerprint latest_version delivery_status degraded_reason
    local resolved_chat_id="" alert_text="" send_output="" delivery_error="" message_id="" delivery_target="none"
    local send_status=0 primary_status="" state_alert_fingerprint="" effective_delivery_status=""
    local run_id="" audit_written_at=""
    release_source_path="${TEMP_DIR}/release-source.txt"
    issue_signals_path="${TEMP_DIR}/issue-signals.json"

    if fetch_source "официального changelog" "$RELEASE_FILE" "$RELEASE_URL" "$DEFAULT_RELEASE_URL" "$release_source_path" RELEASE_SOURCE_ID; then
        release_ok=true
    fi

    if [[ "$INCLUDE_ISSUE_SIGNALS" == "true" ]]; then
        if fetch_source "issue signals" "$ISSUE_SIGNALS_FILE" "$ISSUE_SIGNALS_URL" "$DEFAULT_ISSUE_SIGNALS_URL" "$issue_signals_path" ISSUE_SOURCE_ID; then
            issue_ok=true
        fi
    fi

    state_before="$("$STATE_SCRIPT" get --state-file "$STATE_FILE" --json)"
    profile_payload="$(load_profile_json)"

    python3 - "$release_source_path" "$issue_signals_path" "$release_ok" "$issue_ok" "$MODE" "$MAX_RELEASES" "$RELEASE_SOURCE_ID" "$ISSUE_SOURCE_ID" "$state_before" "$profile_payload" "$INCLUDE_ISSUE_SIGNALS" "$REPORT_PATH" <<'PY'
import hashlib
import html.parser
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

(
    release_path,
    issues_path,
    release_ok_raw,
    issue_ok_raw,
    mode,
    max_releases_raw,
    release_source_id,
    issue_source_id,
    state_raw,
    profile_raw,
    include_issue_signals_raw,
    report_path,
) = sys.argv[1:13]

release_ok = release_ok_raw == "true"
issue_ok = issue_ok_raw == "true"
include_issue_signals = include_issue_signals_raw == "true"
max_releases = int(max_releases_raw)
state = json.loads(state_raw)
profile_payload = json.loads(profile_raw)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def unique_preserve(items, limit=None):
    result = []
    seen = set()
    for item in items:
        if not item or item in seen:
            continue
        seen.add(item)
        result.append(item)
        if limit is not None and len(result) >= limit:
            break
    return result


class TextExtractor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "article", "div"}:
            self.parts.append("\n")

    def handle_data(self, data):
        stripped = data.strip()
        if stripped:
            self.parts.append(stripped)

    def text(self) -> str:
        text = "".join(self.parts)
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        return "\n".join(line for line in lines if line)


def parse_release_source(raw: str, limit: int) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []

    if stripped[0] in "[{":
        data = json.loads(stripped)
        releases = data.get("releases", data if isinstance(data, list) else [])
        normalized = []
        for item in releases:
            if not isinstance(item, dict):
                continue
            normalized.append(
                {
                    "version": str(item.get("version", "")).strip(),
                    "published_at": str(item.get("published_at", "")).strip(),
                    "changes": [str(change).strip() for change in item.get("changes", []) if str(change).strip()],
                }
            )
        return [item for item in normalized if item["version"]][:limit]

    parser = TextExtractor()
    parser.feed(stripped)
    lines = parser.text().splitlines()
    version_pattern = re.compile(r"Codex CLI(?: Release:)?\s*(\d+\.\d+\.\d+)")
    date_pattern = re.compile(r"^\d{4}-\d{2}-\d{2}$")

    releases = []
    current = None
    pending_date = ""
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
        cleaned.append(
            {
                "version": item["version"],
                "published_at": item["published_at"],
                "changes": unique_preserve(item["changes"]),
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
        if not isinstance(item, dict) or item.get("pull_request"):
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


def explain_change(change_text: str, advisory: bool = False):
    text = change_text.lower()
    rules = [
        ("critical", ["breaking", "migration", "deprecated", "security", "vulnerability", "incompatible"], "Есть риск несовместимости, миграции или усиления требований безопасности.", ["breaking", "security"]),
        ("important", ["approval", "permission profile", "sandbox"], "Изменения затрагивают подтверждение действий и sandbox-ограничения.", ["approval", "sandbox"]),
        ("important", ["worktree", "/new", "workspace"], "Изменения затрагивают работу с рабочими деревьями и отдельными ветками.", ["worktree"]),
        ("important", ["multi-agent", "multi agent", "resume", "session"], "Изменения затрагивают восстановление сессий и работу с несколькими агентами.", ["agents"]),
        ("important", ["js_repl", "js repl", "repl"], "Изменения затрагивают сценарии с js_repl и встроенными вычислениями.", ["js-repl"]),
        ("important", ["skill", "mcp", "plugin"], "Изменения затрагивают навыки, MCP-интеграции или инструментальный слой Moltis.", ["skills", "mcp"]),
        ("info", ["docs", "documentation", "example"], "Обновились документы или примеры использования Codex CLI.", ["docs"]),
    ]

    for level, keywords, explanation, tags in rules:
        if any(keyword in text for keyword in keywords):
            if advisory and level == "info":
                return ("important", "Есть дополнительный сигнал из issue tracker Codex CLI; его стоит проверить вместе с changelog.", ["advisory"])
            return level, explanation, tags

    if advisory:
        return ("important", "Есть дополнительный сигнал из issue tracker Codex CLI; он усиливает необходимость проверки.", ["advisory"])
    return ("info", "В changelog появилось новое изменение; детали сохранены в полном отчёте.", ["generic"])


def build_highlight_explanations(highlights: list[str], advisories: list[dict]):
    explanations = []
    tags = []
    rank = {"info": 1, "important": 2, "critical": 3}
    strongest = "info"

    for change in highlights[:5]:
        level, explanation, change_tags = explain_change(change)
        explanations.append(explanation)
        tags.extend(change_tags)
        if rank[level] > rank[strongest]:
            strongest = level

    for advisory in advisories[:3]:
        level, explanation, change_tags = explain_change(advisory["title"], advisory=True)
        explanations.append(explanation)
        tags.extend(change_tags)
        if rank[level] > rank[strongest]:
            strongest = level

    return unique_preserve(explanations, 5), unique_preserve(tags, 10), strongest


def build_severity(primary_status: str, tags: list[str], latest_version: str):
    if primary_status != "ok":
        return {
            "level": "investigate",
            "level_ru": "нужно проверить",
            "reason": "Нельзя надёжно оценить обновление, пока официальный источник недоступен или сломан.",
        }
    if "breaking" in tags or "security" in tags:
        return {
            "level": "critical",
            "level_ru": "критично",
            "reason": f"Версия {latest_version} выглядит рискованной: есть признаки несовместимости, миграции или усиления ограничений.",
        }
    if any(tag in tags for tag in ["approval", "sandbox", "worktree", "agents", "js-repl", "advisory", "skills", "mcp"]):
        return {
            "level": "important",
            "level_ru": "высокая",
            "reason": f"Версия {latest_version} затрагивает сценарии Moltis и Codex, которые используются регулярно.",
        }
    return {
        "level": "info",
        "level_ru": "обычная",
        "reason": f"В версии {latest_version} есть новые возможности без признаков срочного риска.",
    }


def build_fingerprint(latest_version: str, highlights: list[str], primary_status: str, advisories: list[dict]):
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


def build_generic_recommendations(latest_version: str, tags: list[str]):
    items = []
    if any(tag in tags for tag in ["agents", "worktree", "approval", "sandbox"]):
        items.append(
            {
                "title_ru": "Проверить рабочие сценарии Moltis и Codex",
                "rationale_ru": f"Версия {latest_version} затрагивает привычные рабочие сценарии, поэтому стоит быстро сверить ожидания и текущие инструкции.",
                "impacted_paths": ["docs/CODEX-OPERATING-MODEL.md", "AGENTS.md"],
                "next_steps_ru": [
                    "Сверить changelog с текущими операционными правилами.",
                    "Проверить сценарии worktree, resume и approval-boundaries.",
                ],
            }
        )
    if any(tag in tags for tag in ["docs", "skills", "mcp", "js-repl"]):
        items.append(
            {
                "title_ru": "Обновить примеры и guidance",
                "rationale_ru": "Новые возможности стоит быстро отразить в документации и практических подсказках Moltis.",
                "impacted_paths": ["docs/", "skills/"],
                "next_steps_ru": [
                    "Проверить примеры использования в документации.",
                    "Уточнить ограничения и новые возможности в skill guidance.",
                ],
            }
        )
    if not items:
        items.append(
            {
                "title_ru": "Просмотреть changelog и оценить полезность обновления",
                "rationale_ru": "Даже без явного риска полезно проверить, появились ли новые возможности для рабочих процессов Moltis.",
                "impacted_paths": [],
                "next_steps_ru": [
                    "Просмотреть ключевые пункты changelog.",
                    "Зафиксировать, нужно ли возвращаться к обновлению позже.",
                ],
            }
        )
    return items


def build_profile_recommendations(profile: dict, highlights: list[str], advisories: list[dict]):
    haystack = " ".join(highlights + [item["title"] for item in advisories]).lower()
    templates = {
        template["id"]: template
        for template in profile.get("recommendation_templates", [])
        if isinstance(template, dict) and template.get("id")
    }
    items = []
    impacted_paths = []
    for rule in profile.get("relevance_rules", []):
        keywords = [keyword.lower() for keyword in rule.get("keywords", [])]
        if not any(keyword in haystack for keyword in keywords):
            continue
        template = templates.get(rule.get("recommendation_template_id", ""))
        impacted = unique_preserve(rule.get("priority_paths", []) + (template.get("impacted_paths", []) if template else []))
        impacted_paths.extend(impacted)
        next_steps = unique_preserve(rule.get("next_steps_ru", []) + (template.get("next_steps_ru", []) if template else []))
        rationale_parts = []
        if template and template.get("rationale_ru"):
            rationale_parts.append(template["rationale_ru"])
        rationale_parts.append(rule["rationale_ru"])
        items.append(
            {
                "title_ru": (template.get("title_ru") if template else rule.get("title_ru")) or f"Проверить правило {rule['id']} для проекта {profile['project_name']}",
                "rationale_ru": " ".join(part.strip() for part in rationale_parts if part and part.strip()),
                "impacted_paths": impacted,
                "next_steps_ru": next_steps or [
                    "Сверить новое изменение Codex CLI с этим правилом профиля.",
                    "Уточнить, нужны ли project-specific правки или документация.",
                ],
                "source_rule_id": rule["id"],
                "source_template_id": template.get("id", "") if template else "",
            }
        )
    if items:
        return items, unique_preserve(impacted_paths)

    fallback = profile.get("fallback_recommendation") or {}
    fallback_item = {
        "title_ru": fallback.get("title_ru") or f"Сверить обновление Codex CLI с профилем проекта {profile['project_name']}",
        "rationale_ru": fallback.get("rationale_ru") or (
            f"Профиль проекта {profile['project_name']} загружен, поэтому даже без прямого совпадения стоит быстро оценить changelog в контексте traits и рабочих правил."
        ),
        "impacted_paths": unique_preserve(fallback.get("impacted_paths", [])),
        "next_steps_ru": fallback.get("next_steps_ru") or [
            "Сверить changelog с traits проекта и его операционными правилами.",
            "Зафиксировать, нужен ли follow-up по docs, skills или workflow.",
        ],
        "source_rule_id": "",
        "source_template_id": "",
    }
    return [fallback_item], fallback_item["impacted_paths"]


release_text = pathlib.Path(release_path).read_text(encoding="utf-8") if release_ok else ""
issue_text = pathlib.Path(issues_path).read_text(encoding="utf-8") if issue_ok else ""
releases = parse_release_source(release_text, max_releases) if release_ok else []
advisories = parse_issue_signals(issue_text) if include_issue_signals and issue_ok else []
primary_status = "ok" if releases else "investigate"
latest_release = releases[0] if releases else {"version": "unknown", "published_at": "", "changes": []}
latest_version = latest_release["version"]
highlights = latest_release["changes"][:5] if latest_release["changes"] else ([f"Опубликован релиз {latest_version}."] if latest_version != "unknown" else [])
highlight_explanations, tags, strongest = build_highlight_explanations(highlights, advisories)
severity = build_severity(primary_status, tags, latest_version)
fingerprint = build_fingerprint(latest_version, highlights, primary_status, advisories)
release_status = "known" if state.get("last_seen_fingerprint", "") == fingerprint else ("new" if primary_status == "ok" else "investigate")

if primary_status != "ok":
    decision = "investigate"
    decision_ru = "нужно проверить"
    summary_ru = "Не удалось надёжно прочитать официальный changelog Codex CLI."
    why_it_matters_ru = severity["reason"]
elif release_status == "known":
    decision = "ignore"
    decision_ru = "без нового события"
    summary_ru = "С прошлой проверки новых upstream-изменений не появилось."
    why_it_matters_ru = "Фингерпринт upstream не изменился, поэтому новый alert не нужен."
elif severity["level"] in {"critical", "important"}:
    decision = "upgrade-now"
    decision_ru = "разобрать сейчас"
    summary_ru = f"Найдена новая upstream-версия Codex CLI {latest_version}."
    why_it_matters_ru = severity["reason"]
else:
    decision = "upgrade-later"
    decision_ru = "можно разобрать позже"
    summary_ru = f"Вышла новая upstream-версия Codex CLI {latest_version} без признаков срочности."
    why_it_matters_ru = severity["reason"]

profile_status = profile_payload.get("status", "not_requested")
profile = profile_payload.get("profile")
recommendation_items = []
recommendation_paths = []
profile_source = "generic"

if profile_status == "loaded" and isinstance(profile, dict):
    recommendation_items, recommendation_paths = build_profile_recommendations(profile, highlights, advisories)
    if recommendation_items:
        profile_source = f"profile:{profile['profile_id']}"

if not recommendation_items:
    recommendation_items = build_generic_recommendations(latest_version, tags)
    recommendation_paths = unique_preserve([path for item in recommendation_items for path in item.get("impacted_paths", [])])

notes = []
if profile_status == "invalid":
    notes.extend(profile_payload.get("errors", []))
if not advisories and include_issue_signals:
    notes.append("Issue signals не добавили новых подтверждённых данных.")
if primary_status != "ok":
    notes.append("Официальный источник требует проверки или адаптации парсинга.")

delivery_status = "not_attempted"
delivery_reason = "Этот implementation slice пока закрывает on-demand skill path без доставки."
if mode == "scheduler":
    delivery_status = "deferred"
    delivery_reason = "Scheduler delivery и duplicate suppression будут включены в следующем implementation slice."

report = {
    "schema_version": "moltis-codex-update-run/v1",
    "run_id": "moltis-codex-update-" + hashlib.sha256(f"{fingerprint}:{mode}:{now_iso()}".encode("utf-8")).hexdigest()[:16],
    "checked_at": now_iso(),
    "run_mode": mode,
    "sources": {
        "release_source": release_source_id,
        "issue_signals_enabled": include_issue_signals,
        "issue_signals_source": issue_source_id,
    },
    "snapshot": {
        "latest_version": latest_version,
        "published_at": latest_release.get("published_at", ""),
        "primary_status": primary_status,
        "release_status": release_status,
        "release_status_ru": {
            "new": "новое состояние",
            "known": "без изменений",
            "investigate": "нужно проверить",
        }.get(release_status, release_status),
        "highlights": highlights,
        "highlights_ru": highlight_explanations,
        "issue_signals": advisories,
        "fingerprint": fingerprint,
    },
    "decision": {
        "decision": decision,
        "decision_ru": decision_ru,
        "severity": severity["level"],
        "severity_ru": severity["level_ru"],
        "summary_ru": summary_ru,
        "why_it_matters_ru": why_it_matters_ru,
        "project_specific": profile_source != "generic",
        "recommendation_count": len(recommendation_items),
    },
    "recommendation_bundle": {
        "headline_ru": "Практические рекомендации по обновлению Codex CLI",
        "summary_ru": "Moltis сам оценил upstream-сигнал и подготовил следующие шаги.",
        "items": recommendation_items,
        "impacted_paths": recommendation_paths,
        "profile_source": profile_source,
    },
    "profile": {
        "status": profile_status,
        "status_ru": {
            "not_requested": "не запрошен",
            "loaded": "загружен",
            "invalid": "ошибка профиля",
        }.get(profile_status, profile_status),
        "profile_id": profile.get("profile_id", "") if isinstance(profile, dict) else "",
        "project_name": profile.get("project_name", "") if isinstance(profile, dict) else "",
        "traits": profile.get("traits", []) if isinstance(profile, dict) else [],
        "errors": profile_payload.get("errors", []),
    },
    "state": state,
    "delivery": {
        "status": delivery_status,
        "reason": delivery_reason,
    },
    "notes": notes,
}

pathlib.Path(report_path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

    fingerprint="$(jq -r '.snapshot.fingerprint' "$REPORT_PATH")"
    run_id="$(jq -r '.run_id' "$REPORT_PATH")"
    latest_version="$(jq -r '.snapshot.latest_version' "$REPORT_PATH")"
    decision="$(jq -r '.decision.decision' "$REPORT_PATH")"
    primary_status="$(jq -r '.snapshot.primary_status' "$REPORT_PATH")"
    state_alert_fingerprint="$(jq -r '.last_alert_fingerprint // ""' <<<"$state_before")"
    delivery_status="not-attempted"
    degraded_reason="Ручной запуск не отправляет Telegram-уведомление автоматически."
    delivery_error=""
    message_id=""

    if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
        resolved_chat_id="$(resolve_telegram_chat_id "$TELEGRAM_ENV_FILE" || true)"
    fi

    if [[ "$MODE" == "scheduler" ]]; then
        delivery_target="telegram"
        if [[ "$primary_status" != "ok" ]]; then
            delivery_status="deferred"
            degraded_reason="Официальный источник не дал надёжного результата; автоматическая отправка отложена."
        elif [[ "$state_alert_fingerprint" == "$fingerprint" ]]; then
            delivery_status="suppressed"
            degraded_reason="Этот upstream fingerprint уже был отправлен ранее; повторный alert подавлен."
        elif [[ "$TELEGRAM_ENABLED" != "true" ]]; then
            delivery_status="not-configured"
            degraded_reason="Telegram delivery отключён для Moltis-native scheduler path."
        elif [[ -z "$resolved_chat_id" ]]; then
            delivery_status="not-configured"
            degraded_reason="Не удалось определить chat_id для Telegram delivery."
        elif [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            delivery_status="failed"
            delivery_error="Не найден или не исполняется telegram sender script."
            degraded_reason="Автоматическая отправка не выполнена: недоступен telegram sender."
        else
            alert_text="$(render_telegram_alert)"
            set +e
            send_output="$(run_telegram_sender "$resolved_chat_id" "$alert_text" 2>&1)"
            send_status=$?
            set -e

            if [[ $send_status -eq 0 ]] && jq -e '.ok == true' >/dev/null 2>&1 <<<"$send_output"; then
                delivery_status="sent"
                degraded_reason="Moltis отправил одно уведомление для нового upstream fingerprint."
                message_id="$(jq -r '.result.message_id // ""' <<<"$send_output")"
                if [[ "$message_id" == "null" ]]; then
                    message_id=""
                fi
            else
                delivery_status="failed"
                degraded_reason="Автоматическая отправка в Telegram завершилась ошибкой."
                if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$send_output"; then
                    delivery_error="$(jq -r '.description // .error // empty' <<<"$send_output")"
                fi
                if [[ -z "$delivery_error" ]]; then
                    delivery_error="$(printf '%s' "$send_output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
                fi
            fi
        fi
    fi

    jq \
        --arg status "$delivery_status" \
        --arg reason "$degraded_reason" \
        --arg target "$delivery_target" \
        --arg chat_id "$resolved_chat_id" \
        --arg delivery_error "$delivery_error" \
        --argjson message_id "${message_id:-0}" \
        '
        .delivery = {
          status: $status,
          reason: $reason,
          target: $target,
          chat_id: $chat_id,
          message_id: (if $message_id > 0 then $message_id else 0 end),
          error: $delivery_error
        }
        ' "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"

    "$STATE_SCRIPT" update \
        --state-file "$STATE_FILE" \
        --run-mode "$MODE" \
        --fingerprint "$fingerprint" \
        --latest-version "$latest_version" \
        --decision "$decision" \
        --run-id "$run_id" \
        --delivery-status "$delivery_status" \
        --delivery-error "$delivery_error" \
        --degraded-reason "$degraded_reason" \
        --json >/dev/null

    if [[ "$MODE" == "scheduler" ]]; then
        effective_delivery_status="$delivery_status"
        case "$effective_delivery_status" in
            sent|suppressed)
                if [[ -n "$message_id" ]]; then
                    "$STATE_SCRIPT" mark-delivery \
                        --state-file "$STATE_FILE" \
                        --delivery-status "$effective_delivery_status" \
                        --alert-fingerprint "$fingerprint" \
                        --delivery-error "$delivery_error" \
                        --message-id "$message_id" \
                        --json >/dev/null
                else
                    "$STATE_SCRIPT" mark-delivery \
                        --state-file "$STATE_FILE" \
                        --delivery-status "$effective_delivery_status" \
                        --alert-fingerprint "$fingerprint" \
                        --delivery-error "$delivery_error" \
                        --json >/dev/null
                fi
                ;;
            failed|deferred|not-configured|not-attempted)
                "$STATE_SCRIPT" mark-delivery \
                    --state-file "$STATE_FILE" \
                    --delivery-status "$effective_delivery_status" \
                    --delivery-error "$delivery_error" \
                    --json >/dev/null
                ;;
        esac
    fi

    state_after="$("$STATE_SCRIPT" get --state-file "$STATE_FILE" --json)"
    jq --argjson state "$state_after" --argjson notes "$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s '. | map(select(length > 0))')" \
        '.state = $state | .notes = ((.notes // []) + $notes)' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"

    render_summary > "$SUMMARY_PATH"
    audit_written_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    persist_audit_mirror "$run_id" "$audit_written_at"

    if [[ -n "$JSON_OUT" ]]; then
        ensure_parent_dir "$JSON_OUT"
        cp "$REPORT_PATH" "$JSON_OUT"
    fi
    if [[ -n "$SUMMARY_OUT" ]]; then
        ensure_parent_dir "$SUMMARY_OUT"
        cp "$SUMMARY_PATH" "$SUMMARY_OUT"
    fi

    case "$STDOUT_FORMAT" in
        summary)
            cat "$SUMMARY_PATH"
            ;;
        json)
            cat "$REPORT_PATH"
            ;;
        none) ;;
    esac
}

main "$@"
