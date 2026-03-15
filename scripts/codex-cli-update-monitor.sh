#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/beads-resolve-db.sh
source "${PROJECT_ROOT}/scripts/beads-resolve-db.sh"

DEFAULT_RELEASE_URL="https://developers.openai.com/codex/changelog"
DEFAULT_ISSUE_SIGNALS_URL="https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"

JSON_OUT=""
SUMMARY_OUT=""
STDOUT_FORMAT="summary"
CONFIG_FILE="${CODEX_UPDATE_MONITOR_CONFIG_FILE:-${HOME}/.codex/config.toml}"
RELEASE_FILE="${CODEX_UPDATE_MONITOR_RELEASE_FILE:-}"
RELEASE_URL="${CODEX_UPDATE_MONITOR_RELEASE_URL:-${DEFAULT_RELEASE_URL}}"
INCLUDE_ISSUE_SIGNALS=false
ISSUE_SIGNALS_FILE="${CODEX_UPDATE_MONITOR_ISSUE_SIGNALS_FILE:-}"
ISSUE_SIGNALS_URL="${CODEX_UPDATE_MONITOR_ISSUE_SIGNALS_URL:-${DEFAULT_ISSUE_SIGNALS_URL}}"
LOCAL_VERSION_OVERRIDE="${CODEX_UPDATE_MONITOR_LOCAL_VERSION:-}"
MAX_RELEASES="${CODEX_UPDATE_MONITOR_MAX_RELEASES:-3}"
ISSUE_ACTION="none"
ISSUE_TARGET=""
ISSUE_THRESHOLD="${CODEX_UPDATE_MONITOR_ISSUE_THRESHOLD:-upgrade-now}"
BEADS_DB="${CODEX_UPDATE_MONITOR_BEADS_DB:-}"
BEADS_DB_RESOLUTION_NOTE=""
BEADS_DB_RESOLVED_PATH=""

TEMP_DIR=""
REPORT_PATH=""
SUMMARY_PATH=""
EXIT_CODE=0
FETCH_SOURCE_ID=""

declare -a WARNINGS=()

usage() {
    cat <<'EOF'
Usage: codex-cli-update-monitor.sh [options]

Detect the local Codex CLI version, compare it with recent upstream releases,
map changes to repo workflow traits, and emit JSON plus Markdown outputs.

Options:
  --json-out PATH           Write the machine-readable report to PATH
  --summary-out PATH        Write the Markdown summary to PATH
  --stdout MODE             stdout mode: summary|json|none (default: summary)
  --config-file PATH        Codex config TOML file (default: ~/.codex/config.toml)
  --local-version VERSION   Override detected local version (test/fixture use)
  --release-file PATH       Read release source content from a local file
  --release-url URL         Read release source content from URL
  --max-releases N          Limit the number of recent upstream releases to scan
  --include-issue-signals   Include optional upstream issue-signal analysis
  --issue-signals-file PATH Read issue-signal JSON from a local file
  --issue-signals-url URL   Read issue-signal JSON from URL
  --issue-action MODE       Issue sync mode: none|upsert
  --issue-target ID         Optional tracker target identifier
  --issue-threshold VALUE   Minimum recommendation for tracker action:
                            ignore|upgrade-later|upgrade-now|investigate
  --beads-db PATH           Explicit Beads database path for local tracker sync
  -h, --help                Show this help text

Environment overrides:
  CODEX_UPDATE_MONITOR_CONFIG_FILE
  CODEX_UPDATE_MONITOR_LOCAL_VERSION
  CODEX_UPDATE_MONITOR_RELEASE_FILE
  CODEX_UPDATE_MONITOR_RELEASE_URL
  CODEX_UPDATE_MONITOR_ISSUE_SIGNALS_FILE
  CODEX_UPDATE_MONITOR_ISSUE_SIGNALS_URL
  CODEX_UPDATE_MONITOR_MAX_RELEASES
  CODEX_UPDATE_MONITOR_ISSUE_THRESHOLD
  CODEX_UPDATE_MONITOR_BEADS_DB
EOF
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
    local dir
    dir="$(dirname "$path")"
    mkdir -p "$dir"
}

normalize_version() {
    local raw="${1:-}"
    if [[ "$raw" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
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

    beads_resolve_dispatch "$PROJECT_ROOT" update codex-update-monitor-probe --status open

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

issue_priority_for_recommendation() {
    case "${1:-}" in
        investigate) printf '1\n' ;;
        upgrade-now) printf '2\n' ;;
        upgrade-later) printf '3\n' ;;
        *) printf '4\n' ;;
    esac
}

build_issue_title() {
    local recommendation local_version latest_version
    recommendation="$(jq -r '.recommendation' "$REPORT_PATH")"
    local_version="$(jq -r '.local_version' "$REPORT_PATH")"
    latest_version="$(jq -r '.latest_version' "$REPORT_PATH")"

    case "$recommendation" in
        investigate)
            printf 'Investigate Codex CLI update monitor findings (%s -> %s)\n' "$local_version" "$latest_version"
            ;;
        *)
            printf 'Review Codex CLI update %s -> %s (%s)\n' "$local_version" "$latest_version" "$recommendation"
            ;;
    esac
}

build_issue_description() {
    jq -r '
      def fmt_list(items):
        if (items | length) == 0 then "- none"
        else items[] | "- \(.)"
        end;
      def fmt_changes(items):
        if (items | length) == 0 then "- none"
        else items[] | "- [\(.relevance)] \(.summary) -- \(.reason)"
        end;

      [
        "Codex CLI update monitor follow-up created from an explicit `--issue-action upsert` run.",
        "",
        "## Status",
        "- Recommendation: \(.recommendation)",
        "- Local version: \(.local_version)",
        "- Latest checked version: \(.latest_version)",
        "- Version status: \(.version_status)",
        "- Checked at: \(.checked_at)",
        "",
        "## Relevant Changes",
        (fmt_changes(.relevant_changes)),
        "",
        "## Evidence",
        (fmt_list(.evidence)),
        "",
        "## Suggested Next Steps",
        "- Review the relevant changes listed above.",
        "- Decide whether to upgrade the local Codex CLI now or defer intentionally.",
        "- Re-run `scripts/codex-cli-update-monitor.sh` after any upgrade or workflow adjustment."
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

build_issue_note() {
    jq -r '
      [
        "Codex CLI update monitor sync",
        "- Recommendation: \(.recommendation)",
        "- Local version: \(.local_version)",
        "- Latest checked version: \(.latest_version)",
        "- Checked at: \(.checked_at)",
        "- Relevant changes: \(.relevant_changes | length)",
        "- Evidence:",
        (.evidence[] | "  - \(.)")
      ] | join("\n")
    ' "$REPORT_PATH"
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

perform_issue_sync() {
    local recommendation threshold_notes threshold_target beads_db_path issue_title issue_description issue_note created_id priority
    recommendation="$(jq -r '.recommendation' "$REPORT_PATH")"

    if [[ "$ISSUE_ACTION" == "none" ]]; then
        if recommendation_meets_threshold "$recommendation" "$ISSUE_THRESHOLD"; then
            threshold_notes=(
                "Tracker sync was not requested."
                "Recommendation meets the issue threshold '${ISSUE_THRESHOLD}'."
                "Re-run with --issue-action upsert to create or update a Beads follow-up."
            )
            set_issue_action_json "suggested" "false" "${ISSUE_TARGET:-}" "${threshold_notes[@]}"
        else
            set_issue_action_json "none" "false" "${ISSUE_TARGET:-}" "Tracker sync not requested."
        fi
        return 0
    fi

    if ! recommendation_meets_threshold "$recommendation" "$ISSUE_THRESHOLD"; then
        threshold_notes=(
            "Explicit issue sync was requested."
            "Recommendation '${recommendation}' does not meet threshold '${ISSUE_THRESHOLD}'."
            "No tracker mutation was performed."
        )
        set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" "${threshold_notes[@]}"
        return 0
    fi

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
    priority="$(issue_priority_for_recommendation "$recommendation")"

    if [[ -n "$ISSUE_TARGET" ]]; then
        if bd update --db "$beads_db_path" "$ISSUE_TARGET" --status open --priority "$priority" --append-notes "$issue_note" >/dev/null 2>&1; then
            set_issue_action_json "updated" "true" "$ISSUE_TARGET" \
                "Explicit issue sync was requested." \
                "Updated Beads issue '${ISSUE_TARGET}' with the latest monitor evidence."
            return 0
        fi

        set_issue_action_json "skipped" "true" "$ISSUE_TARGET" \
            "Explicit issue sync was requested." \
            "Failed to update Beads issue '${ISSUE_TARGET}'." \
            "No tracker mutation was completed."
        return 0
    fi

    if created_id="$(bd create "$issue_title" --db "$beads_db_path" --type task --priority "$priority" --labels codex-update,backlog --description "$issue_description" --silent 2>/dev/null)"; then
        set_issue_action_json "created" "true" "$created_id" \
            "Explicit issue sync was requested." \
            "Created a new Beads follow-up from the monitor report."
        return 0
    fi

    set_issue_action_json "skipped" "true" "${ISSUE_TARGET:-}" \
        "Explicit issue sync was requested." \
        "Failed to create a Beads follow-up issue." \
        "No tracker mutation was completed."
}

collect_local_config_json() {
    python3 - "$CONFIG_FILE" <<'PY'
import json
import pathlib
import sys

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None

path = pathlib.Path(sys.argv[1])
result = {"features": [], "notes": []}

if not path.is_file():
    result["notes"].append(f"Config file not found: {path}")
    print(json.dumps(result))
    raise SystemExit(0)

if tomllib is None:
    result["notes"].append("python3 tomllib is unavailable; config traits not parsed")
    print(json.dumps(result))
    raise SystemExit(0)

try:
    data = tomllib.loads(path.read_text())
except Exception as exc:  # pragma: no cover - defensive path
    result["notes"].append(f"Failed to parse config TOML: {exc}")
    print(json.dumps(result))
    raise SystemExit(0)

features = []

if data.get("check_for_update_on_startup") is True:
    features.append("config.check_for_update_on_startup")

for key in ("service_tier", "approval_policy", "sandbox_mode", "model"):
    value = data.get(key)
    if isinstance(value, str) and value:
        features.append(f"{key}.{value}")

for key, label in (
    ("multi_agent", "feature.multi_agent"),
    ("js_repl", "feature.js_repl"),
    ("prevent_idle_sleep", "feature.prevent_idle_sleep"),
):
    if data.get("features", {}).get(key) is True:
        features.append(label)

result["features"] = features
print(json.dumps(result))
PY
}

detect_repo_traits_json() {
    local local_features_json="$1"
    python3 - "$PROJECT_ROOT" "$local_features_json" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
local_features = set(json.loads(sys.argv[2]))
traits = []

def add_trait(name: str) -> None:
    if name not in traits:
        traits.append(name)

def safe_read(path: pathlib.Path) -> str:
    try:
        return path.read_text()
    except Exception:
        return ""

operating_model = safe_read(root / "docs" / "CODEX-OPERATING-MODEL.md").lower()
root_agents = safe_read(root / "AGENTS.md").lower()

if "worktree" in operating_model or "worktree" in root_agents:
    add_trait("worktree-discipline")

if "approval" in operating_model or "approval" in root_agents or "sandbox" in root_agents:
    add_trait("approval-boundaries")

if (root / ".claude" / "skills").is_dir() or "skill" in root_agents:
    add_trait("skills-surface")

if "feature.multi_agent" in local_features or "multi-agent" in operating_model:
    add_trait("agents-surface")

if "feature.js_repl" in local_features or "js_repl" in operating_model:
    add_trait("js-repl-surface")

if "non-interactive" in operating_model or "codex exec" in safe_read(root / "docs" / "research" / "codex-cli-update-monitoring-2026-03-09.md").lower():
    add_trait("noninteractive-surface")

if (root / "AGENTS.md").is_file() and (root / "docs" / "AGENTS.md").is_file():
    add_trait("agents-md-boundaries")

print(json.dumps(traits))
PY
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
      def fmt_changes(items):
        if (items | length) == 0 then "- none"
        else
          items[] |
          "- [\(.relevance)] \(.id): \(.summary) -- \(.reason)"
        end;

      [
        "# Codex CLI Update Monitor",
        "",
        "- Checked at: \(.checked_at)",
        "- Recommendation: \(.recommendation)",
        "- Local version: \(.local_version)",
        "- Latest checked version: \(.latest_version)",
        "- Version status: \(.version_status)",
        "- Release source: \(.sources.release_source)",
        "- Issue signals included: \(.sources.issue_signals_included)",
        "",
        "## Repo Workflow Traits",
        (fmt_list(.repo_workflow_traits)),
        "",
        "## Evidence",
        (fmt_list(.evidence)),
        "",
        "## Relevant Changes",
        (fmt_changes(.relevant_changes)),
        "",
        "## Non-Relevant Changes",
        (fmt_changes(.non_relevant_changes)),
        "",
        "## Issue Action",
        "- Mode: \(.issue_action.mode)",
        "- Requested: \(.issue_action.requested)",
        (if (.issue_action.target // "") != "" then "- Target: \(.issue_action.target)" else empty end),
        "- Notes:",
        (fmt_list(.issue_action.notes // []))
      ] | flatten | join("\n")
    ' "$REPORT_PATH"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --config-file)
                CONFIG_FILE="${2:?missing value for --config-file}"
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
            --issue-action)
                ISSUE_ACTION="${2:?missing value for --issue-action}"
                shift 2
                ;;
            --issue-target)
                ISSUE_TARGET="${2:?missing value for --issue-target}"
                shift 2
                ;;
            --issue-threshold)
                ISSUE_THRESHOLD="${2:?missing value for --issue-threshold}"
                shift 2
                ;;
            --beads-db)
                BEADS_DB="${2:?missing value for --beads-db}"
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

    case "$ISSUE_ACTION" in
        none|upsert) ;;
        *)
            printf 'Invalid --issue-action mode: %s\n' "$ISSUE_ACTION" >&2
            exit 2
            ;;
    esac

    case "$ISSUE_THRESHOLD" in
        ignore|upgrade-later|upgrade-now|investigate) ;;
        *)
            printf 'Invalid --issue-threshold value: %s\n' "$ISSUE_THRESHOLD" >&2
            exit 2
            ;;
    esac

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

    local local_version_raw=""
    local local_version="missing"
    if [[ -n "$LOCAL_VERSION_OVERRIDE" ]]; then
        local_version_raw="$LOCAL_VERSION_OVERRIDE"
    elif command -v codex >/dev/null 2>&1; then
        local_version_raw="$(codex --version 2>/dev/null || true)"
    else
        add_warning "codex CLI not found in PATH"
    fi

    if normalize_version "$local_version_raw" >/dev/null 2>&1; then
        local_version="$(normalize_version "$local_version_raw")"
    else
        add_warning "Unable to detect a local Codex CLI version"
    fi

    local local_config_json local_features_json local_notes_json repo_traits_json
    local_config_json="$(collect_local_config_json)"
    local_features_json="$(printf '%s' "$local_config_json" | jq -c '.features')"
    local_notes_json="$(printf '%s' "$local_config_json" | jq -c '.notes')"
    repo_traits_json="$(detect_repo_traits_json "$local_features_json")"

    local release_source_path issue_source_path
    release_source_path="${TEMP_DIR}/release-source"
    issue_source_path="${TEMP_DIR}/issue-signals.json"

    local release_source_id issue_source_id
    release_source_id="unavailable"
    issue_source_id=""
    FETCH_SOURCE_ID=""
    if fetch_source "release" "$RELEASE_FILE" "$RELEASE_URL" "$DEFAULT_RELEASE_URL" "$release_source_path"; then
        :
    fi
    if [[ -n "$FETCH_SOURCE_ID" ]]; then
        release_source_id="$FETCH_SOURCE_ID"
    fi

    if [[ "$INCLUDE_ISSUE_SIGNALS" == "true" ]]; then
        FETCH_SOURCE_ID=""
        if fetch_source "issue-signal" "$ISSUE_SIGNALS_FILE" "$ISSUE_SIGNALS_URL" "$DEFAULT_ISSUE_SIGNALS_URL" "$issue_source_path"; then
            :
        fi
        if [[ -n "$FETCH_SOURCE_ID" ]]; then
            issue_source_id="$FETCH_SOURCE_ID"
        fi
    fi

    # Keep the parsing and classification logic in one deterministic block so
    # fixtures and live sources produce the same normalized report shape.
    python3 - \
        "$local_version" \
        "$local_features_json" \
        "$local_notes_json" \
        "$repo_traits_json" \
        "$release_source_id" \
        "$release_source_path" \
        "$MAX_RELEASES" \
        "$INCLUDE_ISSUE_SIGNALS" \
        "$issue_source_id" \
        "$issue_source_path" \
        "$ISSUE_ACTION" \
        "$ISSUE_TARGET" \
        "$(printf '%s\n' "${WARNINGS[@]:-}" | jq -R . | jq -s .)" \
        > "$REPORT_PATH" <<'PY'
import datetime as dt
import json
import pathlib
import re
import sys
from html.parser import HTMLParser

local_version = sys.argv[1]
local_features = json.loads(sys.argv[2])
local_notes = json.loads(sys.argv[3])
repo_traits = json.loads(sys.argv[4])
release_source_id = sys.argv[5]
release_source_path = pathlib.Path(sys.argv[6])
max_releases = int(sys.argv[7])
include_issue_signals = sys.argv[8] == "true"
issue_source_id = sys.argv[9]
issue_source_path = pathlib.Path(sys.argv[10])
issue_action_requested = sys.argv[11]
issue_target = sys.argv[12]
warnings = json.loads(sys.argv[13])

RELEVANCE_RANK = {"none": 0, "low": 1, "medium": 2, "high": 3}


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):  # noqa: D401 - HTMLParser hook
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):  # noqa: D401 - HTMLParser hook
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div"}:
            self.parts.append("\n")

    def handle_data(self, data):  # noqa: D401 - HTMLParser hook
        stripped = data.strip()
        if stripped:
            self.parts.append(stripped)

    def text(self) -> str:
        text = "".join(self.parts)
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        return "\n".join(line for line in lines if line)


def normalize_semver(value: str) -> tuple[int, int, int] | None:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", value or "")
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def compare_versions(left: str, right: str) -> int | None:
    left_tuple = normalize_semver(left)
    right_tuple = normalize_semver(right)
    if left_tuple is None or right_tuple is None:
        return None
    if left_tuple < right_tuple:
        return -1
    if left_tuple > right_tuple:
        return 1
    return 0


def parse_release_source(raw: str, limit: int) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []

    if stripped[0] in "[{":
        data = json.loads(stripped)
        if isinstance(data, dict):
            releases = data.get("releases", [])
        elif isinstance(data, list):
            releases = data
        else:
            releases = []
        normalized = []
        for item in releases:
            if not isinstance(item, dict):
                continue
            changes = item.get("changes", [])
            normalized.append(
                {
                    "version": str(item.get("version", "")).strip(),
                    "published_at": str(item.get("published_at", "")).strip(),
                    "changes": [str(change).strip() for change in changes if str(change).strip()],
                }
            )
        return normalized[:limit]

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
    if isinstance(data, dict):
        issues = data.get("issues", [])
    elif isinstance(data, list):
        issues = data
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
        labels = []
        for label in item.get("labels", []):
            if isinstance(label, dict):
                name = label.get("name")
                if name:
                    labels.append(name)
            elif isinstance(label, str):
                labels.append(label)
        normalized.append(
            {
                "id": str(issue_id),
                "title": str(item.get("title", "")).strip(),
                "state": str(item.get("state", item.get("status", ""))).strip() or "unknown",
                "labels": labels,
                "url": str(item.get("html_url", item.get("url", ""))).strip(),
            }
        )
    return normalized


def relevance_reason(change_text: str, traits: set[str], advisory: bool = False) -> tuple[str, str, list[str]]:
    text = change_text.lower()
    evidence = []

    candidates = [
        ("high", "Relevant because this repo relies on dedicated worktrees and topology checks.", ["worktree-discipline"], ["worktree", "/new"]),
        ("high", "Relevant because repo instructions enforce explicit approval and sandbox boundaries.", ["approval-boundaries"], ["approval", "permission profile", "sandbox"]),
        ("high", "Relevant because multi-agent delegation is part of this repo's day-to-day workflow.", ["agents-surface"], ["multi-agent", "multi agent", "resume"]),
        ("high", "Relevant because the repo actively uses js_repl-backed workflows.", ["js-repl-surface"], ["js_repl", "js repl", "repl"]),
        ("medium", "Relevant because the repo uses non-interactive Codex execution patterns.", ["noninteractive-surface"], ["non-interactive", "noninteractive", "codex exec"]),
        ("medium", "Relevant because the repo depends on AGENTS boundaries and instruction refresh flows.", ["agents-md-boundaries"], ["agents.md", "project docs", "doc refresh"]),
        ("low", "Low relevance because the repo currently leans on bridged skills and MCP surfaces more than plugin-first workflows.", ["skills-surface"], ["plugin", "@plugin"]),
        ("medium", "Relevant because the repo actively uses skills, commands, and MCP integrations.", ["skills-surface"], ["skill", "mcp"]),
    ]

    best = ("none", "No strong link to current repo workflow traits was detected.", [])
    for level, reason, required_traits, keywords in candidates:
        if not set(required_traits).intersection(traits):
            continue
        if not any(keyword in text for keyword in keywords):
            continue
        if RELEVANCE_RANK[level] > RELEVANCE_RANK[best[0]]:
            best = (level, reason, required_traits)

    if advisory:
        if best[0] != "none":
            reason = f"{best[1]} Issue signals remain advisory and do not drive the recommendation on their own."
        else:
            reason = "Advisory issue signal captured for operator awareness; no strong repo-specific relevance detected."
        return best[0], reason, list(best[2])

    return best[0], best[1], list(best[2])


release_fetch_ok = release_source_path.is_file()
release_text = release_source_path.read_text() if release_fetch_ok else ""
releases = parse_release_source(release_text, max_releases) if release_fetch_ok else []
latest_version = releases[0]["version"] if releases else "unknown"

compare_result = compare_versions(local_version, latest_version)
if compare_result is None:
    version_status = "unknown"
elif compare_result < 0:
    version_status = "behind"
elif compare_result > 0:
    version_status = "ahead"
else:
    version_status = "current"

traits = set(repo_traits)

candidate_releases = []
if version_status == "behind":
    candidate_releases = [release for release in releases if compare_versions(local_version, release["version"]) == -1]
elif version_status == "unknown" and releases:
    candidate_releases = [releases[0]]

relevant_changes = []
non_relevant_changes = []

for release in candidate_releases:
    for index, change in enumerate(release.get("changes", []), start=1):
        relevance, reason, matched_traits = relevance_reason(change, traits)
        item = {
            "id": f"release:{release['version']}:{index}",
            "summary": change,
            "relevance": relevance,
            "reason": reason,
            "evidence": [f"Release {release['version']} published {release.get('published_at') or 'unknown date'}"]
            + [f"Matched repo trait: {trait}" for trait in matched_traits],
        }
        if relevance in {"high", "medium"}:
            relevant_changes.append(item)
        else:
            non_relevant_changes.append(item)

issue_sources = []
issue_signals = []
if include_issue_signals:
    if issue_source_id:
        issue_sources.append(issue_source_id)
    if issue_source_path.is_file():
        try:
            issue_signals = parse_issue_signals(issue_source_path.read_text())
        except Exception as exc:
            warnings.append(f"Failed to parse issue-signal source: {exc}")
    else:
        warnings.append("Issue-signal intake requested but no issue source was fetched")

for issue in issue_signals:
    relevance, reason, matched_traits = relevance_reason(issue["title"], traits, advisory=True)
    item = {
        "id": f"issue:{issue['id']}",
        "summary": issue["title"],
        "relevance": relevance,
        "reason": reason,
        "evidence": [f"Issue state: {issue['state']}"] + [f"Matched repo trait: {trait}" for trait in matched_traits],
    }
    if relevance in {"high", "medium"}:
        relevant_changes.append(item)
    else:
        non_relevant_changes.append(item)

relevant_changes.sort(key=lambda item: (-RELEVANCE_RANK[item["relevance"]], item["id"]))
non_relevant_changes.sort(key=lambda item: (-RELEVANCE_RANK[item["relevance"]], item["id"]))

evidence = []
if local_version != "missing":
    evidence.append(f"Detected local Codex CLI version {local_version}.")
else:
    evidence.append("Local Codex CLI version could not be detected from PATH.")

if release_fetch_ok and releases:
    evidence.append(f"Compared against latest upstream release {latest_version} from {release_source_id}.")
else:
    evidence.append(f"Primary upstream release source was unavailable: {release_source_id}.")

for note in local_notes:
    evidence.append(note)

if version_status == "behind":
    evidence.append(f"Local Codex CLI is behind the latest checked release by {len(candidate_releases)} scanned release window(s).")
elif version_status == "current":
    evidence.append("Local Codex CLI matches the latest checked release.")
elif version_status == "ahead":
    evidence.append("Local Codex CLI appears newer than the latest checked release source.")
else:
    evidence.append("Version comparison could not be completed confidently.")

if relevant_changes:
    evidence.append(f"Found {len(relevant_changes)} repository-relevant change(s) in the scanned evidence.")
else:
    evidence.append("No newer repository-relevant changes were found in the scanned evidence.")

if include_issue_signals:
    evidence.append(f"Issue-signal intake reviewed {len(issue_signals)} advisory item(s).")

for warning in warnings:
    if warning:
        evidence.append(warning)

high_count = sum(1 for item in relevant_changes if item["relevance"] == "high")
medium_count = sum(1 for item in relevant_changes if item["relevance"] == "medium")

if not release_fetch_ok or latest_version == "unknown":
    recommendation = "investigate"
elif version_status == "ahead":
    recommendation = "investigate"
elif version_status == "unknown":
    recommendation = "investigate"
elif version_status == "current":
    recommendation = "ignore"
elif high_count > 0 or (len(candidate_releases) >= 2 and medium_count > 0):
    recommendation = "upgrade-now"
elif medium_count > 0 or len(candidate_releases) >= 2:
    recommendation = "upgrade-later"
else:
    recommendation = "upgrade-later"

if issue_action_requested == "none":
    issue_action = {
        "mode": "none",
        "requested": False,
        "notes": ["Tracker sync not requested."],
    }
else:
    notes = [
        f"Requested issue action '{issue_action_requested}' was recorded without tracker mutation.",
        "Beads mutation remains deferred until the User Story 3 implementation slice lands.",
    ]
    issue_action = {
        "mode": "skipped",
        "requested": True,
        "notes": notes,
    }
    if issue_target:
        issue_action["target"] = issue_target

report = {
    "checked_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "local_version": local_version,
    "latest_version": latest_version,
    "version_status": version_status,
    "local_features": local_features,
    "repo_workflow_traits": repo_traits,
    "sources": {
        "release_source": release_source_id,
        "issue_signals_included": include_issue_signals,
    },
    "relevant_changes": relevant_changes,
    "non_relevant_changes": non_relevant_changes,
    "recommendation": recommendation,
    "evidence": evidence,
    "issue_action": issue_action,
}

if issue_sources:
    report["sources"]["issue_sources"] = issue_sources

print(json.dumps(report, indent=2))
PY

    perform_issue_sync
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

    local recommendation
    recommendation="$(jq -r '.recommendation' "$REPORT_PATH")"
    if [[ "$recommendation" == "investigate" ]]; then
        EXIT_CODE=0
    fi

    return "$EXIT_CODE"
}

main "$@"
