---
title: "Worktree cleanup helper treated derived branch-only path as a path/branch conflict"
date: 2026-04-15
severity: P2
category: tooling
tags: [worktree, cleanup, branches, git, beads, rca]
root_cause: "The repo-owned cleanup helper synthesized a sibling worktree path from `--branch` too early and then treated the absence of a discovered managed worktree as a path/branch conflict, blocking legitimate branch-only cleanup."
---

# RCA: Worktree cleanup helper treated derived branch-only path as a path/branch conflict

Date: 2026-04-15  
Status: Resolved in source, pending review/merge  
Context: beads `moltinger-zjgi`, follow-up governance cleanup after merged lane `moltinger-crq6`

## Ошибка

Во время cleanup stale local-only branches:

```bash
scripts/worktree-ready.sh cleanup --branch pr-159-review --delete-branch --format env
scripts/worktree-ready.sh cleanup --branch review-mempalace-skill --delete-branch --format env
```

repo-owned helper возвращал `cleanup_blocked` и warning такого вида:

```text
Cleanup arguments conflict: --path /Users/.../moltinger-main-pr-159-review resolves to branch 'unknown', not requested branch 'pr-159-review'.
```

При этом фактическое состояние было другим:

- у branch вообще не было связанного worktree;
- `git diff --stat origin/main...<branch>` был пустым;
- `git rev-list --left-right --count origin/main...<branch>` показывал behind-only merge-safe состояние;
- PR по этим head-веткам отсутствовал;
- branch требовал именно branch-only cleanup, а не path/branch disambiguation.

## Проверка прошлых уроков

Проверены:

- `docs/LESSONS-LEARNED.md`
- `rg -n "cleanup helper|worktree cleanup|path/branch conflict|merged behind-only" docs/rca docs/LESSONS-LEARNED.md -S`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые RCA:

1. `docs/rca/2026-04-15-worktree-cleanup-helper-blocked-merged-behind-only-branch-on-stale-upstream-guard.md`
   - уже закрывал cleanup path, где lower-layer `unpushed commits` ошибочно блокировал safe cleanup merged clean worktree.
2. `docs/rca/2026-04-15-worktree-governance-helpers-trusted-contextual-beads-state.md`
   - уже фиксировал, что worktree governance helpers нельзя строить на раннем предположении о target identity без canonical discovery.

Что оказалось новым:

- cleanup branch-only path мог сломаться ещё до merge-proof и delete-branch stage;
- сама branch-only операция ошибочно считалась конфликтом только потому, что helper заранее синтезировал ожидаемый sibling path;
- отсутствие managed worktree трактовалось как ambiguity, хотя для stale local-only branch это и было нормальным cleanup target state.

## Evidence

Собранная evidence:

1. Live cleanup на `pr-159-review` и `review-mempalace-skill` reproducibly возвращал `cleanup_blocked` с `Cleanup arguments conflict`.
2. `git worktree list --porcelain` не показывал worktree для этих веток.
3. `git diff --stat origin/main...pr-159-review` и `git diff --stat origin/main...review-mempalace-skill` были пустыми.
4. После source fix те же команды завершились успешно:
   - `worktree_action=already_missing`
   - `local_branch_action=deleted`
   - `merge_check=git_ancestor_local`
5. Новый unit regression воспроизвёл именно сценарий:
   - branch существует;
   - branch уже merged into remote default branch;
   - worktree отсутствует;
   - cleanup должен пройти без ложного `Cleanup arguments conflict`.

## 5 Whys

| Why | Ответ | Доказательство |
| --- | --- | --- |
| 1 | Почему helper блокировал branch-only cleanup? | Потому что cleanup path решил, что `--branch` конфликтует с `--path`. | live helper output |
| 2 | Почему появился `--path`, хотя user передал только `--branch`? | Потому что `prepare_cleanup_context()` заранее вызывал `derive_sibling_worktree_path "${branch}"`. | `scripts/worktree-ready.sh` cleanup preparation |
| 3 | Почему derived path считался конфликтом? | Потому что `cleanup_target_arguments_conflict()` трактовал отсутствие `discovered_worktree_path` как конфликтное состояние. | pre-fix function behavior |
| 4 | Почему это неверно для stale local-only branch? | Потому что при branch-only cleanup отсутствие managed worktree — ожидаемое состояние, а не ambiguity. | `git worktree list --porcelain`, live repo evidence |
| 5 | Почему helper не был защищён тестом? | Потому что suite покрывал branch cleanup только когда branch резолвится в существующий worktree, но не branch-only cleanup без worktree. | pre-fix `tests/unit/test_worktree_ready.sh` coverage |

## Корневая причина

Repo-owned cleanup helper слишком рано превращал `--branch` в ожидаемый sibling path и затем воспринимал отсутствие найденного managed worktree как path/branch ambiguity. В результате legitimate branch-only cleanup ошибочно блокировался ещё до branch deletion logic и merge-proof stage.

## Fixes Applied

1. `scripts/worktree-ready.sh`
   - `cleanup_target_arguments_conflict()` теперь срабатывает только когда helper действительно обнаружил managed worktree и может сравнить его с target path;
   - отсутствие `discovered_worktree_path` больше не считается конфликтом для branch-only cleanup.
2. `tests/unit/test_worktree_ready.sh`
   - добавлен positive regression для `--branch ... --delete-branch` без существующего worktree;
   - добавлен companion regression для branch-only cleanup без `--delete-branch`, чтобы helper не трогал branch и не выдавал ложный conflict.
3. Live cleanup replay
   - `pr-159-review` и `review-mempalace-skill` после фикса реально удалились через repo-owned helper, а не через ручной git workaround.

## Prevention

1. Derived preview/path нельзя путать с authoritative discovered target.
2. Для cleanup branch-only режима отсутствие worktree — это нормальное состояние target, а не признак ambiguity.
3. Если repo-owned helper synthesizes operator-visible state, любой synthetic field должен быть помечен как hypothesis до discovery.
4. У каждого conflict guard должен быть unit test не только на positive conflict, но и на no-worktree branch-only non-conflict path.

## Уроки

1. В worktree cleanup synthetic sibling path — это только preview, не доказанный target.
2. Branch-only cleanup должен работать и без живого worktree, если merge-safe branch proof уже существует.
3. Если helper блокирует cleanup из-за собственного derived path, это defect owning layer, а не повод делать ручной git cleanup и считать задачу закрытой.
