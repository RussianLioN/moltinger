#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"
BRIEF_CONFIRM_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/telegram/update-brief-confirm.json"

send_turn() {
    local tmpdir="$1"
    local state_root="$2"
    local turn_id="$3"
    local message_id="$4"
    local message_text="$5"
    cat > "$tmpdir/input-${turn_id}.json" <<JSON
{
  "update_id": $((880220000 + turn_id)),
  "message": {
    "message_id": $message_id,
    "date": $((1779000000 + turn_id)),
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

run_integration_local_agent_factory_telegram_confirmation_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_telegram_confirmation_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_telegram_confirmation_correction_then_confirm"
    if send_turn "$tmpdir" "$tmpdir/state" 1 7101 "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 2 7102 "Основной пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 3 7103 "Сейчас документ формируется вручную, много времени уходит на сверку и оформление." \
      && send_turn "$tmpdir" "$tmpdir/state" 4 7104 "После автоматизации нужен готовый one-page с рекомендацией и обоснованием." \
      && send_turn "$tmpdir" "$tmpdir/state" 5 7105 "Агент помогает клиентскому менеджеру перед заседанием комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 6 7106 "Входы: CSV-выгрузка по клиенту и комментарии менеджера." \
      && send_turn "$tmpdir" "$tmpdir/state" 7 7107 "Выход: one-page PDF с рекомендацией для кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 8 7108 "Ограничение: использовать только обезличенные синтетические данные." \
      && send_turn "$tmpdir" "$tmpdir/state" 9 7109 "Метрики: время подготовки и количество ошибок."; then
        local before_version
        before_version="$(jq -r '.runtime_response.brief_version' "$tmpdir/output-9.json")"
        assert_eq "awaiting_confirmation" "$(jq -r '.runtime_response.status' "$tmpdir/output-9.json")" \
            "Flow should reach awaiting_confirmation before correction"

        send_turn "$tmpdir" "$tmpdir/state" 10 7110 "Исправь выход: добавь markdown-версию alongside PDF."
        assert_eq "reopen_brief" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/output-10.json")" \
            "Correction message should be routed as reopen_brief intent"
        assert_eq "awaiting_confirmation" "$(jq -r '.runtime_response.status' "$tmpdir/output-10.json")" \
            "After correction adapter should return to brief confirmation loop"
        assert_ne "$before_version" "$(jq -r '.runtime_response.brief_version' "$tmpdir/output-10.json")" \
            "Correction should produce a new brief version"

        cat > "$tmpdir/confirm.json" <<JSON
$(cat "$BRIEF_CONFIRM_FIXTURE")
JSON
        if python3 "$ADAPTER_SCRIPT" handle-update \
            --source "$tmpdir/confirm.json" \
            --state-root "$tmpdir/state" \
            --output "$tmpdir/output-confirm.json" >/dev/null; then
            assert_eq "confirm_brief" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/output-confirm.json")" \
                "Explicit confirmation message should route as confirm_brief intent"
            assert_true "$(jq -r '.runtime_response.status | test("confirmed|completed")' "$tmpdir/output-confirm.json")" \
                "Confirmed brief should switch runtime into confirmed/completed handoff state"
            assert_true "$(jq -r '.runtime_response.next_action | test("start_concept_pack_handoff|run_factory_intake|publish_downloads")' "$tmpdir/output-confirm.json")" \
                "After confirmation runtime should switch to downstream handoff or publish action"
            assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$tmpdir/output-confirm.json")" "status_update" \
                "Confirmation response should include user-facing status payload"
            test_pass
        else
            test_fail "Adapter should confirm brief from Telegram message"
        fi
    else
        test_fail "Adapter should reach brief confirmation before correction/confirm checks"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_telegram_confirmation_tests
fi
