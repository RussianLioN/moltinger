#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ADAPTER_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-telegram-adapter.py"
NEW_PROJECT_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/telegram/update-new-project.json"

run_component_agent_factory_telegram_intents_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_telegram_intents_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_telegram_intents_status_help_confirm_reopen"
    cat > "$tmpdir/help.json" <<'JSON'
{
  "update_id": 880010110,
  "message": {
    "message_id": 4510,
    "date": 1774000100,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "/help"
  }
}
JSON
    cat > "$tmpdir/status.json" <<'JSON'
{
  "update_id": 880010111,
  "message": {
    "message_id": 4511,
    "date": 1774000110,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "/status"
  }
}
JSON
    cat > "$tmpdir/confirm.json" <<'JSON'
{
  "update_id": 880010112,
  "message": {
    "message_id": 4512,
    "date": 1774000120,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "Подтверждаю brief"
  }
}
JSON
    cat > "$tmpdir/reopen.json" <<'JSON'
{
  "update_id": 880010113,
  "message": {
    "message_id": 4513,
    "date": 1774000130,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "Нужно внести правки и переоткрыть brief"
  }
}
JSON

    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/help.json" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/help-out.json" >/dev/null \
      && python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/status.json" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/status-out.json" >/dev/null \
      && python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/confirm.json" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/confirm-out.json" >/dev/null \
      && python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$tmpdir/reopen.json" \
        --state-root "$tmpdir/state" \
        --output "$tmpdir/reopen-out.json" >/dev/null; then
        assert_eq "request_help" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/help-out.json")" \
            "Adapter should detect /help as request_help intent"
        assert_eq "request_status" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/status-out.json")" \
            "Adapter should detect /status as request_status intent"
        assert_eq "confirm_brief" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/confirm-out.json")" \
            "Adapter should detect explicit confirmation markers"
        assert_eq "reopen_brief" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/reopen-out.json")" \
            "Adapter should detect reopen markers"
        test_pass
    else
        test_fail "Adapter should parse Telegram control intents"
    fi

    test_start "component_agent_factory_telegram_intents_continue_active_session"
    if python3 "$ADAPTER_SCRIPT" handle-update \
        --source "$NEW_PROJECT_FIXTURE" \
        --state-root "$tmpdir/state-active" \
        --output "$tmpdir/start-out.json" >/dev/null; then
        cat > "$tmpdir/follow-up.json" <<'JSON'
{
  "update_id": 880010120,
  "message": {
    "message_id": 4520,
    "date": 1774000200,
    "chat": {
      "id": 262872984,
      "type": "private"
    },
    "from": {
      "id": 262872984,
      "first_name": "Сергей",
      "language_code": "ru"
    },
    "text": "Пользователь — клиентский менеджер, выгодоприобретатель — кредитный комитет."
  }
}
JSON
        if python3 "$ADAPTER_SCRIPT" handle-update \
            --source "$tmpdir/follow-up.json" \
            --state-root "$tmpdir/state-active" \
            --output "$tmpdir/follow-up-out.json" >/dev/null; then
            assert_eq "answer_discovery_question" "$(jq -r '.telegram_intent.intent_type' "$tmpdir/follow-up-out.json")" \
                "Adapter should route free-form follow-up into active discovery intent"
            test_pass
        else
            test_fail "Follow-up message should be treated as active discovery answer"
        fi
    else
        test_fail "New project fixture should create active Telegram session"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_telegram_intents_tests
fi
