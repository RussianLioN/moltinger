#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

DISCOVERY_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-discovery.py"
SESSION_CLARIFICATION_FIXTURE="$PROJECT_ROOT/tests/fixtures/agent-factory/discovery/session-awaiting-clarification.json"

run_integration_local_agent_factory_discovery_flow_tests() {
    start_timer
    require_commands_or_skip python3 jq || {
        test_start "integration_local_agent_factory_discovery_flow_prereqs"
        test_skip "python3 and jq are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "integration_local_agent_factory_discovery_flow_starts_from_raw_idea_without_template"
    cat > "$tmpdir/raw-idea.json" <<'JSON'
{
  "project_key": "claims-routing-discovery-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-001",
    "display_name": "Ирина"
  },
  "working_language": "ru",
  "raw_idea": "Хочу, чтобы агент помогал маршрутизировать страховые обращения и сразу подсказывал, какие из них типовые, а какие нужно эскалировать специалисту."
}
JSON
    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/raw-idea.json" --output "$tmpdir/raw-idea-out.json" >/dev/null; then
        assert_eq "telegram" "$(jq -r '.discovery_session.request_channel' "$tmpdir/raw-idea-out.json")" "Telegram should stay the discovery channel"
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/raw-idea-out.json")" "New raw idea should produce the next guided question"
        assert_eq "target_users" "$(jq -r '.next_topic' "$tmpdir/raw-idea-out.json")" "Target users should be the next discovery topic"
        assert_contains "$(jq -r '.agent_summary' "$tmpdir/raw-idea-out.json")" "AI бизнес-аналитик" "Agent summary should explain the business-analyst role"
        assert_eq "user,agent" "$(jq -r '[.conversation_turns[].actor] | join(",")' "$tmpdir/raw-idea-out.json")" "Discovery should create one user turn and one follow-up agent turn"
        assert_eq "false" "$(jq -r '.topic_progress.ready_for_brief' "$tmpdir/raw-idea-out.json")" "Raw idea alone cannot unlock the brief"
        test_pass
    else
        test_fail "Discovery flow should start directly from a raw idea"
    fi

    test_start "integration_local_agent_factory_discovery_flow_advances_after_free_form_business_answers"
    cat > "$tmpdir/free-form-answers.json" <<'JSON'
{
  "project_key": "claims-routing-discovery-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "business-user-001",
    "display_name": "Ирина"
  },
  "working_language": "ru",
  "raw_idea": "Нужен агент, который поможет распределять страховые обращения.",
  "captured_answers": {
    "target_business_problem": "Операторы долго читают типовые обращения вручную и тратят время на однотипные решения.",
    "target_users": "Оператор первой линии и руководитель смены.",
    "current_workflow_summary": "Сейчас каждое обращение читают вручную, ищут типовой сценарий и только потом либо отвечают, либо эскалируют эксперту.",
    "desired_outcome": "Чтобы агент сразу подсказывал категорию обращения и рекомендовал, кому его отдать дальше.",
    "constraints_or_exclusions": [
      "На первом этапе без автоматической отправки ответа клиенту",
      "Только текстовые обращения"
    ],
    "measurable_success_expectation": [
      "Сократить время первичной маршрутизации минимум в 2 раза"
    ]
  }
}
JSON
    if python3 "$DISCOVERY_SCRIPT" run --source "$tmpdir/free-form-answers.json" --output "$tmpdir/free-form-answers-out.json" >/dev/null; then
        assert_eq "awaiting_user_reply" "$(jq -r '.status' "$tmpdir/free-form-answers-out.json")" "Structured business answers should still keep the interview conversational"
        assert_eq "user_story" "$(jq -r '.next_topic' "$tmpdir/free-form-answers-out.json")" "After core business context, the next question should move to user story"
        assert_contains "$(jq -r '.next_question' "$tmpdir/free-form-answers-out.json")" "Какому сотруднику" "User-story follow-up should remain business-readable"
        assert_eq "0" "$(jq -r '.topic_progress.blocking_topics_remaining | length' "$tmpdir/free-form-answers-out.json")" "All blocking topics should be covered by the free-form answers"
        assert_gt "$(jq -r '.topic_progress.resolved_topics' "$tmpdir/free-form-answers-out.json")" "4" "Most core topics should already be resolved"
        assert_eq "false" "$(jq -r '.topic_progress.ready_for_brief' "$tmpdir/free-form-answers-out.json")" "Optional discovery topics should still keep the brief blocked"
        test_pass
    else
        test_fail "Discovery flow should normalize free-form business answers and move to the next uncovered topic"
    fi

    test_start "integration_local_agent_factory_discovery_flow_keeps_open_clarification_blocking"
    if python3 "$DISCOVERY_SCRIPT" run --source "$SESSION_CLARIFICATION_FIXTURE" --output "$tmpdir/clarification-out.json" >/dev/null; then
        assert_eq "awaiting_clarification" "$(jq -r '.status' "$tmpdir/clarification-out.json")" "Open clarification should block the next stage"
        assert_eq "resolve_clarification" "$(jq -r '.next_action' "$tmpdir/clarification-out.json")" "Clarification should be the explicit next action"
        assert_eq "false" "$(jq -r '.topic_progress.ready_for_brief' "$tmpdir/clarification-out.json")" "An unsafe example should keep the discovery flow blocked"
        test_pass
    else
        test_fail "Discovery flow should not advance while a clarification item remains open"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_integration_local_agent_factory_discovery_flow_tests
fi
