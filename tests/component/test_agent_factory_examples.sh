#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"

run_component_agent_factory_examples_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_examples_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_examples_extracts_structured_example_cases"
    cat >"$tmpdir/example-extraction.json" <<'JSON'
{
  "project_key": "claims-routing-examples-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-qa-002",
    "display_name": "Елена"
  },
  "working_language": "ru",
  "raw_idea": "Нужен агент, который помогает маршрутизировать страховые обращения.",
  "captured_answers": {
    "target_business_problem": "Операторы тратят слишком много времени на разбор типовых обращений.",
    "target_users": [
      "Оператор первой линии",
      "Руководитель смены"
    ],
    "current_workflow_summary": "Оператор читает обращение вручную, ищет похожий сценарий и решает, отвечать самому или эскалировать эксперту.",
    "desired_outcome": "Чтобы агент сразу классифицировал обращение и рекомендовал следующий шаг.",
    "constraints_or_exclusions": [
      "На первом этапе только текстовые обращения",
      "Без автоматической отправки ответа клиенту"
    ],
    "measurable_success_expectation": [
      "Сократить время первичной маршрутизации минимум в 2 раза"
    ],
    "business_rules": [
      "Подозрение на мошенничество всегда эскалируется эксперту"
    ],
    "exceptions": [
      "VIP-клиенты идут по отдельной очереди"
    ],
    "input_examples": [
      "Клиент просит статус уже открытого страхового случая",
      "Клиент сообщает о новом повреждении имущества"
    ],
    "expected_outputs": [
      "Показать категорию обращения и типовой следующий шаг",
      "Показать категорию и рекомендовать эскалацию эксперту"
    ]
  }
}
JSON
    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/example-extraction.json" --output "$tmpdir/example-extraction-out.json" >/dev/null; then
        assert_eq "2" "$(jq -r '.example_cases | length' "$tmpdir/example-extraction-out.json")" "Input and output examples should become structured example cases"
        assert_eq "sanitized" "$(jq -r '.example_cases[0].data_safety_status' "$tmpdir/example-extraction-out.json")" "Safe text examples should default to sanitized status"
        assert_contains "$(jq -r '.example_cases[0].linked_rules | join(",")' "$tmpdir/example-extraction-out.json")" "мошенничество" "Example cases should retain linked business rules"
        assert_contains "$(jq -r '.example_cases[0].exception_notes' "$tmpdir/example-extraction-out.json")" "VIP-клиенты" "Example cases should retain exception context"
        test_pass
    else
        test_fail "Discovery runtime should capture example cases from business-facing inputs"
    fi

    test_start "component_agent_factory_examples_flags_unsafe_example_data"
    cat >"$tmpdir/example-unsafe.json" <<'JSON'
{
  "project_key": "invoice-unsafe-example-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-qa-003",
    "display_name": "Ольга"
  },
  "working_language": "ru",
  "raw_idea": "Нужен агент, который помогает проверять заявки на оплату счетов.",
  "captured_answers": {
    "target_business_problem": "Ручная сверка реквизитов перегружает финансовый контроль.",
    "target_users": "Финансовый контролер",
    "current_workflow_summary": "Контролер вручную сверяет лимиты и комплектность документов.",
    "desired_outcome": "Автоматически подсказывать, когда заявку нужно эскалировать.",
    "constraints_or_exclusions": [
      "Использовать только sanitized examples на этапе прототипа"
    ],
    "measurable_success_expectation": [
      "Сократить время первичной проверки минимум на 50 процентов"
    ],
    "input_examples": [
      "Счет от ООО Ромашка, ИНН 7701234567, р/с 40702810900001234567"
    ],
    "expected_outputs": [
      "Подсказать, что заявку нужно проверить дополнительно"
    ]
  }
}
JSON
    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/example-unsafe.json" --output "$tmpdir/example-unsafe-out.json" >/dev/null; then
        assert_eq "needs_redaction" "$(jq -r '.example_cases[0].data_safety_status' "$tmpdir/example-unsafe-out.json")" "Unsafe example data should be flagged for redaction"
        assert_eq "resolve_clarification" "$(jq -r '.next_action' "$tmpdir/example-unsafe-out.json")" "Unsafe example should block the flow with a clarification"
        assert_eq "unsafe_data_example" "$(jq -r '.clarification_items[] | select(.status == "open") | .reason' "$tmpdir/example-unsafe-out.json")" "Unsafe example should create a structured clarification item"
        assert_contains "$(jq -r '.open_questions | join(" | ")' "$tmpdir/example-unsafe-out.json")" "без реальных реквизитов" "The clarification should ask for a sanitized replacement"
        test_pass
    else
        test_fail "Discovery runtime should not accept unsafe business examples silently"
    fi

    test_start "component_agent_factory_examples_detects_contradictory_expected_output"
    cat >"$tmpdir/example-contradiction.json" <<'JSON'
{
  "project_key": "claims-contradiction-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-qa-004",
    "display_name": "Ирина"
  },
  "working_language": "ru",
  "raw_idea": "Нужен агент, который помогает маршрутизировать спорные страховые обращения.",
  "captured_answers": {
    "target_business_problem": "Операторы долго решают, какие обращения нужно сразу эскалировать.",
    "target_users": "Оператор первой линии",
    "current_workflow_summary": "Оператор читает обращение и решает, нужен ли эксперт.",
    "desired_outcome": "Чтобы агент быстро показывал, когда нужна эскалация.",
    "constraints_or_exclusions": [
      "Без автоматической отправки ответа клиенту"
    ],
    "measurable_success_expectation": [
      "Сократить время первичной маршрутизации минимум в 2 раза"
    ],
    "business_rules": [
      "Подозрение на мошенничество всегда эскалируется эксперту"
    ],
    "input_examples": [
      "Клиент сообщает о серии однотипных повреждений и просит немедленную выплату"
    ],
    "expected_outputs": [
      "Автоматически одобрить обращение без дополнительного согласования"
    ]
  }
}
JSON
    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/example-contradiction.json" --output "$tmpdir/example-contradiction-out.json" >/dev/null; then
        assert_eq "resolve_clarification" "$(jq -r '.next_action' "$tmpdir/example-contradiction-out.json")" "Contradictory example should block the flow with a clarification"
        assert_eq "contradictory_examples" "$(jq -r '.clarification_items[] | select(.status == "open") | .reason' "$tmpdir/example-contradiction-out.json")" "Contradictory example should create a contradiction clarification"
        assert_eq "true" "$(jq -r '[.requirement_topics[] | select(.topic_name == "expected_outputs" and .status == "unresolved")] | length == 1' "$tmpdir/example-contradiction-out.json")" "The conflicting output topic should remain unresolved"
        assert_eq "false" "$(jq -r '.topic_progress.ready_for_brief' "$tmpdir/example-contradiction-out.json")" "Contradictory examples must keep the brief blocked"
        assert_contains "$(jq -r '.open_questions | join(" | ")' "$tmpdir/example-contradiction-out.json")" "противоречие" "The user-facing clarification should explain the contradiction"
        test_pass
    else
        test_fail "Discovery runtime should detect contradictions between examples and business rules"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_examples_tests
fi
