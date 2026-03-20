---
title: "Moltis stayed on 0.9.10 because pinned GHCR tag format was wrong and production deploy gate allowed bypass semantics"
date: 2026-03-20
severity: P1
category: cicd
tags: [moltis, ghcr, github-actions, gitops, deploy-gate, rollback]
root_cause: "Deploy contract pinned a non-pullable GHCR tag (`v0.10.18`) and workflow allowed production-host path ambiguity via dispatch input semantics, so upgrade intent was not durable"
---

# RCA: Moltis stayed on 0.9.10 because pinned GHCR tag format was wrong and production deploy gate allowed bypass semantics

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Production оставался на `0.9.10`; обновление до целевой версии не закреплялось и легко деградировало в повторяемый не-upgrade path.  
**Контекст:** Завершение стабилизации Moltis update contract и production deploy path после incident chain из `2026-03-13`.

## Ошибка

Обновление Moltis до `0.10.18` не закреплялось как GitOps-гарантированный итог:

1. tracked pin использовал `v0.10.18`, но GHCR pullable tag для релиза был `0.10.18` (без `v`);
2. deploy workflow допускал семантику input `environment=staging` при фактическом деплое на production host;
3. существовал риск повторного "ложного" rollout path из соседних веток/worktree через неоднозначный dispatch-контракт.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production не закреплялся на новой версии Moltis? | Потому что deploy пытался работать с неверным image tag-контрактом и неоднозначным environment gating | `docker manifest inspect ghcr.io/moltis-org/moltis:v0.10.18` не pullable; workflow до фикса имел `staging` option при deploy на тот же host |
| 2 | Почему tag-контракт оказался неверным? | Release tag (`v0.10.18`) был напрямую принят за GHCR tag | Официальный артефакт: `docs/research/moltis-official-version-update-channel-2026-03-20.md`; проверка registry показала pullable `0.10.18` |
| 3 | Почему deploy-gate пропускал неоднозначный path? | Контроль "только main/tag" зависел от runtime `TARGET_ENV`, а не от однозначной production-only dispatch модели | `.github/workflows/deploy.yml` до фикса имел input `environment` с `staging`; preflight/repair guard основывались на `TARGET_ENV` |
| 4 | Почему это давало риск повторного отката/незакрепления? | Любой повторный dispatch с нестрогим env contract мог уходить в неправильный operational path и мешать deterministic rollout | История incident chain + повторяющийся drift/repair контур из RCA `2026-03-13` |
| 5 | Почему дефект не ловился заранее как policy violation? | Отсутствовали жёсткие static-проверки на формат GHCR tag, запрет `latest`, запрет dispatch override-версии и production-only dispatch | `tests/static/test_config_validation.sh` до доработки не покрывал весь набор guardrail-проверок |

## Корневая причина

Корневая причина двойная:

1. **Неверный артефакт-контракт версии**: release tag и GHCR tag были смешаны.
2. **Недостаточно жёсткий deploy contract**: workflow оставлял неоднозначность target semantics для production deploy.

## Принятые меры

1. **Немедленное исправление (version contract):**
   - `docker-compose.yml` и `docker-compose.prod.yml` закреплены на `ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-0.10.18}`.
   - `scripts/moltis-version.sh` теперь:
     - запрещает `latest`,
     - запрещает префикс `v`,
     - принимает только semver-like GHCR tag (`0.10.18` и semver suffix-паттерны).
2. **Немедленное исправление (deploy gate contract):**
   - `workflow_dispatch.environment` ограничен только `production`;
   - удалён ad-hoc `version` override из deploy workflow;
   - добавлен hard block при `TARGET_ENV != production`;
   - production deploy разрешён только с `main`; tag-triggered deploy допускается только если tag SHA совпадает с текущим `origin/main` HEAD;
   - запрещён `MOLTIS_VERSION` override в серверном `.env`.
3. **Немедленное исправление (test guardrails):**
   - расширены static тесты для проверки:
     - GHCR tag без `v`,
     - отсутствия `latest` default,
     - production-only dispatch,
     - отсутствия ручного `version` input.
4. **Документация и официальный артефакт:**
   - добавлен исследовательский документ по официальному update channel:
     - `docs/research/moltis-official-version-update-channel-2026-03-20.md`;
   - обновлён индекс `docs/research/README.md`;
   - обновлены runbook/version docs для нового контракта.

## Подтверждение устранения

- PR с фиксом: `#72` (merged в `main`, merge commit `5b4a186638d8e8e9ab156c08e28e83cb6a530a95`)
- Production deploy run (успешно): `23321428031`
- Runtime факт на сервере:
  - `docker inspect moltis` => `ghcr.io/moltis-org/moltis:0.10.18`
  - container health => `healthy`
  - `https://moltis.ainetic.tech/health` => `200`
  - `http://localhost:13131/health` => `200`
  - `/opt/moltinger` checkout => `main@5b4a186...`, без `.env` override `MOLTIS_VERSION`.

## Уроки

1. **Для Moltis нельзя использовать `latest` как tracked default**: обновления должны идти через явный pinned GHCR tag в git.
2. **Release tag (`vX.Y.Z`) и GHCR runtime tag (`X.Y.Z`) нужно верифицировать как разные артефакты** перед pin/update.
3. **Production deploy contract должен быть однозначным и неизбыточным**: без staging-ветвлений и без version override в dispatch.
4. **Rollback должен оставаться только recovery-path** (по health-failure/manual rollback), а не побочным эффектом нестрогого deploy flow.
5. **Static CI guards должны проверять policy-контракт, а не только синтаксис**, иначе drift semantics замечается слишком поздно.
