---
title: "GitHub Actions bad logs from post-deploy image prune and calendar tag rejection"
date: 2026-04-20
severity: P1
category: cicd
tags: [github-actions, deploy, update-proposal, moltis, ghcr, docker]
root_cause: "Deploy and update-proposal workflows still relied on stale contracts: post-deploy reclaim pruned a tracked browser image, version normalization stayed semver-only, and active deploy surfaces still referenced removed GLM secrets."
---

# RCA: GitHub Actions bad logs from post-deploy image prune and calendar tag rejection

**Дата:** 2026-04-20  
**Статус:** Resolved in code, merge pending  
**Влияние:** `main` показывал ложный красный `Deploy Moltis`, scheduled `Moltis Update Proposal` падал на валидном upstream release tag, а deploy logs дополнительно шумели предупреждением про уже удалённый `GLM_API_KEY`.  
**Контекст:** beads `moltinger-4hqr.2`, runs `24665090156` (`Deploy Moltis`) и `24658547770` (`Moltis Update Proposal`).

## Ошибка

Наблюдались три связанных симптома:

1. `Deploy Moltis` run `24665090156` завершался `failure`, хотя deploy доходил до healthy runtime.
2. `Moltis Update Proposal` run `24658547770` падал со строкой `Latest release tag '20260417.02' does not normalize to a valid GHCR runtime tag`.
3. В deploy logs оставалось предупреждение `The "GLM_API_KEY" variable is not set. Defaulting to a blank string.`

Ключевой факт по deploy run:

- итоговый JSON payload показывал `"health": "healthy"`, но runtime attestation падала с `BROWSER_SANDBOX_IMAGE_UNAVAILABLE` для `moltis-browserless-chrome:tracked`.

Ключевой факт по update-proposal run:

- официальный latest release уже шёл в календарном формате (`20260417.02`, позже `20260420.02`), а workflow и общий helper-контракт всё ещё трактовали только semver-style runtime tags.

## Проверка прошлых уроков

**Проверенные источники:**

- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag deploy`
- `./scripts/query-lessons.sh --tag moltis`
- `docs/rca/2026-03-20-moltis-ghcr-tag-normalization-and-production-deploy-gate-hardening.md`

**Релевантные прошлые RCA/уроки:**

1. `docs/rca/2026-04-02-tracked-deploy-empty-stdout-broke-json-contract.md` — красный deploy при healthy runtime нельзя считать “просто шумом GitHub”, нужно искать сломанный boundary contract.
2. `docs/rca/2026-03-28-moltis-deploy-auto-rollback-recreate-and-health-monitor-interference.md` — background cleanup в production не должен мутировать deploy-managed surface без awareness к rollout contract.
3. `docs/rca/2026-03-20-moltis-ghcr-tag-normalization-and-production-deploy-gate-hardening.md` — release tag normalization должен быть централизованным contract-слоем, а не adhoc логикой по workflow.

**Что могло быть упущено без этой сверки:**

- можно было чинить только один workflow и оставить тот же дефект в общем version helper;
- можно было посчитать `BROWSER_SANDBOX_IMAGE_UNAVAILABLE` новой production anomaly вместо self-inflicted cleanup drift;
- можно было убрать предупреждение про `GLM_API_KEY` только из `.env` rendering, но оставить его в active compose/preflight surface.

**Что в текущем инциденте действительно новое:**

- post-deploy reclaim path удалял именно tracked browser sandbox image, который затем требовался для финальной runtime attestation;
- upstream release contract сдвинулся к календарным тегам, и repo source of truth не был полностью под это обновлён.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему на GitHub появились плохие логи и красные workflow? | Потому что `Deploy Moltis` и `Moltis Update Proposal` исполняли уже устаревшие контракты относительно tracked runtime surface и release tag format. | `gh run view 24665090156 --log-failed`, `gh run view 24658547770 --log-failed` |
| 2 | Почему `Deploy Moltis` стал красным при healthy runtime? | Потому что после успешного rollout post-deploy reclaim запускал docker image prune и удалял tracked browser sandbox image до финальной attestation. | deploy log с `BROWSER_SANDBOX_IMAGE_UNAVAILABLE`, код `scripts/deploy.sh` + `scripts/moltis-storage-maintenance.sh` |
| 3 | Почему `Moltis Update Proposal` падал на валидном release tag? | Потому что workflow и `scripts/moltis-version.sh` принимали только semver-like tracked tags и отвергали календарные release tags, хотя upstream уже публиковал их как официальный latest release. | log line `Latest release tag '20260417.02' ...`, latest release `20260420.02`, старый код workflow/helper |
| 4 | Почему warning про `GLM_API_KEY` продолжал шуметь в deploy logs после отказа от Z.ai? | Потому что `.env` rendering уже не использовал этот secret, но active compose/preflight surface всё ещё ссылался на `GLM_API_KEY` / `glm_api_key`. | `docker-compose.yml`, `docker-compose.prod.yml`, `scripts/preflight-check.sh` до фикса |
| 5 | Почему эти три дефекта прошли вместе? | Потому что migration work шёл послойно и частично: source config, workflow logic, shared helpers и active deploy surface обновлялись не как единый CI/runtime contract. | разрыв между workflow YAML, shared scripts и live deploy logs |

## Корневая причина

Root cause был не в одном конкретном workflow, а в неполной миграции shared contract:

- deploy control plane не защищал tracked browser sandbox image от post-deploy cleanup;
- release normalization contract оставался semver-only вместо общей explicit GHCR tag grammar;
- active deploy surface хранил следы удалённого GLM/Z.ai секрета, хотя runtime source of truth уже был обновлён.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| Actionable? | yes | Исправляется в shared scripts, workflows и active deploy config surface |
| Systemic? | yes | Проблема затрагивает общий CI/runtime contract, а не разовый ручной шаг |
| Preventable? | yes | Покрывается централизованной normalization logic, static guards и targeted tests |

## Принятые меры

1. **Немедленное исправление:**  
   `scripts/deploy.sh` теперь вызывает reclaim c `--skip-docker-image-prune`, чтобы post-deploy cleanup не удалял tracked browser sandbox image.
2. **Предотвращение:**  
   Добавлен shared helper `scripts/moltis-update-proposal-resolver.sh`, а `scripts/moltis-version.sh` получил общий `normalize-tag` и explicit GHCR tag validation для semver и календарных тегов.
3. **Конфигурационная санация:**  
   Из active deploy surface удалены `GLM_API_KEY` / `glm_api_key` ссылки в `docker-compose.yml`, `docker-compose.prod.yml` и `scripts/preflight-check.sh`.
4. **Тестовое покрытие:**  
   Добавлены/обновлены component/static/unit tests на:
   - calendar-tag normalization;
   - update-proposal resolver;
   - deploy browser-sandbox preservation contract;
   - отсутствие active GLM secret contract.
5. **Документация:**  
   Создан этот RCA и запланирован rebuild lessons index.

## Связанные обновления

- [ ] Новый файл правила создан
- [ ] Краткая ссылка добавлена в CLAUDE.md
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [x] Новый RCA создан

## Уроки

1. Post-deploy cleanup нельзя запускать вслепую против deploy-managed Docker surface; cleanup обязан знать, какие tracked artifacts ещё нужны для attestation.
2. Workflow-level tag parsing нельзя держать как локальную ad hoc логику; нормализация release/runtime tags должна идти через один shared helper.
3. Provider-removal или secret-removal считается завершённым только тогда, когда очищены все active deploy surfaces, а не только source `.env` generation.
