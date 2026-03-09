#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/codex-cli-update-monitor.sh"

JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"
MONITOR_REPORT=""
STATE_FILE="${CODEX_UPDATE_ADVISOR_STATE_FILE:-${PROJECT_ROOT}/.tmp/current/codex-cli-update-advisor-state.json}"
NOTIFICATION_THRESHOLD="${CODEX_UPDATE_ADVISOR_NOTIFICATION_THRESHOLD:-upgrade-later}"
ISSUE_ACTION="none"
ISSUE_TARGET=""
BEADS_DB="${CODEX_UPDATE_ADVISOR_BEADS_DB:-}"
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
    local redirect_file resolved_path

    if [[ -n "$BEADS_DB" ]]; then
        [[ -f "$BEADS_DB" ]] || return 1
        printf '%s\n' "$BEADS_DB"
        return 0
    fi

    redirect_file="${PROJECT_ROOT}/.beads/redirect"
    if [[ -f "$redirect_file" ]]; then
        resolved_path="$(<"$redirect_file")"
        if [[ -n "$resolved_path" ]]; then
            if [[ "$resolved_path" == /* ]]; then
                resolved_path="${resolved_path}/beads.db"
            else
                resolved_path="${PROJECT_ROOT}/${resolved_path}/beads.db"
            fi
            if [[ -f "$resolved_path" ]]; then
                printf '%s\n' "$resolved_path"
                return 0
            fi
        fi
    fi

    if [[ -f "${PROJECT_ROOT}/.beads/beads.db" ]]; then
        printf '%s\n' "${PROJECT_ROOT}/.beads/beads.db"
        return 0
    fi

    return 1
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

    if ! beads_db_path="$(resolve_beads_db)"; then
        set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" \
            "Explicit issue sync was requested." \
            "Could not resolve a Beads database path for this worktree." \
            "No tracker mutation was performed."
        return 0
    fi

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

    python3 - \
        "$MONITOR_REPORT_PATH" \
        "$STATE_FILE" \
        "$NOTIFICATION_THRESHOLD" \
        "$ISSUE_ACTION" \
        "$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s .)" \
        > "$REPORT_PATH" <<'PY'
import datetime as dt
import hashlib
import json
import pathlib
import sys

monitor_path = pathlib.Path(sys.argv[1])
state_path = pathlib.Path(sys.argv[2])
threshold = sys.argv[3]
issue_action_mode = sys.argv[4]
warnings = json.loads(sys.argv[5])

ALLOWED_RECOMMENDATIONS = {"upgrade-now", "upgrade-later", "ignore", "investigate"}
ALLOWED_VERSION_STATUS = {"ahead", "current", "behind", "unknown"}
PRIORITY_RANK = {"low": 1, "medium": 2, "high": 3}


def load_monitor_report(path: pathlib.Path):
    notes = []
    evidence = []
    data = {}
    if not path.is_file():
        notes.append(f"Monitor report not found: {path}")
        evidence.append("Advisor could not load the underlying monitor report.")
        return data, notes, evidence
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Failed to parse monitor report JSON: {exc}")
        evidence.append("Advisor could not parse the underlying monitor report.")
        return {}, notes, evidence
    return data, notes, evidence


def normalize_change(item, index):
    if not isinstance(item, dict):
        return None
    change_id = str(item.get("id", f"change:{index}")).strip() or f"change:{index}"
    summary = str(item.get("summary", "")).strip()
    reason = str(item.get("reason", "")).strip()
    relevance = str(item.get("relevance", "none")).strip()
    if not summary or not reason or relevance not in {"high", "medium", "low", "none"}:
        return None
    return {
        "id": change_id,
        "summary": summary,
        "relevance": relevance,
        "reason": reason,
    }


def normalize_monitor_snapshot(raw, notes, evidence):
    if not isinstance(raw, dict):
        raw = {}

    local_version = str(raw.get("local_version", "unknown")).strip() or "unknown"
    latest_version = str(raw.get("latest_version", "unknown")).strip() or "unknown"
    version_status = str(raw.get("version_status", "unknown")).strip()
    if version_status not in ALLOWED_VERSION_STATUS:
        notes.append(f"Monitor report had invalid version_status '{version_status}', normalized to unknown.")
        version_status = "unknown"

    recommendation = str(raw.get("recommendation", "investigate")).strip()
    if recommendation not in ALLOWED_RECOMMENDATIONS:
        notes.append(f"Monitor report had invalid recommendation '{recommendation}', normalized to investigate.")
        recommendation = "investigate"

    repo_traits = []
    for item in raw.get("repo_workflow_traits", []):
        value = str(item).strip()
        if value and value not in repo_traits:
            repo_traits.append(value)

    relevant_changes = []
    for index, item in enumerate(raw.get("relevant_changes", []), start=1):
        normalized = normalize_change(item, index)
        if normalized is not None:
            relevant_changes.append(normalized)

    monitor_evidence = []
    for item in raw.get("evidence", []):
        value = str(item).strip()
        if value and value not in monitor_evidence:
            monitor_evidence.append(value)

    required = ["local_version", "latest_version", "version_status", "recommendation", "repo_workflow_traits", "relevant_changes", "evidence"]
    missing = [field for field in required if field not in raw]
    if missing:
        notes.append("Monitor report was missing required fields: " + ", ".join(missing))
        recommendation = "investigate"
        if not monitor_evidence:
            monitor_evidence.append("Advisor fell back to investigate because the underlying monitor contract was incomplete.")

    if not monitor_evidence:
        monitor_evidence.extend(evidence or ["Advisor did not receive explicit evidence from the monitor report."])

    return {
        "local_version": local_version,
        "latest_version": latest_version,
        "version_status": version_status,
        "recommendation": recommendation,
        "repo_workflow_traits": repo_traits,
        "relevant_changes": relevant_changes,
        "evidence": monitor_evidence,
    }


def load_state(path: pathlib.Path):
    notes = []
    if not path.is_file():
        notes.append("Advisor state file not found; treating this as a fresh evaluation.")
        return {}, notes
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Advisor state file could not be parsed and was ignored: {exc}")
        return {}, notes
    if not isinstance(data, dict):
        notes.append("Advisor state file was not an object and was ignored.")
        return {}, notes
    return data, notes


def meets_threshold(recommendation: str, configured: str) -> bool:
    if configured == "ignore":
        return True
    if configured == "upgrade-later":
        return recommendation in {"upgrade-later", "upgrade-now"}
    if configured == "upgrade-now":
        return recommendation == "upgrade-now"
    if configured == "investigate":
        return recommendation == "investigate"
    return False


RULES = [
    {
        "id": "worktree-guidance",
        "title": "Review worktree guidance and topology helpers",
        "priority": "high",
        "category": "workflow",
        "keywords": ["worktree", "workspace"],
        "traits": ["worktree-discipline"],
        "rationale": "Upstream Codex behavior changed in an area this repository uses heavily for dedicated worktree lanes.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            "docs/GIT-TOPOLOGY-REGISTRY.md",
        ],
        "next_steps": [
            "Review worktree instructions and examples against the latest Codex behavior.",
            "Validate any worktree helper flows that assume older Codex semantics.",
        ],
    },
    {
        "id": "approval-profile-review",
        "title": "Audit approval and sandbox guidance",
        "priority": "high",
        "category": "workflow",
        "keywords": ["approval", "permission profile", "sandbox"],
        "traits": ["approval-boundaries"],
        "rationale": "This repository encodes explicit approval and sandbox expectations, so Codex changes in that area can change operator behavior.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            "scripts/codex-profile-launch.sh",
        ],
        "next_steps": [
            "Re-read approval policy guidance and compare it with the new Codex release behavior.",
            "Update local launch defaults or docs if the approval surface changed.",
        ],
    },
    {
        "id": "agent-delegation-review",
        "title": "Review multi-agent and resume workflow guidance",
        "priority": "high",
        "category": "workflow",
        "keywords": ["multi-agent", "multi agent", "resume"],
        "traits": ["agents-surface"],
        "rationale": "The repository relies on agent delegation patterns, so Codex changes around delegation or resume can require workflow updates.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            ".claude/commands/",
        ],
        "next_steps": [
            "Review delegation guidance and any long-running session instructions.",
            "Check whether resumed sessions still match the current repo expectations.",
        ],
    },
    {
        "id": "js-repl-guidance",
        "title": "Refresh js_repl usage guidance",
        "priority": "high",
        "category": "tooling",
        "keywords": ["js_repl", "js repl", "repl"],
        "traits": ["js-repl-surface"],
        "rationale": "The repo uses js_repl as a first-class tool, so Codex changes there can require examples or guardrail updates.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
        ],
        "next_steps": [
            "Check whether js_repl examples and caveats still reflect current Codex behavior.",
            "Update wrapper guidance if js_repl capabilities or constraints changed.",
        ],
    },
    {
        "id": "skills-surface-review",
        "title": "Review skill bridge and MCP guidance",
        "priority": "medium",
        "category": "tooling",
        "keywords": ["skill", "mcp", "plugin"],
        "traits": ["skills-surface", "agents-md-boundaries"],
        "rationale": "Changes to skills, plugins, or MCP behavior can affect how this repo documents or bridges Codex capabilities.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            ".claude/skills/",
        ],
        "next_steps": [
            "Check whether skill or MCP guidance needs refresh after the Codex update.",
            "Verify any repo-specific bridge expectations still hold.",
        ],
    },
    {
        "id": "runbook-refresh",
        "title": "Refresh Codex runbooks and examples",
        "priority": "medium",
        "category": "docs",
        "keywords": ["agents.md", "project docs", "doc refresh", "prompt"],
        "traits": ["agents-md-boundaries"],
        "rationale": "Codex workflow changes often land first as instruction or runbook drift in this repository.",
        "impacted_paths": [
            "AGENTS.md",
            "docs/CODEX-OPERATING-MODEL.md",
            "docs/codex-cli-update-monitor.md",
        ],
        "next_steps": [
            "Compare the current runbooks with the updated Codex behavior.",
            "Refresh examples where operator steps have changed.",
        ],
    },
]


def build_suggestions(snapshot):
    suggestion_map = {}
    combined_texts = []
    for change in snapshot["relevant_changes"]:
        combined_texts.append(" ".join([change["summary"], change["reason"]]).lower())
    combined_text = "\n".join(combined_texts)
    trait_set = set(snapshot["repo_workflow_traits"])

    for rule in RULES:
        if rule["traits"] and not trait_set.intersection(rule["traits"]):
            continue
        if not any(keyword in combined_text for keyword in rule["keywords"]):
            continue
        suggestion_map[rule["id"]] = {
            "id": rule["id"],
            "title": rule["title"],
            "priority": rule["priority"],
            "category": rule["category"],
            "rationale": rule["rationale"],
            "impacted_paths": rule["impacted_paths"],
            "next_steps": rule["next_steps"],
        }

    if snapshot["recommendation"] == "investigate" and "investigate-gap" not in suggestion_map:
        suggestion_map["investigate-gap"] = {
            "id": "investigate-gap",
            "title": "Investigate the underlying monitor gap before changing repo workflows",
            "priority": "high",
            "category": "investigation",
            "rationale": "The advisor cannot safely recommend concrete repository changes until the underlying monitor evidence is reliable again.",
            "impacted_paths": [
                "scripts/codex-cli-update-monitor.sh",
                "docs/codex-cli-update-monitor.md",
                "docs/research/",
            ],
            "next_steps": [
                "Inspect why the monitor returned investigate or incomplete evidence.",
                "Regenerate a trustworthy monitor report before making repository workflow changes.",
            ],
        }

    if not suggestion_map and snapshot["relevant_changes"]:
        suggestion_map["codex-runtime-review"] = {
            "id": "codex-runtime-review",
            "title": "Review Codex runtime guidance for this repository",
            "priority": "medium",
            "category": "workflow",
            "rationale": "Relevant Codex changes were detected, but they did not map cleanly to a narrower heuristic bucket.",
            "impacted_paths": [
                "AGENTS.md",
                "docs/CODEX-OPERATING-MODEL.md",
            ],
            "next_steps": [
                "Review the relevant monitor evidence and decide which operator guidance needs refresh.",
            ],
        }

    suggestions = list(suggestion_map.values())
    suggestions.sort(key=lambda item: (-PRIORITY_RANK[item["priority"]], item["title"]))
    return suggestions


def build_fingerprint(snapshot, suggestions):
    payload = {
        "latest_version": snapshot["latest_version"],
        "local_version": snapshot["local_version"],
        "version_status": snapshot["version_status"],
        "recommendation": snapshot["recommendation"],
        "relevant_change_ids": [item["id"] for item in snapshot["relevant_changes"]],
        "suggestion_ids": [item["id"] for item in suggestions],
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode()).hexdigest()


def build_notification(snapshot, state, threshold_value, fingerprint, notes):
    recommendation = snapshot["recommendation"]
    previous = str(state.get("last_fingerprint", "")).strip()

    if recommendation == "investigate":
        if previous and previous == fingerprint:
            return {
                "status": "suppressed",
                "changed": False,
                "threshold": threshold_value,
                "fingerprint": fingerprint,
                "reason": "The same investigate state was already seen earlier, so the advisor suppressed a duplicate alert.",
                "notes": notes + ["Underlying monitor still requires investigation."],
            }
        return {
            "status": "investigate",
            "changed": True,
            "threshold": threshold_value,
            "fingerprint": fingerprint,
            "reason": "The underlying monitor requires investigation, so the advisor cannot stay silent.",
            "notes": notes,
        }

    if not meets_threshold(recommendation, threshold_value):
        return {
            "status": "none",
            "changed": False,
            "threshold": threshold_value,
            "fingerprint": fingerprint,
            "reason": f"Recommendation '{recommendation}' is below notification threshold '{threshold_value}'.",
            "notes": notes,
        }

    if previous and previous == fingerprint:
        return {
            "status": "suppressed",
            "changed": False,
            "threshold": threshold_value,
            "fingerprint": fingerprint,
            "reason": "This actionable Codex update state matches the last one the advisor already surfaced.",
            "notes": notes,
        }

    return {
        "status": "notify",
        "changed": True,
        "threshold": threshold_value,
        "fingerprint": fingerprint,
        "reason": "A new actionable Codex update state was detected for this repository.",
        "notes": notes,
    }


def build_implementation_brief(snapshot, notification, suggestions):
    impacted_paths = []
    for suggestion in suggestions:
        for path in suggestion["impacted_paths"]:
            if path not in impacted_paths:
                impacted_paths.append(path)

    top_priorities = [suggestion["title"] for suggestion in suggestions[:3]]
    if not top_priorities:
        if snapshot["recommendation"] == "ignore":
            top_priorities = ["No repository follow-up is needed right now."]
        else:
            top_priorities = ["Review the advisor evidence before changing repository workflows."]

    summary = (
        f"Codex CLI {snapshot['local_version']} -> {snapshot['latest_version']} "
        f"is currently '{snapshot['recommendation']}' for this repository, and the advisor marked the run as '{notification['status']}'."
    )

    notes = [
        f"Notification threshold: {notification['threshold']}",
        f"Relevant change count: {len(snapshot['relevant_changes'])}",
    ]
    if not suggestions:
        notes.append("No concrete repository change suggestion was generated from the current evidence.")

    return {
        "summary": summary,
        "top_priorities": top_priorities,
        "impacted_paths": impacted_paths,
        "notes": notes,
    }


raw_monitor, load_notes, load_evidence = load_monitor_report(monitor_path)
state_data, state_notes = load_state(state_path)
base_notes = list(load_notes) + list(state_notes)
for warning in warnings:
    if warning:
        base_notes.append(f"Advisor warning: {warning}")

monitor_snapshot = normalize_monitor_snapshot(raw_monitor, base_notes, load_evidence)
suggestions = build_suggestions(monitor_snapshot)
fingerprint = build_fingerprint(monitor_snapshot, suggestions)
notification = build_notification(monitor_snapshot, state_data, threshold, fingerprint, base_notes)
implementation_brief = build_implementation_brief(monitor_snapshot, notification, suggestions)

if issue_action_mode == "upsert":
    issue_action = {
        "mode": "skipped",
        "requested": True,
        "notes": ["Explicit issue sync was requested; final issue action will be applied after advisor evaluation."],
    }
else:
    issue_action = {
        "mode": "suggested" if notification["status"] in {"notify", "investigate"} else "none",
        "requested": False,
        "notes": ["Tracker sync was not requested during initial advisor evaluation."],
    }

report = {
    "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    "monitor_snapshot": monitor_snapshot,
    "notification": notification,
    "project_change_suggestions": suggestions,
    "implementation_brief": implementation_brief,
    "issue_action": issue_action,
}
print(json.dumps(report, indent=2))
PY

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
