---
title: "Telegram Web probe collapsed multiline /status replies before exact semantic review"
date: 2026-04-23
severity: P1
category: process
tags: [telegram, uat, telegram-web, probe, status, safe-text, multiline, rca]
root_cause: "The authoritative Telegram Web probe normalized all whitespace in captured bubble text, so multiline user-visible replies were flattened into one line before remote UAT compared them against the exact five-line /status contract."
---

# RCA: Telegram Web probe collapsed multiline /status replies before exact semantic review

**Дата:** 2026-04-23
**Статус:** Resolved
**Влияние:** post-deploy authoritative Telegram `/status` UAT ложно падал с `semantic_status_mismatch`, хотя live reply был атрибутируемым и содержательно корректным
**Контекст:** follow-up после merge/deploy Telegram ingress terminalization fix; live smoke для `/status` стал единственным remaining blocker перед cleanup

## Ошибка

После успешных merge и deploy authoritative Telegram Web UAT для `/status` вернул:

- observed reply: `Статус: Online Канал: Telegram (@moltinger_bot) Модель: openai-codex::gpt-5.4 Провайдер: openai-codex Режим: safe-text`
- expected reply: exact five-line safe-text contract with embedded `\n`

Симптом выглядел как runtime formatting drift, но локальный анализ показал, что exact mismatch возникал уже внутри repo-owned authoritative probe pipeline.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `docs/rules/moltis-user-facing-telegram-browser-heavy-paths-must-degrade-gracefully.md`
- `docs/rca/2026-03-28-moltis-operator-browser-session-isolation-and-telegram-send-attribution-drift.md`
- `docs/rca/2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run.md`

**Релевантные прошлые RCA/уроки:**
1. `2026-03-28-moltis-operator-browser-session-isolation-and-telegram-send-attribution-drift` — authoritative Telegram Web layer already owned attribution and reply-shape correctness, so new drift had to be diagnosed there first.
2. `2026-04-14-telegram-codex-update-direct-fastpath-raced-underlying-run` — user-facing Telegram verdicts must be validated against the actual terminal reply contract, not just against a superficially clean intermediate artifact.

**Что могло быть упущено без этой сверки:**
- можно было бы ошибочно чинить live runtime send path, хотя повреждение происходило в UAT probe;
- можно было бы снова “лечить” deploy/session state вместо repo-owned verification layer.

**Что в текущем инциденте действительно новое:**
- this failure was not about attribution timing or second replies; it was a data-shape bug where the probe destroyed multiline formatting before exact semantic comparison.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему live `/status` UAT упал с `semantic_status_mismatch`? | Потому что observed reply оказался одной строкой с пробелами вместо exact five-line reply. | Artifact `telegram-e2e-result.json` from authoritative run `24856960937` |
| 2 | Почему observed reply стал одной строкой? | Потому что probe normalised captured bubble text through whitespace collapse before exposing `reply_text`. | `scripts/telegram-web-user-probe.mjs`, `normalizeMessageText()` and `collectMessages()` |
| 3 | Почему exact semantic review не отличил raw user-visible text от normalized correlation text? | Потому что `reply_text` reused the same normalized field that correlation helpers use for matching/interim detection. | `scripts/telegram-web-user-probe.mjs: normalizeProbeMessage(), successPayload()` |
| 4 | Почему это не было поймано раньше тестами? | Потому что probe tests covered correlation and stability behavior, but did not assert preservation of raw multiline reply text for exact downstream contracts. | `tests/component/test_telegram_web_probe_correlation.sh` before fix |
| 5 | Почему это важно системно? | Потому что authoritative UAT is the repo-owned decision boundary before merge/cleanup; if it mutates user-visible text, operator decisions become false-negative. | `scripts/telegram-e2e-on-demand.sh` exact `/status` compare + cleanup gate usage in workflow |

## Корневая причина

Repo-owned authoritative Telegram Web probe смешал два разных представления текста в одно поле:

- normalized correlation text for matching, filtering, and heuristics;
- raw user-visible reply text for exact semantic contracts.

Из-за этого probe сам разрушал newline-sensitive `/status` contract before remote UAT wrapper compared it to the canonical five-line safe-text reply.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Fix lives in repo-owned probe/wrapper tests |
| □ Systemic? | yes | Any exact multiline Telegram contract could false-fail the same way |
| □ Preventable? | yes | Preserve raw text separately and add regression tests |

## Принятые меры

1. **Немедленное исправление:** `scripts/telegram-web-user-probe.mjs` now preserves multiline `raw_text` for message bubbles and emits raw `reply_text`, while normalized text remains internal to correlation/heuristics.
2. **Предотвращение:** added regression coverage proving raw multiline `/status` survives probe normalization boundaries.
3. **Документация:** this RCA was added and `docs/LESSONS-LEARNED.md` was regenerated.

## Связанные обновления

- [ ] Новый файл правила создан (docs/rules/ или .claude/skills/)
- [ ] Краткая ссылка добавлена в CLAUDE.md (1-2 строки)
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [ ] Чеклисты обновлены

## Уроки

1. Authoritative probes must preserve raw user-visible payloads separately from normalized matcher text.
2. If a downstream contract is exact and multiline-sensitive, the probe layer must never collapse whitespace before emitting the comparable field.
3. Telegram UAT regressions should be tested not only for attribution and leak filtering, but also for fidelity of the user-visible reply shape.

## Regression Test (Optional - for code errors only)

**Test File:** `tests/component/test_telegram_web_probe_correlation.sh`

**Test Status:**
- [x] Test created
- [x] Fix applied
- [x] Test passes

---

*Создано по протоколу RCA-5-Whys.*
