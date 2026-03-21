# Consilium Report

## Question

Как безопасно и надёжно остановить деградацию Moltis по двум главным оставшимся направлениям: Tavily search и `memory_search`/embeddings, не ломая рабочий OpenAI OAuth path и не внося новую конфигурационную хрупкость?

## Execution Mode

Mode A

## Evidence

- Tracked config отключает built-in web search и опирается на Tavily MCP по SSE: [config/moltis.toml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/config/moltis.toml#L423), [config/moltis.toml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/config/moltis.toml#L548)
- Tracked memory остаётся на auto-detect без `provider`, `model` и `watch_dirs`: [config/moltis.toml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/config/moltis.toml#L654)
- Preflight уже считает `tavily_api_key` обязательным, но env render раньше не fail-closed на пустой `TAVILY_API_KEY`: [scripts/preflight-check.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/preflight-check.sh#L140), [scripts/render-moltis-env.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/render-moltis-env.sh#L68)
- Live runtime logs показывают Tavily SSE handshake/auto-restart failures при наличии успешных `mcp__tavily__tavily_search` вызовов; это указывает на нестабильный transport path, а не на полный outage.
- Live runtime logs показывают `memory_search` fallback chain: `https://api.z.ai/api/coding/paas/v4/embeddings -> 400` и `https://api.groq.com/openai/v1/embeddings -> 401`.
- Официальные docs Moltis разделяют memory embeddings provider contract и chat providers, а docs providers показывают first-class `zai` provider отдельно от generic `openai`: https://docs.moltis.org/memory.html, https://docs.moltis.org/providers.html
- Официальные docs Tavily MCP допускают remote MCP по query-key URL; текущий syntax сам по себе не доказывает misconfig: https://docs.tavily.com/documentation/mcp

## Expert Opinions

### Architect

- Opinion: Tavily и `memory_search` сейчас не один баг, а два разных systemic failure modes поверх хрупкого runtime contract.
- Key points: Tavily нужно лечить как transport/dependency reliability problem. Memory нужно лечить как deterministic-contract problem, потому что auto-detect уводит embeddings на неподходящий chat endpoint.

### SRE

- Opinion: Основная ошибка процесса в том, что текущие deploy/UAT сигналы недостаточно семантичны.
- Key points: `/health`, auth и базовый chat ещё не доказывают readiness search и memory surfaces; нужны отдельные probes и fail taxonomy.

### DevOps

- Opinion: Самый безопасный repo-side шаг сейчас это fail-closed secrets/render + read-only diagnostics, а не немедленная смена production memory provider.
- Key points: `TAVILY_API_KEY` должен стать обязательным уже на render stage. Для memory provider сначала нужен диагностический контракт, потом live pinning.

### Security

- Opinion: Нельзя продолжать дебажить это через произвольные правки runtime secrets/state.
- Key points: Любая ручная чистка provider state без дифференциации tracked config vs runtime drift повышает шанс снести OAuth или вернуть старую нестабильность.

### QA

- Opinion: Нужно отделить transport-green от capability-green.
- Key points: Необходимо добавить machine-readable diagnostics для Tavily/memory и acceptance criteria, которые явно считают `400/401` embeddings chain failure и SSE churn деградацией.

### Domain Specialist (Moltis)

- Opinion: `memory_search` нельзя оставлять на auto-detect в текущем проекте.
- Key points: Repo уже использует Z.ai Coding endpoint как chat fallback через `[providers.openai]`; для embeddings это плохой implicit match. До выбора поддержанного embedding backend безопаснее иметь deterministic memory contract либо keyword-only fallback.

### GitOps / Delivery

- Opinion: Все follow-up fixes должны оставаться в tracked artifacts и guardrails, а не в устных договорённостях.
- Key points: Backlog обязан ранжировать Tavily и memory выше браузера и хвостовой уборки, а runbooks должны давать один канонический read-only diagnostic path.

## Root Cause Analysis

- Primary root cause: Неполный repository-managed runtime contract. Tavily и memory surfaces не имеют детерминированного и проверяемого контракта уровня deploy/UAT.
- Contributing factors:
  - search зависит от удалённого Tavily SSE transport без отдельного capability-proof
  - memory embeddings оставлены на auto-detect и подхватывают chat-oriented provider chain
  - `TAVILY_API_KEY` до этого не fail-closed в env render path
  - runtime drift может возвращать лишние providers вроде Groq в embedding chain
- Confidence: High

## Solution Options

1. Ничего не менять в repo и чинить только live runtime руками — Pros: быстро локально. Cons: повторяемость нулевая, высокий риск снова снести OAuth или drift guard. Risk: High. Effort: Low.
2. Сразу пинить memory на новый embedding provider в tracked config — Pros: потенциально быстро уберёт `memory_search` errors. Cons: high-risk config/provider change без отдельной live validation. Risk: High. Effort: Medium.
3. Временно перевести memory в keyword-only mode и отложить embeddings — Pros: быстро убирает noisy provider-chain failures. Cons: режет vector semantics до следующего этапа. Risk: Medium. Effort: Low.
4. Оставить behavior как есть, но добавить fail-closed env rendering и read-only diagnostics — Pros: безопасно, не ломает working OAuth/chat path, улучшает observability. Cons: не чинит сам runtime behavior целиком. Risk: Low. Effort: Low.
5. Добавить fail-closed env rendering, read-only diagnostics, а затем отдельно принять deterministic memory contract после live probe supported backend — Pros: минимальный риск, хороший audit trail, лучший порядок для следующего этапа. Cons: требует ещё один follow-up шаг для окончательного memory fix. Risk: Low. Effort: Medium.
6. Заменить Tavily remote SSE на другой search path немедленно — Pros: может устранить transport fragility. Cons: нет доказанного safer replacement в этой ветке, высокий риск нового drift. Risk: Medium. Effort: Medium.

## Recommended Plan

1. Немедленно поднять Tavily и `memory_search` в backlog как P0 unresolved blockers.
2. Сделать `TAVILY_API_KEY` обязательным уже на `render-moltis-env.sh`, чтобы пустой search secret не проходил в runtime.
3. Добавить канонический read-only diagnostic entrypoint для tracked Tavily/memory contract и runtime log taxonomy.
4. Расширить runbook и UAT/backlog так, чтобы Tavily SSE churn и `400/401` embeddings chain считались явной деградацией.
5. Отдельным следующим slice выбрать deterministic memory contract: либо supported embedding backend, либо временный keyword-only fallback до live validation.

## Rollback Plan

- Для repo-side fixes: revert commit с `render-moltis-env.sh`, новым diagnostic script и docs/tasks changes.
- Не выполнять rollback через удаление runtime auth/state файлов.
- Если новый render guard неожиданно блокирует deploy, сначала восстановить недостающий `TAVILY_API_KEY`, а не ослаблять guard.

## Verification Checklist

- [ ] `scripts/render-moltis-env.sh` падает на пустом `TAVILY_API_KEY`
- [ ] diagnostic script выдаёт JSON по tracked config без логов
- [ ] diagnostic script корректно считает Tavily SSE и embeddings failure taxonomy на sample/runtime logs
- [ ] Speckit backlog ранжирует Tavily и `memory_search` выше browser/runtime cleanup
- [ ] Runbook содержит канонический read-only triage path для search/memory
