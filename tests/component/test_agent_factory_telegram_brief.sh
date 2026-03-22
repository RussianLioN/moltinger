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
  "update_id": $((880120000 + turn_id)),
  "message": {
    "message_id": $message_id,
    "date": $((1778000000 + turn_id)),
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

run_component_agent_factory_telegram_brief_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_telegram_brief_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_telegram_brief_renders_summary_and_confirmation_prompt"
    if send_turn "$tmpdir" "$tmpdir/state" 1 6101 "Автоматизировать подготовку one-page summary по клиенту для кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 2 6102 "Основной пользователь — клиентский менеджер, выгодоприобретатели — члены кредитного комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 3 6103 "Сейчас документ готовится вручную в Word и PDF, много времени уходит на сверку." \
      && send_turn "$tmpdir" "$tmpdir/state" 4 6104 "Нужен готовый one-page с рекомендацией, чтобы сократить время подготовки." \
      && send_turn "$tmpdir" "$tmpdir/state" 5 6105 "В первую очередь агент помогает клиентскому менеджеру перед заседанием комитета." \
      && send_turn "$tmpdir" "$tmpdir/state" 6 6106 "Входы: CSV-выгрузка по клиенту и текстовые комментарии менеджера." \
      && send_turn "$tmpdir" "$tmpdir/state" 7 6107 "Выход: one-page PDF с рекомендацией и кратким обоснованием." \
      && send_turn "$tmpdir" "$tmpdir/state" 8 6108 "Ограничения: использовать только обезличенные синтетические данные." \
      && send_turn "$tmpdir" "$tmpdir/state" 9 6109 "Метрики: скорость подготовки и число ошибок в финальном документе."; then
        local out
        out="$tmpdir/output-9.json"
        assert_eq "awaiting_confirmation" "$(jq -r '.runtime_response.status' "$out")" \
            "Discovery should transition to awaiting_confirmation after full topic coverage"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$out")" "brief_summary" \
            "Telegram reply payloads should include brief_summary chunks"
        assert_contains "$(jq -r '.reply_payloads | map(.reply_kind) | join(",")' "$out")" "confirmation_prompt" \
            "Telegram reply payloads should include explicit confirmation prompt"
        local brief_count
        brief_count="$(jq '[.reply_payloads[] | select(.reply_kind=="brief_summary")] | length' "$out")"
        assert_gt "$brief_count" "0" "At least one brief_summary chunk should be rendered"
        assert_contains "$(jq -r '.reply_payloads[] | select(.reply_kind=="brief_summary") | .rendered_text' "$out" | head -n 1)" "Summary brief v" \
            "Brief summary chunk should include brief version header"
        assert_false "$(jq -r '[.reply_payloads[].rendered_text | test("/Users/|/opt/|data/agent-factory|\\\\.beads/")] | any' "$out")" \
            "Brief payloads must not leak internal filesystem paths"
        test_pass
    else
        test_fail "Adapter should render Telegram-readable brief summary and confirmation prompt"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_telegram_brief_tests
fi
