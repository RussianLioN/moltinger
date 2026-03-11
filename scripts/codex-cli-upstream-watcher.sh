#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_RELEASE_URL="https://developers.openai.com/codex/changelog"
DEFAULT_ISSUE_SIGNALS_URL="https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"
DEFAULT_STATE_FILE="${PROJECT_ROOT}/.tmp/current/codex-cli-upstream-watcher-state.json"
DEFAULT_TELEGRAM_SEND_SCRIPT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"

MODE="${CODEX_UPSTREAM_WATCHER_MODE:-manual}"
STATE_FILE="${CODEX_UPSTREAM_WATCHER_STATE_FILE:-${DEFAULT_STATE_FILE}}"
JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"

RELEASE_FILE="${CODEX_UPSTREAM_WATCHER_RELEASE_FILE:-}"
RELEASE_URL="${CODEX_UPSTREAM_WATCHER_RELEASE_URL:-${DEFAULT_RELEASE_URL}}"
INCLUDE_ISSUE_SIGNALS=false
ISSUE_SIGNALS_FILE="${CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_FILE:-}"
ISSUE_SIGNALS_URL="${CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_URL:-${DEFAULT_ISSUE_SIGNALS_URL}}"
MAX_RELEASES="${CODEX_UPSTREAM_WATCHER_MAX_RELEASES:-3}"

TELEGRAM_ENABLED="${CODEX_UPSTREAM_WATCHER_TELEGRAM_ENABLED:-false}"
TELEGRAM_CHAT_ID="${CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENV_FILE="${CODEX_UPSTREAM_WATCHER_TELEGRAM_ENV_FILE:-${MOLTIS_ENV_FILE:-}}"
TELEGRAM_SILENT=false
TELEGRAM_SEND_SCRIPT="${CODEX_UPSTREAM_WATCHER_TELEGRAM_SEND_SCRIPT:-${DEFAULT_TELEGRAM_SEND_SCRIPT}}"

TEMP_DIR=""
REPORT_PATH=""
SUMMARY_PATH=""
FETCH_SOURCE_ID=""

declare -a WARNINGS=()

usage() {
    cat <<'USAGE'
Usage: codex-cli-upstream-watcher.sh [options]

Watch official Codex upstream sources, compute a stable upstream fingerprint, and
optionally send one Telegram alert per new fingerprint.

Options:
  --mode MODE                Run mode: manual|scheduler (default: manual)
  --state-file PATH          Persist watcher state to PATH
  --json-out PATH            Write the machine-readable watcher report to PATH
  --summary-out PATH         Write the human-readable summary to PATH
  --stdout MODE              stdout mode: summary|json|none (default: summary)
  --release-file PATH        Read the primary changelog source from a local file
  --release-url URL          Read the primary changelog source from URL
  --max-releases N           Maximum recent releases to scan from the primary source
  --include-issue-signals    Include advisory issue-signal intake
  --issue-signals-file PATH  Read issue-signal JSON from a local file
  --issue-signals-url URL    Read issue-signal JSON from URL
  --telegram-enabled         Enable Telegram delivery for scheduler runs
  --telegram-chat-id ID      Explicit Telegram chat target
  --telegram-env-file PATH   Env file used by telegram-bot-send.sh
  --telegram-silent          Send Telegram messages silently
  --telegram-send-script PATH Override telegram sender script path
  -h, --help                 Show this help text

Environment overrides:
  CODEX_UPSTREAM_WATCHER_MODE
  CODEX_UPSTREAM_WATCHER_STATE_FILE
  CODEX_UPSTREAM_WATCHER_RELEASE_FILE
  CODEX_UPSTREAM_WATCHER_RELEASE_URL
  CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_FILE
  CODEX_UPSTREAM_WATCHER_ISSUE_SIGNALS_URL
  CODEX_UPSTREAM_WATCHER_MAX_RELEASES
  CODEX_UPSTREAM_WATCHER_TELEGRAM_ENABLED
  CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID
  CODEX_UPSTREAM_WATCHER_TELEGRAM_ENV_FILE
  CODEX_UPSTREAM_WATCHER_TELEGRAM_SEND_SCRIPT
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
        printf 'Missing required dependency: %s\n' "$name" >&2
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
            printf 'Invalid boolean value: %s\n' "$1" >&2
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
        add_warning "${kind} source file not found: ${file_arg}"
        return 1
    fi

    local source_url="${url_arg:-$default_url}"
    if [[ -z "$source_url" ]]; then
        add_warning "No ${kind} source URL configured"
        return 1
    fi

    FETCH_SOURCE_ID="url:${source_url}"
    require_command curl
    if curl -fsSL --connect-timeout 20 --max-time 60 "$source_url" -o "$target" 2>/dev/null; then
        return 0
    fi

    add_warning "Failed to fetch ${kind} source: ${source_url}"
    return 1
}

render_summary() {
    jq -r '
      def fmt_list(items):
        if (items | length) == 0 then "- none"
        else items[] | "- \(.)"
        end;
      def fmt_source(source):
        [
          "- \(source.name): \(source.status)",
          (if (source.url // "") != "" then "  url: \(source.url)" else empty end),
          (if (source.notes | length) > 0 then "  notes:" else empty end),
          (source.notes[]? | "    - \(.)")
        ];

      [
        "# Codex Upstream Watcher",
        "",
        "- Checked at: \(.checked_at)",
        "- Latest version: \(.snapshot.latest_version)",
        "- Freshness: \(.snapshot.release_status)",
        "- Decision: \(.decision.status)",
        "- Why: \(.decision.reason)",
        "- Telegram enabled: \(.telegram_target.enabled)",
        (if (.telegram_target.chat_id // "") != "" then "- Telegram chat: \(.telegram_target.chat_id)" else empty end),
        "",
        "## Highlights",
        (fmt_list(.snapshot.highlights)),
        "",
        "## Sources",
        (fmt_source(.snapshot.primary_source)),
        (if (.snapshot.advisory_sources | length) > 0 then "" else empty end),
        (.snapshot.advisory_sources[]? | fmt_source(.)),
        "",
        "## Watcher Notes",
        (fmt_list(.notes)),
        "",
        "## Persisted State",
        "- Last status: \(.state.last_status)",
        (if (.state.last_seen_fingerprint // "") != "" then "- Last seen fingerprint: \(.state.last_seen_fingerprint)" else empty end),
        (if (.state.last_delivered_fingerprint // "") != "" then "- Last delivered fingerprint: \(.state.last_delivered_fingerprint)" else empty end),
        (if (.state.last_checked_at // "") != "" then "- Last checked at: \(.state.last_checked_at)" else empty end)
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

build_telegram_message() {
    jq -r '
      def first_or_none(items):
        if (items | length) == 0 then "- none"
        else items[] | "- \(.)"
        end;

      [
        "Codex CLI upstream watcher",
        "Latest version: \(.snapshot.latest_version)",
        "Freshness: \(.snapshot.release_status)",
        "Decision: \(.decision.reason)",
        "Highlights:",
        (first_or_none(.snapshot.highlights[:4]))
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

run_telegram_sender() {
    local chat_id="$1"
    local text="$2"
    local -a cmd=(
        "$TELEGRAM_SEND_SCRIPT"
        --chat-id "$chat_id"
        --text "$text"
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

patch_report_with_telegram_success() {
    local chat_id="$1"
    jq \
        --arg chat_id "$chat_id" \
        '
        .notes += ["Telegram alert sent successfully."] |
        .state.notes = ((.state.notes + ["Telegram alert delivered to " + $chat_id + "."]) | .[-8:]) |
        .telegram_target.chat_id = $chat_id
        ' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

patch_report_with_telegram_failure() {
    local previous_delivered="$1"
    local failure_message="$2"

    jq \
        --arg previous_delivered "$previous_delivered" \
        --arg failure_message "$failure_message" \
        '
        .decision.status = "retry" |
        .decision.reason = "Telegram delivery failed; the upstream fingerprint remains retryable." |
        .state.last_status = "failed" |
        .notes += ["Telegram delivery failed: " + $failure_message] |
        .state.notes = ((.state.notes + ["Telegram delivery failed: " + $failure_message]) | .[-8:]) |
        (
          if $previous_delivered == "" then
            .state |= del(.last_delivered_fingerprint)
          else
            .state.last_delivered_fingerprint = $previous_delivered
          end
        )
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
            printf 'Invalid --mode value: %s\n' "$MODE" >&2
            exit 2
            ;;
    esac

    case "$STDOUT_FORMAT" in
        summary|json|none) ;;
        *)
            printf 'Invalid --stdout mode: %s\n' "$STDOUT_FORMAT" >&2
            exit 2
            ;;
    esac

    TELEGRAM_ENABLED="$(normalize_bool "$TELEGRAM_ENABLED")"

    if ! [[ "$MAX_RELEASES" =~ ^[1-9][0-9]*$ ]]; then
        printf '--max-releases must be a positive integer\n' >&2
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

    local release_source_path issue_source_path
    release_source_path="${TEMP_DIR}/release-source"
    issue_source_path="${TEMP_DIR}/issue-source"

    local release_source_id issue_source_id previous_delivered resolved_chat_id
    release_source_id=""
    issue_source_id=""
    previous_delivered=""
    resolved_chat_id=""

    fetch_source "release" "$RELEASE_FILE" "$RELEASE_URL" "$DEFAULT_RELEASE_URL" "$release_source_path" || true
    release_source_id="$FETCH_SOURCE_ID"

    if [[ "$INCLUDE_ISSUE_SIGNALS" == "true" ]]; then
        fetch_source "issue-signal" "$ISSUE_SIGNALS_FILE" "$ISSUE_SIGNALS_URL" "$DEFAULT_ISSUE_SIGNALS_URL" "$issue_source_path" || true
        issue_source_id="$FETCH_SOURCE_ID"
    fi

    if [[ -f "$STATE_FILE" ]]; then
        previous_delivered="$(jq -r '.last_delivered_fingerprint // ""' "$STATE_FILE" 2>/dev/null || true)"
    fi

    if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
        resolved_chat_id="$(resolve_telegram_chat_id "$TELEGRAM_ENV_FILE" || true)"
        if [[ -z "$resolved_chat_id" ]]; then
            add_warning "Telegram delivery was enabled but no chat id could be resolved."
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
warnings = json.loads(sys.argv[15])


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


def compact_notes(notes: list[str], limit: int = 8) -> list[str]:
    cleaned = [note for note in notes if note]
    return cleaned[-limit:]


def load_state(path: pathlib.Path) -> tuple[dict, list[str]]:
    default = {
        "last_status": "unknown",
        "notes": [],
    }
    notes: list[str] = []
    if not path.is_file():
        return default, notes
    try:
        raw = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Failed to parse watcher state file: {exc}")
        return default, notes

    if not isinstance(raw, dict):
        notes.append("Watcher state file did not contain an object; ignored.")
        return default, notes

    state = {
        "last_seen_fingerprint": str(raw.get("last_seen_fingerprint", "")).strip(),
        "last_delivered_fingerprint": str(raw.get("last_delivered_fingerprint", "")).strip(),
        "last_status": str(raw.get("last_status", "unknown")).strip() or "unknown",
        "last_checked_at": str(raw.get("last_checked_at", "")).strip(),
        "notes": [str(item).strip() for item in raw.get("notes", []) if str(item).strip()],
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
        deduped = []
        seen = set()
        for change in item["changes"]:
            if change not in seen:
                deduped.append(change)
                seen.add(change)
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
        issues = data.get("issues", [])
    else:
        issues = []
    normalized = []
    for item in issues:
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


def build_fingerprint(latest_version: str, highlights: list[str], primary_status: str) -> str:
    payload = json.dumps(
        {
            "latest_version": latest_version,
            "highlights": highlights[:5],
            "primary_status": primary_status,
        },
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


previous_state, state_warnings = load_state(state_path)
notes = list(warnings) + state_warnings
checked_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

primary_notes: list[str] = []
releases: list[dict] = []
primary_status = "unavailable"

if release_source_path.is_file():
    try:
        releases = parse_release_source(release_source_path.read_text(), max_releases)
        if releases:
            primary_status = "ok"
            primary_notes.append(f"Parsed {len(releases)} release entries from the primary source.")
        else:
            primary_status = "investigate"
            primary_notes.append("Primary source was readable but no Codex CLI release entries were parsed.")
    except Exception as exc:
        primary_status = "investigate"
        primary_notes.append(f"Failed to parse the primary source: {exc}")
else:
    primary_status = "unavailable"
    primary_notes.append("Primary source could not be fetched.")

latest_version = releases[0]["version"] if releases else "unknown"
highlights = releases[0]["changes"][:5] if releases else []
if releases and not highlights:
    highlights = [f"Release {latest_version} was published."]

advisory_sources: list[dict] = []
if include_issue_signals:
    advisory_notes: list[str] = []
    advisory_status = "unavailable"
    advisory_issues: list[dict] = []
    if issue_source_path.is_file():
        try:
            advisory_issues = parse_issue_signals(issue_source_path.read_text())
            advisory_status = "ok"
            advisory_notes.append(f"Advisory issue intake reviewed {len(advisory_issues)} item(s).")
            if advisory_issues:
                advisory_notes.append(f"Newest advisory title: {advisory_issues[0]['title']}")
        except Exception as exc:
            advisory_status = "investigate"
            advisory_notes.append(f"Failed to parse advisory issue signals: {exc}")
    else:
        advisory_status = "unavailable"
        advisory_notes.append("Advisory issue-signal source could not be fetched.")

    advisory_sources.append(
        {
            "name": "codex-advisory-issues",
            "status": advisory_status,
            "url": issue_source_url,
            "notes": advisory_notes,
        }
    )

fingerprint = build_fingerprint(latest_version, highlights, primary_status)
release_status = "unavailable"
decision_status = "investigate"
decision_reason = "Primary changelog evidence is unavailable."
decision_changed = False

if primary_status == "investigate":
    release_status = "investigate"
    decision_status = "investigate"
    decision_reason = "Primary changelog evidence is malformed or incomplete."
elif primary_status == "ok":
    delivered_matches = previous_state.get("last_delivered_fingerprint", "") == fingerprint
    seen_matches = previous_state.get("last_seen_fingerprint", "") == fingerprint
    release_status = "known" if seen_matches else "new"

    if mode == "scheduler" and telegram_enabled:
        if not telegram_chat_id:
            decision_status = "investigate"
            decision_reason = "Telegram delivery was enabled but no chat id could be resolved."
        elif delivered_matches:
            decision_status = "suppress"
            decision_reason = "This upstream fingerprint was already delivered to Telegram."
        elif seen_matches:
            decision_status = "deliver"
            decision_reason = "This upstream fingerprint is known locally but has not been delivered to Telegram yet."
        else:
            decision_status = "deliver"
            decision_reason = "Fresh upstream fingerprint detected and queued for Telegram delivery."
    else:
        if seen_matches:
            decision_status = "suppress"
            decision_reason = "This upstream fingerprint was already seen earlier."
        else:
            decision_status = "deliver"
            decision_reason = "Fresh upstream fingerprint detected."

    decision_changed = not seen_matches

state = {
    "last_status": "unknown",
    "notes": [],
}
if previous_state.get("last_seen_fingerprint"):
    state["last_seen_fingerprint"] = previous_state["last_seen_fingerprint"]
if previous_state.get("last_delivered_fingerprint"):
    state["last_delivered_fingerprint"] = previous_state["last_delivered_fingerprint"]
if previous_state.get("last_checked_at"):
    state["last_checked_at"] = previous_state["last_checked_at"]
state["notes"] = previous_state.get("notes", [])

run_note = f"{checked_at}: {decision_status} ({decision_reason})"

if decision_status == "investigate":
    state["last_status"] = "investigate"
    state["last_checked_at"] = checked_at
    state["notes"] = compact_notes(previous_state.get("notes", []) + [run_note])
else:
    state["last_seen_fingerprint"] = fingerprint
    state["last_checked_at"] = checked_at
    if decision_status == "deliver":
        state["last_status"] = "delivered"
        if mode == "scheduler" and telegram_enabled and telegram_chat_id:
            state["last_delivered_fingerprint"] = fingerprint
    elif decision_status == "suppress":
        state["last_status"] = "suppressed"
    state["notes"] = compact_notes(previous_state.get("notes", []) + [run_note])

report = {
    "checked_at": checked_at,
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
        "highlights": highlights,
    },
    "fingerprint": fingerprint,
    "decision": {
        "status": decision_status,
        "reason": decision_reason,
        "changed": decision_changed,
    },
    "state": state,
    "telegram_target": {
        "enabled": telegram_enabled,
    },
    "notes": compact_notes(
        notes
        + [f"Mode: {mode}."]
        + ([f"Resolved Telegram chat id: {telegram_chat_id}."] if telegram_chat_id else [])
        + ([f"Telegram env file: {telegram_env_file}."] if telegram_env_file else [])
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

    if [[ "$MODE" == "scheduler" && "$TELEGRAM_ENABLED" == "true" && "$(jq -r '.decision.status' "$REPORT_PATH")" == "deliver" ]]; then
        local telegram_text telegram_output send_code
        telegram_text="$(build_telegram_message)"

        if [[ ! -x "$TELEGRAM_SEND_SCRIPT" ]]; then
            patch_report_with_telegram_failure "$previous_delivered" "telegram sender script is missing or not executable: ${TELEGRAM_SEND_SCRIPT}"
        elif [[ -z "$resolved_chat_id" ]]; then
            patch_report_with_telegram_failure "$previous_delivered" "telegram chat id could not be resolved"
        else
            set +e
            telegram_output="$(run_telegram_sender "$resolved_chat_id" "$telegram_text" 2>&1)"
            send_code=$?
            set -e
            if [[ $send_code -eq 0 ]]; then
                patch_report_with_telegram_success "$resolved_chat_id"
            else
                patch_report_with_telegram_failure "$previous_delivered" "${telegram_output:-telegram sender exited with status ${send_code}}"
            fi
        fi
    fi

    ensure_parent_dir "$STATE_FILE"
    jq '.state' "$REPORT_PATH" > "$STATE_FILE"

    render_summary > "$SUMMARY_PATH"

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
        none)
            ;;
    esac
}

main "$@"
