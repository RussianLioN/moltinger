---
title: "Child worktree reconciliation renames authoritative feature worktree"
date: 2026-03-08
severity: P2
category: shell
tags: [git-worktree, topology-registry, worktree-identity, ux, rca]
root_cause: "Numbered feature worktree identity depended on the caller branch, so doctor from a child branch could rename and orphan the authoritative parent worktree."
---

# RCA: Child worktree reconciliation renames authoritative feature worktree

**Дата:** 2026-03-08
**Статус:** Resolved
**Влияние:** Среднее; generated registry мог показывать неверную идентичность authoritative feature worktree и вызывать неожиданные диффы при работе из дочерней task branch
**Контекст:** Пост-UAT проверка `006-git-topology-registry` на реальном sibling worktree `feat/moltinger-jb6-gpt54-primary`

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-08T17:29:25Z |
| PWD | /Users/rl/coding/moltinger-006-git-topology-registry |
| Shell | /bin/zsh |
| Git Branch | 006-git-topology-registry |
| Git Status | modified feature branch during hardening pass |
| Error Type | shell |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | process + code |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | `derive_worktree_id` wrongly depends on `current_branch`, so the same physical `006-*` worktree renders under different ids depending on caller context | 90% |
| H2 | The dirty `docs/GIT-TOPOLOGY-REGISTRY.md` after `doctor --write-doc` is entirely a UX misunderstanding and not a code defect | 40% |
| H3 | Legacy sidecar keys for `parallel-feature-NNN` become orphaned after child-branch reconciliation | 75% |

## Ошибка

При создании нового sibling worktree и запуске `scripts/git-topology-registry.sh doctor --prune --write-doc` из дочерней task branch происходило следующее:

1. authoritative worktree для `006-git-topology-registry` рендерился не как `primary-feature-006`, а как `parallel-feature-006`;
2. reviewed intent для `primary-feature-006` всплывал в orphan section;
3. пользователь видел неожиданный diff в `docs/GIT-TOPOLOGY-REGISTRY.md` и не мог понять, это нормальное обновление snapshot или реальная ошибка workflow.

Симптомы были воспроизведены на реальном sibling worktree и затем зафиксированы regression E2E-тестом.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему `doctor --write-doc` из child branch менял идентичность authoritative worktree? | Скрипт определял `primary-feature-NNN` только когда обрабатываемая ветка совпадала с `current_branch` вызывающего worktree | `scripts/git-topology-registry.sh: derive_worktree_id/derive_location_class` до фикса |
| 2 | Почему это ломало reviewed intent? | Sidecar был привязан к `primary-feature-006`, а новый рендер выдавал `parallel-feature-006`, поэтому запись переставала матчиться | Diff в `docs/GIT-TOPOLOGY-REGISTRY.md` из sibling worktree; orphan section для `primary-feature-006` |
| 3 | Почему это дошло до UAT? | Тесты покрывали managed mutations и out-of-band drift, но не сценарий "child branch created from numbered feature worktree" | До hardening отсутствовал regression test для child worktree reconcile |
| 4 | Почему пользователь столкнулся с этим через обычный workflow? | Я запустил параллельный worktree-тест из активной feature-ветки и дал команду `doctor --write-doc` в новом worktree, не объяснив чётко, что tracked registry будет переписан при реальном drift | История сессии + пользовательский вывод `git status` с `M docs/GIT-TOPOLOGY-REGISTRY.md` |
| 5 | Почему команда выглядела как "ошибка" даже там, где поведение было ожидаемым? | В quick reference и quickstart не было явного UX-объяснения, что `doctor --write-doc` намеренно меняет tracked registry, а read-only путём является только `doctor --prune` | `docs/QUICK-REFERENCE.md` и `specs/006-git-topology-registry/quickstart.md` до фикса |

## Корневая причина

Каноническая идентичность numbered feature worktree была смоделирована как относительная к вызывающему worktree (`current_branch`), а не как observer-independent свойство live topology. Из-за этого child-branch reconcile мог переименовывать и orphan-ить authoritative parent worktree. Дополнительно UX-документация не объясняла, что `--write-doc` намеренно меняет tracked snapshot.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется в одном owner-script и тестах |
| □ Systemic? | yes | Любая numbered feature branch могла попасть в тот же сценарий |
| □ Preventable? | yes | Через stable id model, regression tests и явную UX-документацию |

## Принятые меры

1. **Немедленное исправление:** `scripts/git-topology-registry.sh` теперь всегда канонизирует numbered feature worktree как `primary-feature-NNN`, независимо от caller branch.
2. **Предотвращение:** legacy sidecar keys `parallel-feature-NNN` нормализуются в `primary-feature-NNN`; добавлен E2E regression test для child-branch reconcile и обновлены unit/integration expectations.
3. **Документация:** quick reference, quickstart и `/git-topology` command wrapper теперь явно объясняют разницу между `doctor --prune` и `doctor --prune --write-doc`.

## Связанные обновления

- [x] RCA-отчёт создан в `docs/rca/`
- [x] Тесты добавлены
- [x] Чеклисты обновлены
- [x] Generated registry/intent snapshot обновлён
- [ ] Новый файл правила создан (не требовалось)

## Уроки

1. Worktree identity в shared registry не должна зависеть от observer context.
2. Если команда изменяет tracked snapshot по дизайну, это нужно писать буквально в user-facing docs, иначе пользователь считывает ожидаемый diff как сбой.
3. UAT для workflow automation должен включать реальные sibling/child worktree сценарии, а не только temp-repo happy paths.

## Regression Test (Optional - for code errors only)

**Test File:** `tests/e2e/test_git_topology_registry_workflow.sh`

Сценарий: authoritative `006-*` worktree коммитит generated registry, затем создаётся child branch worktree `feat/demo-child`, запускается `doctor --prune --write-doc`, и тест подтверждает:

- authoritative row остаётся `primary-feature-006`;
- reviewed note сохраняется;
- orphan row для `primary-feature-006` не появляется.
