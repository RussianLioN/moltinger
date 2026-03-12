#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
WATCHER_SCRIPT="${PROJECT_ROOT}/scripts/codex-cli-upstream-watcher.sh"
ROUTER_SCRIPT="${PROJECT_ROOT}/scripts/moltis-codex-consent-router.sh"
STORE_SCRIPT="${PROJECT_ROOT}/scripts/codex-telegram-consent-store.sh"
DEFAULT_RELEASE_FILE="${PROJECT_ROOT}/tests/fixtures/codex-upstream-watcher/releases-0.114.0.html"
DEFAULT_ISSUE_SIGNALS_FILE="${PROJECT_ROOT}/tests/fixtures/codex-upstream-watcher/issue-signals.json"

MODE="hermetic"
OUTPUT_PATH="${PROJECT_ROOT}/.tmp/current/codex-telegram-consent-e2e-report.json"
RELEASE_FILE="${DEFAULT_RELEASE_FILE}"
ISSUE_SIGNALS_FILE="${DEFAULT_ISSUE_SIGNALS_FILE}"
KEEP_TEMP=false
VERBOSE=false

RUN_ID=""
STARTED_AT=""
FINISHED_AT=""
START_MS=0
DURATION_MS=0
TRANSPORT="telegram_codex_consent_hermetic"
OBSERVED_RESPONSE=""
STATUS=""
ERROR_CODE=""
ERROR_MESSAGE=""
CONTEXT_JSON='{}'

TMP_DIR=""
PERSISTED_TMP_DIR=""

usage() {
    cat <<'EOF'
Usage: scripts/codex-telegram-consent-e2e.sh [options]

Run a Codex-specific hermetic E2E scenario:
  alert -> consent action -> immediate recommendations
plus degraded fallback validation for one-way alerts.

Options:
  --mode MODE                hermetic (default: hermetic)
  --output PATH              JSON report path
  --release-file PATH        Fixture-backed release source
  --issue-signals-file PATH  Fixture-backed issue signals source
  --keep-temp                Keep temporary artifacts for operator inspection
  --verbose                  Enable verbose logs
  -h, --help                 Show help
EOF
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        printf '[codex-consent-e2e] %s\n' "$*" >&2
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
            --release-file)
                RELEASE_FILE="${2:?missing value for --release-file}"
                shift 2
                ;;
            --issue-signals-file)
                ISSUE_SIGNALS_FILE="${2:?missing value for --issue-signals-file}"
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
        precondition_fail "Missing required dependencies for codex consent E2E"
    fi

    [[ "$MODE" == "hermetic" ]] || precondition_fail "--mode currently supports only hermetic"
    [[ -x "$WATCHER_SCRIPT" ]] || precondition_fail "Watcher script is not executable: $WATCHER_SCRIPT"
    [[ -x "$ROUTER_SCRIPT" ]] || precondition_fail "Router script is not executable: $ROUTER_SCRIPT"
    [[ -x "$STORE_SCRIPT" ]] || precondition_fail "Consent store script is not executable: $STORE_SCRIPT"
    [[ -f "$RELEASE_FILE" ]] || precondition_fail "Release fixture not found: $RELEASE_FILE"
    [[ -f "$ISSUE_SIGNALS_FILE" ]] || precondition_fail "Issue-signals fixture not found: $ISSUE_SIGNALS_FILE"
}

init_runtime() {
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    STARTED_AT="$(now_iso)"
    START_MS="$(now_ms)"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-consent-e2e.XXXXXX")"
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

state_dir="${CODEX_CONSENT_E2E_FAKE_TELEGRAM_STATE_DIR:?}"
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
disable_notification=false
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
        --disable-notification)
            disable_notification=true
            shift
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
  --argjson disable_notification "$disable_notification" \
  '{
    call: $call,
    chat_id: $chat_id,
    text: $text,
    reply_to: (if $reply_to == "" then null else ($reply_to | tonumber) end),
    reply_markup_json: (if $reply_markup_json == "" then null else ($reply_markup_json | fromjson?) end),
    disable_notification: $disable_notification
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
    local alert_dir consent_store_dir fake_bin_dir fake_state_dir fake_env
    local watcher_report watcher_summary watcher_state
    local request_id action_token chat_id consent_record
    local alert_text router_event router_result consent_text
    local degraded_dir degraded_fake_bin degraded_fake_state degraded_fake_env
    local degraded_report degraded_summary degraded_state degraded_text

    alert_dir="${TMP_DIR}/alert"
    consent_store_dir="${TMP_DIR}/consent-store"
    fake_bin_dir="${TMP_DIR}/fake-bin"
    fake_state_dir="${TMP_DIR}/fake-state"
    fake_env="${TMP_DIR}/fake.env"
    watcher_report="${alert_dir}/watcher-report.json"
    watcher_summary="${alert_dir}/watcher-summary.md"
    watcher_state="${alert_dir}/watcher-state.json"

    degraded_dir="${TMP_DIR}/degraded"
    degraded_fake_bin="${TMP_DIR}/degraded-fake-bin"
    degraded_fake_state="${TMP_DIR}/degraded-fake-state"
    degraded_fake_env="${TMP_DIR}/degraded.env"
    degraded_report="${degraded_dir}/watcher-report.json"
    degraded_summary="${degraded_dir}/watcher-summary.md"
    degraded_state="${degraded_dir}/watcher-state.json"

    mkdir -p "$alert_dir" "$degraded_dir"
    printf 'TELEGRAM_ALLOWED_USERS=262872984\nTELEGRAM_BOT_TOKEN=fake-token\n' > "$fake_env"
    printf 'TELEGRAM_ALLOWED_USERS=262872984\nTELEGRAM_BOT_TOKEN=fake-token\n' > "$degraded_fake_env"
    create_fake_sender "$fake_state_dir" "$fake_bin_dir"
    create_fake_sender "$degraded_fake_state" "$degraded_fake_bin"

    log "Running consent-capable watcher alert"
    CODEX_CONSENT_E2E_FAKE_TELEGRAM_STATE_DIR="$fake_state_dir" \
    CODEX_UPSTREAM_WATCHER_TELEGRAM_COMMAND_HOOK_READY=true \
    bash "$WATCHER_SCRIPT" \
        --mode scheduler \
        --state-file "$watcher_state" \
        --release-file "$RELEASE_FILE" \
        --include-issue-signals \
        --issue-signals-file "$ISSUE_SIGNALS_FILE" \
        --telegram-enabled \
        --telegram-env-file "$fake_env" \
        --telegram-send-script "${fake_bin_dir}/telegram-bot-send.sh" \
        --telegram-consent-store-script "$STORE_SCRIPT" \
        --telegram-consent-store-dir "$consent_store_dir" \
        --json-out "$watcher_report" \
        --summary-out "$watcher_summary" \
        --stdout none

    assert_jq "$watcher_report" '.decision.status == "deliver"' "Watcher should deliver a fresh consent-capable alert"
    assert_jq "$watcher_report" '.followup.consent.status == "pending"' "Watcher should open a pending consent flow"
    assert_jq "$watcher_report" '.followup.consent.router_mode == "authoritative"' "Watcher should advertise authoritative routing"
    assert_jq "$watcher_report" '.automation.alert.consent_requested == true' "Watcher should request consent in authoritative mode"

    request_id="$(jq -r '.followup.consent.pending_state.request_id // ""' "$watcher_report")"
    [[ -n "$request_id" ]] || upstream_fail "Watcher report did not expose request_id for the consent flow"
    consent_record="${consent_store_dir}/${request_id}.json"
    [[ -f "$consent_record" ]] || upstream_fail "Watcher did not persist the shared consent record"
    chat_id="$(jq -r '.request.chat_id // ""' "$consent_record")"
    [[ -n "$chat_id" ]] || upstream_fail "Consent record is missing chat id"

    alert_text="$(jq -r '.text // ""' "${fake_state_dir}/call-1.json")"
    assert_text_contains "$alert_text" "Хотите получить практические рекомендации" "Consent-capable alert should ask for recommendations"
    assert_text_contains "$alert_text" "/codex_da" "Consent-capable alert should expose the short accept command"

    router_event="${TMP_DIR}/accept-event.json"
    jq -n \
        --arg chat_id "$chat_id" \
        '{
            message: {
                message_id: 501,
                text: "/codex_da",
                chat: {id: $chat_id},
                from: {id: $chat_id}
            }
        }' > "$router_event"

    router_result="${TMP_DIR}/router-result.json"
    log "Routing consent accept event"
    CODEX_CONSENT_E2E_FAKE_TELEGRAM_STATE_DIR="$fake_state_dir" \
    bash "$ROUTER_SCRIPT" \
        --store-script "$STORE_SCRIPT" \
        --store-dir "$consent_store_dir" \
        --event-file "$router_event" \
        --telegram-send-script "${fake_bin_dir}/telegram-bot-send.sh" \
        --telegram-env-file "$fake_env" \
        --send-reply true \
        --json-out "$router_result" \
        --stdout none

    assert_jq "$router_result" '.decision == "accept"' "Router should accept the structured fallback command"
    assert_jq "$router_result" '.delivery.status == "sent"' "Router should send recommendations immediately"
    assert_jq "$consent_record" '.request.status == "delivered"' "Shared store should persist delivered status"
    assert_jq "$consent_record" '.delivery.status == "sent"' "Shared store should persist follow-up delivery success"

    consent_text="$(jq -r '.text // ""' "${fake_state_dir}/call-2.json")"
    assert_text_contains "$consent_text" "Практические рекомендации по обновлению Codex CLI" "Follow-up should contain the recommendations heading"
    assert_text_contains "$consent_text" "Что можно сделать в проекте" "Follow-up should contain concrete project guidance"
    OBSERVED_RESPONSE="$consent_text"

    log "Running degraded one-way watcher alert"
    CODEX_CONSENT_E2E_FAKE_TELEGRAM_STATE_DIR="$degraded_fake_state" \
    bash "$WATCHER_SCRIPT" \
        --mode scheduler \
        --state-file "$degraded_state" \
        --release-file "$RELEASE_FILE" \
        --include-issue-signals \
        --issue-signals-file "$ISSUE_SIGNALS_FILE" \
        --telegram-enabled \
        --telegram-env-file "$degraded_fake_env" \
        --telegram-send-script "${degraded_fake_bin}/telegram-bot-send.sh" \
        --telegram-consent-router-disabled \
        --json-out "$degraded_report" \
        --summary-out "$degraded_summary" \
        --stdout none

    assert_jq "$degraded_report" '.decision.status == "deliver"' "Degraded watcher should still deliver the upstream alert"
    assert_jq "$degraded_report" '.followup.consent.status == "disabled"' "Degraded watcher should disable consent"
    assert_jq "$degraded_report" '.followup.consent.router_mode == "one_way_only"' "Degraded watcher should declare one-way only routing"
    assert_jq "$degraded_report" '.automation.alert.consent_requested == false' "Degraded watcher must not advertise a broken consent flow"

    degraded_text="$(jq -r '.text // ""' "${degraded_fake_state}/call-1.json")"
    assert_text_not_contains "$degraded_text" "Хотите получить практические рекомендации" "One-way alert must not ask a broken consent question"

    CONTEXT_JSON="$(jq -n \
        --arg alert_report "$watcher_report" \
        --arg router_result "$router_result" \
        --arg degraded_report "$degraded_report" \
        --arg consent_record "$consent_record" \
        --arg request_id "$request_id" \
        --arg alert_text "$alert_text" \
        --arg followup_text "$consent_text" \
        --arg degraded_text "$degraded_text" \
        --arg temp_dir "${PERSISTED_TMP_DIR}" \
        '{
            alert: {
                request_id: $request_id,
                text: $alert_text,
                report_path: $alert_report,
                consent_record_path: $consent_record
            },
            consent: {
                result_path: $router_result,
                followup_text: $followup_text
            },
            degraded: {
                report_path: $degraded_report,
                text: $degraded_text
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
