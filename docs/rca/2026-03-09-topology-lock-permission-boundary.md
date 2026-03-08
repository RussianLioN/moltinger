---
title: "Topology refresh misclassified permission boundary as a held lock"
date: 2026-03-09
severity: P1
category: shell
tags: [git-worktree, topology-registry, sandbox, permissions, ux, rca]
root_cause: "Lock acquisition treated any mkdir failure as an active lock, so Codex sandbox permission errors against the shared common .git directory were misreported as sibling refresh contention."
---

# RCA: Topology Refresh Misclassified Permission Boundary As A Held Lock

**Дата:** 2026-03-09
**Статус:** Resolved
**Влияние:** Высокое; managed `command-worktree` create-flow останавливался на ложном stale-lock сообщении и предлагал опасный ручной `rm` даже когда активного sibling refresh не было
**Контекст:** ручной UAT из `uat/006-git-topology-registry` при создании `feat/remote-uat-sanity-check`

## Ошибка

Во время UAT новый worktree создавался успешно, но шаг `scripts/git-topology-registry.sh refresh --write-doc` дважды завершался сообщением про lock:

- `Timed out waiting for lock`
- `Lock owner metadata is unavailable`

При этом реального активного параллельного `refresh/doctor` не было. После анализа выяснилось, что команда запускалась из Codex-сессии, где общий `git-common-dir` (`/Users/rl/coding/moltinger/.git`) находился вне writable boundary текущего worktree sandbox.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему `refresh --write-doc` сообщил о lock timeout? | Потому что `acquire_lock` интерпретировал любой неуспешный `mkdir lock_dir` как занятый lock и уходил в retry loop. |
| 2 | Почему `mkdir lock_dir` вообще падал? | Потому что команда пыталась писать в shared `git-common-dir`, который находился вне writable boundary текущей Codex-сессии. |
| 3 | Почему это выглядело как активный sibling lock? | Потому что логика не различала `lock already exists` и `permission denied / operation not permitted`. |
| 4 | Почему пользователь получил вводящую в заблуждение remediation-команду с `rm lock`? | Потому что fallback-диагностика считала отсутствие `owner.env` признаком старого/stale lock, хотя реального lock-dir могло не быть или он не был доступен на запись из этой сессии. |
| 5 | Почему это дошло до UAT? | Потому что предыдущие тесты проверяли живой lock и missing metadata, но не сценарий permission-boundary, где shared `.git` недоступен на запись из sibling worktree session. |

## Корневая причина

Скрипт ошибочно отождествлял любую ошибку `mkdir lock_dir` с уже занятым lock. В условиях Codex sandbox это приводило к ложной диагностике lock contention вместо корректного сообщения о permission boundary на shared `.git`.

## Принятые меры

1. **Немедленное исправление:** `acquire_lock` теперь различает:
   - реальный lock (`lock_dir` существует)
   - и permission-boundary / write-denied (`mkdir` не создал каталог и `lock_dir` не появился)
2. **Предотвращение:** `command-worktree` теперь явно требует approval/escalation для topology refresh, если shared `.git` находится вне writable sandbox.
3. **Валидация:** добавлен integration test на permission-boundary сценарий.

## Связанные обновления

- [x] RCA-отчёт создан
- [x] Тест добавлен
- [x] Workflow docs обновлены
- [ ] Новый отдельный rule-file не требовался

## Уроки

1. Любая shared-state операция в multi-worktree workflow должна различать real contention и permission boundary.
2. Если session не может писать в `git-common-dir`, это не “lock”; это отдельный класс ошибки с другой remediation path.
3. В Codex/App workflow команды, которые пишут в общий `.git`, должны заранее запрашивать approval/escalation, а не пытаться работать как обычная tracked-file mutation.
