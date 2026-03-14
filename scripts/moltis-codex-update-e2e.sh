#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
RUN_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-update-run.sh"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/codex-update-skill"
DEFAULT_RELEASE_FILE="${FIXTURE_DIR}/releases-0.114.0.html"
DEFAULT_ISSUE_SIGNALS_FILE="${FIXTURE_DIR}/issue-signals.json"
DEFAULT_PROFILE_FILE="${FIXTURE_DIR}/project-profile-basic.json"

MODE="hermetic"
OUTPUT_PATH="${PROJECT_ROOT}/.tmp/current/moltis-codex-update-e2e-report.json"
KEEP_TEMP=false
VERBOSE=false

TMP_DIR=""
ARTIFACT_DIR=""
RUN_ID=""
STARTED_AT=""
FINISHED_AT=""
START_MS=0
DURATION_MS=0
STATUS=""
ERROR_CODE=""
ERROR_MESSAGE=""
CONTEXT_JSON='{}'

usage() {
    cat <<'EOF'
Usage: scripts/moltis-codex-update-e2e.sh [options]

Run a hermetic Moltis-native Codex update skill proof:
  manual with profile -> scheduler send -> scheduler suppress
plus audit evidence for both paths.

Options:
  --mode MODE    hermetic (default: hermetic)
  --output PATH  JSON report path
  --keep-temp    Keep temp artifacts for operator inspection
  --verbose      Enable verbose logs
  -h, --help     Show help
EOF
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        printf '[moltis-codex-update-e2e] %s\n' "$*" >&2
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
        printf '%s\n' "$(( sec * 1000 + 10#${ns:0:3} ))"
        return 0
    fi
    printf '%s\n' "$(( sec * 1000 ))"
}

ensure_parent_dir() {
    mkdir -p "$(dirname "$1")"
}

copy_artifact() {
    local source_path="$1"
    local target_name="$2"
    local target_path="${ARTIFACT_DIR}/${target_name}"
    cp "$source_path" "$target_path"
    printf '%s\n' "$target_path"
}

write_report() {
    ensure_parent_dir "$OUTPUT_PATH"
    jq -n \
        --arg run_id "$RUN_ID" \
        --arg mode "$MODE" \
        --arg started_at "$STARTED_AT" \
        --arg finished_at "$FINISHED_AT" \
        --arg status "$STATUS" \
        --arg error_code "$ERROR_CODE" \
        --arg error_message "$ERROR_MESSAGE" \
        --argjson duration_ms "$DURATION_MS" \
        --argjson context "$CONTEXT_JSON" \
        '{
          run_id: $run_id,
          mode: $mode,
          started_at: $started_at,
          finished_at: $finished_at,
          duration_ms: $duration_ms,
          status: $status,
          error_code: (if $error_code == "" then null else $error_code end),
          error_message: (if $error_message == "" then null else $error_message end),
          context: $context
        }' > "$OUTPUT_PATH"
}

finish_with_status() {
    local exit_code="$1"
    local finished_ms
    finished_ms="$(now_ms)"
    FINISHED_AT="$(now_iso)"
    if [[ "$START_MS" =~ ^[0-9]+$ && "$finished_ms" =~ ^[0-9]+$ ]]; then
        DURATION_MS=$(( finished_ms - START_MS ))
        if [[ "$DURATION_MS" -lt 0 ]]; then
            DURATION_MS=0
        fi
    fi
    write_report
    exit "$exit_code"
}

precondition_fail() {
    STATUS="precondition_failed"
    ERROR_CODE="precondition"
    ERROR_MESSAGE="$1"
    finish_with_status 2
}

scenario_fail() {
    STATUS="failed"
    ERROR_CODE="scenario"
    ERROR_MESSAGE="$1"
    finish_with_status 4
}

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" && "$KEEP_TEMP" != "true" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                MODE="${2:?missing value for --mode}"
                shift 2
                ;;
            --output)
                OUTPUT_PATH="${2:?missing value for --output}"
                shift 2
                ;;
            --keep-temp)
                KEEP_TEMP=true
                shift
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
                precondition_fail "Unknown option: $1"
                ;;
        esac
    done
}

require_dependencies() {
    local missing=() cmd
    for cmd in bash jq mktemp python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        CONTEXT_JSON="$(printf '%s\n' "${missing[@]}" | jq -R . | jq -cs '{missing_dependencies: .}')"
        precondition_fail "Missing required dependencies for Moltis Codex update E2E"
    fi

    [[ "$MODE" == "hermetic" ]] || precondition_fail "--mode currently supports only hermetic"
    [[ -x "$RUN_SCRIPT" ]] || precondition_fail "Run script is not executable: $RUN_SCRIPT"
    [[ -f "$DEFAULT_RELEASE_FILE" ]] || precondition_fail "Release fixture not found: $DEFAULT_RELEASE_FILE"
    [[ -f "$DEFAULT_ISSUE_SIGNALS_FILE" ]] || precondition_fail "Issue signals fixture not found: $DEFAULT_ISSUE_SIGNALS_FILE"
    [[ -f "$DEFAULT_PROFILE_FILE" ]] || precondition_fail "Profile fixture not found: $DEFAULT_PROFILE_FILE"
}

init_runtime() {
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    STARTED_AT="$(now_iso)"
    START_MS="$(now_ms)"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/moltis-codex-update-e2e.XXXXXX")"
    ARTIFACT_DIR="${OUTPUT_PATH%.json}.artifacts"
    mkdir -p "$ARTIFACT_DIR"
}

create_fake_sender() {
    local bin_dir="$1"
    local state_dir="$2"
    mkdir -p "$bin_dir" "$state_dir"
    cat > "${bin_dir}/telegram-bot-send.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${FAKE_MOLTIS_CODEX_UPDATE_SENDER_DIR:?}"
count_file="${state_dir}/count.txt"
calls_dir="${state_dir}/calls"
mkdir -p "$calls_dir"
count=0
if [[ -f "$count_file" ]]; then
    count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

chat_id=""
text=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --chat-id)
            chat_id="${2:-}"
            shift 2
            ;;
        --text)
            text="${2:-}"
            shift 2
            ;;
        --json|--disable-notification)
            shift
            ;;
        *)
            shift
            ;;
    esac
done

jq -n \
  --argjson call "$count" \
  --arg chat_id "$chat_id" \
  --arg text "$text" \
  '{call: $call, chat_id: $chat_id, text: $text}' > "${calls_dir}/${count}.json"

printf '{"ok":true,"result":{"message_id":%s,"chat":{"id":"%s"}}}\n' "$((800 + count))" "$chat_id"
EOF
    chmod +x "${bin_dir}/telegram-bot-send.sh"
}

assert_file_exists() {
    [[ -f "$1" ]] || scenario_fail "$2"
}

assert_json_eq() {
    local file="$1" query="$2" expected="$3" message="$4" actual
    actual="$(jq -r "$query" "$file")"
    [[ "$actual" == "$expected" ]] || scenario_fail "$message (expected: $expected, got: $actual)"
}

run_manual_profile_path() {
    local base_dir="$1"
    mkdir -p "$base_dir"
    bash "$RUN_SCRIPT" \
        --mode manual \
        --state-file "$base_dir/state.json" \
        --audit-dir "$base_dir/audit" \
        --release-file "$DEFAULT_RELEASE_FILE" \
        --include-issue-signals \
        --issue-signals-file "$DEFAULT_ISSUE_SIGNALS_FILE" \
        --profile-file "$DEFAULT_PROFILE_FILE" \
        --json-out "$base_dir/report.json" \
        --summary-out "$base_dir/summary.md" \
        --stdout none >/dev/null

    assert_file_exists "$base_dir/report.json" "Manual path did not write a JSON report"
    assert_file_exists "$base_dir/summary.md" "Manual path did not write a summary"
    assert_json_eq "$base_dir/report.json" '.decision.decision' "upgrade-now" "Manual path should find a fresh actionable upstream state"
    assert_json_eq "$base_dir/report.json" '.profile.status' "loaded" "Manual path should load the project profile"
    assert_file_exists "$(jq -r '.audit.record_path' "$base_dir/report.json")" "Manual path should write an audit JSON record"
}

run_scheduler_delivery_path() {
    local base_dir="$1" sender_script="$2" sender_state="$3"
    mkdir -p "$base_dir"

    FAKE_MOLTIS_CODEX_UPDATE_SENDER_DIR="$sender_state" \
    bash "$RUN_SCRIPT" \
        --mode scheduler \
        --state-file "$base_dir/state.json" \
        --audit-dir "$base_dir/audit" \
        --release-file "$DEFAULT_RELEASE_FILE" \
        --include-issue-signals \
        --issue-signals-file "$DEFAULT_ISSUE_SIGNALS_FILE" \
        --profile-file "$DEFAULT_PROFILE_FILE" \
        --telegram-enabled \
        --telegram-chat-id 262872984 \
        --telegram-send-script "$sender_script" \
        --json-out "$base_dir/report-first.json" \
        --summary-out "$base_dir/summary-first.md" \
        --stdout none >/dev/null

    assert_json_eq "$base_dir/report-first.json" '.delivery.status' "sent" "First scheduler run should send a Telegram alert"
    assert_file_exists "$(jq -r '.audit.record_path' "$base_dir/report-first.json")" "First scheduler run should write an audit JSON record"

    FAKE_MOLTIS_CODEX_UPDATE_SENDER_DIR="$sender_state" \
    bash "$RUN_SCRIPT" \
        --mode scheduler \
        --state-file "$base_dir/state.json" \
        --audit-dir "$base_dir/audit" \
        --release-file "$DEFAULT_RELEASE_FILE" \
        --include-issue-signals \
        --issue-signals-file "$DEFAULT_ISSUE_SIGNALS_FILE" \
        --profile-file "$DEFAULT_PROFILE_FILE" \
        --telegram-enabled \
        --telegram-chat-id 262872984 \
        --telegram-send-script "$sender_script" \
        --json-out "$base_dir/report-second.json" \
        --summary-out "$base_dir/summary-second.md" \
        --stdout none >/dev/null

    assert_json_eq "$base_dir/report-second.json" '.delivery.status' "suppressed" "Second scheduler run should suppress the duplicate fingerprint"
}

build_context() {
    local manual_dir="$1" scheduler_dir="$2" sender_state="$3"
    local sender_call_count="0"
    local manual_audit_record manual_audit_summary scheduler_first_audit scheduler_second_audit
    local manual_report_copy manual_summary_copy scheduler_first_report_copy scheduler_second_report_copy sender_call_copy
    if [[ -f "${sender_state}/count.txt" ]]; then
        sender_call_count="$(cat "${sender_state}/count.txt")"
    fi
    manual_audit_record="$(copy_artifact "$(jq -r '.audit.record_path' "$manual_dir/report.json")" "manual-audit.json")"
    manual_audit_summary="$(copy_artifact "$(jq -r '.audit.summary_path' "$manual_dir/report.json")" "manual-audit.summary.md")"
    scheduler_first_audit="$(copy_artifact "$(jq -r '.audit.record_path' "$scheduler_dir/report-first.json")" "scheduler-first-audit.json")"
    scheduler_second_audit="$(copy_artifact "$(jq -r '.audit.record_path' "$scheduler_dir/report-second.json")" "scheduler-second-audit.json")"
    manual_report_copy="$(copy_artifact "$manual_dir/report.json" "manual-report.json")"
    manual_summary_copy="$(copy_artifact "$manual_dir/summary.md" "manual-summary.md")"
    scheduler_first_report_copy="$(copy_artifact "$scheduler_dir/report-first.json" "scheduler-first-report.json")"
    scheduler_second_report_copy="$(copy_artifact "$scheduler_dir/report-second.json" "scheduler-second-report.json")"
    sender_call_copy="$(copy_artifact "${sender_state}/calls/1.json" "scheduler-first-send.json")"

    CONTEXT_JSON="$(
        jq -n \
            --arg temp_dir "$TMP_DIR" \
            --arg artifact_dir "$ARTIFACT_DIR" \
            --argjson manual "$(jq '.' "$manual_dir/report.json")" \
            --argjson scheduler_first "$(jq '.' "$scheduler_dir/report-first.json")" \
            --argjson scheduler_second "$(jq '.' "$scheduler_dir/report-second.json")" \
            --argjson sender_call_count "$sender_call_count" \
            --arg alert_text "$(jq -r '.text' "${sender_state}/calls/1.json")" \
            --arg manual_audit_record "$manual_audit_record" \
            --arg manual_audit_summary "$manual_audit_summary" \
            --arg scheduler_first_audit "$scheduler_first_audit" \
            --arg scheduler_second_audit "$scheduler_second_audit" \
            --arg manual_report_copy "$manual_report_copy" \
            --arg manual_summary_copy "$manual_summary_copy" \
            --arg scheduler_first_report_copy "$scheduler_first_report_copy" \
            --arg scheduler_second_report_copy "$scheduler_second_report_copy" \
            --arg sender_call_copy "$sender_call_copy" \
            '{
              temp_dir: $temp_dir,
              artifact_dir: $artifact_dir,
              manual: {
                run_id: $manual.run_id,
                decision: $manual.decision.decision,
                profile_status: $manual.profile.status,
                report_path: $manual_report_copy,
                summary_path: $manual_summary_copy,
                audit_record_path: $manual_audit_record,
                audit_summary_path: $manual_audit_summary,
                recommendation_title_ru: ($manual.recommendation_bundle.items[0].title_ru // "")
              },
              scheduler: {
                first: {
                  run_id: $scheduler_first.run_id,
                  delivery_status: $scheduler_first.delivery.status,
                  message_id: $scheduler_first.delivery.message_id,
                  report_path: $scheduler_first_report_copy,
                  audit_record_path: $scheduler_first_audit
                },
                second: {
                  run_id: $scheduler_second.run_id,
                  delivery_status: $scheduler_second.delivery.status,
                  report_path: $scheduler_second_report_copy,
                  audit_record_path: $scheduler_second_audit
                },
                sender_call_count: $sender_call_count,
                alert_text: $alert_text,
                sender_call_path: $sender_call_copy
              }
            }'
    )"
}

main() {
    parse_args "$@"
    require_dependencies
    init_runtime

    local manual_dir scheduler_dir fake_bin_dir fake_sender_dir fake_sender_script
    manual_dir="${TMP_DIR}/manual"
    scheduler_dir="${TMP_DIR}/scheduler"
    fake_bin_dir="${TMP_DIR}/bin"
    fake_sender_dir="${TMP_DIR}/fake-sender"

    create_fake_sender "$fake_bin_dir" "$fake_sender_dir"
    fake_sender_script="${fake_bin_dir}/telegram-bot-send.sh"

    log "Run manual profile path"
    run_manual_profile_path "$manual_dir"

    log "Run scheduler delivery path"
    run_scheduler_delivery_path "$scheduler_dir" "$fake_sender_script" "$fake_sender_dir"

    local sender_call_count="0"
    if [[ -f "${fake_sender_dir}/count.txt" ]]; then
        sender_call_count="$(cat "${fake_sender_dir}/count.txt")"
    fi
    [[ "$sender_call_count" == "1" ]] || scenario_fail "Scheduler path should call the sender exactly once for duplicate suppression proof"

    build_context "$manual_dir" "$scheduler_dir" "$fake_sender_dir"
    STATUS="completed"
    finish_with_status 0
}

main "$@"
