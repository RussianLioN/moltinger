#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"

send_turn() {
    local tmpdir="$1"
    local state_root="$2"
    local turn_id="$3"
    local message_id="$4"
    local message_text="$5"
    cat > "$tmpdir/input-${turn_id}.json" <<JSON
{
  "update_id": $((880420000 + turn_id)),
  "message": {
    "message_id": $message_id,
    "date": $((1781000000 + turn_id)),
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "$message_text"
  }
}
JSON
    python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/input-${turn_id}.json" \
        --state-root "$state_root" \
        --output "$tmpdir/output-${turn_id}.json" >/dev/null
}

run_integration_local_agent_factory_telegram_handoff_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_telegram_handoff_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_telegram_handoff_confirm_to_delivery_and_status"
    if send_turn "$tmpdir" "$tmpdir/state" 1 9101 "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 2 9102 "Основной пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 3 9103 "Сейчас one-page собирается вручную в Word и потом переносится в PDF." \
      && send_turn "$tmpdir" "$tmpdir/state" 4 9104 "Бизнес должен получать готовый one-page с рекомендацией и обоснованием." \
      && send_turn "$tmpdir" "$tmpdir/state" 5 9105 "Агент помогает клиентскому менеджеру перед заседанием кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 6 9106 "Входы: синтетическая CSV-выгрузка и краткие комментарии менеджера." \
      && send_turn "$tmpdir" "$tmpdir/state" 7 9107 "Выходы: one-page PDF, markdown summary и презентационный материал." \
      && send_turn "$tmpdir" "$tmpdir/state" 8 9108 "Ограничения: использовать только обезличенные синтетические данные." \
      && send_turn "$tmpdir" "$tmpdir/state" 9 9109 "Метрики: время подготовки документа и количество ошибок." \
      && send_turn "$tmpdir" "$tmpdir/state" 10 9110 "Подтверждаю brief"; then
        local confirm_out
        confirm_out="$tmpdir/output-10.json"
        local session_id brief_id
        session_id="$(jq -r '.telegram_adapter_session.telegram_adapter_session_id' "$confirm_out")"
        brief_id="$(jq -r '.runtime_response.brief_id' "$confirm_out")"
        assert_eq "completed" "$(jq -r '.runtime_response.status' "$confirm_out")" \
            "Explicit confirmation should complete handoff pipeline"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$confirm_out")" "artifact_delivery" \
            "Confirmation response should include artifact delivery payload"
        assert_gt "$(jq '.delivery_items | length' "$confirm_out")" "2" \
            "Confirmation response should include generated artifacts list"
        assert_file_exists "$tmpdir/state/deliveries/${session_id}/concept-pack.json" \
            "Adapter should persist generated concept-pack manifest"
        assert_eq "$brief_id" "$(jq -r '.source_provenance.brief_id' "$tmpdir/state/deliveries/${session_id}/concept-pack.json")" \
            "Generated manifest should keep brief provenance from confirmed handoff"
        assert_eq "ready" "$(jq -r '.source_provenance.handoff_status' "$tmpdir/state/deliveries/${session_id}/concept-pack.json")" \
            "Generated manifest should preserve downstream handoff status"

        send_turn "$tmpdir" "$tmpdir/state" 11 9111 "/status"
        assert_eq "request_status" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/output-11.json")" \
            "Status command should remain available after delivery"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$tmpdir/output-11.json")" "artifact_delivery" \
            "Status response should reuse stored artifact delivery payloads"
        test_pass
    else
        test_fail "Telegram flow should auto-run handoff and expose artifacts in chat"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_telegram_handoff_tests
fi
