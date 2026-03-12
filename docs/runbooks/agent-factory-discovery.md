# Agent Factory Discovery Runbook

## Purpose

This runbook describes the current `US1` runtime slice for `022-telegram-ba-intake`.

Current scope:

1. start discovery from a raw Telegram idea
2. normalize free-form business answers into tracked requirement topics
3. keep topic-level progress across the required discovery areas
4. surface one next useful question or one open clarification
5. stop before brief confirmation and before downstream concept-pack generation

## Runtime Contract

The discovery entrypoint is:

```bash
python3 scripts/agent-factory-discovery.py run --source <input.json> --output <result.json>
```

The command currently returns:

- `status`
- `next_action`
- `next_topic`
- `next_question`
- `discovery_session`
- `topic_progress`
- `requirement_topics`
- `clarification_items`
- `conversation_turns`
- `open_questions`

## Accepted Input Shapes

### 1. Raw discovery request

Recommended fields:

- `project_key`
- `request_channel`
- `requester_identity`
- `working_language`
- `raw_idea`
- optional `captured_answers`

`captured_answers` may use business-facing keys already known in the repo, for example:

- `target_business_problem`
- `target_users`
- `current_workflow_summary`
- `desired_outcome`
- `constraints_or_exclusions`
- `measurable_success_expectation`

### 2. Existing discovery session snapshot

The command also accepts an existing snapshot containing:

- `discovery_session`
- `requirement_topics`
- `clarification_items`
- optional `conversation_turns`

This lets the runtime recompute progress and preserve the next question without requiring an external state service.

## Commands

### 1. Start from a raw idea

```bash
cat >/tmp/discovery-raw-idea.json <<'JSON'
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

python3 scripts/agent-factory-discovery.py run \
  --source /tmp/discovery-raw-idea.json \
  --output /tmp/discovery-raw-idea-out.json
```

Expected result:

- `status = awaiting_user_reply`
- `next_action = ask_next_question`
- `next_topic = target_users`
- `conversation_turns` contains one user idea turn and one agent follow-up question

### 2. Continue from richer business answers

```bash
cat >/tmp/discovery-free-form-answers.json <<'JSON'
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

python3 scripts/agent-factory-discovery.py run \
  --source /tmp/discovery-free-form-answers.json \
  --output /tmp/discovery-free-form-answers-out.json
```

Expected result:

- blocking topics are no longer the bottleneck
- `next_topic = user_story`
- the session still remains conversational and does not jump to downstream generation

### 3. Re-evaluate an open clarification

```bash
python3 scripts/agent-factory-discovery.py run \
  --source tests/fixtures/agent-factory/discovery/session-awaiting-clarification.json \
  --output /tmp/discovery-clarification-out.json
```

Expected result:

- `status = awaiting_clarification`
- `next_action = resolve_clarification`
- `next_question` matches the open clarification item
- `topic_progress.ready_for_brief = false`

## State Mapping

### `status`

- `awaiting_user_reply` — there is a next discovery question for the user
- `awaiting_clarification` — one explicit clarification item blocks the flow
- `in_progress` — no immediate next question is required and the flow can proceed to the next slice

### `next_action`

- `ask_next_question`
- `resolve_clarification`
- `prepare_brief`

## Current Boundary

This runbook only covers `US1`.

Not included yet:

- draft brief rendering
- explicit confirmation
- handoff into the existing concept-pack pipeline
- resume/reopen semantics beyond snapshot recomputation

Those arrive in `US2`, `US4`, and `US5`.
