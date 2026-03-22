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
  "update_id": $((880320000 + turn_id)),
  "message": {
    "message_id": $message_id,
    "date": $((1780000000 + turn_id)),
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

run_component_agent_factory_telegram_delivery_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_telegram_delivery_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_telegram_delivery_runs_handoff_and_sanitizes_payloads"
    if send_turn "$tmpdir" "$tmpdir/state" 1 8101 "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 2 8102 "Основной пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 3 8103 "Сейчас one-page собирается вручную и часто требует повторной сверки." \
      && send_turn "$tmpdir" "$tmpdir/state" 4 8104 "Нужен готовый one-page с рекомендацией по решению для комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 5 8105 "В первую очередь агент помогает клиентскому менеджеру перед заседанием." \
      && send_turn "$tmpdir" "$tmpdir/state" 6 8106 "Входы: синтетическая CSV-выгрузка и комментарии менеджера." \
      && send_turn "$tmpdir" "$tmpdir/state" 7 8107 "Выход: one-page PDF и markdown-версия с кратким обоснованием." \
      && send_turn "$tmpdir" "$tmpdir/state" 8 8108 "Ограничения: только обезличенные синтетические данные." \
      && send_turn "$tmpdir" "$tmpdir/state" 9 8109 "Метрики: время подготовки и количество ошибок." \
      && send_turn "$tmpdir" "$tmpdir/state" 10 8110 "Подтверждаю brief"; then
        local out
        out="$tmpdir/output-10.json"
        local session_id
        session_id="$(jq -r '.telegram_adapter_session.telegram_adapter_session_id' "$out")"
        assert_eq "completed" "$(jq -r '.runtime_response.status' "$out")" \
            "After explicit confirmation adapter should finish with completed status"
        assert_eq "publish_downloads" "$(jq -r '.runtime_response.next_action' "$out")" \
            "Completed delivery should expose publish_downloads action"
        assert_gt "$(jq '.delivery_items | length' "$out")" "2" \
            "Delivery response should contain generated artifacts"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$out")" "artifact_delivery" \
            "Delivery response should contain artifact_delivery payload"
        assert_false "$(jq -r '[.reply_payloads[].rendered_text | test("/Users/|/opt/|data/agent-factory|\\\\.beads/")] | any' "$out")" \
            "Delivery payloads must not leak internal filesystem paths"
        assert_file_exists "$tmpdir/state/deliveries/${session_id}/delivery-index.json" \
            "Adapter should persist delivery index for generated concept pack"
        assert_gt "$(jq '.items | length' "$tmpdir/state/deliveries/${session_id}/delivery-index.json")" "2" \
            "Delivery index should contain concept-pack artifacts"
        test_pass
    else
        test_fail "Adapter should run downstream handoff and produce sanitized delivery payloads"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_telegram_delivery_tests
fi
