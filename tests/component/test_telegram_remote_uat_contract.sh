#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

WRAPPER_SCRIPT="$PROJECT_ROOT/scripts/telegram-e2e-on-demand.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"
REMOTE_UAT_CONTRACT_ORIG_SHARED_TARGET_LOCK="__unset__"

setup_remote_uat_contract_fixture() {
    TEST_TMPDIR="$(mktemp -d)"
    REMOTE_UAT_CONTRACT_ORIG_SHARED_TARGET_LOCK="${SHARED_TARGET_LOCK-__unset__}"
    export SHARED_TARGET_LOCK="$TEST_TMPDIR/telegram-remote-uat.lock"
    cp "$WRAPPER_SCRIPT" "$TEST_TMPDIR/telegram-e2e-on-demand.sh"
    chmod +x "$TEST_TMPDIR/telegram-e2e-on-demand.sh"

cat > "$TEST_TMPDIR/telegram-web-user-monitor.sh" <<'SH'
#!/usr/bin/env bash
mode="${TELEGRAM_WEB_STUB_MODE:-send_failure}"
probe_message="${TELEGRAM_WEB_MESSAGE:-}"

if [[ "$mode" == "status_semantic_mismatch" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "## Статус системы\nМодель: gpt-5.4",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "status_extra_line_mismatch" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text\nДополнительно: tmux healthy",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "verification_gate_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "To use this bot, please enter the verification code.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "activity_log_emoji_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "📋 Activity log • 🗺️ mcp__tavily__tavily_map • 🧠 Searching memory...",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "tavily_validator_leak_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "MCP tool error: Internal error: 3 validation errors for call[tavily_search] query Missing required argument session_key Unexpected keyword argument text Unexpected keyword argument",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "pre_send_invalid_incoming_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сначала проверю память и каталог навыков.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven",
    "last_pre_send_activity": {
      "observed_max_mid": 40,
      "messages": [
        {
          "mid": 40,
          "direction": "in",
          "text": "📋 Activity log • 💻 Running: `find /home/moltis/.moltis/skills -maxdepth 2 -type...`"
        }
      ]
    }
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "internal_planning_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Нашёл официальную документацию Moltis. Давай изучу её полностью и вернусь с инструкцией.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "final_progress_preface_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сейчас проверю формулировку ответа и вернусь с кратким планом.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "doc_search_plan_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Хорошо, изучу документацию Moltis и существующие навыки как примеры. Начну с поиска официальной документации и анализа имеющегося навыка codex-update, который как раз занимается проверкой версий.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "friendly_doc_search_plan_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Отлично! Давай изучу официальную документацию и существующие навыки как примеры. Начну с поиска документации Moltis и анализа навыка codex-update (он как раз проверяет версии):",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "template_search_plan_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Поищу темплейт в системе:",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "template_searching_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Ищу темплейт:",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "template_minimal_reply_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Канонический минимальный шаблон навыка: ```md --- name: <skill-name> description: Базовый навык <skill-name>. Использовать, когда пользователь явно просит этот workflow. --- ```",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "template_live_reply_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Канонический минимальный шаблон навыка: ```md --- name: <skill-name> description: Базовый навык <skill-name>. Использовать, когда пользователь явно просит сценарий <skill-name>. --- # <skill-name> ## Активация Когда пользователь явно просит сценарий <skill-name> или доработку этого навыка, используй его. ## Workflow 1. Уточни цель, если для точного выполнения не хватает контекста. 2. Выполни основной сценарий навыка. 3. Верни краткий итог и предложи, как доработать навык дальше. ## Templates - TODO: добавить конкретные шаблоны под сценарий навыка. ``` Если хочешь, следующим сообщением я создам такой базовый навык по имени/slug.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "template_wrong_reply_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Навыки (3): codex-update, template-skill, telegram-learner.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_reading_plan_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Давай наконец сделаю это! Читаю существующий навык codex-update как пример и найду документацию:",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "pre_send_internal_planning_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Нормальный человеческий ответ",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven",
    "last_pre_send_activity": {
      "observed_max_mid": 40,
      "messages": [
        {
          "mid": 40,
          "direction": "in",
          "text": "Нашёл официальный репозиторий Moltis на GitHub. Давайте получу полную документацию."
        }
      ]
    }
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "host_path_leak_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Для этого навыка использую /server/scripts/moltis-codex-update-run.sh --mode manual --stdout summary.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_false_negative_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "По-честному: подтверждённых новых версий Codex у меня сейчас нет. Что проверилось: путь к skill codex-update сейчас не существует физически; каталога /home/moltis/.moltis/skills в текущем файловом окружении тоже нет.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_remote_execution_claim_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сейчас запущу make codex-update и, если потребуется, обновлю вашу локальную установку Codex.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_memory_state_false_negative_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "В базе у меня не зафиксирована отдельная текущая версия Codex CLI. В памяти записи о последней известной версии не найдено, значит механизм сейчас не в рабочем состоянии.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_state_helper_safe_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Последнее зафиксированное состояние я читаю не из памяти чата, а из runtime state codex-update. Последняя сохранённая версия: 1.2.3, fingerprint: abc123, время последнего чтения: 2026-03-28T10:00:00Z.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_false_negative_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Не вижу подтверждения, что такой крон у меня есть. Я бы хотел это проверить по памяти/расписанию, но инструмент поиска памяти сейчас тоже отвечает криво, так что честно: подтвердить наличие такого крона я сейчас не могу.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_positive_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Да — есть. В памяти у меня явно записано: «Ежедневно проверяю стабильные обновления Codex CLI и присылаю краткое уведомление только если вышла новая стабильная версия.» cron list снова вернул missing 'action' parameter, memory_search — missing 'query' parameter, exec — missing 'command' parameter.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_recorded_logic_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Да, есть. По сохранённой памяти у меня зафиксировано, что настроена такая логика: - ежедневно проверять стабильные обновления Codex CLI; - присылать краткое уведомление только если вышла новая стабильная версия. По сохранённому контексту наличие такого крона подтверждено.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_live_recorded_context_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Да, есть. По сохранённой памяти зафиксировано такое поведение: ежедневно проверяется новая стабильная версия Codex CLI и уведомление отправляется только при её появлении. Но по сохранённому контексту крон есть.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_safe_negative_runtime_check_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Нет. По сохранённому контексту наличие такого крона подтверждено не было и подтверждено быть не может без runtime check. Для такого вывода нужен отдельный операторский/runtime check.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_action_unquoted_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Да — есть. В памяти у меня явно записано: «Ежедневно проверяю стабильные обновления Codex CLI и присылаю краткое уведомление только если вышла новая стабильная версия.» cron list снова вернул missing action parameter.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_query_unquoted_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Да — есть. В памяти у меня явно записано: «Ежедневно проверяю стабильные обновления Codex CLI и присылаю краткое уведомление только если вышла новая стабильная версия.» memory_search снова вернул missing query parameter.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_memory_command_unquoted_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Да — есть. В памяти у меня явно записано: «Ежедневно проверяю стабильные обновления Codex CLI и присылаю краткое уведомление только если вышла новая стабильная версия.» exec снова вернул missing command parameter.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_contract_safe_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "По проектному контракту у codex-update есть отдельный scheduler path для регулярной проверки обновлений Codex CLI. Но в Telegram-safe чате я не подтверждаю по памяти, что live cron сейчас действительно включён. Для точного статуса нужен операторский/runtime check, а не memory search.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_scheduler_skill_detail_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "codex-update — показывает, есть ли новая стабильная версия Codex CLI, почему это важно и что стоит делать дальше. Полезен, когда нужно быстро понять важность нового релиза без ручного обхода changelog.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_context_contract_safe_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Раньше повторные сообщения про Codex CLI появлялись из-за дефекта старого контура дедупликации. После исправлений схема такая: scheduler path проверяет официальный upstream Codex CLI каждые 6 часов, считает fingerprint и сравнивает его с `last_alert_fingerprint`. Если fingerprint уже объявлялся, навык пишет `suppressed`, сохраняет `last_seen_version`, `last_seen_fingerprint`, `last_run_at` и не шлёт дубль.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "codex_update_context_release_summary_false_positive_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "По официальному release latest у Codex CLI сейчас версия rust-v0.124.0. Дата публикации: 2026-04-23. В сохранённом состоянии навыка codex-update раньше была 0.123.0 по проверке от 2026-04-23.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_visibility_false_negative_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Интересная ситуация: заявлено в системе несколько навыков, но по факту папки /home/moltis/.moltis/skills/ не существует. Навыки либо были удалены, либо ещё не созданы.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_visibility_runtime_truth_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сейчас в runtime вижу навыки: codex-update, template-skill, telegram-learner.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_create_success_reply_pass" ]]; then
  if printf '%s' "$probe_message" | grep -Eiq 'что у тебя с навыками|skills\?'; then
    cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сейчас в runtime вижу навыки: codex-update, codex-update-new, template-skill, telegram-learner.",
  "reply_mid": 43,
  "sent_mid": 42,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
    exit 0
  fi
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Готово: создал навык codex-update-new и добавил его в список доступных навыков.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_create_followup_missing_pass" ]]; then
  if printf '%s' "$probe_message" | grep -Eiq 'что у тебя с навыками|skills\?'; then
    cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Сейчас в runtime вижу навыки: codex-update, template-skill, telegram-learner.",
  "reply_mid": 43,
  "sent_mid": 42,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
    exit 0
  fi
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Готово: создал навык codex-update-new и добавил его в список доступных навыков.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_update_success_reply_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Готово: обновил навык codex-update и сохранил изменения.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_update_missing_name_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Готово: обновил навык и сохранил изменения.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_delete_success_reply_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Готово: удалил навык codex-update из списка доступных навыков.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

if [[ "$mode" == "skill_delete_missing_name_pass" ]]; then
  cat <<'JSON'
{
  "ok": true,
  "status": "pass",
  "stage": "wait_reply",
  "reply_text": "Готово: удалил навык из списка доступных навыков.",
  "reply_mid": 42,
  "sent_mid": 41,
  "checks": {
    "non_empty": true,
    "min_length": true,
    "reply_settled": true,
    "error_signature_clean": true,
    "sensitive_signature_clean": true
  },
  "failures": [],
  "attribution_evidence": {
    "attribution_confidence": "proven"
  },
  "diagnostic_context": {
    "stats": {
      "url": "https://web.telegram.org/k/#@moltinger_bot",
      "hasSearch": true
    }
  },
  "recommended_action": "Authoritative Telegram Web path passed; no secondary diagnostics are needed."
}
JSON
  exit 0
fi

base_payload="$(cat <<'JSON'
{
  "ok": false,
  "status": "fail",
  "stage": "send",
  "failure": {
    "code": "send_failure",
    "stage": "send",
    "summary": "Probe message was not observed in chat after send",
    "actionability": "engineering",
    "fallback_relevant": true
  },
  "attribution_evidence": {
    "attribution_confidence": "absent"
  },
  "diagnostic_context": {
    "token": "secret-token",
    "session": "secret-session",
    "state_path": "/opt/moltinger/data/.telegram-web-state.json",
    "stats": {
      "url": "https://web.telegram.org/k/",
      "hasSearch": true
    }
  },
  "recommended_action": "Inspect send diagnostics and rerun."
}
JSON
)"

if [[ "${TELEGRAM_WEB_DEBUG:-false}" == "true" ]]; then
  jq '. + {
    restricted_debug: {
      debug_flag: true,
      dom: {
        send_button_present: true,
        draft_matches_probe: true
      }
    }
  }' <<<"$base_payload"
else
  printf '%s\n' "$base_payload"
fi
SH
    chmod +x "$TEST_TMPDIR/telegram-web-user-monitor.sh"

    cat > "$TEST_TMPDIR/telegram-real-user-e2e.py" <<'PY'
#!/usr/bin/env python3
import json
import os

mode = os.environ.get("MTPROTO_STUB_MODE", "precondition")
if mode == "verification_gate":
    payload = {
        "status": "completed",
        "observed_response": "To use this bot, please enter the verification code.",
        "error_code": None,
        "error_message": None,
        "context": {"bot_username": "moltinger_bot"},
        "transport": "telegram_mtproto_real_user"
    }
else:
    payload = {
        "status": "precondition_failed",
        "observed_response": None,
        "error_code": "precondition",
        "error_message": "missing TELEGRAM_TEST_SESSION",
        "context": {"missing": ["TELEGRAM_TEST_SESSION"]},
        "transport": "telegram_mtproto_real_user"
    }
print(json.dumps(payload))
PY
    chmod +x "$TEST_TMPDIR/telegram-real-user-e2e.py"

    cat > "$TEST_TMPDIR/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
write_format=""
url=""
args=("$@")

index=0
while [[ $index -lt ${#args[@]} ]]; do
  arg="${args[$index]}"
  case "$arg" in
    -o)
      index=$((index + 1))
      output_file="${args[$index]:-}"
      ;;
    -w)
      index=$((index + 1))
      write_format="${args[$index]:-}"
      ;;
    http://*|https://*)
      url="$arg"
      ;;
  esac
  index=$((index + 1))
done

mode="${MOLTIS_CURL_STUB_MODE:-runtime_skills_present}"
status_code="200"
body='{}'
counter_file="${MOLTIS_CURL_STUB_COUNTER_FILE:-$(dirname "$0")/curl-skills-count}"
url_log_file="${MOLTIS_CURL_URL_LOG_FILE:-}"

if [[ -n "$url_log_file" && -n "$url" ]]; then
  printf '%s\n' "$url" >> "$url_log_file"
fi

case "$url" in
  */api/auth/login)
    body='{"ok":true}'
    ;;
  */api/skills)
    skills_call_count=0
    if [[ -f "$counter_file" ]]; then
      skills_call_count="$(cat "$counter_file" 2>/dev/null || printf '0')"
    fi
    skills_call_count=$((skills_call_count + 1))
    printf '%s\n' "$skills_call_count" > "$counter_file"
    case "$mode" in
      runtime_skills_present)
        body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        ;;
      create_not_persisted)
        body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        ;;
      create_persisted)
        if [[ "$skills_call_count" -eq 1 ]]; then
          body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        else
          body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"},{"name":"codex-update-new"}]}'
        fi
        ;;
      create_already_exists)
        body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"},{"name":"codex-update-new"}]}'
        ;;
      update_persisted)
        body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        ;;
      update_missing_target)
        body='{"skills":[{"name":"template-skill"},{"name":"telegram-learner"}]}'
        ;;
      update_not_visible_after_mutation)
        if [[ "$skills_call_count" -eq 1 ]]; then
          body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        else
          body='{"skills":[{"name":"template-skill"},{"name":"telegram-learner"}]}'
        fi
        ;;
      delete_removed)
        if [[ "$skills_call_count" -eq 1 ]]; then
          body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        else
          body='{"skills":[{"name":"template-skill"},{"name":"telegram-learner"}]}'
        fi
        ;;
      delete_missing_target)
        body='{"skills":[{"name":"template-skill"},{"name":"telegram-learner"}]}'
        ;;
      delete_not_removed)
        body='{"skills":[{"name":"codex-update"},{"name":"template-skill"},{"name":"telegram-learner"}]}'
        ;;
      empty_skills)
        body='{"skills":[]}'
        ;;
      *)
        status_code="500"
        body='{"error":"unexpected stub mode"}'
        ;;
    esac
    ;;
  *)
    status_code="404"
    body='{"error":"unexpected url"}'
    ;;
esac

if [[ -n "$output_file" && "$output_file" != "/dev/null" ]]; then
  printf '%s\n' "$body" > "$output_file"
fi

if [[ -z "$write_format" ]]; then
  if [[ -z "$output_file" ]]; then
    printf '%s\n' "$body"
  fi
else
  printf '%s' "${write_format//\%\{http_code\}/$status_code}"
fi
SH
    chmod +x "$TEST_TMPDIR/curl"
}

cleanup_remote_uat_contract_fixture() {
    if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR:-}" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
    if [[ "$REMOTE_UAT_CONTRACT_ORIG_SHARED_TARGET_LOCK" == "__unset__" ]]; then
        unset SHARED_TARGET_LOCK || true
    else
        export SHARED_TARGET_LOCK="$REMOTE_UAT_CONTRACT_ORIG_SHARED_TARGET_LOCK"
    fi
}

run_component_telegram_remote_uat_contract_tests() {
    start_timer
    setup_remote_uat_contract_fixture
    trap cleanup_remote_uat_contract_fixture EXIT

    test_start "component_telegram_remote_uat_review_safe_artifact_redacts_sensitive_fields"
    if "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result.json" \
        --debug-output "$TEST_TMPDIR/debug.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should fail closed when the stubbed Telegram Web helper reports send_failure"
    else
        if jq -e '.failure.code == "send_failure"' "$TEST_TMPDIR/result.json" >/dev/null 2>&1 \
            && ! grep -q 'secret-token' "$TEST_TMPDIR/result.json" \
            && ! grep -q 'secret-session' "$TEST_TMPDIR/result.json" \
            && ! grep -q '/opt/moltinger/data/.telegram-web-state.json' "$TEST_TMPDIR/result.json" \
            && jq -e '.diagnostic_context.state_file == ".telegram-web-state.json"' "$TEST_TMPDIR/result.json" >/dev/null 2>&1 \
            && jq -e '.debug_bundle.available == true' "$TEST_TMPDIR/result.json" >/dev/null 2>&1 \
            && grep -q 'secret-token' "$TEST_TMPDIR/debug.json" \
            && jq -e '.authoritative_raw.restricted_debug.debug_flag == true' "$TEST_TMPDIR/debug.json" >/dev/null 2>&1 \
            && ! grep -q 'debug_flag' "$TEST_TMPDIR/result.json"
        then
            test_pass
        else
            test_fail "Review-safe artifact must redact token/session/state-path and keep restricted debug only in the debug bundle"
        fi
    fi

    test_start "component_telegram_remote_uat_default_output_path_stays_outside_repo_checkout"
    mkdir -p "$TEST_TMPDIR/runtime-tmp"
    rm -f "$TEST_TMPDIR/telegram-e2e-result.json"
    if TMPDIR="$TEST_TMPDIR/runtime-tmp" \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should still fail closed on the default send_failure stub"
    else
        if [[ ! -f "$TEST_TMPDIR/telegram-e2e-result.json" ]] \
            && [[ -f "$TEST_TMPDIR/runtime-tmp/moltinger-telegram-remote-uat/telegram-e2e-result.json" ]] \
            && jq -e '.failure.code == "send_failure"' "$TEST_TMPDIR/runtime-tmp/moltinger-telegram-remote-uat/telegram-e2e-result.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Default authoritative output must land under TMPDIR outside the checkout so manual server-side runs cannot dirty /opt/moltinger"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_status_reply_without_canonical_model"
    if TELEGRAM_WEB_STUB_MODE=status_semantic_mismatch \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result-status-mismatch.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when /status reply omits the canonical model contract"
    else
        if jq -e '.failure.code == "semantic_status_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-status-mismatch.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.expected_model == "openai-codex::gpt-5.4"' "$TEST_TMPDIR/result-status-mismatch.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.expected_provider == "openai-codex"' "$TEST_TMPDIR/result-status-mismatch.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.expected_reply == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"' "$TEST_TMPDIR/result-status-mismatch.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface semantic /status mismatches as a failed authoritative verdict"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_status_reply_with_extra_lines_even_if_canonical_fields_exist"
    if TELEGRAM_WEB_STUB_MODE=status_extra_line_mismatch \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result-status-extra-line.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when /status includes extra lines beyond the canonical five-line safe-text contract"
    else
        if jq -e '.failure.code == "semantic_status_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-status-extra-line.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.expected_reply == "Статус: Online\nКанал: Telegram (@moltinger_bot)\nМодель: openai-codex::gpt-5.4\nПровайдер: openai-codex\nРежим: safe-text"' "$TEST_TMPDIR/result-status-extra-line.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must require the exact five-line /status reply and reject attributable extra tail text"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_verification_gate_reply_even_after_attributable_pass"
    if TELEGRAM_WEB_STUB_MODE=verification_gate_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "/status" \
        --output "$TEST_TMPDIR/result-verification-gate-primary.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the attributable /status reply is a verification gate"
    else
        if jq -e '.failure.code == "verification_gate_reply" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-verification-gate-primary.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must mark verification-gate replies as non-green authoritative outcomes"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_emoji_prefixed_activity_log_reply_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=activity_log_emoji_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Проверь память и каталог навыков" \
        --output "$TEST_TMPDIR/result-activity-log.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the helper falsely passes an emoji-prefixed internal activity reply"
    else
        if jq -e '.failure.code == "semantic_activity_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-activity-log.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface emoji-prefixed activity-log replies as failed authoritative outcomes"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_bare_tavily_validator_leak_even_without_activity_log_prefix"
    if TELEGRAM_WEB_STUB_MODE=tavily_validator_leak_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Проверь последние релизы Codex" \
        --output "$TEST_TMPDIR/result-tavily-validator-leak.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the helper falsely passes a bare Tavily validator leak"
    else
        if jq -e '.failure.code == "semantic_activity_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-tavily-validator-leak.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must treat bare Tavily validator/fetch traces as semantic activity leakage"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_recent_invalid_pre_send_activity_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=pre_send_invalid_incoming_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Проверь память и каталог навыков" \
        --output "$TEST_TMPDIR/result-pre-send-activity.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when recent invalid incoming activity already contaminated the chat before send"
	    else
	        if jq -e '.failure.code == "semantic_pre_send_activity_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-pre-send-activity.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must fail on recent invalid pre-send activity leakage even when the helper payload is otherwise green"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_internal_planning_leak_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=internal_planning_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "Изучи документацию Moltis" \
	        --output "$TEST_TMPDIR/result-internal-planning.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the reply exposes internal planning/tool inventory without explicit Activity log markers"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-internal-planning.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface internal planning/tool inventory leakage as a failed authoritative outcome"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_final_progress_preface_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=final_progress_preface_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "Изучи документацию Moltis" \
	        --output "$TEST_TMPDIR/result-final-progress-preface.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the final reply remains only a progress preface without a user-facing answer"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-final-progress-preface.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface final progress-preface replies as failed authoritative outcomes"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_doc_search_plan_without_tool_names_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=doc_search_plan_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "Изучи документацию Moltis" \
	        --output "$TEST_TMPDIR/result-doc-search-plan.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the final reply promises a doc-search plan instead of a user-facing answer"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-doc-search-plan.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface doc-search planning replies as failed authoritative outcomes"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_short_template_search_phrase_poiuschu_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=template_search_plan_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "У тебя должен быть темплейт" \
	        --output "$TEST_TMPDIR/result-template-search-plan.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the reply leaks the exact short 'Поищу темплейт в системе' planning phrase"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-template-search-plan.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface the exact short 'Поищу темплейт в системе' reply as failed authoritative outcome"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_short_template_search_phrase_ischu_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=template_searching_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "У тебя должен быть темплейт" \
	        --output "$TEST_TMPDIR/result-template-searching.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the reply leaks the exact short 'Ищу темплейт' planning phrase"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-template-searching.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface the exact short 'Ищу темплейт' reply as failed authoritative outcome"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_allows_deterministic_template_reply_without_runtime_skill_visibility_semantics"
	    if TELEGRAM_WEB_STUB_MODE=template_minimal_reply_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "У тебя должен быть темплейт" \
	        --output "$TEST_TMPDIR/result-template-minimal-reply.json" \
	        >/dev/null 2>&1
	    then
	        if jq -e '.run.verdict == "passed" and .failure == null' "$TEST_TMPDIR/result-template-minimal-reply.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must allow a deterministic template reply without misclassifying it as skills visibility"
	        fi
	    else
	        test_fail "Authoritative wrapper must pass a deterministic template reply for template requests"
	    fi

	    test_start "component_telegram_remote_uat_allows_live_template_reply_even_when_authenticated_skills_api_is_available"
	    if PATH="$TEST_TMPDIR:$PATH" \
	        MOLTIS_PASSWORD='stub-password' \
	        MOLTIS_CURL_STUB_MODE=runtime_skills_present \
	        TELEGRAM_WEB_STUB_MODE=template_minimal_reply_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "У тебя должен быть темплейт" \
	        --output "$TEST_TMPDIR/result-template-minimal-reply-with-skills-api.json" \
	        >/dev/null 2>&1
	    then
	        if jq -e '.run.verdict == "passed" and .failure == null' "$TEST_TMPDIR/result-template-minimal-reply-with-skills-api.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Template replies must not be reclassified as skill visibility checks when live /api/skills is available"
	        fi
	    else
	        test_fail "Authoritative wrapper must keep template replies green even with authenticated /api/skills access"
	    fi

	    test_start "component_telegram_remote_uat_allows_exact_live_template_reply_even_when_authenticated_skills_api_is_available"
	    if PATH="$TEST_TMPDIR:$PATH" \
	        MOLTIS_PASSWORD='stub-password' \
	        MOLTIS_CURL_STUB_MODE=runtime_skills_present \
	        TELEGRAM_WEB_STUB_MODE=template_live_reply_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "У тебя должен быть темплейт" \
	        --output "$TEST_TMPDIR/result-template-live-reply-with-skills-api.json" \
	        >/dev/null 2>&1
	    then
	        if jq -e '.run.verdict == "passed" and .failure == null' "$TEST_TMPDIR/result-template-live-reply-with-skills-api.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Exact live template replies must stay green instead of being misclassified as skill visibility checks"
	        fi
	    else
	        test_fail "Authoritative wrapper must pass the exact live template reply when /api/skills is available"
	    fi

	    test_start "component_telegram_remote_uat_fails_template_reply_that_does_not_match_template_contract"
	    if TELEGRAM_WEB_STUB_MODE=template_wrong_reply_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "У тебя должен быть темплейт" \
	        --output "$TEST_TMPDIR/result-template-wrong-reply.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when a template request receives a non-template reply that lacks the deterministic scaffold contract"
	    else
	        if jq -e '.failure.code == "semantic_skill_template_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-template-wrong-reply.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must classify non-template replies on template turns as semantic_skill_template_mismatch"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_exact_live_friendly_doc_search_plan_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=friendly_doc_search_plan_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "Изучи документацию Moltis" \
	        --output "$TEST_TMPDIR/result-friendly-doc-search-plan.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the final reply uses the exact live friendly doc-search wording instead of a user-facing answer"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-friendly-doc-search-plan.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface the exact live friendly doc-search wording as a failed authoritative outcome"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_exact_live_codex_update_reading_phrase_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=codex_update_reading_plan_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "Изучи документацию Moltis" \
	        --output "$TEST_TMPDIR/result-codex-update-reading-plan.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when the final reply uses the exact live codex-update reading phrase instead of a user-facing answer"
	    else
	        if jq -e '.failure.code == "semantic_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-reading-plan.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must surface the exact live codex-update reading phrase as a failed authoritative outcome"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_recent_invalid_pre_send_internal_planning_leak_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=pre_send_internal_planning_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
	        --mode authoritative \
	        --message "Изучи документацию Moltis" \
	        --output "$TEST_TMPDIR/result-pre-send-internal-planning.json" \
	        >/dev/null 2>&1
	    then
	        test_fail "Authoritative wrapper must fail when recent invalid internal planning already contaminated the chat before send"
	    else
	        if jq -e '.failure.code == "semantic_pre_send_internal_planning_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-pre-send-internal-planning.json" >/dev/null 2>&1
	        then
	            test_pass
	        else
	            test_fail "Wrapper must fail on recent invalid pre-send internal planning leakage even when the helper payload is otherwise green"
	        fi
	    fi

	    test_start "component_telegram_remote_uat_fails_host_path_leak_even_if_helper_passes"
	    if TELEGRAM_WEB_STUB_MODE=host_path_leak_pass \
	        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что умеет codex-update?" \
        --output "$TEST_TMPDIR/result-host-path-leak.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the reply exposes host filesystem or repo runtime paths"
    else
        if jq -e '.failure.code == "semantic_host_path_leak" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-host-path-leak.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface host-path leakage as a failed authoritative outcome"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_false_negative_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_false_negative_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что с новыми версиями codex?" \
        --output "$TEST_TMPDIR/result-codex-update-false-negative.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update is falsely treated as missing from a sandboxed Telegram surface"
    else
        if jq -e '.failure.code == "semantic_codex_update_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-false-negative.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface codex-update false negatives caused by sandbox-invisible host paths"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_remote_contract_violation_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_remote_execution_claim_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что с новыми версиями codex?" \
        --output "$TEST_TMPDIR/result-codex-update-remote-contract.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when remote codex-update reply promises operator-only runtime execution"
    else
        if jq -e '.failure.code == "semantic_codex_update_remote_contract_violation" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-remote-contract.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface remote codex-update execution-contract violations on user-facing surfaces"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_memory_state_false_negative_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_memory_state_false_negative_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Какая текущая версия Codex CLI у тебя зафиксирована в базе?" \
        --output "$TEST_TMPDIR/result-codex-update-memory-state.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update state queries are answered from memory-search style false negatives"
    else
        if jq -e '.failure.code == "semantic_codex_update_state_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-memory-state.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface codex-update state replies that substitute chat memory for runtime state truth"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_codex_update_state_helper_reply_that_mentions_chat_memory_only_as_contrast"
    if TELEGRAM_WEB_STUB_MODE=codex_update_state_helper_safe_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Какая текущая версия Codex CLI у тебя зафиксирована в базе?" \
        --output "$TEST_TMPDIR/result-codex-update-state-helper-safe.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must not fail a correct codex-update runtime-state reply only because it contrasts with chat memory"
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_memory_false_negative_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_false_negative_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-memory.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update scheduler questions drift into memory/schedule speculation"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-memory.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must surface codex-update scheduler replies that substitute memory-search speculation for the remote-safe scheduler contract"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_memory_positive_false_positive_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_positive_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-memory-positive.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update scheduler questions are answered from chat-memory assertions or leaked tool errors even if the helper claims success"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-memory-positive.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify memory-asserted codex-update scheduler claims as the same semantic scheduler-contract failure"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_recorded_logic_false_positive_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_recorded_logic_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-recorded-logic.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update scheduler replies assert live cron from saved memory/context even without explicit tool-error leakage"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-recorded-logic.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify recorded-memory scheduler confirmations as the same semantic scheduler-contract failure"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_live_recorded_context_false_positive_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_live_recorded_context_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-live-recorded-context.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the live wording family asserts cron from saved memory/context even without tool-error leakage"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-live-recorded-context.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify the exact live recorded-memory/context wording as the same semantic scheduler-contract failure"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_codex_update_scheduler_negative_runtime_check_reply"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_safe_negative_runtime_check_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-negative-runtime-check.json" \
        >/dev/null 2>&1
    then
        if jq -e '.run.verdict == "passed" and .failure == null' "$TEST_TMPDIR/result-codex-update-scheduler-negative-runtime-check.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Authoritative wrapper should preserve a safe scheduler reply that explicitly refuses memory-based confirmation and requires runtime check"
        fi
    else
        test_fail "Authoritative wrapper must not overfit on safe codex-update scheduler replies that contain contrastive confirmation wording"
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_action_unquoted_false_positive_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_action_unquoted_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-action-unquoted.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update scheduler replies leak an unquoted missing action parameter variant"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-action-unquoted.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify unquoted missing action parameter replies as the same semantic scheduler-contract failure"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_query_unquoted_false_positive_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_query_unquoted_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-query-unquoted.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update scheduler replies leak an unquoted missing query parameter variant"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-query-unquoted.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify unquoted missing query parameter replies as the same semantic scheduler-contract failure"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_command_unquoted_false_positive_even_if_helper_passes"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_memory_command_unquoted_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-command-unquoted.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when codex-update scheduler replies leak an unquoted missing command parameter variant"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_memory_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-command-unquoted.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify unquoted missing command parameter replies as the same semantic scheduler-contract failure"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_codex_update_scheduler_contract_safe_reply"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_contract_safe_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А разе у тебя нет крона по проверке вышедшей новой версии Codex cli?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-safe.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must allow the remote-safe codex-update scheduler contract reply"
    fi

    test_start "component_telegram_remote_uat_allows_exact_schedule_phrase_for_codex_update_scheduler_contract"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_contract_safe_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "По какому расписанию сейчас работает навык codex-update?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-safe-exact-phrase.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must classify the exact schedule phrasing as the codex-update scheduler contract"
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_scheduler_question_when_reply_falls_into_skill_detail_summary"
    if TELEGRAM_WEB_STUB_MODE=codex_update_scheduler_skill_detail_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Как часто навык codex-update автоматически проверяет обновления Codex CLI?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-skill-detail.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when a codex-update scheduler question gets a generic skill-detail summary instead of the dedicated scheduler contract"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_contract_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-skill-detail.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify codex-update scheduler questions that degrade into skill-detail wording as a scheduler contract mismatch"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_exact_schedule_phrase_when_reply_drifts_into_codex_update_context_contract"
    if TELEGRAM_WEB_STUB_MODE=codex_update_context_contract_safe_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "По какому расписанию сейчас работает навык codex-update?" \
        --output "$TEST_TMPDIR/result-codex-update-scheduler-context-drift.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the exact schedule phrasing drifts into the codex-update context reply"
    else
        if jq -e '.failure.code == "semantic_codex_update_scheduler_contract_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-scheduler-context-drift.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify the exact schedule phrasing that drifts into context wording as a scheduler contract mismatch"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_codex_update_context_contract_reply"
    if TELEGRAM_WEB_STUB_MODE=codex_update_context_contract_safe_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что изменилось в навыке codex-update после исправлений?" \
        --output "$TEST_TMPDIR/result-codex-update-context-safe.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must allow the dedicated codex-update history/scheme contract reply and must not misclassify it as a skill-update mutation"
    fi

    test_start "component_telegram_remote_uat_fails_codex_update_context_question_when_reply_falls_into_release_summary"
    if TELEGRAM_WEB_STUB_MODE=codex_update_context_release_summary_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Почему раньше ты три раза подряд присылал новость про обновление Codex CLI?" \
        --output "$TEST_TMPDIR/result-codex-update-context-release-summary.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when a codex-update history/scheme question gets only a release/state summary instead of the dedicated context contract"
    else
        if jq -e '.failure.code == "semantic_codex_update_context_contract_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-context-release-summary.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must classify codex-update history/scheme questions that degrade into plain release summaries as a context contract mismatch"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_exact_live_duplicate_history_question_when_reply_falls_into_release_summary"
    if TELEGRAM_WEB_STUB_MODE=codex_update_context_release_summary_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Почему раньше ты присылал три одинаковых сообщения подряд про обновление Codex CLI?" \
        --output "$TEST_TMPDIR/result-codex-update-context-duplicate-live.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must classify the exact live duplicate-history wording as a codex-update context question and fail if it drifts into a release summary"
    else
        if jq -e '.failure.code == "semantic_codex_update_context_contract_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-context-duplicate-live.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must fail the exact live duplicate-history wording with the codex-update context mismatch code"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_exact_live_post_fix_question_when_reply_falls_into_release_summary"
    if TELEGRAM_WEB_STUB_MODE=codex_update_context_release_summary_false_positive_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Что изменилось в навыке codex-update после починки?" \
        --output "$TEST_TMPDIR/result-codex-update-context-post-fix-live.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must classify the exact live post-fix wording as a codex-update context question and fail if it drifts into a release summary"
    else
        if jq -e '.failure.code == "semantic_codex_update_context_contract_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-codex-update-context-post-fix-live.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must fail the exact live post-fix wording with the codex-update context mismatch code"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_skill_visibility_false_negative_against_live_api_skills"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_MODE=runtime_skills_present \
        TELEGRAM_WEB_STUB_MODE=skill_visibility_false_negative_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А что у тебя с навыками/skills?" \
        --output "$TEST_TMPDIR/result-skill-visibility-false-negative.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when skills visibility falls back to sandbox filesystem absence despite live /api/skills data"
    else
        if jq -e '.failure.code == "semantic_skill_visibility_false_negative" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-visibility-false-negative.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.runtime_skill_names == ["codex-update","template-skill","telegram-learner"]' "$TEST_TMPDIR/result-skill-visibility-false-negative.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must use live /api/skills truth to reject filesystem-based skill-visibility false negatives"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_skill_visibility_reply_that_mentions_live_runtime_skills"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_MODE=runtime_skills_present \
        TELEGRAM_WEB_STUB_MODE=skill_visibility_runtime_truth_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А что у тебя с навыками/skills?" \
        --output "$TEST_TMPDIR/result-skill-visibility-runtime-truth.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must allow skills visibility replies that reflect live /api/skills names"
    fi

    test_start "component_telegram_remote_uat_defaults_live_skills_api_to_production_domain_for_local_authoritative_runs"
    local production_url_log="$TEST_TMPDIR/curl-production-urls.log"
    : > "$production_url_log"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_MODE=runtime_skills_present \
        MOLTIS_CURL_URL_LOG_FILE="$production_url_log" \
        TELEGRAM_WEB_STUB_MODE=skill_visibility_runtime_truth_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А что у тебя с навыками/skills?" \
        --output "$TEST_TMPDIR/result-skill-visibility-production-default.json" \
        >/dev/null 2>&1
    then
        if grep -Fqx 'https://moltis.ainetic.tech/api/auth/login' "$production_url_log" \
            && grep -Fqx 'https://moltis.ainetic.tech/api/skills' "$production_url_log"
        then
            test_pass
        else
            test_fail "Local authoritative Telegram UAT must default live skills verification to the production Moltis domain when no explicit MOLTIS_URL override is supplied"
        fi
    else
        test_fail "Local authoritative Telegram UAT should stay green while proving the production-domain default for live /api/skills verification"
    fi

    test_start "component_telegram_remote_uat_honors_explicit_moltis_url_override_for_live_skills_api"
    local localhost_url_log="$TEST_TMPDIR/curl-localhost-urls.log"
    : > "$localhost_url_log"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        MOLTIS_URL=http://localhost:13131 \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_MODE=runtime_skills_present \
        MOLTIS_CURL_URL_LOG_FILE="$localhost_url_log" \
        TELEGRAM_WEB_STUB_MODE=skill_visibility_runtime_truth_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "А что у тебя с навыками/skills?" \
        --output "$TEST_TMPDIR/result-skill-visibility-explicit-localhost.json" \
        >/dev/null 2>&1
    then
        if grep -Fqx 'http://localhost:13131/api/auth/login' "$localhost_url_log" \
            && grep -Fqx 'http://localhost:13131/api/skills' "$localhost_url_log"
        then
            test_pass
        else
            test_fail "Explicit MOLTIS_URL overrides must keep authoritative Telegram UAT on the requested live /api/skills base URL"
        fi
    else
        test_fail "Authoritative Telegram UAT should allow an explicit MOLTIS_URL override while keeping live skills verification green"
    fi

    test_start "component_telegram_remote_uat_fails_skill_create_when_requested_skill_is_not_persisted_in_live_api"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-not-persisted" \
        MOLTIS_CURL_STUB_MODE=create_not_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_create_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Давай создадим навык codex-update-new" \
        --output "$TEST_TMPDIR/result-skill-create-not-persisted.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when skill creation reply succeeds but the requested skill is still absent from live /api/skills"
    else
        if jq -e '.failure.code == "semantic_skill_create_not_persisted" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-create-not-persisted.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.requested_skill_name == "codex-update-new"' "$TEST_TMPDIR/result-skill-create-not-persisted.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must require the requested skill to appear in live /api/skills before treating Telegram skill creation as green"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_skill_create_for_create_name_skill_word_order_when_post_state_appears"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-word-order" \
        MOLTIS_CURL_STUB_MODE=create_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_create_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Create codex-update-new skill" \
        --output "$TEST_TMPDIR/result-skill-create-word-order.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must parse common 'Create <name> skill' wording and accept the run only when post-state shows the new skill"
    fi

    test_start "component_telegram_remote_uat_allows_skill_create_for_mixed_case_name_when_runtime_skill_slug_matches_case_insensitively"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-mixed-case" \
        MOLTIS_CURL_STUB_MODE=create_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_create_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Create Codex-Update-New skill" \
        --output "$TEST_TMPDIR/result-skill-create-mixed-case.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must treat requested skill names case-insensitively when comparing user wording against live /api/skills skill slugs"
    fi

    test_start "component_telegram_remote_uat_allows_skill_create_only_after_followup_visibility_mentions_new_skill"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-persisted" \
        MOLTIS_CURL_STUB_MODE=create_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_create_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Давай создадим навык codex-update-new" \
        --output "$TEST_TMPDIR/result-skill-create-persisted.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must allow Telegram skill creation only after live /api/skills proves persistence and the immediate follow-up visibility reply mentions the new skill"
    fi

    test_start "component_telegram_remote_uat_allows_skill_create_for_exact_russian_create_prompt_with_description_tail"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-russian-tail" \
        MOLTIS_CURL_STUB_MODE=create_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_create_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Создай навык codex-update-new для отслеживания новых версий Moltis" \
        --output "$TEST_TMPDIR/result-skill-create-russian-tail.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must parse exact Russian create-skill wording with a descriptive tail and accept the run only after live /api/skills plus follow-up visibility prove persistence"
    fi

    test_start "component_telegram_remote_uat_fails_skill_create_when_followup_visibility_does_not_mention_new_skill"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-followup-missing" \
        MOLTIS_CURL_STUB_MODE=create_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_create_followup_missing_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Давай создадим навык codex-update-new" \
        --output "$TEST_TMPDIR/result-skill-create-followup-missing.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the post-create visibility follow-up does not mention the newly created skill"
    else
        if jq -e '.failure.code == "semantic_skill_create_followup_visibility_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-create-followup-missing.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.skill_create_followup.requested_skill_name == "codex-update-new"' "$TEST_TMPDIR/result-skill-create-followup-missing.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must require the post-create follow-up visibility reply to mention the requested new skill"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_skill_create_when_requested_name_already_existed_before_send"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-create-preexisting" \
        MOLTIS_CURL_STUB_MODE=create_already_exists \
        TELEGRAM_WEB_STUB_MODE=skill_create_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Create codex-update-new skill" \
        --output "$TEST_TMPDIR/result-skill-create-preexisting.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail when the requested skill name already existed before the create probe was sent"
    else
        if jq -e '.failure.code == "semantic_skill_create_preexisting_name" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-create-preexisting.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must require a true pre->post creation transition rather than passing when the skill name was already present"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_skill_update_when_target_exists_before_send_and_remains_visible_after_reply"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-update-persisted" \
        MOLTIS_CURL_STUB_MODE=update_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_update_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Обнови навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-update-persisted.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must allow Telegram skill update only when the target existed before send and remains visible in live /api/skills after the reply"
    fi

    test_start "component_telegram_remote_uat_fails_skill_update_when_target_missing_before_send"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-update-missing-target" \
        MOLTIS_CURL_STUB_MODE=update_missing_target \
        TELEGRAM_WEB_STUB_MODE=skill_update_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Обнови навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-update-missing-target.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail skill update when the target skill was missing before the mutation turn"
    else
        if jq -e '.failure.code == "semantic_skill_update_missing_target_before_send" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-update-missing-target.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.requested_skill_name == "codex-update"' "$TEST_TMPDIR/result-skill-update-missing-target.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must produce an update-specific missing-target-before-send failure when the requested skill did not exist in the baseline"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_skill_update_when_reply_does_not_name_target_skill"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-update-name-mismatch" \
        MOLTIS_CURL_STUB_MODE=update_persisted \
        TELEGRAM_WEB_STUB_MODE=skill_update_missing_name_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Обнови навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-update-name-mismatch.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail skill update when the user-facing reply does not mention the target skill name"
    else
        if jq -e '.failure.code == "semantic_skill_update_reply_name_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-update-name-mismatch.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must produce an update-specific reply-name mismatch failure when the target skill is not named in the reply"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_skill_update_when_target_disappears_after_reply"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-update-disappeared" \
        MOLTIS_CURL_STUB_MODE=update_not_visible_after_mutation \
        TELEGRAM_WEB_STUB_MODE=skill_update_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Обнови навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-update-disappeared.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail skill update when the target skill is no longer visible after the mutation reply"
    else
        if jq -e '.failure.code == "semantic_skill_update_not_visible_after_mutation" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-update-disappeared.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must require the updated target skill to remain visible in live /api/skills after the mutation"
        fi
    fi

    test_start "component_telegram_remote_uat_allows_skill_delete_when_target_exists_before_send_and_disappears_after_reply"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-delete-removed" \
        MOLTIS_CURL_STUB_MODE=delete_removed \
        TELEGRAM_WEB_STUB_MODE=skill_delete_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Удали навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-delete-removed.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must allow Telegram skill delete only when the target existed before send and disappears from live /api/skills after the reply"
    fi

    test_start "component_telegram_remote_uat_allows_skill_delete_for_exact_russian_prompt_with_trailing_period"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-delete-trailing-dot" \
        MOLTIS_CURL_STUB_MODE=delete_removed \
        TELEGRAM_WEB_STUB_MODE=skill_delete_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Удали навык codex-update." \
        --output "$TEST_TMPDIR/result-skill-delete-trailing-dot.json" \
        >/dev/null 2>&1
    then
        test_pass
    else
        test_fail "Authoritative wrapper must trim trailing sentence punctuation from the requested skill name for exact Russian delete prompts"
    fi

    test_start "component_telegram_remote_uat_fails_skill_delete_when_target_missing_before_send"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-delete-missing-target" \
        MOLTIS_CURL_STUB_MODE=delete_missing_target \
        TELEGRAM_WEB_STUB_MODE=skill_delete_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Удали навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-delete-missing-target.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail skill delete when the target skill was missing before the mutation turn"
    else
        if jq -e '.failure.code == "semantic_skill_delete_missing_target_before_send" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-delete-missing-target.json" >/dev/null 2>&1 \
            && jq -e '.diagnostic_context.semantic_review.requested_skill_name == "codex-update"' "$TEST_TMPDIR/result-skill-delete-missing-target.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must produce a delete-specific missing-target-before-send failure when the requested skill did not exist in the baseline"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_skill_delete_when_reply_does_not_name_target_skill"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-delete-name-mismatch" \
        MOLTIS_CURL_STUB_MODE=delete_removed \
        TELEGRAM_WEB_STUB_MODE=skill_delete_missing_name_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Удали навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-delete-name-mismatch.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail skill delete when the user-facing reply does not mention the target skill name"
    else
        if jq -e '.failure.code == "semantic_skill_delete_reply_name_mismatch" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-delete-name-mismatch.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must produce a delete-specific reply-name mismatch failure when the target skill is not named in the reply"
        fi
    fi

    test_start "component_telegram_remote_uat_fails_skill_delete_when_target_still_visible_after_reply"
    if PATH="$TEST_TMPDIR:$PATH" \
        MOLTIS_PASSWORD=test-password \
        SKILLS_API_ATTEMPTS=1 \
        MOLTIS_CURL_STUB_COUNTER_FILE="$TEST_TMPDIR/curl-count-delete-still-visible" \
        MOLTIS_CURL_STUB_MODE=delete_not_removed \
        TELEGRAM_WEB_STUB_MODE=skill_delete_success_reply_pass \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --message "Удали навык codex-update" \
        --output "$TEST_TMPDIR/result-skill-delete-still-visible.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper must fail skill delete when the target skill remains visible after the mutation reply"
    else
        if jq -e '.failure.code == "semantic_skill_delete_still_visible_after_mutation" and .run.stage == "semantic_review"' "$TEST_TMPDIR/result-skill-delete-still-visible.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must require the deleted target skill to disappear from live /api/skills after the mutation"
        fi
    fi

    test_start "component_telegram_remote_uat_marks_mtproto_fallback_unavailable_when_prerequisites_missing"
    if "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --secondary-diagnostics mtproto \
        --message "/status" \
        --output "$TEST_TMPDIR/result-fallback.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should still fail when the primary verdict is red even if fallback is evaluated"
    else
        if jq -e '.fallback_assessment.requested == true and .fallback_assessment.outcome == "unavailable"' "$TEST_TMPDIR/result-fallback.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must record unavailable MTProto fallback prerequisites explicitly"
        fi
    fi

    test_start "component_telegram_remote_uat_marks_mtproto_verification_gate_as_noncomparable"
    if MTPROTO_STUB_MODE=verification_gate \
        TELEGRAM_TEST_API_ID=12345 \
        TELEGRAM_TEST_API_HASH=test-hash \
        TELEGRAM_TEST_SESSION=test-session \
        "$TEST_TMPDIR/telegram-e2e-on-demand.sh" \
        --mode authoritative \
        --secondary-diagnostics mtproto \
        --message "/status" \
        --output "$TEST_TMPDIR/result-verification-gate.json" \
        >/dev/null 2>&1
    then
        test_fail "Authoritative wrapper should still fail when the primary verdict is red even if MTProto only reaches a verification gate"
    else
        if jq -e '.fallback_assessment.requested == true and .fallback_assessment.outcome == "completed" and .fallback_assessment.observed_verification_gate == true and .fallback_assessment.comparable_to_authoritative == false' "$TEST_TMPDIR/result-verification-gate.json" >/dev/null 2>&1
        then
            test_pass
        else
            test_fail "Wrapper must mark MTProto verification-code responses as non-comparable secondary diagnostics"
        fi
    fi

    test_start "component_telegram_remote_uat_deploy_guard_keeps_scheduler_disabled"
    if grep -q "apply-moltis-host-automation.sh" "$PROJECT_ROOT/.github/workflows/deploy.yml" \
        && grep -Fq 'DISABLED_FALLBACK_SCHEDULER="moltis-telegram-web-user-monitor"' "$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh" \
        && grep -Fq 'systemctl disable --now "${DISABLED_FALLBACK_SCHEDULER}.timer"' "$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh" \
        && ! grep -Fq '${{ env.DEPLOY_ACTIVE_PATH }}/scripts/cron.d/moltis-telegram-web-user-monitor' "$PROJECT_ROOT/.github/workflows/deploy.yml" \
        && ! grep -q "systemctl enable --now .*telegram-web-user-monitor.timer" "$PROJECT_ROOT/scripts/apply-moltis-host-automation.sh"
    then
        test_pass
    else
        test_fail "Deploy workflow must keep the Telegram Web scheduler disabled by default"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_remote_uat_contract_tests
fi
