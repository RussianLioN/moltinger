#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"

run_integration_local_agent_factory_confirmation_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_confirmation_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_confirmation_flow_moves_from_draft_to_confirmed_brief"
    cat >"$tmpdir/ready-discovery.json" <<'JSON'
{
  "project_key": "invoice-approval-discovery-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-qa-001",
    "display_name": "Ольга"
  },
  "working_language": "ru",
  "raw_idea": "Нужен агент, который поможет быстрее проверять заявки на оплату счетов.",
  "captured_answers": {
    "target_business_problem": "Ручная сверка заявок на оплату счетов перегружает финансовый контроль и замедляет согласование.",
    "target_users": [
      "Финансовый контролер",
      "Руководитель подразделения"
    ],
    "current_workflow_summary": "Контролер вручную сверяет лимиты, реквизиты и комплектность документов, затем эскалирует исключения руководителю.",
    "desired_outcome": "Автоматически отфильтровывать типовые заявки и подсказывать, когда нужна эскалация или отказ.",
    "user_story": "Как финансовый контролер, я хочу быстро видеть, какие заявки проходят правила, а какие требуют дополнительного согласования.",
    "input_examples": [
      "Заявка на оплату с суммой выше лимита подразделения",
      "Заявка без подписанного договора"
    ],
    "expected_outputs": [
      "Статус проверки заявки",
      "Причина блокировки или рекомендация по дальнейшему шагу"
    ],
    "constraints_or_exclusions": [
      "Использовать только sanitized examples на этапе прототипа",
      "Не требовать от пользователя технических формулировок"
    ],
    "measurable_success_expectation": [
      "Сократить время первичной проверки минимум на 50 процентов",
      "Снизить долю ручных возвратов из-за неполного комплекта документов"
    ],
    "scope_boundaries": [
      "Только внутренняя проверка заявок на оплату счетов",
      "Без автоматического списания денег или отправки платежа"
    ],
    "business_rules": [
      "Превышение лимита требует дополнительного согласования",
      "Без обязательных документов заявка не должна проходить дальше"
    ],
    "exceptions": [
      "Срочные платежи CFO могут идти по отдельному сценарию"
    ],
    "open_risks": [
      "Нужно дополнительно согласовать сценарий для срочных платежей CFO"
    ]
  }
}
JSON

    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/ready-discovery.json" --output "$tmpdir/draft-brief.json" >/dev/null &&
        jq '. + {
          "brief_feedback_text": "Уточни, что срочные платежи CFO остаются вне первого прототипа и считаются отдельным открытым риском.",
          "brief_section_updates": {
            "exceptions": [
              "Срочные платежи CFO идут по отдельному сценарию и фиксируются как open risk для MVP0"
            ],
            "open_risks": [
              "Отдельный сценарий для срочных платежей CFO останется вне первого прототипа"
            ]
          }
        }' "$tmpdir/draft-brief.json" >"$tmpdir/revision-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/revision-source.json" --output "$tmpdir/revised-brief.json" >/dev/null &&
        jq '. + {
          "confirmation_reply": {
            "confirmed": true,
            "confirmation_text": "Да, это верное описание требований для первого прототипа.",
            "confirmed_by": "business-user-qa-001"
          }
        }' "$tmpdir/revised-brief.json" >"$tmpdir/confirmation-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/confirmation-source.json" --output "$tmpdir/confirmed-brief.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/draft-brief.json")" "Ready discovery context should first produce a draft brief"
        assert_eq "1.0" "$(jq -r '.requirement_brief.version' "$tmpdir/draft-brief.json")" "The initial draft should start with version 1.0"
        assert_eq "1.1" "$(jq -r '.requirement_brief.version' "$tmpdir/revised-brief.json")" "A conversational correction should create the next brief version"
        assert_eq "2" "$(jq -r '.brief_revisions | length' "$tmpdir/revised-brief.json")" "The revised brief should keep revision history"
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/confirmed-brief.json")" "An explicit confirmation reply should finalize the brief"
        assert_eq "confirmed" "$(jq -r '.requirement_brief.status' "$tmpdir/confirmed-brief.json")" "The confirmed brief should persist its terminal state"
        assert_eq "1.1" "$(jq -r '.confirmation_snapshot.brief_version' "$tmpdir/confirmed-brief.json")" "Confirmation should bind to the latest reviewed version"
        assert_eq "active" "$(jq -r '.confirmation_snapshot.status' "$tmpdir/confirmed-brief.json")" "The confirmation snapshot should stay active"
        assert_eq "1.1" "$(jq -r '.discovery_session.latest_brief_version' "$tmpdir/confirmed-brief.json")" "Discovery session state should point to the latest confirmed version"
        assert_eq "start_concept_pack_handoff" "$(jq -r '.next_action' "$tmpdir/confirmed-brief.json")" "The next action should signal downstream handoff readiness"
        assert_eq "false" "$(jq -r 'has("factory_handoff_record")' "$tmpdir/confirmed-brief.json")" "US2 should stop before creating the downstream handoff record"
        assert_contains "$(jq -r '.brief_markdown' "$tmpdir/confirmed-brief.json")" "Срочные платежи CFO" "The final rendered brief should keep the corrected business wording"
        test_pass
    else
        test_fail "Discovery confirmation flow should move from draft to revised to confirmed brief without manual file edits"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_confirmation_tests
fi
