# Agent Factory Discovery Runbook

## Purpose

This runbook describes the current `US1` through `US5` runtime slice for `022-telegram-ba-intake`.

Clarification:

- `022-telegram-ba-intake` is the legacy feature id.
- The runtime slice belongs to the factory business-analyst agent on `Moltis`.
- `Telegram` is only the current reference/default interface adapter.

Current scope:

1. start discovery from a raw idea coming from a supported factory interface
2. normalize free-form business answers into tracked requirement topics
3. keep topic-level progress across the required discovery areas
4. surface one next useful question or one open clarification
5. build a reviewable requirements brief when discovery is sufficiently complete
6. let the user request corrections and explicitly confirm one exact brief version
7. emit one canonical handoff record after replaying a confirmed brief
8. bridge the ready handoff into the existing concept-pack intake without manual copy-paste
9. resume interrupted discovery and reopen confirmed briefs without losing prior confirmation or handoff history

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
- optional `confirmation_history`
- optional `factory_handoff_record`
- optional `handoff_history`
- optional `brief_markdown`
- optional `brief_template_path`
- optional `example_cases`
- optional `resume_context`

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
- optional `requirement_brief`
- optional `brief_revisions`
- optional `confirmation_snapshot`
- optional `confirmation_history`
- optional `factory_handoff_record`
- optional `handoff_history`

This lets the runtime recompute progress and preserve the next question without requiring an external state service.

### 3. Existing brief review state

The command also accepts:

- `requirement_brief`
- optional `brief_revisions`
- optional `confirmation_snapshot`
- optional `confirmation_history`
- optional `factory_handoff_record`
- optional `handoff_history`
- optional `brief_feedback_text`
- optional `brief_section_updates`
- optional `confirmation_reply`

This lets the runtime keep the same conversation while the user:

- reviews the current brief
- asks for corrections in normal language
- explicitly confirms one exact version

### 4. Existing confirmed handoff state

The command also accepts:

- `requirement_brief` in confirmed state
- active `confirmation_snapshot`
- optional existing `factory_handoff_record`

This lets the runtime replay a confirmed brief and emit or preserve the canonical handoff record for the downstream concept-pack pipeline.

### 5. Example-first discovery state

The command also accepts explicit `example_cases` when the caller already has normalized cases.

Each case should carry:

- `case_type`
- `input_summary`
- `expected_output_summary`
- optional `linked_rules`
- optional `exception_notes`
- optional `data_safety_status`

If `example_cases` are not provided, the runtime derives them from `input_examples`, `expected_outputs`, `business_rules`, and `exceptions`.

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

### 7. Replay the confirmed brief and create canonical handoff

```bash
python3 scripts/agent-factory-discovery.py run \
  --source /tmp/discovery-confirmation-out.json \
  --output /tmp/discovery-handoff-out.json
```

Expected result:

- `status = confirmed`
- `next_action = run_factory_intake`
- `factory_handoff_record.handoff_status = ready`
- `factory_handoff_record.brief_version` matches the active confirmation snapshot

### 8. Bridge handoff into the existing concept-pack intake

```bash
python3 scripts/agent-factory-intake.py \
  --source /tmp/discovery-handoff-out.json \
  --output /tmp/discovery-handoff-intake.json
```

Expected result:

- `status = ready_for_pack`
- `concept_request.source_kind = confirmed_discovery_handoff`
- `concept_record.source_request_id` equals `factory_handoff_record.factory_handoff_id`
- no manual reconstruction of the brief is required

### 9. Resume an interrupted discovery snapshot

```bash
python3 scripts/agent-factory-discovery.py run \
  --source tests/fixtures/agent-factory/discovery/session-new.json \
  --output /tmp/discovery-resume-out.json
```

Expected result:

- `resume_context.resumed = true`
- `resume_context.resumed_from_status` reflects the previous session state
- `resume_context.pending_question` restores the exact pending agent question
- `conversation_turns` do not duplicate the already asked question

### 10. Reopen a confirmed brief with preserved history

```bash
tmpdir="$(mktemp -d)"

jq '. + {
  "brief_feedback_text": "Добавь, что срочные платежи CFO идут по отдельному сценарию и требуют нового согласования.",
  "brief_section_updates": {
    "exceptions": [
      "Срочные платежи CFO идут по отдельному сценарию и требуют нового согласования"
    ],
    "open_risks": [
      "Нужно отдельно описать сценарий срочных платежей CFO"
    ]
  }
}' tests/fixtures/agent-factory/discovery/brief-confirmed-handoff.json >"$tmpdir/reopen-source.json"

python3 scripts/agent-factory-discovery.py run \
  --source "$tmpdir/reopen-source.json" \
  --output "$tmpdir/reopened-brief.json"
```

Expected result:

- `status = reopened`
- `requirement_brief.version` moves to the next version
- `confirmation_history[0].status = superseded`
- `handoff_history[0].handoff_status = superseded`
- active `factory_handoff_record` remains absent until the reopened brief is confirmed again

## Example And Clarification Policy

- The runtime preserves grounded cases as `example_cases`, not only as free text in the brief.
- Each case is classified with one `data_safety_status`.
- `needs_redaction` means the example appears to contain real identifiers, account data, or other production-like details and must be replaced with a sanitized or synthetic version.
- Contradictions between example outcomes and business rules or constraints create `ClarificationItem` records with reason `contradictory_examples`.
- Unsafe examples create `ClarificationItem` records with reason `unsafe_data_example`.
- While such clarifications remain open, the flow must stay blocked from confirmation even if a draft brief already exists.

## State Mapping

### `status`

- `awaiting_user_reply` — there is a next discovery question for the user
- `awaiting_clarification` — one explicit clarification item blocks the flow
- `awaiting_confirmation` — discovery is complete enough to review the current brief version
- `confirmed` — one exact brief version was explicitly confirmed and is ready for later handoff
- `reopened` — a previously confirmed brief was corrected and now requires a fresh confirmation pass
- `in_progress` — no immediate next question is required and the flow can proceed to the next slice

### `next_action`

- `ask_next_question`
- `resolve_clarification`
- `prepare_brief`
- `request_explicit_confirmation`
- `start_concept_pack_handoff`
- `run_factory_intake`
- `return_to_discovery_handoff`

## Current Boundary

This runbook currently covers `US1` through `US5`.

Current runtime additions from `US5`:

- `resume_context` for explicit recovery metadata
- `confirmation_history` for superseded confirmation snapshots
- `handoff_history` for superseded downstream handoff records
