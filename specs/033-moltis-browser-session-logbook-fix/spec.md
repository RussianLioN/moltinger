# Spec: Moltis Browser Session And Telegram Logbook Containment

## Summary

После выката `main` пользовательский Telegram path всё ещё может уходить в:

- `⚠️ Timed out: Agent run timed out after 30s`
- отдельное сообщение с `📋 Activity log`
- browser failures вида `browser connection dead` и `pool exhausted: no browser instances available`

По текущим доказанным фактам это уже не чисто repo-config bug. Корень сейчас split:

1. upstream/runtime browser session lifecycle defect;
2. upstream/channel delivery behavior, который может публиковать internal status logbook в Telegram;
3. недостаточно строгая repo-side диагностика и отсутствие временного degraded-mode для Telegram user path.

Этот slice не обещает починить upstream Moltis/OpenClaw runtime внутри репозитория. Он должен:

- зафиксировать инцидент как отдельную tracked проблему;
- добавить repo-side fail-closed containment и точную failure taxonomy;
- оформить official-first RCA/rule/runbook;
- подготовить качественный upstream issue contract вместо гадания.

## Goals

- Не давать repo-side smoke/canary скрывать stale browser session contamination за общим `timed out`.
- Уменьшить вероятность повторного tool-heavy browser/search path в Telegram user chat до upstream fix.
- Зафиксировать official docs baseline по browser automation, sandbox mode и Pair semantics.
- Обновить backlog/lessons так, чтобы новые инстансы агента не повторяли ту же ошибку closure.

## Non-Goals

- Не переписывать upstream Moltis transport/gateway/browser code внутри этого репозитория.
- Не считать prompt guardrail достаточным окончательным решением channel log leakage.
- Не менять production через feature-branch deploy.

## Acceptance Criteria

1. `scripts/test-moltis-api.sh` умеет отдельно классифицировать:
   - stale browser session contamination;
   - browser pool exhaustion;
   - generic browser timeout/failure.
2. `scripts/moltis-browser-canary.sh` fail-closed на live log signatures:
   - `browser connection dead`
   - `pool exhausted: no browser instances available`
   - readiness / launch failures
3. `config/moltis.toml` явно переводит Telegram/DM path в safe degraded-mode для browser/search/memory-heavy flows.
4. Добавлены targeted tests и static coverage.
5. Оформлены RCA, consilium memo, rule, runbook update и lessons refresh.
6. Подготовлен upstream issue artifact с evidence и четкими closure criteria.
