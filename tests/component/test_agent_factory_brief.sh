#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"
BRIEF_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/brief-awaiting-confirmation.json"

run_component_agent_factory_brief_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "component_agent_factory_brief_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_brief_generates_draft_and_renders_markdown"
    cat >"$tmpdir/ready-for-brief.json" <<'JSON'
{
  "project_key": "claims-routing-discovery-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-qa-001",
    "display_name": "Ирина"
  },
  "working_language": "ru",
  "raw_idea": "Нужен агент, который поможет распределять страховые обращения.",
  "captured_answers": {
    "target_business_problem": "Операторы долго читают типовые обращения вручную и тратят время на однотипные решения.",
    "target_users": [
      "Оператор первой линии",
      "Руководитель смены"
    ],
    "current_workflow_summary": "Сейчас каждое обращение читают вручную, ищут типовой сценарий и только потом либо отвечают, либо эскалируют эксперту.",
    "desired_outcome": "Чтобы агент сразу подсказывал категорию обращения и рекомендовал, кому его отдать дальше.",
    "user_story": "Как оператор первой линии, я хочу быстро понимать, куда маршрутизировать обращение и нужно ли сразу привлекать эксперта.",
    "input_examples": [
      "Клиент просит статус уже открытого страхового случая",
      "Клиент сообщает о новом повреждении имущества"
    ],
    "expected_outputs": [
      "Категория обращения",
      "Рекомендованный следующий шаг"
    ],
    "constraints_or_exclusions": [
      "На первом этапе без автоматической отправки ответа клиенту",
      "Только текстовые обращения"
    ],
    "measurable_success_expectation": [
      "Сократить время первичной маршрутизации минимум в 2 раза"
    ],
    "scope_boundaries": [
      "Только первичная маршрутизация обращения",
      "Без принятия страхового решения по выплате"
    ],
    "business_rules": [
      "Подозрение на мошенничество всегда эскалируется эксперту",
      "Запрос статуса без новых данных идет по типовой очереди"
    ],
    "exceptions": [
      "VIP-клиенты обрабатываются отдельной группой"
    ],
    "open_risks": [
      "Нужно уточнить правила для обращений от партнерских СТО"
    ]
  }
}
JSON
    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/ready-for-brief.json" --output "$tmpdir/ready-for-brief-out.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/ready-for-brief-out.json")" "Ready discovery context should produce a reviewable draft brief"
        assert_eq "request_explicit_confirmation" "$(jq -r '.next_action' "$tmpdir/ready-for-brief-out.json")" "Draft brief should request explicit confirmation"
        assert_eq "1.0" "$(jq -r '.requirement_brief.version' "$tmpdir/ready-for-brief-out.json")" "The first brief version should start at 1.0"
        assert_eq "awaiting_confirmation" "$(jq -r '.requirement_brief.status' "$tmpdir/ready-for-brief-out.json")" "Draft brief should stay in awaiting confirmation state"
        assert_eq "1" "$(jq -r '.brief_revisions | length' "$tmpdir/ready-for-brief-out.json")" "Initial draft should record the first revision"
        assert_contains "$(jq -r '.brief_markdown' "$tmpdir/ready-for-brief-out.json")" "# Требования к будущему AI-агенту" "Rendered markdown should come from the brief template"
        assert_contains "$(jq -r '.brief_markdown' "$tmpdir/ready-for-brief-out.json")" "VIP-клиенты" "Rendered markdown should include exception cases"
        assert_contains "$(jq -r '.brief_template_path' "$tmpdir/ready-for-brief-out.json")" "docs/templates/agent-factory/requirements-brief.md" "The response should expose the template source"
        test_pass
    else
        test_fail "Discovery runtime should generate a draft requirements brief from a ready discovery context"
    fi

    test_start "component_agent_factory_brief_versions_revision_before_confirmation"
    if jq '. + {
      "brief_feedback_text": "Добавь, что срочные платежи CFO идут по отдельному сценарию и остаются открытым риском первого прототипа.",
      "brief_section_updates": {
        "exceptions": [
          "Срочные платежи CFO идут по отдельному сценарию и требуют отдельной регламентации"
        ],
        "open_risks": [
          "Отдельный сценарий для срочных платежей CFO останется вне первого прототипа"
        ]
      }
    }' "$BRIEF_FIXTURE" >"$tmpdir/brief-revision-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/brief-revision-source.json" --output "$tmpdir/brief-revision-out.json" >/dev/null; then
        assert_eq "awaiting_confirmation" "$(jq -r '.status' "$tmpdir/brief-revision-out.json")" "A correction request should keep the brief in awaiting confirmation state"
        assert_eq "1.1" "$(jq -r '.requirement_brief.version' "$tmpdir/brief-revision-out.json")" "Meaningful brief changes should create a new version"
        assert_eq "2" "$(jq -r '.brief_revisions | length' "$tmpdir/brief-revision-out.json")" "A new brief version should append a revision record"
        assert_contains "$(jq -r '.brief_revisions[-1].changed_sections | join(",")' "$tmpdir/brief-revision-out.json")" "exceptions" "Revision metadata should list updated sections"
        assert_contains "$(jq -r '.brief_revisions[-1].changed_sections | join(",")' "$tmpdir/brief-revision-out.json")" "open_risks" "Revision metadata should keep risk updates traceable"
        assert_contains "$(jq -r '.brief_markdown' "$tmpdir/brief-revision-out.json")" "Срочные платежи CFO" "Updated markdown should reflect the correction"
        test_pass
    else
        test_fail "Discovery runtime should version the brief when the user requests corrections"
    fi

    test_start "component_agent_factory_brief_records_explicit_confirmation"
    if jq '. + {
      "confirmation_reply": {
        "confirmed": true,
        "confirmation_text": "Да, это верное описание требований для первого прототипа.",
        "confirmed_by": "demo-business-user"
      }
    }' "$BRIEF_FIXTURE" >"$tmpdir/brief-confirmation-source.json" &&
        python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/brief-confirmation-source.json" --output "$tmpdir/brief-confirmation-out.json" >/dev/null; then
        assert_eq "confirmed" "$(jq -r '.status' "$tmpdir/brief-confirmation-out.json")" "Explicit confirmation should move the brief to confirmed state"
        assert_eq "confirmed" "$(jq -r '.requirement_brief.status' "$tmpdir/brief-confirmation-out.json")" "The requirement brief should persist the confirmed state"
        assert_eq "start_concept_pack_handoff" "$(jq -r '.next_action' "$tmpdir/brief-confirmation-out.json")" "A confirmed brief should expose the next downstream action"
        assert_eq "active" "$(jq -r '.confirmation_snapshot.status' "$tmpdir/brief-confirmation-out.json")" "Confirmation should create an active snapshot"
        assert_eq "1.0" "$(jq -r '.confirmation_snapshot.brief_version' "$tmpdir/brief-confirmation-out.json")" "Snapshot should point to the exact confirmed brief version"
        test_pass
    else
        test_fail "Discovery runtime should capture an explicit confirmation snapshot"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_brief_tests
fi
