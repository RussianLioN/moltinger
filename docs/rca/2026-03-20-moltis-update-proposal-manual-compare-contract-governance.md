---
title: "Moltis update proposal had contract drift: manual compare fallback existed in code but was not formalized as governance contract"
date: 2026-03-20
severity: P2
category: process
tags: [cicd, moltis-update, github-actions, governance, permissions, docs]
root_cause: "Workflow already handled missing createPullRequest permission via compare URL, but docs/summary framed it as implicit fallback instead of explicit supported contract"
---

# RCA: Moltis update proposal had contract drift (manual compare URL path not formalized)

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** issue `#87` оставался открытым из-за неоднозначного governance-контракта: не было ясно, нужно ли повышать GitHub permissions или закреплять manual compare URL path.

## Ошибка

Технический fallback уже работал:

- при `createPullRequest` denial workflow не падал;
- формировался compare URL и оператор мог создать PR вручную.

Но contract-слой был неполным:

- `docs/version-update.md` не фиксировал manual compare URL как постоянный supported path;
- summary/email формулировки могли восприниматься как “degraded exception”, а не как штатный режим.

## Анализ 5 Почему

| Уровень | Почему | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему #87 оставался нерешённым? | Не был формально зафиксирован выбор между расширением permission и manual compare governance mode | issue `#87` body |
| 2 | Почему появилась дилемма? | Код и документация разошлись по уровню явности контракта | `.github/workflows/moltis-update-proposal.yml` vs `docs/version-update.md` (до фикса) |
| 3 | Почему документация не покрывала manual mode явно? | Фокус был на устранении hard-fail и восстановлении работоспособности pipeline | RCA `2026-03-20-moltis-update-proposal-perl-backreference-and-pr-permission-fallback.md` |
| 4 | Почему этого недостаточно для governance? | Без явного policy operators трактуют compare URL как временный workaround | consilium review по #87 |
| 5 | Почему важно закрыть именно policy-уровень? | Permissions в repo settings вне git-контракта; без doc contract можно повторно вернуться к хрупкому поведению | GitOps/least-privilege требования проекта |

## Корневая причина

Реальная проблема была не в отсутствии fallback-логики, а в contract drift: manual compare URL path был реализован технически, но не зафиксирован как официальный постоянный режим в документации и operator-facing summary.

## Принятые меры

1. Обновлён workflow `moltis-update-proposal`:
   - fallback mode именован как `manual_compare_url`;
   - summary показывает contract-level `Approval mode (contract)`;
   - email формулирует compare URL как supported path (не failure state).
2. Обновлён `docs/version-update.md`:
   - добавлен явный контракт `manual_compare_url` и правило, что это supported permanent contract.
3. Добавлен статический guard:
   - `tests/static/test_config_validation.sh` проверяет contract language в docs и workflow.

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass (92/92) | локальный прогон после изменений |
| Workflow YAML parse | pass | `YAML_OK .github/workflows/moltis-update-proposal.yml` |
| Existing fallback guard | pass | `static_moltis_update_proposal_falls_back_to_compare_url_when_pr_create_is_forbidden` |
| New docs contract guard | pass | `static_version_update_docs_fix_manual_compare_url_contract` |

## Уроки

1. Для CI/CD governance недостаточно “код работает”; operator contract должен быть явно зафиксирован в docs и summary.
2. Для репозиториев с ограниченным `GITHUB_TOKEN` нужно считать manual compare URL path штатным режимом, а не временной деградацией.
3. Least-privilege решение должно быть зафиксировано тестами, чтобы future edits не вернули зависимость от внешних repo settings.
