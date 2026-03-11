---
title: "Beads recovery audit mislabeled owner-branch snapshots as missing worktrees"
date: 2026-03-12
severity: P2
category: shell
tags: [beads, recovery-audit, tracker-ownership, worktree, rca]
root_cause: "The recovery audit treated attached worktrees as the only proof of ownership, so it skipped checking owner branch snapshots before emitting missing_worktree blockers."
---

# RCA: Beads recovery audit mislabeled owner-branch snapshots as missing worktrees

**Дата:** 2026-03-12
**Статус:** Resolved
**Влияние:** Среднее; forensic cleanup of root `.beads/issues.jsonl` produced misleading blockers and hid which leaked issues were already localized in owning branches

## Ошибка

`scripts/beads-recovery-batch.sh audit` correctly stayed fail-closed, but it localized several blocked candidates too coarsely. When an owner branch existed without an attached worktree, the audit always emitted `missing_worktree`, even if the issue was already present in that branch's committed `.beads/issues.jsonl`.

On the real `stash@{0}` residue this obscured the true picture:

- `molt-2` and `moltinger-ejy` were already present in their owner branch snapshots;
- `moltinger-248`, `moltinger-dmi`, and `moltinger-jb6` were already present in owner worktrees;
- only `moltinger-z8m` remained genuinely unresolved because ownership was ambiguous.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему audit называл часть blocked-кандидатов `missing_worktree`? | В `build_audit_candidates()` ветка без attached worktree сразу классифицировалась как blocked `missing_worktree`. |
| 2 | Почему отсутствие worktree считалось достаточным доказательством? | Скрипт проверял наличие issue только в live owner worktree и не смотрел owner branch snapshot через git object store. |
| 3 | Почему branch snapshot не использовался как вторичный источник истины? | Логика recovery изначально была сфокусирована на безопасном `apply`, где нужен реальный worktree path для локализации и бэкапа. |
| 4 | Почему это стало проблемой именно в forensic cleanup? | Для расследования root leakage оператору важна точная локализация blocked-кандидатов, а не только готовность к `apply`. |
| 5 | Почему система не подсветила этот пробел раньше? | Unit-тесты покрывали safe apply, redirected owners и true missing-worktree, но не кейс "owner branch already contains the issue without attached worktree". |

## Корневая причина

Audit-проход использовал слишком узкое определение ownership-proof: только attached worktree. Из-за этого deterministic fail-closed behavior сохранялся, но forensic localization была неточной и завышала число "потерянных" кандидатов.

## Принятые меры

1. **Немедленное исправление:** `scripts/beads-recovery-batch.sh` теперь проверяет owner branch snapshot перед тем, как ставить blocker `missing_worktree`.
2. **Предотвращение:** live-state resolver синхронизирован с тем же правилом и теперь возвращает `already_present_in_owner_branch` вместо ложного `missing_worktree`.
3. **Тесты и контракты:** добавлен unit-тест для branch-snapshot случая и обновлён `specs/010-beads-recovery-batch/data-model.md`.

## Связанные обновления

- [x] RCA-отчёт создан в `docs/rca/`
- [x] Новый файл правила создан в `docs/rules/`
- [x] Unit-тест добавлен
- [x] Data model updated

## Уроки

1. Fail-closed audit должен различать "нельзя применить" и "непонятно, где уже локализовано".
2. Для tracker forensics branch snapshot через `git show <branch>:.beads/issues.jsonl` является валидным источником ownership evidence даже без attached worktree.
3. Любой новый blocker в recovery tooling должен иметь fixture-тест, который доказывает, что он не маскирует более точный статус.
