---
title: "Telegram skill visibility/create needed direct fast-path because live Moltis ignored hook modify payloads"
date: 2026-04-01
tags: [moltis, telegram, hooks, skills, create-skill, visibility, rca]
root_cause: "Repo-side mitigation relied on shell-hook `modify` for BeforeLLMCall/AfterLLMCall, but live Moltis 0.10.18 Telegram path still sent the raw model reply, so skill visibility and sparse create had to bypass the LLM path with direct Bot API send + runtime scaffold write."
---

# RCA: Telegram skill visibility/create needed direct fast-path because live Moltis ignored hook modify payloads

## Ошибка

В Telegram пользователь видел неправильные ответы на `skills?` и `создай навык <name>`:

- вместо детерминированного списка навыков приходили `Да.` или follow-up мусор;
- вместо создания навыка модель уходила в churn, спрашивала про template и зависала до `90s timeout`.

## Сначала проверили предыдущие уроки

- [docs/reports/2026-03-28-moltis-upstream-telegram-codex-update-and-activity-log-issue-artifact.md](/Users/rl/coding/moltinger/moltinger-main-telegram-skill-land-20260401d/docs/reports/2026-03-28-moltis-upstream-telegram-codex-update-and-activity-log-issue-artifact.md)
- [docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md](/Users/rl/coding/moltinger/moltinger-main-telegram-skill-land-20260401d/docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md)

Они уже указывали, что Telegram delivery path может расходиться с чистым `chat.history`, но текущий инцидент требовал отдельной фиксации для skill visibility/create.

## 5 Почему

1. Почему пользователь видел `Да.` и churn вместо правильного skill-ответа?
   - Потому что live Telegram получил сырой ответ модели, а не переписанный hook-ответ.
2. Почему hook-ответ не попал в Telegram?
   - Потому что shell hook реально возвращал `{"action":"modify","data":...}`, но Moltis `0.10.18` live Telegram path его не применял к фактическому outbound reply.
3. Почему мы сначала считали, что mitigation уже работает?
   - Потому что component tests проверяли только hook script на synthetic payloads и подтверждали корректный `modify`, но не доказывали применение этого `modify` в живом Telegram runtime.
4. Почему это особенно ломало `skills?` и sparse create?
   - Потому что эти сценарии требовали жёсткого deterministic поведения: перечислить runtime skills или сразу создать базовый scaffold без tool-churn.
5. Почему repo-side fix пришлось делать вне обычного LLM path?
   - Потому что до устранения upstream/runtime gap единственный надёжный repo-owned способ был обойти модельный ответ: отправить текст напрямую через Bot API и, для sparse create, записать scaffold прямо в runtime skills dir.

## Корневая причина

Synthetic hook tests давали ложное ощущение завершённости: hook-скрипт был корректен, но live Moltis Telegram path в `0.10.18` не применял `modify` так, как обещает hook contract. Из-за этого skill visibility/create нельзя было чинить только через rewrite prompt payload или AfterLLM response.

## Исправление

В `scripts/telegram-safe-llm-guard.sh` добавлен deterministic fast-path для Telegram-safe lane:

- `skills?` отправляется напрямую через `/server/scripts/telegram-bot-send.sh`;
- запрос про template/шаблон навыка получает канонический scaffold без LLM;
- `создай навык <name>` пишет минимальный `SKILL.md` прямо в runtime `skills/<name>/SKILL.md` и отправляет подтверждение напрямую в Telegram.

LLM path при этом блокируется, чтобы пользователь не получил второй сырой ответ модели.

## Что подтвердили после live deploy

После deploy `47eab85` и authoritative Telegram Web UAT выяснилось следующее:

- `/status` проходит по живому Telegram path и возвращает канонический safe-text ответ без `Activity log`.
- `А что у тебя с навыками/skills?` проходит по живому Telegram path и перечисляет live runtime skills, включая freshly created skill.
- `Давай создадим навык <slug>` проходит по живому Telegram path, а follow-up visibility сразу видит новый skill.
- запрос `У тебя должен быть темплейт` тоже возвращает хороший user-facing шаблон без внутренних логов, но старый UAT harness ошибочно помечал такой ответ как `semantic_skill_visibility_mismatch`.

Отдельно выявили ещё один важный операторский источник путаницы:

- внутри runtime/логов live skills видны по контейнерному пути `/home/moltis/.moltis/skills/...`;
- на host filesystem тот же созданный skill лежит в `/opt/moltinger/data/skills/...`.

Это не оказалось потерей skill как таковой. Это расхождение host/container path projection, которое давало ложное ощущение, что skill "создался только на словах".

## Дополнительная корневая причина

После первого repo-side fast-path фикса остался второй repo-side дефект:

- stale suppression marker мог пережить fast-path turn и заглушить следующий нормальный ответ;
- authoritative on-demand harness мог ложно заваливать template-reply, применяя семантику проверки live skill visibility к запросу про template.

То есть инцидент был не одним багом, а связкой:

1. runtime/upstream gap: live Moltis Telegram path не всегда уважал hook `modify` так, как это доказывали synthetic tests;
2. repo-side follow-up defects: suppression lifecycle и UAT semantic classifier были слишком хрупкими.

## Предотвращение

1. Не считать shell-hook `modify` доказанным до живого Telegram UAT.
2. Для user-facing Telegram критичные deterministic flows держать в repo-owned fast-path, если live runtime не уважает hook rewrite contract.
3. Для future regressions отдельно проверять:
   - direct visibility answer;
   - direct sparse create;
   - template reply;
   - отсутствие второго сырого ответа после direct send.
4. Не смешивать semantic contracts:
   - `skills?` должен проверяться against live `/api/skills`;
   - `template` должен проверяться как deterministic scaffold reply, а не как skill visibility response.
5. Документировать container-vs-host skill path projection, чтобы оператор не принимал её за потерю данных.
