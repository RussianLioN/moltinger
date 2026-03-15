#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
INTAKE_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-advisory-intake.sh"
ROUTER_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-advisory-router.sh"
STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-advisory-session-store.sh"
DEFAULT_EVENT_FILE="${PROJECT_ROOT}/tests/fixtures/codex-advisory-events/advisory-event-interactive-ready.json"

MODE="hermetic"
OUTPUT_PATH="${PROJECT_ROOT}/.tmp/current/codex-advisory-e2e-report.json"
EVENT_FILE="${DEFAULT_EVENT_FILE}"
KEEP_TEMP=false
VERBOSE=false

RUN_ID=""
STARTED_AT=""
FINISHED_AT=""
START_MS=0
DURATION_MS=0
TRANSPORT="telegram_codex_advisory_hermetic"
OBSERVED_RESPONSE=""
STATUS=""
ERROR_CODE=""
ERROR_MESSAGE=""
CONTEXT_JSON='{}'

TMP_DIR=""
PERSISTED_TMP_DIR=""

usage() {
    cat <<'EOF'
Usage: scripts/codex-advisory-e2e.sh [options]

Run a Moltis-native Codex advisory hermetic E2E scenario:
  alert -> callback accept -> immediate recommendations
plus degraded one-way validation with audit evidence.

Options:
  --mode MODE        hermetic (default: hermetic)
  --output PATH      JSON report path
  --event-file PATH  Advisory event fixture path
  --keep-temp        Keep temporary artifacts for operator inspection
  --verbose          Enable verbose logs
  -h, --help         Show help
EOF
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        printf '[codex-advisory-e2e] %s\n' "$*" >&2
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

write_report() {
    ensure_parent_dir "$OUTPUT_PATH"
    jq -n \
        --arg run_id "$RUN_ID" \
        --arg mode "$MODE" \
        --arg started_at "$STARTED_AT" \
        --arg finished_at "$FINISHED_AT" \
        --arg transport "$TRANSPORT" \
        --arg observed_response "$OBSERVED_RESPONSE" \
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
            transport: $transport,
            observed_response: (if $observed_response == "" then null else $observed_response end),
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

upstream_fail() {
    STATUS="upstream_failed"
    ERROR_CODE="upstream"
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
            --event-file)
                EVENT_FILE="${2:?missing value for --event-file}"
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
    local missing=()
    local cmd
    for cmd in bash jq mktemp python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        CONTEXT_JSON="$(printf '%s\n' "${missing[@]}" | jq -R . | jq -cs '{missing_dependencies: .}')"
        precondition_fail "Missing required dependencies for codex advisory E2E"
    fi

    [[ "$MODE" == "hermetic" ]] || precondition_fail "--mode currently supports only hermetic"
    [[ -x "$INTAKE_SCRIPT" ]] || precondition_fail "Intake script is not executable: $INTAKE_SCRIPT"
    [[ -x "$ROUTER_SCRIPT" ]] || precondition_fail "Router script is not executable: $ROUTER_SCRIPT"
    [[ -x "$STORE_SCRIPT" ]] || precondition_fail "Session store script is not executable: $STORE_SCRIPT"
    [[ -f "$EVENT_FILE" ]] || precondition_fail "Event fixture not found: $EVENT_FILE"
}

init_runtime() {
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    STARTED_AT="$(now_iso)"
    START_MS="$(now_ms)"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-advisory-e2e.XXXXXX")"
    if [[ "$KEEP_TEMP" == "true" ]]; then
        PERSISTED_TMP_DIR="$TMP_DIR"
    fi
}

create_fake_sender() {
    local state_dir="$1"
    local bin_dir="$2"
    mkdir -p "$state_dir" "$bin_dir"
    cat > "${bin_dir}/telegram-bot-send.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${CODEX_ADVISORY_E2E_FAKE_TELEGRAM_STATE_DIR:?}"
count_file="${state_dir}/count.txt"
count=0
if [[ -f "$count_file" ]]; then
    count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

chat_id=""
text=""
reply_to=""
reply_markup_json=""
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
        --reply-to)
            reply_to="${2:-}"
            shift 2
            ;;
        --reply-markup-json)
            reply_markup_json="${2:-}"
            shift 2
            ;;
        --json)
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
  --arg reply_to "$reply_to" \
  --arg reply_markup_json "$reply_markup_json" \
  '{
    call: $call,
    chat_id: $chat_id,
    text: $text,
    reply_to: (if $reply_to == "" then null else ($reply_to | tonumber) end),
    reply_markup_json: (if $reply_markup_json == "" then null else ($reply_markup_json | fromjson?) end)
  }' > "${state_dir}/call-${count}.json"

printf '{"ok":true,"result":{"message_id":%s}}\n' "$count"
EOF
    chmod +x "${bin_dir}/telegram-bot-send.sh"
}

assert_jq() {
    local file="$1"
    local expr="$2"
    local message="$3"
    if ! jq -e "$expr" "$file" >/dev/null 2>&1; then
        CONTEXT_JSON="$(jq -cn --arg file "$file" --arg expr "$expr" --arg message "$message" '{assertion_failed:{file:$file, expr:$expr, message:$message}}')"
        upstream_fail "$message"
    fi
}

assert_text_contains() {
    local text="$1"
    local needle="$2"
    local message="$3"
    if ! grep -Fq "$needle" <<<"$text"; then
        CONTEXT_JSON="$(jq -cn --arg text "$text" --arg needle "$needle" --arg message "$message" '{assertion_failed:{needle:$needle, message:$message, text:$text}}')"
        upstream_fail "$message"
    fi
}

assert_text_not_contains() {
    local text="$1"
    local needle="$2"
    local message="$3"
    if grep -Fq "$needle" <<<"$text"; then
        CONTEXT_JSON="$(jq -cn --arg text "$text" --arg needle "$needle" --arg message "$message" '{assertion_failed:{needle:$needle, message:$message, text:$text}}')"
        upstream_fail "$message"
    fi
}

run_hermetic() {
    local healthy_dir degraded_dir
    local fake_bin_dir fake_state_dir fake_env
    local degraded_fake_bin degraded_fake_state degraded_fake_env
    local session_store_dir audit_dir degraded_audit_dir
    local intake_report router_result degraded_report
    local session_id callback_data session_file session_audit_file degraded_event_audit_file
    local session_audit_json degraded_audit_json
    local alert_text followup_text degraded_text

    healthy_dir="${TMP_DIR}/healthy"
    degraded_dir="${TMP_DIR}/degraded"
    fake_bin_dir="${TMP_DIR}/fake-bin"
    fake_state_dir="${TMP_DIR}/fake-state"
    fake_env="${TMP_DIR}/fake.env"
    degraded_fake_bin="${TMP_DIR}/degraded-fake-bin"
    degraded_fake_state="${TMP_DIR}/degraded-fake-state"
    degraded_fake_env="${TMP_DIR}/degraded.env"
    session_store_dir="${healthy_dir}/session-store"
    audit_dir="${healthy_dir}/audit"
    degraded_audit_dir="${degraded_dir}/audit"
    intake_report="${healthy_dir}/intake-report.json"
    router_result="${healthy_dir}/router-result.json"
    degraded_report="${degraded_dir}/intake-report.json"

    mkdir -p "$healthy_dir" "$degraded_dir"
    printf 'TELEGRAM_ALLOWED_USERS=262872984\nTELEGRAM_BOT_TOKEN=fake-token\n' > "$fake_env"
    printf 'TELEGRAM_ALLOWED_USERS=262872984\nTELEGRAM_BOT_TOKEN=fake-token\n' > "$degraded_fake_env"
    create_fake_sender "$fake_state_dir" "$fake_bin_dir"
    create_fake_sender "$degraded_fake_state" "$degraded_fake_bin"

    log "Running healthy interactive advisory path"
    CODEX_ADVISORY_E2E_FAKE_TELEGRAM_STATE_DIR="$fake_state_dir" \
    bash "$INTAKE_SCRIPT" \
        --event-file "$EVENT_FILE" \
        --send true \
        --chat-id 262872984 \
        --interactive-mode inline_callbacks \
        --session-store-script "$STORE_SCRIPT" \
        --session-store-dir "$session_store_dir" \
        --audit-dir "$audit_dir" \
        --telegram-send-script "${fake_bin_dir}/telegram-bot-send.sh" \
        --telegram-env-file "$fake_env" \
        --json-out "$intake_report" \
        --stdout none

    assert_jq "$intake_report" '.status == "sent"' "Healthy intake should send the advisory alert"
    assert_jq "$intake_report" '.alert.interactive_mode == "inline_callbacks"' "Healthy intake should keep interactive mode"
    assert_jq "$intake_report" '.session.session_id != null' "Healthy intake should open an advisory session"

    session_id="$(jq -r '.session.session_id // ""' "$intake_report")"
    [[ -n "$session_id" ]] || upstream_fail "Healthy intake did not return a session id"
    callback_data="$(jq -r '.alert.reply_markup.inline_keyboard[0][0].callback_data // ""' "$intake_report")"
    [[ -n "$callback_data" ]] || upstream_fail "Healthy intake did not return callback data"
    session_file="${session_store_dir}/${session_id}.json"
    session_audit_file="${audit_dir}/${session_id}.json"
    degraded_event_audit_file="${degraded_audit_dir}/$(jq -r '.event_id' "$EVENT_FILE").json"

    [[ -f "$session_file" ]] || upstream_fail "Healthy intake did not persist a session record"
    [[ -f "$session_audit_file" ]] || upstream_fail "Healthy intake did not mirror the session into the audit dir"
    assert_jq "$session_file" '.interaction_record.followup_status == "awaiting_user"' "Session should start in awaiting_user state"
    alert_text="$(jq -r '.text // ""' "${fake_state_dir}/call-1.json")"
    assert_text_contains "$alert_text" "Если нужны практические рекомендации" "Healthy alert should advertise inline callback actions"
    assert_text_not_contains "$alert_text" "/codex_" "Healthy alert must not advertise retired repo-side commands"

    log "Routing accept callback"
    CODEX_ADVISORY_E2E_FAKE_TELEGRAM_STATE_DIR="$fake_state_dir" \
    bash "$ROUTER_SCRIPT" \
        --store-script "$STORE_SCRIPT" \
        --store-dir "$session_store_dir" \
        --audit-dir "$audit_dir" \
        --callback-data "$callback_data" \
        --chat-id 262872984 \
        --actor-id 262872984 \
        --reply-to 1 \
        --telegram-send-script "${fake_bin_dir}/telegram-bot-send.sh" \
        --telegram-env-file "$fake_env" \
        --send-reply true \
        --json-out "$router_result" \
        --stdout none

    assert_jq "$router_result" '.decision == "accept"' "Router should accept the callback"
    assert_jq "$router_result" '.delivery.status == "sent"' "Router should send recommendations immediately"
    assert_jq "$session_file" '.session.status == "accepted"' "Session should be marked accepted"
    assert_jq "$session_file" '.interaction_record.followup_status == "sent"' "Session should persist sent follow-up status"
    assert_jq "$session_audit_file" '.interaction_record.followup_status == "sent"' "Audit mirror should show sent follow-up status"
    assert_jq "$session_audit_file" '.decision.decision == "accept"' "Audit mirror should show accept decision"
    session_audit_json="$(jq -c '.' "$session_audit_file")"
    followup_text="$(jq -r '.text // ""' "${fake_state_dir}/call-2.json")"
    assert_text_contains "$followup_text" "Практические рекомендации" "Follow-up should contain the recommendations headline"
    assert_text_contains "$followup_text" "Что проверить в первую очередь" "Follow-up should contain priority checks"
    OBSERVED_RESPONSE="$followup_text"

    log "Running degraded one-way advisory path"
    CODEX_ADVISORY_E2E_FAKE_TELEGRAM_STATE_DIR="$degraded_fake_state" \
    bash "$INTAKE_SCRIPT" \
        --event-file "$EVENT_FILE" \
        --send true \
        --chat-id 262872984 \
        --interactive-mode one_way_only \
        --audit-dir "$degraded_audit_dir" \
        --telegram-send-script "${degraded_fake_bin}/telegram-bot-send.sh" \
        --telegram-env-file "$degraded_fake_env" \
        --json-out "$degraded_report" \
        --stdout none

    assert_jq "$degraded_report" '.status == "sent"' "Degraded intake should still send the advisory alert"
    assert_jq "$degraded_report" '.alert.interactive_mode == "one_way_only"' "Degraded intake should declare one-way mode"
    assert_jq "$degraded_report" '.session == null' "Degraded intake must not open an advisory session"
    [[ -f "$degraded_event_audit_file" ]] || upstream_fail "Degraded intake did not persist an audit record"
    assert_jq "$degraded_event_audit_file" '.degraded_reason != ""' "Degraded audit record should persist the degraded reason"
    degraded_audit_json="$(jq -c '.' "$degraded_event_audit_file")"
    degraded_text="$(jq -r '.text // ""' "${degraded_fake_state}/call-1.json")"
    assert_text_contains "$degraded_text" "one-way alert" "Degraded alert should explain one-way delivery"
    assert_text_not_contains "$degraded_text" "Если нужны практические рекомендации" "Degraded alert must not advertise an interactive follow-up"

    CONTEXT_JSON="$(jq -n \
        --arg intake_report "$intake_report" \
        --arg router_result "$router_result" \
        --arg degraded_report "$degraded_report" \
        --arg session_file "$session_file" \
        --arg session_audit_file "$session_audit_file" \
        --arg degraded_audit_file "$degraded_event_audit_file" \
        --argjson session_audit_record "$session_audit_json" \
        --argjson degraded_audit_record "$degraded_audit_json" \
        --arg session_id "$session_id" \
        --arg alert_text "$alert_text" \
        --arg followup_text "$followup_text" \
        --arg degraded_text "$degraded_text" \
        --arg temp_dir "${PERSISTED_TMP_DIR}" \
        '{
            healthy: {
                session_id: $session_id,
                intake_report_path: $intake_report,
                router_result_path: $router_result,
                session_record_path: $session_file,
                session_audit_path: (if $temp_dir == "" then null else $session_audit_file end),
                session_audit_record: $session_audit_record,
                alert_text: $alert_text,
                followup_text: $followup_text
            },
            degraded: {
                intake_report_path: $degraded_report,
                audit_record_path: (if $temp_dir == "" then null else $degraded_audit_file end),
                audit_record: $degraded_audit_record,
                alert_text: $degraded_text
            },
            kept_temp_dir: (if $temp_dir == "" then null else $temp_dir end)
        }')"
}

main() {
    parse_args "$@"
    require_dependencies
    init_runtime

    case "$MODE" in
        hermetic)
            run_hermetic
            ;;
        *)
            precondition_fail "Unsupported mode"
            ;;
    esac

    STATUS="completed"
    finish_with_status 0
}

main "$@"
