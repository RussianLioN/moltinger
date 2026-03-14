# Agent Factory Discovery Runbook

## Purpose

This runbook describes the current `US1` + `US2` runtime slice for `022-telegram-ba-intake`.

Current scope:

1. start discovery from a raw Telegram idea
2. normalize free-form business answers into tracked requirement topics
3. keep topic-level progress across the required discovery areas
4. surface one next useful question or one open clarification
5. build a reviewable requirements brief when discovery is sufficiently complete
6. let the user request corrections and explicitly confirm one exact brief version
7. stop before canonical handoff generation and downstream concept-pack execution

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
- optional `requirement_brief`
- optional `brief_revisions`
- optional `confirmation_snapshot`
- optional `brief_markdown`
- optional `brief_template_path`

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

### 3. Existing brief review state

The command also accepts:

- `requirement_brief`
- optional `brief_revisions`
- optional `confirmation_snapshot`
- optional `brief_feedback_text`
- optional `brief_section_updates`
- optional `confirmation_reply`

This lets the runtime keep the same conversation while the user:

- reviews the current brief
- asks for corrections in normal language
- explicitly confirms one exact version

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

### 4. Build a reviewable requirements brief

```bash
cat >/tmp/discovery-ready-for-brief.json <<'JSON'
{
  "project_key": "invoice-approval-discovery-demo",
  "request_channel": "telegram",
  "requester_identity": {
    "telegram_user_id": "demo-business-user",
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
      "Сократить время первичной проверки минимум на 50 процентов"
    ],
    "scope_boundaries": [
      "Только внутренняя проверка заявок на оплату счетов",
      "Без автоматического списания денег или отправки платежа"
    ],
    "business_rules": [
      "Превышение лимита требует дополнительного согласования"
    ],
    "exceptions": [
      "Срочные платежи CFO могут идти по отдельному сценарию"
    ]
  }
}
JSON

python3 scripts/agent-factory-discovery.py run \
  --source /tmp/discovery-ready-for-brief.json \
  --output /tmp/discovery-ready-for-brief-out.json
```

Expected result:

- `status = awaiting_confirmation`
- `next_action = request_explicit_confirmation`
- `requirement_brief.version = 1.0`
- `brief_markdown` is rendered from `docs/templates/agent-factory/requirements-brief.md`

### 5. Apply a conversational correction before confirmation

```bash
jq '. + {
  "brief_feedback_text": "Уточни, что срочные платежи CFO остаются вне первого прототипа.",
  "brief_section_updates": {
    "exceptions": [
      "Срочные платежи CFO идут по отдельному сценарию и фиксируются как open risk для MVP0"
    ],
    "open_risks": [
      "Отдельный сценарий для срочных платежей CFO останется вне первого прототипа"
    ]
  }
}' /tmp/discovery-ready-for-brief-out.json >/tmp/discovery-revision-source.json

python3 scripts/agent-factory-discovery.py run \
  --source /tmp/discovery-revision-source.json \
  --output /tmp/discovery-revision-out.json
```

Expected result:

- `status = awaiting_confirmation`
- `requirement_brief.version` increments
- `brief_revisions` appends one more revision entry
- rendered markdown reflects the corrected sections

### 6. Record explicit confirmation

```bash
jq '. + {
  "confirmation_reply": {
    "confirmed": true,
    "confirmation_text": "Да, это верное описание требований для первого прототипа.",
    "confirmed_by": "demo-business-user"
  }
}' /tmp/discovery-revision-out.json >/tmp/discovery-confirmation-source.json

python3 scripts/agent-factory-discovery.py run \
  --source /tmp/discovery-confirmation-source.json \
  --output /tmp/discovery-confirmation-out.json
```

Expected result:

- `status = confirmed`
- `confirmation_snapshot.status = active`
- `next_action = start_concept_pack_handoff`
- no handoff record is created yet; that starts in `US4`

## State Mapping

### `status`

- `awaiting_user_reply` — there is a next discovery question for the user
- `awaiting_clarification` — one explicit clarification item blocks the flow
- `awaiting_confirmation` — discovery is complete enough to review the current brief version
- `confirmed` — one exact brief version was explicitly confirmed and is ready for later handoff
- `in_progress` — no immediate next question is required and the flow can proceed to the next slice

### `next_action`

- `ask_next_question`
- `resolve_clarification`
- `prepare_brief`
- `request_explicit_confirmation`
- `start_concept_pack_handoff`

## Current Boundary

This runbook currently covers `US1` and `US2`.

Not included yet:

- canonical handoff record generation
- downstream concept-pack execution
- resume/reopen semantics beyond snapshot recomputation

Those arrive in `US4` and `US5`.
