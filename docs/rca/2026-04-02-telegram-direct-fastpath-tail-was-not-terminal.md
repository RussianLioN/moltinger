---
title: "Telegram direct fastpath tail was not terminal and live outbound hooks were incomplete"
date: 2026-04-02
tags: [telegram, moltis, hooks, delivery, tavily, mcp, rca]
root_cause: "The repo guard assumed the live Telegram runtime would always emit a final MessageSending hook and that one suppress marker consumption was enough. In reality, the user-visible turn could continue through late AfterLLMCall/tool/outbound paths, while MessageSending was absent in the captured live path, so duplicate and dirty tails escaped after the already-sent direct fastpath answer."
---

# RCA: Telegram direct fastpath tail was not terminal and live outbound hooks were incomplete

## Ошибка

Пользователь видел в Telegram сначала нормальный ответ про релизы Codex, а затем повторный или грязный хвост:

- повтор того же ответа;
- `Activity log`;
- `mcp__tavily__tavily_search`;
- ошибки вида `missing 'url' parameter` / validation errors.

## Проверка прошлых уроков

**Проверенные источники:**
- `./scripts/query-lessons.sh --tag telegram`
- `./scripts/query-lessons.sh --tag hooks`
- `./scripts/query-lessons.sh --tag moltis`
- [docs/rca/2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass.md)

**Релевантные прошлые RCA/уроки:**
1. `2026-04-01-telegram-skill-visibility-and-create-hook-modify-bypass` уже фиксировал, что live Moltis `0.10.18` не всегда применяет hook `modify` к реальному Telegram outbound path.
2. `2026-03-20-telegram-uat-false-pass-on-model-not-found` уже требовал добавлять regression-тесты на каждый новый класс runtime ошибок.
3. `2026-03-28-moltis-browser-timeout-budget-equalled-navigation-timeout` напоминал, что после первого hotfix изменившийся live симптом надо считать новой корневой причиной, а не «тем же багом».

**Что могло быть упущено без этой сверки:**
- что `MessageSending` как synthetic contract и live outbound path уже расходились раньше;
- что unit/component green не доказывают применение hook rewrite в живом Telegram runtime;
- что новый dirty tail нужно ловить отдельным regression-контрактом, а не надеяться на старый single-event suppress.

**Что в текущем инциденте действительно новое:**
- container audit показал отсутствие `MessageSending` hook-события в проблемной live цепочке;
- suppression marker был спроектирован как одноразовый, хотя live tail мог быть многошаговым;
- dirty Tavily/MCP хвост шёл уже после user-visible direct fastpath ответа.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему пользователь видел второй грязный ответ после уже нормального ответа? | Потому что один Telegram turn не завершался после direct fastpath и поздний runtime хвост продолжал жить дальше. |
| 2 | Почему хвост не был подавлен guard-логикой? | Потому что suppression marker считался одноразовым и очищался на первом suppress-событии. |
| 3 | Почему этого оказалось недостаточно? | Потому что live Telegram chain могла породить несколько поздних событий подряд: поздний `AfterLLMCall`, дополнительные `BeforeToolCall`, а затем dirty outbound. |
| 4 | Почему guard вообще не увидел финальную outbound-фазу в проблемной live сессии? | Потому что container audit/capture для этой цепочки показал `BeforeLLMCall`, `AfterLLMCall`, `BeforeToolCall`, но не показал `MessageSending`, хотя outbound в Telegram реально произошёл. |
| 5 | Почему мы сделали неправильное предположение о контракте? | Потому что repo mitigation опирался на synthetic hook contract, а не на доказанный live delivery contract текущего Moltis/OpenClaw runtime. |

## Корневая причина

Repo guard опирался на неверное допущение: будто direct fastpath нужно лишь один раз подавить на `MessageSending`, после чего turn уже завершён. В реальном runtime Telegram turn мог продолжаться дальше без наблюдаемого `MessageSending` hook, а suppression marker очищался слишком рано. Из-за этого поздние `AfterLLMCall`/tool/outbound хвосты всё ещё могли просочиться в Telegram после уже отправленного пользователю ответа.

## Внешние подтверждения

**Официальная документация:**
- official hooks docs обещают outbound event `message:sent`, то есть система концептуально должна давать post-send hook point: <https://docs.openclaw.ai/zh-CN/automation/hooks>

**Upstream issues:**
1. `#21789` — `message_sent hook is never called in outbound delivery path`: <https://github.com/openclaw/openclaw/issues/21789>
2. `#52390` — `message:sent internal hook not firing for Telegram group deliveries (missing sessionKey)`: <https://github.com/openclaw/openclaw/issues/52390>
3. `#59150` — commentary leakage and duplicate visible replies after tool sends: <https://github.com/openclaw/openclaw/issues/59150>
4. `#51628` — Telegram delivery queue can replay old replies and duplicate `delivery-mirror`: <https://github.com/openclaw/openclaw/issues/51628>

**Community signal:**
- точного forum recipe с готовым fix не найдено; community signal скорее подтверждает общий delivery/reliability class problem, чем даёт готовый обход.

## Принятые меры

1. **Немедленное исправление:** `scripts/telegram-safe-llm-guard.sh` теперь:
   - не очищает `persisted_delivery_suppression` на первом `MessageSending`;
   - держит same-turn suppression живым до нового user turn;
   - подавляет поздний `AfterLLMCall` после direct fastpath, обнуляя текст и tool calls для остатка turn.
2. **Предотвращение:** добавлены regression-тесты на:
   - repeated same-turn `MessageSending` tails после direct fastpath;
   - repeated dirty tails после `clean_delivery`;
   - late `AfterLLMCall` после уже отправленного direct fastpath ответа.
3. **Документация:** этот live/runtime gap зафиксирован как отдельный RCA, а не смешан с предыдущим incident про skills visibility/create.

## Связанные обновления

- [x] Тесты добавлены
- [x] RCA добавлен
- [ ] Отдельный upstream hardening/upgrade follow-up при необходимости

## Уроки

1. **Synthetic hook contract не равен live Telegram contract** — для user-facing delivery нужно снимать container audit/capture, а не только верить component tests.
2. **Same-turn suppression должна жить до нового user turn, а не до первого suppress-события** — delivery tails у Telegram runtime многошаговые.
3. **Direct fastpath должен быть terminal для всего остатка turn** — если ответ уже отправлен напрямую, поздние `AfterLLMCall` и dirty outbound хвосты нельзя оставлять на best-effort эвристиках.
