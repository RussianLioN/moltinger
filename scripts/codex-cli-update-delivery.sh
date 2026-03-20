#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ADVISOR_SCRIPT_DEFAULT="${PROJECT_ROOT}/scripts/codex-cli-update-advisor.sh"
TELEGRAM_SEND_SCRIPT_DEFAULT="${PROJECT_ROOT}/scripts/telegram-bot-send.sh"

SURFACE="on-demand"
ADVISOR_REPORT=""
ADVISOR_SCRIPT="$ADVISOR_SCRIPT_DEFAULT"
ADVISOR_STATE_FILE="${CODEX_UPDATE_DELIVERY_ADVISOR_STATE_FILE:-${PROJECT_ROOT}/.tmp/current/codex-cli-update-advisor-state.json}"
STATE_FILE="${CODEX_UPDATE_DELIVERY_STATE_FILE:-${PROJECT_ROOT}/.tmp/current/codex-cli-update-delivery-state.json}"
JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"

MONITOR_REPORT=""
NOTIFICATION_THRESHOLD="${CODEX_UPDATE_DELIVERY_ADVISOR_NOTIFICATION_THRESHOLD:-upgrade-later}"
CONFIG_FILE_OVERRIDE=""
LOCAL_VERSION_OVERRIDE=""
RELEASE_FILE=""
RELEASE_URL=""
MAX_RELEASES=""
INCLUDE_ISSUE_SIGNALS=false
ISSUE_SIGNALS_FILE=""
ISSUE_SIGNALS_URL=""

TELEGRAM_ENABLED="${CODEX_UPDATE_DELIVERY_TELEGRAM_ENABLED:-false}"
TELEGRAM_CHAT_ID="${CODEX_UPDATE_DELIVERY_TELEGRAM_CHAT_ID:-}"
TELEGRAM_ENV_FILE="${CODEX_UPDATE_DELIVERY_TELEGRAM_ENV_FILE:-}"
TELEGRAM_SILENT=false
TELEGRAM_SEND_SCRIPT="$TELEGRAM_SEND_SCRIPT_DEFAULT"

TEMP_DIR=""
REPORT_PATH=""
SUMMARY_PATH=""
ADVISOR_REPORT_PATH=""

declare -a WARNINGS=()

usage() {
    cat <<'USAGE'
Usage: codex-cli-update-delivery.sh [options]

Deliver Codex CLI update awareness across user-facing surfaces without forcing
operators to remember raw advisor flags.

Options:
  --surface SURFACE            Delivery surface: on-demand|launcher|telegram
  --advisor-report PATH        Use an existing advisor JSON report
  --advisor-script PATH        Override advisor script path
  --advisor-state-file PATH    Advisor state file when invoking the advisor
  --state-file PATH            Delivery state file
  --json-out PATH              Write delivery JSON report to PATH
  --summary-out PATH           Write human-readable summary to PATH
  --stdout MODE                stdout mode: summary|json|none (default: summary)

Telegram options:
  --telegram-enabled           Enable Telegram delivery for this run
  --telegram-chat-id ID        Telegram chat target
  --telegram-env-file PATH     Env file for telegram-bot-send.sh token loading
  --telegram-silent            Send Telegram notification silently
  --telegram-send-script PATH  Override Telegram send script path

Advisor passthrough options:
  --monitor-report PATH
  --notification-threshold VAL ignore|upgrade-later|upgrade-now|investigate
  --config-file PATH
  --local-version VERSION
  --release-file PATH
  --release-url URL
  --max-releases N
  --include-issue-signals
  --issue-signals-file PATH
  --issue-signals-url URL
USAGE
}

cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

require_command() {
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        printf 'Missing required dependency: %s\n' "$name" >&2
        exit 2
    fi
}

ensure_parent_dir() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
}

normalize_bool() {
    case "$1" in
        true|1|yes|on) printf 'true\n' ;;
        false|0|no|off|'') printf 'false\n' ;;
        *)
            printf 'Invalid boolean value: %s\n' "$1" >&2
            exit 2
            ;;
    esac
}

run_advisor_capture() {
    local advisor_summary_path="${TEMP_DIR}/advisor-summary.md"
    local -a cmd=(
        "$ADVISOR_SCRIPT"
        --state-file "$ADVISOR_STATE_FILE"
        --json-out "$ADVISOR_REPORT_PATH"
        --summary-out "$advisor_summary_path"
        --stdout none
        --issue-action none
        --notification-threshold "$NOTIFICATION_THRESHOLD"
    )

    [[ -n "$MONITOR_REPORT" ]] && cmd+=(--monitor-report "$MONITOR_REPORT")
    [[ -n "$CONFIG_FILE_OVERRIDE" ]] && cmd+=(--config-file "$CONFIG_FILE_OVERRIDE")
    [[ -n "$LOCAL_VERSION_OVERRIDE" ]] && cmd+=(--local-version "$LOCAL_VERSION_OVERRIDE")
    [[ -n "$RELEASE_FILE" ]] && cmd+=(--release-file "$RELEASE_FILE")
    [[ -n "$RELEASE_URL" ]] && cmd+=(--release-url "$RELEASE_URL")
    [[ -n "$MAX_RELEASES" ]] && cmd+=(--max-releases "$MAX_RELEASES")
    [[ "$INCLUDE_ISSUE_SIGNALS" == "true" ]] && cmd+=(--include-issue-signals)
    [[ -n "$ISSUE_SIGNALS_FILE" ]] && cmd+=(--issue-signals-file "$ISSUE_SIGNALS_FILE")
    [[ -n "$ISSUE_SIGNALS_URL" ]] && cmd+=(--issue-signals-url "$ISSUE_SIGNALS_URL")

    "${cmd[@]}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --surface)
                SURFACE="${2:?missing value for --surface}"
                shift 2
                ;;
            --advisor-report)
                ADVISOR_REPORT="${2:?missing value for --advisor-report}"
                shift 2
                ;;
            --advisor-script)
                ADVISOR_SCRIPT="${2:?missing value for --advisor-script}"
                shift 2
                ;;
            --advisor-state-file)
                ADVISOR_STATE_FILE="${2:?missing value for --advisor-state-file}"
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
            --monitor-report)
                MONITOR_REPORT="${2:?missing value for --monitor-report}"
                shift 2
                ;;
            --notification-threshold)
                NOTIFICATION_THRESHOLD="${2:?missing value for --notification-threshold}"
                shift 2
                ;;
            --config-file)
                CONFIG_FILE_OVERRIDE="${2:?missing value for --config-file}"
                shift 2
                ;;
            --local-version)
                LOCAL_VERSION_OVERRIDE="${2:?missing value for --local-version}"
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

    case "$SURFACE" in
        on-demand|launcher|telegram) ;;
        *)
            printf 'Invalid --surface value: %s\n' "$SURFACE" >&2
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

    case "$NOTIFICATION_THRESHOLD" in
        ignore|upgrade-later|upgrade-now|investigate) ;;
        *)
            printf 'Invalid --notification-threshold value: %s\n' "$NOTIFICATION_THRESHOLD" >&2
            exit 2
            ;;
    esac

    TELEGRAM_ENABLED="$(normalize_bool "$TELEGRAM_ENABLED")"

    if [[ -n "$ADVISOR_REPORT" && ! -f "$ADVISOR_REPORT" ]]; then
        printf 'Advisor report not found: %s\n' "$ADVISOR_REPORT" >&2
        exit 2
    fi

    if [[ -n "$MONITOR_REPORT" && ! -f "$MONITOR_REPORT" ]]; then
        printf 'Monitor report not found: %s\n' "$MONITOR_REPORT" >&2
        exit 2
    fi
}

main() {
    parse_args "$@"
    require_command jq
    require_command python3

    TEMP_DIR="$(mktemp -d)"
    REPORT_PATH="${TEMP_DIR}/delivery-report.json"
    SUMMARY_PATH="${TEMP_DIR}/delivery-summary.md"
    ADVISOR_REPORT_PATH="${TEMP_DIR}/advisor-report.json"

    if [[ -n "$ADVISOR_REPORT" ]]; then
        cp "$ADVISOR_REPORT" "$ADVISOR_REPORT_PATH"
    else
        if [[ ! -x "$ADVISOR_SCRIPT" ]]; then
            printf 'Advisor script is unavailable: %s\n' "$ADVISOR_SCRIPT" >&2
            exit 2
        fi
        run_advisor_capture
    fi

    python3 - \
        "$ADVISOR_REPORT_PATH" \
        "$STATE_FILE" \
        "$SURFACE" \
        "$TELEGRAM_ENABLED" \
        "$TELEGRAM_CHAT_ID" \
        "$TELEGRAM_ENV_FILE" \
        "$TELEGRAM_SILENT" \
        "$TELEGRAM_SEND_SCRIPT" \
        "$SUMMARY_PATH" \
        "$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s .)" \
        > "$REPORT_PATH" <<'PY'
import datetime as dt
import json
import hashlib
import os
import pathlib
import subprocess
import sys

advisor_path = pathlib.Path(sys.argv[1])
state_path = pathlib.Path(sys.argv[2])
surface = sys.argv[3]
telegram_enabled = sys.argv[4].lower() == "true"
telegram_chat_id = sys.argv[5]
telegram_env_file = sys.argv[6]
telegram_silent = sys.argv[7].lower() == "true"
telegram_send_script = pathlib.Path(sys.argv[8])
summary_path = pathlib.Path(sys.argv[9])
warnings = json.loads(sys.argv[10])

SURFACES = ("on-demand", "launcher", "telegram")
ACTIONABLE_STATUSES = {"notify", "investigate"}


def now_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def normalize_list(value):
    return value if isinstance(value, list) else []


def load_json(path, default):
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def normalize_advisor(data, notes):
    if not isinstance(data, dict):
        notes.append("Advisor report was missing or invalid; treating the result as investigate.")
        data = {}

    monitor_snapshot = data.get("monitor_snapshot", {})
    notification = data.get("notification", {})
    if not isinstance(monitor_snapshot, dict):
        monitor_snapshot = {}
        notes.append("Advisor monitor_snapshot was invalid.")
    if not isinstance(notification, dict):
        notification = {}
        notes.append("Advisor notification object was invalid.")

    recommendation = str(monitor_snapshot.get("recommendation", "")).strip()
    if recommendation not in {"upgrade-now", "upgrade-later", "ignore", "investigate"}:
        recommendation = "investigate"
        notes.append("Advisor recommendation was missing or invalid.")

    notification_status = str(notification.get("status", "")).strip()
    if notification_status not in {"notify", "suppressed", "none", "investigate"}:
        notification_status = "investigate"
        notes.append("Advisor notification status was missing or invalid.")

    brief = data.get("implementation_brief", {})
    if not isinstance(brief, dict):
        brief = {}
        notes.append("Advisor implementation_brief was invalid.")

    snapshot = {
        "recommendation": recommendation,
        "notification_status": notification_status,
        "project_change_suggestions": normalize_list(data.get("project_change_suggestions")),
        "implementation_brief": {
            "summary": str(brief.get("summary", "")).strip()
            or "Codex update delivery needs investigation because the advisor result was unavailable or incomplete.",
            "top_priorities": [str(item).strip() for item in normalize_list(brief.get("top_priorities")) if str(item).strip()],
            "impacted_paths": [str(item).strip() for item in normalize_list(brief.get("impacted_paths")) if str(item).strip()],
            "notes": [str(item).strip() for item in normalize_list(brief.get("notes")) if str(item).strip()],
        },
    }

    fingerprint = str(notification.get("fingerprint", "")).strip()
    if not fingerprint:
        fingerprint = hashlib.sha256(
            json.dumps(snapshot, sort_keys=True, ensure_ascii=False).encode("utf-8")
        ).hexdigest()

    return snapshot, fingerprint


def load_state(path):
    data = load_json(path, {})
    surfaces = data.get("surfaces", {}) if isinstance(data, dict) else {}
    result = {"surfaces": {}}
    for name in SURFACES:
        current = surfaces.get(name, {}) if isinstance(surfaces, dict) else {}
        if not isinstance(current, dict):
            current = {}
        result["surfaces"][name] = {
            "last_fingerprint": str(current.get("last_fingerprint", "")).strip(),
            "last_delivered_fingerprint": str(current.get("last_delivered_fingerprint", "")).strip(),
            "last_delivered_at": str(current.get("last_delivered_at", "")).strip(),
            "last_status": str(current.get("last_status", "unknown")).strip() or "unknown",
            "notes": [str(item).strip() for item in normalize_list(current.get("notes")) if str(item).strip()],
        }
    return result


def make_decision(surface_name, snapshot, fingerprint, state_row, telegram_cfg):
    status = snapshot["notification_status"]
    seen = state_row["last_fingerprint"] == fingerprint
    previous_status = state_row["last_status"]

    if status not in ACTIONABLE_STATUSES:
        reason = (
            "The advisor already marked this update state as known."
            if status == "suppressed"
            else "The advisor did not produce a fresh actionable update."
        )
        return {"surface": surface_name, "status": "suppress", "reason": reason, "changed": False}

    if seen and previous_status != "failed":
        reason = (
            f"The current investigate state was already shown on the {surface_name} surface."
            if status == "investigate"
            else f"The current actionable state was already delivered on the {surface_name} surface."
        )
        return {"surface": surface_name, "status": "suppress", "reason": reason, "changed": False}

    if seen and previous_status == "failed":
        return {
            "surface": surface_name,
            "status": "retry",
            "reason": f"The same fingerprint previously failed on the {surface_name} surface and remains retryable.",
            "changed": True,
        }

    if surface_name == "telegram":
        if not telegram_cfg["enabled"]:
            return {
                "surface": surface_name,
                "status": "retry",
                "reason": "Telegram delivery is disabled for this run.",
                "changed": True,
            }
        if not telegram_cfg["chat_id"]:
            return {
                "surface": surface_name,
                "status": "retry",
                "reason": "Telegram delivery is enabled but no chat target was configured.",
                "changed": True,
            }

    return {
        "surface": surface_name,
        "status": "investigate" if status == "investigate" else "deliver",
        "reason": (
            "The advisor requires investigation before the repository should change."
            if status == "investigate"
            else "A fresh actionable Codex update is ready to be delivered."
        ),
        "changed": True,
    }


def update_state_row(row, fingerprint, checked_at, status, note):
    row["last_fingerprint"] = fingerprint
    row["notes"] = [note]
    if status == "delivered":
        row["last_status"] = "delivered"
        row["last_delivered_fingerprint"] = fingerprint
        row["last_delivered_at"] = checked_at
    elif status == "suppressed":
        row["last_status"] = "suppressed"
    else:
        row["last_status"] = "failed"


def surface_state_rows(state):
    rows = []
    for name in SURFACES:
        current = state["surfaces"][name]
        row = {
            "surface": name,
            "last_status": current["last_status"],
            "notes": current["notes"],
        }
        if current["last_delivered_fingerprint"]:
            row["last_delivered_fingerprint"] = current["last_delivered_fingerprint"]
        if current["last_delivered_at"]:
            row["last_delivered_at"] = current["last_delivered_at"]
        rows.append(row)
    return rows


def render_summary(report, active_surface):
    decision = next(item for item in report["surface_decisions"] if item["surface"] == active_surface)
    brief = report["advisor_snapshot"]["implementation_brief"]
    priorities = brief["top_priorities"]
    suggestions = report["advisor_snapshot"]["project_change_suggestions"]

    if active_surface == "launcher":
        if decision["status"] == "suppress":
            return ""
        lines = [
            "[Codex Update Alert]",
            brief["summary"],
            f"Delivery: {decision['status']}",
            f"Reason: {decision['reason']}",
        ]
        if priorities:
            lines.append("Next:")
            lines.extend(f"- {item}" for item in priorities[:2])
        return "\n".join(line for line in lines if line.strip())

    lines = [
        "# Codex CLI Update Delivery",
        "",
        f"- Surface: {active_surface}",
        f"- Delivery: {decision['status']}",
        f"- Freshness: {'new' if decision['changed'] else 'already-known'}",
        f"- Recommendation: {report['advisor_snapshot']['recommendation']}",
        f"- Advisor notification: {report['advisor_snapshot']['notification_status']}",
        "",
        "## Summary",
        f"- {brief['summary']}",
    ]

    if priorities:
        lines.extend(["", "## Top Priorities", *[f"- {item}" for item in priorities[:3]]])

    if active_surface == "on-demand" and suggestions:
        lines.append("")
        lines.append("## Suggested Project Changes")
        for item in suggestions[:5]:
            if not isinstance(item, dict):
                continue
            title = str(item.get("title", "Unnamed suggestion")).strip()
            rationale = str(item.get("rationale", "")).strip()
            lines.append(f"- {title}" + (f" -- {rationale}" if rationale else ""))

    lines.extend(["", "## Notes", f"- {decision['reason']}"])
    for note in report["notes"]:
        lines.append(f"- {note}")
    return "\n".join(lines)


def build_telegram_message(snapshot):
    lines = [
        "Codex CLI update for this repository",
        f"Recommendation: {snapshot['recommendation']}",
        f"Freshness: {snapshot['notification_status']}",
        snapshot["implementation_brief"]["summary"],
    ]
    priorities = snapshot["implementation_brief"]["top_priorities"]
    if priorities:
        lines.append("Top priorities:")
        lines.extend(f"- {item}" for item in priorities[:3])
    return "\n".join(line for line in lines if line.strip())


checked_at = now_iso()
notes = list(warnings)
advisor_data = load_json(advisor_path, {})
snapshot, fingerprint = normalize_advisor(advisor_data, notes)
state = load_state(state_path)

telegram_target = {"enabled": telegram_enabled}
if telegram_chat_id:
    telegram_target["chat_id"] = telegram_chat_id
if telegram_env_file:
    telegram_target["env_file"] = telegram_env_file
if telegram_silent:
    telegram_target["silent"] = True

decisions = {
    name: make_decision(name, snapshot, fingerprint, state["surfaces"][name], telegram_target)
    for name in SURFACES
}
active = decisions[surface]

if surface == "telegram":
    if active["status"] in {"deliver", "investigate", "retry"} and telegram_target["enabled"] and telegram_target.get("chat_id"):
        if not telegram_send_script.is_file():
            active["status"] = "retry"
            active["reason"] = f"Telegram send script not found: {telegram_send_script}"
            notes.append(active["reason"])
            update_state_row(state["surfaces"][surface], fingerprint, checked_at, "failed", active["reason"])
        else:
            env = os.environ.copy()
            if telegram_env_file:
                env["MOLTIS_ENV_FILE"] = telegram_env_file
            cmd = [
                str(telegram_send_script),
                "--chat-id",
                telegram_target["chat_id"],
                "--text",
                build_telegram_message(snapshot),
                "--json",
            ]
            if telegram_silent:
                cmd.append("--disable-notification")
            result = subprocess.run(cmd, capture_output=True, text=True, env=env)
            if result.returncode == 0:
                active["status"] = "investigate" if snapshot["notification_status"] == "investigate" else "deliver"
                active["reason"] = "Telegram notification was sent successfully."
                notes.append(active["reason"])
                update_state_row(state["surfaces"][surface], fingerprint, checked_at, "delivered", active["reason"])
            else:
                detail = (result.stderr or result.stdout or "").strip() or f"exit code {result.returncode}"
                active["status"] = "retry"
                active["reason"] = f"Telegram delivery failed: {detail}"
                notes.append(active["reason"])
                update_state_row(state["surfaces"][surface], fingerprint, checked_at, "failed", active["reason"])
    elif active["status"] == "suppress":
        update_state_row(state["surfaces"][surface], fingerprint, checked_at, "suppressed", active["reason"])
    else:
        notes.append(active["reason"])
        update_state_row(state["surfaces"][surface], fingerprint, checked_at, "failed", active["reason"])
else:
    if active["status"] == "suppress":
        update_state_row(state["surfaces"][surface], fingerprint, checked_at, "suppressed", active["reason"])
    else:
        update_state_row(state["surfaces"][surface], fingerprint, checked_at, "delivered", active["reason"])

decisions[surface] = active

report = {
    "checked_at": checked_at,
    "advisor_snapshot": snapshot,
    "fingerprint": fingerprint,
    "surface_decisions": [decisions[name] for name in SURFACES],
    "surface_state": surface_state_rows(state),
    "notes": [note for note in notes if str(note).strip()],
}
if telegram_target["enabled"] or telegram_target.get("chat_id") or telegram_target.get("env_file") or telegram_target.get("silent"):
    report["telegram_target"] = telegram_target

summary_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.write_text(render_summary(report, surface))
state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(report, indent=2, ensure_ascii=False))
PY

    if [[ -n "$JSON_OUT" ]]; then
        ensure_parent_dir "$JSON_OUT"
        cp "$REPORT_PATH" "$JSON_OUT"
    fi

    if [[ -n "$SUMMARY_OUT" ]]; then
        ensure_parent_dir "$SUMMARY_OUT"
        cp "$SUMMARY_PATH" "$SUMMARY_OUT"
    fi

    case "$STDOUT_FORMAT" in
        json)
            cat "$REPORT_PATH"
            ;;
        summary)
            if [[ -s "$SUMMARY_PATH" ]]; then
                cat "$SUMMARY_PATH"
            fi
            ;;
        none)
            ;;
    esac
}

main "$@"
