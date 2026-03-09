---
title: "UAT registry snapshots were treated as disposable during UAT maintenance"
date: 2026-03-09
severity: P2
category: process
tags: [git-worktree, topology-registry, uat, process, handoff, rca]
root_cause: "UAT maintenance had no explicit preserve-before-reset protocol for branch-local topology registry snapshots, so newer UAT evidence could be discarded or appear ignored during UAT refresh/reset."
---

# RCA: UAT Registry Snapshot Loss During UAT Maintenance

**Дата:** 2026-03-09
**Статус:** Resolved
**Влияние:** Среднее; обновленный branch-local snapshot `docs/GIT-TOPOLOGY-REGISTRY.md` в UAT worktree мог быть воспринят как потерянный или проигнорированный при reset/update UAT, что скрывает часть audit trail по новым веткам и worktree.
**Контекст:** повторяющееся обслуживание `uat/006-git-topology-registry` во время ручных UAT прогонов для `006-git-topology-registry`

## Ошибка

Во время UAT обновленный registry snapshot в `uat/006-git-topology-registry` оказывался в состоянии "локальный diff + ветка behind", после чего UAT ветка обновлялась как тестовая. Это создавало повторяющееся ощущение, что новые worktree/branch записи из UAT теряются или игнорируются.

Факты последнего инцидента:

- `git -C /Users/rl/coding/moltinger-uat-006-git-topology-registry status --short --branch`
  показывал `behind 2` и `M docs/GIT-TOPOLOGY-REGISTRY.md`
- текущая `006-git-topology-registry` тоже содержала такой же локальный diff
- `diff -u` между двумя registry-файлами был пуст, то есть UAT snapshot уже существовал локально и требовал явного landing в текущую ветку
- `./scripts/git-topology-registry.sh check` в текущей ветке показывал `stale`, то есть вопрос был не только в копировании файла, но и в неявной ownership/reconcile модели

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему казалось, что UAT теряет обновленный registry snapshot? | Потому что UAT worktree обновлялся как disposable test branch, а его локальный `docs/GIT-TOPOLOGY-REGISTRY.md` не имел явного preserve-before-reset шага. | `git -C .../moltinger-uat-006-git-topology-registry status --short --branch` показывал `behind 2` и `M docs/GIT-TOPOLOGY-REGISTRY.md`. |
| 2 | Почему snapshot не промотировался в owning branch автоматически? | Потому что create-flow умеет landing-the-plane для invoking branch, но maintenance/reset UAT flow не имел отдельного контракта на promotion snapshot'а перед reset/update. | В `command-worktree` был описан managed create/attach flow, но не правило на UAT refresh/reset. |
| 3 | Почему UAT вообще мог содержать более новый registry snapshot, чем текущая feature branch? | Потому что UAT запускает реальные topology mutations и refresh в своей ветке, а owning branch может отставать, пока кто-то явно не перенесет или не refresh'нет registry там. | Последний UAT прогон создал новые worktree, а diff между current/UAT registry уже совпадал локально, но не был landed. |
| 4 | Почему live git не снимал проблему сам по себе? | Потому что live git позволяет пересобрать текущую topology, но не заменяет branch-local audit trail и не подсказывает, какую именно ветку нужно обновить перед reset UAT. | `./scripts/git-topology-registry.sh check` в текущей ветке показывал `stale`, несмотря на наличие UAT-derived snapshot. |
| 5 | Почему это повторялось больше одного раза? | Потому что ownership registry mutation между authoritative branch и UAT branch оставалась неявной: UAT считался disposable, но его registry snapshot не был явно объявлен disposable до promotion check. | Повторяющийся паттерн ручных UAT прогонов и просьба пользователя отдельно "забрать реестр из UAT перед обновлением". |

## Корневая причина

В процессе отсутствовал явный протокол **preserve-before-reset** для branch-local registry snapshot'ов, появляющихся в UAT worktree. Из-за этого UAT обслуживался как disposable ветка, хотя его `docs/GIT-TOPOLOGY-REGISTRY.md` мог содержать еще не landed audit evidence, которую сначала нужно было сравнить и промотировать в owning branch.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| Actionable? | yes | Можно добавить обязательное правило и explicit workflow шаг перед reset/update UAT. |
| Systemic? | yes | Проблема не в одном коммите, а в неявном контракте между authoritative branch и UAT branch. |
| Preventable? | yes | Повтор предотвращается правилом preserve-before-reset и короткой ссылкой в source instructions. |

## Принятые меры

1. **Немедленное исправление:** зафиксирован факт, что UAT-derived registry snapshot должен сначала сравниваться с owning branch и сохраняться там до reset/update UAT.
2. **Предотвращение:** добавлено отдельное правило `docs/rules/uat-registry-snapshot-preservation.md` и ссылка на него в source instructions.
3. **Документация:** RCA оформлен в `docs/rca/`, source instructions обновлены и `AGENTS.md` будет перегенерирован стандартным способом.

## Связанные обновления

- [x] Новый файл правила создан
- [x] Краткая ссылка добавлена в source instructions
- [ ] Новые навыки созданы
- [ ] Тесты добавлены
- [x] Чеклисты обновлены через RCA/lessons workflow

## Уроки

1. UAT worktree может быть disposable как execution context, но его registry snapshot не является disposable до explicit promotion check.
2. Для topology registry важно различать две вещи:
   - live git как source of truth
   - branch-local markdown snapshot как audit trail, который тоже требует ownership
3. Перед `reset`, `pull`, `rebase`, `merge` или любым sync UAT worktree нужно сначала ответить на один вопрос: несет ли UAT локальный registry diff более новый snapshot, чем owning branch?
4. Если да, сначала нужно перенести или пересобрать этот snapshot в owning branch, и только потом обновлять UAT.

---

*Создано с помощью навыка rca-5-whys*
