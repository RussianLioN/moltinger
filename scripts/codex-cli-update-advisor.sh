#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/codex-cli-update-monitor.sh"
ADVISOR_REPORT_HELPER="${PROJECT_ROOT}/scripts/codex-cli-update-advisor-report.py"
# shellcheck source=scripts/beads-resolve-db.sh
source "${PROJECT_ROOT}/scripts/beads-resolve-db.sh"

JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"
MONITOR_REPORT=""
STATE_FILE="${CODEX_UPDATE_ADVISOR_STATE_FILE:-${PROJECT_ROOT}/.tmp/current/codex-cli-update-advisor-state.json}"
NOTIFICATION_THRESHOLD="${CODEX_UPDATE_ADVISOR_NOTIFICATION_THRESHOLD:-upgrade-later}"
ISSUE_ACTION="none"
ISSUE_TARGET=""
BEADS_DB="${CODEX_UPDATE_ADVISOR_BEADS_DB:-}"
BEADS_DB_RESOLUTION_NOTE=""
BEADS_DB_RESOLVED_PATH=""
CONFIG_FILE_OVERRIDE=""
LOCAL_VERSION_OVERRIDE=""
RELEASE_FILE=""
RELEASE_URL=""
MAX_RELEASES=""
INCLUDE_ISSUE_SIGNALS=false
ISSUE_SIGNALS_FILE=""
ISSUE_SIGNALS_URL=""

TEMP_DIR=""
REPORT_PATH=""
SUMMARY_PATH=""
MONITOR_REPORT_PATH=""

declare -a WARNINGS=()

usage() {
    cat <<'USAGE'
Usage: codex-cli-update-advisor.sh [options]

Wrap the Codex CLI update monitor with duplicate-suppression, repository
change suggestions, and optional Beads implementation handoff.

Options:
  --monitor-report PATH         Use an existing monitor JSON report instead of invoking the monitor
  --state-file PATH             Persist advisor notification state at PATH
  --notification-threshold VAL  Threshold for notify-worthy results:
                                ignore|upgrade-later|upgrade-now|investigate
  --json-out PATH               Write advisor JSON report to PATH
  --summary-out PATH            Write advisor Markdown summary to PATH
  --stdout MODE                 stdout mode: summary|json|none (default: summary)
  --issue-action MODE           Issue sync mode: none|upsert
  --issue-target ID             Optional Beads issue target identifier
  --beads-db PATH               Explicit Beads database path

Monitor passthrough options:
  --config-file PATH
  --local-version VERSION
  --release-file PATH
  --release-url URL
  --max-releases N
  --include-issue-signals
  --issue-signals-file PATH
  --issue-signals-url URL

Environment overrides:
  CODEX_UPDATE_ADVISOR_STATE_FILE
  CODEX_UPDATE_ADVISOR_NOTIFICATION_THRESHOLD
  CODEX_UPDATE_ADVISOR_BEADS_DB
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
    local path="$1"
    mkdir -p "$(dirname "$path")"
}

recommendation_meets_threshold() {
    local recommendation="$1"
    local threshold="$2"
    case "$threshold" in
        ignore)
            return 0
            ;;
        upgrade-later)
            [[ "$recommendation" == "upgrade-later" || "$recommendation" == "upgrade-now" ]]
            ;;
        upgrade-now)
            [[ "$recommendation" == "upgrade-now" ]]
            ;;
        investigate)
            [[ "$recommendation" == "investigate" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_beads_db() {
    BEADS_DB_RESOLUTION_NOTE=""
    BEADS_DB_RESOLVED_PATH=""

    if [[ -n "$BEADS_DB" ]]; then
        if [[ ! -f "$BEADS_DB" ]]; then
            BEADS_DB_RESOLUTION_NOTE="Explicit --beads-db path does not exist: $BEADS_DB"
            return 1
        fi
        BEADS_DB_RESOLVED_PATH="$BEADS_DB"
        return 0
    fi

    beads_resolve_dispatch "$PROJECT_ROOT" update codex-update-advisor-probe --status open

    case "${BEADS_RESOLVE_DECISION}" in
        execute_local)
            BEADS_DB_RESOLVED_PATH="${BEADS_RESOLVE_DB_PATH}"
            return 0
            ;;
        *)
            if [[ -n "${BEADS_RESOLVE_MESSAGE:-}" ]]; then
                BEADS_DB_RESOLUTION_NOTE="${BEADS_RESOLVE_MESSAGE}"
                if [[ -n "${BEADS_RESOLVE_RECOVERY_HINT:-}" ]]; then
                    BEADS_DB_RESOLUTION_NOTE="${BEADS_DB_RESOLUTION_NOTE} Recovery: ${BEADS_RESOLVE_RECOVERY_HINT}"
                fi
            else
                BEADS_DB_RESOLUTION_NOTE="Could not resolve a Beads database path for this worktree."
            fi
            return 1
            ;;
    esac
}

issue_priority_for_report() {
    local notification_status recommendation
    notification_status="$(jq -r '.notification.status' "$REPORT_PATH")"
    recommendation="$(jq -r '.monitor_snapshot.recommendation' "$REPORT_PATH")"

    case "$notification_status" in
        investigate) printf '1\n' ;;
        notify)
            case "$recommendation" in
                upgrade-now) printf '2\n' ;;
                upgrade-later) printf '3\n' ;;
                *) printf '4\n' ;;
            esac
            ;;
        *) printf '4\n' ;;
    esac
}

set_issue_action_json() {
    local mode="$1"
    local requested="$2"
    local target="${3:-}"
    shift 3
    local notes_json

    if [[ $# -gt 0 ]]; then
        notes_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
    else
        notes_json='[]'
    fi

    jq \
        --arg mode "$mode" \
        --argjson requested "$requested" \
        --argjson notes "$notes_json" \
        --arg target "$target" \
        '.issue_action = (
            {
                mode: $mode,
                requested: $requested,
                notes: $notes
            }
            + (if $target == "" then {} else {target: $target} end)
        )' \
        "$REPORT_PATH" > "${REPORT_PATH}.tmp"
    mv "${REPORT_PATH}.tmp" "$REPORT_PATH"
}

build_issue_title() {
    local status local_version latest_version
    status="$(jq -r '.notification.status' "$REPORT_PATH")"
    local_version="$(jq -r '.monitor_snapshot.local_version' "$REPORT_PATH")"
    latest_version="$(jq -r '.monitor_snapshot.latest_version' "$REPORT_PATH")"

    case "$status" in
        investigate)
            printf 'Investigate Codex advisor findings (%s -> %s)\n' "$local_version" "$latest_version"
            ;;
        *)
            printf 'Apply Codex advisor suggestions %s -> %s\n' "$local_version" "$latest_version"
            ;;
    esac
}

build_issue_description() {
    jq -r '
      def fmt_list(items):
        if (items | length) == 0 then "- none"
        else items[] | "- \(.)"
        end;
      def fmt_paths(items):
        if (items | length) == 0 then "- none"
        else items[] | "- `\(.)`"
        end;
      def fmt_suggestions(items):
        if (items | length) == 0 then "- none"
        else items[] | "- [\(.priority)] \(.title) -- \(.rationale)"
        end;

      [
        "Codex CLI update advisor follow-up created from an explicit `--issue-action upsert` run.",
        "",
        "## Status",
        "- Notification: \(.notification.status)",
        "- Notification reason: \(.notification.reason)",
        "- Recommendation: \(.monitor_snapshot.recommendation)",
        "- Local version: \(.monitor_snapshot.local_version)",
        "- Latest checked version: \(.monitor_snapshot.latest_version)",
        "- Version status: \(.monitor_snapshot.version_status)",
        "- Checked at: \(.checked_at)",
        "",
        "## Suggested Project Changes",
        (fmt_suggestions(.project_change_suggestions)),
        "",
        "## Top Priorities",
        (fmt_list(.implementation_brief.top_priorities)),
        "",
        "## Impacted Paths",
        (fmt_paths(.implementation_brief.impacted_paths)),
        "",
        "## Notes",
        (fmt_list(.implementation_brief.notes))
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

build_issue_note() {
    jq -r '
      [
        "Codex CLI update advisor sync",
        "- Notification: \(.notification.status)",
        "- Recommendation: \(.monitor_snapshot.recommendation)",
        "- Local version: \(.monitor_snapshot.local_version)",
        "- Latest checked version: \(.monitor_snapshot.latest_version)",
        "- Checked at: \(.checked_at)",
        "- Top priorities:",
        (.implementation_brief.top_priorities[]? | "  - \(.)")
      ] | join("\n")
    ' "$REPORT_PATH"
}

save_state_from_report() {
    local status
    status="$(jq -r '.notification.status' "$REPORT_PATH")"
    case "$status" in
        notify|investigate) ;;
        *) return 0 ;;
    esac

    ensure_parent_dir "$STATE_FILE"
    jq '{
          last_fingerprint: .notification.fingerprint,
          last_recommendation: .monitor_snapshot.recommendation,
          last_notified_at: .checked_at
        }
        + (if (.issue_action.target // "") != "" then {last_issue_target: .issue_action.target} else {} end)
       ' "$REPORT_PATH" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

perform_issue_sync() {
    local notification_status beads_db_path issue_title issue_description issue_note created_id priority
    notification_status="$(jq -r '.notification.status' "$REPORT_PATH")"

    if [[ "$ISSUE_ACTION" == "none" ]]; then
        case "$notification_status" in
            notify|investigate)
                set_issue_action_json "suggested" "false" "${ISSUE_TARGET:-}" \
                    "Tracker sync was not requested." \
                    "This advisor result is new and actionable for the repository." \
                    "Re-run with --issue-action upsert to create or update a Beads implementation brief."
                ;;
            suppressed)
                set_issue_action_json "none" "false" "${ISSUE_TARGET:-}" \
                    "Tracker sync was not requested." \
                    "This actionable state was already seen, so the advisor suppressed a duplicate alert."
                ;;
            *)
                set_issue_action_json "none" "false" "${ISSUE_TARGET:-}" \
                    "Tracker sync was not requested." \
                    "No notify-worthy advisor result was produced."
                ;;
        esac
        return 0
    fi

    case "$notification_status" in
        notify|investigate) ;;
        *)
            set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" \
                "Explicit issue sync was requested." \
                "The advisor result was not in a fresh notify-worthy state." \
                "No tracker mutation was performed."
            return 0
            ;;
    esac

    if ! command -v bd >/dev/null 2>&1; then
        set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" \
            "Explicit issue sync was requested." \
            "The bd CLI is not available in PATH." \
            "No tracker mutation was performed."
        return 0
    fi

    if ! resolve_beads_db; then
        set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" \
            "Explicit issue sync was requested." \
            "${BEADS_DB_RESOLUTION_NOTE:-Could not resolve a Beads database path for this worktree.}" \
            "No tracker mutation was performed."
        return 0
    fi
    beads_db_path="${BEADS_DB_RESOLVED_PATH}"

    issue_title="$(build_issue_title)"
    issue_description="$(build_issue_description)"
    issue_note="$(build_issue_note)"
    priority="$(issue_priority_for_report)"

    if [[ -n "$ISSUE_TARGET" ]]; then
        if bd update --db "$beads_db_path" "$ISSUE_TARGET" --status open --priority "$priority" --append-notes "$issue_note" >/dev/null 2>&1; then
            set_issue_action_json "updated" "true" "$ISSUE_TARGET" \
                "Explicit issue sync was requested." \
                "Updated Beads issue '${ISSUE_TARGET}' with the latest advisor brief."
            return 0
        fi

        set_issue_action_json "skipped" "true" "$ISSUE_TARGET" \
            "Explicit issue sync was requested." \
            "Failed to update Beads issue '${ISSUE_TARGET}'." \
            "No tracker mutation was completed."
        return 0
    fi

    if created_id="$(bd create "$issue_title" --db "$beads_db_path" --type task --priority "$priority" --labels codex-update,advisor --description "$issue_description" --silent 2>/dev/null)"; then
        set_issue_action_json "created" "true" "$created_id" \
            "Explicit issue sync was requested." \
            "Created a new Beads implementation brief from the advisor report."
        return 0
    fi

    set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" \
        "Explicit issue sync was requested." \
        "Failed to create a Beads implementation brief." \
        "No tracker mutation was completed."
}

render_summary() {
    jq -r '
      def fmt_list(items):
        if (items | length) == 0 then "- none"
        else items[] | "- \(.)"
        end;
      def fmt_suggestions(items):
        if (items | length) == 0 then "- none"
        else items[] | "- [\(.priority)] \(.title) -- \(.rationale)"
        end;

      [
        "# Codex CLI Update Advisor",
        "",
        "- Checked at: \(.checked_at)",
        "- Notification: \(.notification.status)",
        "- Notification reason: \(.notification.reason)",
        "- Recommendation: \(.monitor_snapshot.recommendation)",
        "- Local version: \(.monitor_snapshot.local_version)",
        "- Latest checked version: \(.monitor_snapshot.latest_version)",
        "- Version status: \(.monitor_snapshot.version_status)",
        "",
        "## Top Priorities",
        (fmt_list(.implementation_brief.top_priorities)),
        "",
        "## Suggested Project Changes",
        (fmt_suggestions(.project_change_suggestions)),
        "",
        "## Issue Action",
        "- Mode: \(.issue_action.mode)",
        "- Requested: \(.issue_action.requested)",
        (if (.issue_action.target // "") != "" then "- Target: \(.issue_action.target)" else empty end),
        "",
        "## Notes",
        (fmt_list(.notification.notes)),
        (fmt_list(.issue_action.notes // []))
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

run_monitor_capture() {
    local monitor_summary_path="${TEMP_DIR}/monitor-summary.md"
    local -a cmd=(
        "$MONITOR_SCRIPT"
        --json-out "$MONITOR_REPORT_PATH"
        --summary-out "$monitor_summary_path"
        --stdout none
        --issue-action none
    )

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
            --monitor-report)
                MONITOR_REPORT="${2:?missing value for --monitor-report}"
                shift 2
                ;;
            --state-file)
                STATE_FILE="${2:?missing value for --state-file}"
                shift 2
                ;;
            --notification-threshold)
                NOTIFICATION_THRESHOLD="${2:?missing value for --notification-threshold}"
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
            --issue-action)
                ISSUE_ACTION="${2:?missing value for --issue-action}"
                shift 2
                ;;
            --issue-target)
                ISSUE_TARGET="${2:?missing value for --issue-target}"
                shift 2
                ;;
            --beads-db)
                BEADS_DB="${2:?missing value for --beads-db}"
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

    case "$ISSUE_ACTION" in
        none|upsert) ;;
        *)
            printf 'Invalid --issue-action mode: %s\n' "$ISSUE_ACTION" >&2
            exit 2
            ;;
    esac

    if [[ -n "$MONITOR_REPORT" && ! -f "$MONITOR_REPORT" ]]; then
        printf 'Monitor report not found: %s\n' "$MONITOR_REPORT" >&2
        exit 2
    fi

    if [[ -n "$MAX_RELEASES" ]] && ! [[ "$MAX_RELEASES" =~ ^[1-9][0-9]*$ ]]; then
        printf '--max-releases must be a positive integer\n' >&2
        exit 2
    fi
}

main() {
    parse_args "$@"
    require_command jq
    require_command python3

    if [[ ! -x "$MONITOR_SCRIPT" ]]; then
        printf 'Base monitor script is unavailable: %s\n' "$MONITOR_SCRIPT" >&2
        exit 2
    fi

    TEMP_DIR="$(mktemp -d)"
    REPORT_PATH="${TEMP_DIR}/advisor-report.json"
    SUMMARY_PATH="${TEMP_DIR}/advisor-summary.md"
    MONITOR_REPORT_PATH="${TEMP_DIR}/monitor-report.json"

    if [[ -n "$MONITOR_REPORT" ]]; then
        cp "$MONITOR_REPORT" "$MONITOR_REPORT_PATH"
    else
        run_monitor_capture
    fi

    if [[ ! -f "$ADVISOR_REPORT_HELPER" ]]; then
        printf 'Missing advisor report helper: %s\n' "$ADVISOR_REPORT_HELPER" >&2
        exit 2
    fi

    python3 "$ADVISOR_REPORT_HELPER" \
        "$MONITOR_REPORT_PATH" \
        "$STATE_FILE" \
        "$NOTIFICATION_THRESHOLD" \
        "$ISSUE_ACTION" \
        "$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s .)" \
        > "$REPORT_PATH"

    perform_issue_sync
    render_summary > "$SUMMARY_PATH"
    save_state_from_report

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
