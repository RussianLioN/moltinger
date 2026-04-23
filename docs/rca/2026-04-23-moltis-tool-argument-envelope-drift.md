---
title: "Moltis tool argument envelope drift surfaced as missing required parameters"
date: 2026-04-23
severity: P1
category: product
tags: [telegram, moltis, hooks, tools, skills, runtime, rca]
root_cause: "Repo-owned hook logic treated visible missing-parameter cards as a delivery hygiene problem while live session artifacts showed a deeper argument-envelope drift: required fields were present in persisted tool-call JSON but reached runner validation as missing."
---

# RCA: Moltis tool argument envelope drift surfaced as missing required parameters

**Дата:** 2026-04-23
**Статус:** Resolved
**Влияние:** Telegram/Web turns could show `missing 'command' parameter`, `missing 'query' parameter`, `missing 'name'`, `missing 'action'`, or `missing 'pattern'` even when the persisted tool-call JSON contained the required field.
**Контекст:** Moltis `BeforeToolCall` hook, Telegram bot skill editing/maintenance turns, OpenAI Codex provider path.

## Ошибка

Previous containment changed delivery behavior so raw cards were less visible, but it did not fix why valid tool calls were failing. Production session artifacts showed calls like:

- `read_skill` with `name: "codex-update"` and `file_path: null`, followed by `missing 'name'`;
- `memory_search` with `query: "..."`, followed by `missing 'query' parameter`;
- `exec` with `command: "..."`, followed by `missing 'command' parameter`;
- `cron` with `action: "list"`, followed by `missing 'action' parameter`;
- `Glob` with `pattern: "**/codex-update/**"`, followed by `missing 'pattern' parameter`.

The common shape was not absent required fields. It was an enriched runtime argument envelope with repo/runtime metadata such as `_channel`, `_session_key`, and null optional fields.

## Проверка прошлых уроков

Проверенные источники:

- `MEMORY.md`
- `SESSION_SUMMARY.md`
- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`
- `./scripts/query-lessons.sh --tag skills`

Релевантные прошлые уроки:

1. `2026-04-20-telegram-safe-maintenance-turns-fell-into-upstream-tool-boundary-errors` already warned that maintenance/debug turns need source-level contracts, not just user-facing cleanup.
2. `2026-04-14-telegram-codex-update-array-content-bypassed-turn-classifier` covered payload-shape drift as a public hook contract issue.
3. `2026-04-02-telegram-skill-detail-fell-back-to-tool-error-leak` covered that component tests must prove runtime/container behavior, not host-only assumptions.

Что новое:

- The runner error text was misleading: the required fields were present before execution. The missing piece was canonicalizing the argument object before the runner validates it.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Why did users still see missing-parameter failures? | The hook hid some final messages but valid tool calls still reached runtime in a non-canonical envelope. | Live session JSONL showed required args plus runner errors. |
| 2 | Why did validation say fields were missing? | The argument object contained runtime metadata/null fields and was not normalized before tool execution. | Same failure family across `read_skill`, `memory_search`, `exec`, `cron`, `Glob`. |
| 3 | Why was this not fixed in the previous PR? | The fix targeted delivery hygiene and fail-closed suppression, not the `BeforeToolCall` argument boundary. | Existing tests asserted synthetic `exec true` for malformed/blocked calls, not canonical native tool calls. |
| 4 | Why did the hook allow this class to persist? | It had validators for missing arguments but no path for “required args present, envelope dirty”. | `tool_call_has_missing_required_arguments` could only suppress absent fields. |
| 5 | Why could the issue recur? | There was no regression test proving that live-like envelopes are normalized to the original tool identity. | New component tests now cover `read_skill`, `memory_search`, `exec`, `cron`, `Glob`, `web_fetch`, and `browser`. |

## Корневая причина

The owning layer was the repo-managed Moltis hook contract. It did not normalize valid enriched `BeforeToolCall.arguments` payloads before runner validation. Treating the resulting errors as Telegram delivery leakage was insufficient because it hid symptoms while preserving the invalid runtime boundary.

## Принятые меры

1. Added a `BeforeToolCall` canonicalization path for known tools when required fields are present but the envelope contains `_channel`, `_session_key`, or null fields.
2. Preserved original tool identity instead of replacing valid calls with synthetic `exec true`.
3. Added `read_skill` to the native skill allowlist and missing-argument taxonomy.
4. Expanded missing-argument taxonomy for `process`, `Glob`, `web_fetch`, `browser`, and Tavily search.
5. Added component regression tests for live-like valid envelopes and kept existing fail-closed tests for truly malformed calls.

## Уроки

1. If required fields are present in persisted tool-call JSON, do not classify the incident as model omission or message hygiene; inspect and fix the argument boundary.
2. Telegram/Web tool error cleanup is not a root fix unless a test proves the original valid tool call can execute as that same tool.
3. Hook tests must cover “dirty but valid runtime envelope” separately from “malformed missing required argument”.

## Regression Test

**Test File:** `tests/component/test_telegram_safe_llm_guard.sh`

**Test Status:**

- [x] Test created
- [x] Test reproduces the class as a live-like envelope
- [x] Fix applied
- [x] Test passes
