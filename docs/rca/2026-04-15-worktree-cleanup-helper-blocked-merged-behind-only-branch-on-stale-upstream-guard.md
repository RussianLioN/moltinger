---
title: "Worktree cleanup helper blocked merged behind-only branch on stale upstream unpushed-guard"
date: 2026-04-15
severity: P2
category: tooling
tags: [worktree, cleanup, beads, git, stale-upstream, rca]
root_cause: "The repo-owned cleanup helper trusted lower-layer cleanup signals and local branch inputs too early: it treated `bd worktree remove` stale-upstream `unpushed commits` as authoritative, allowed CLI `--branch` to outrank the actual worktree record, and relied on stale local refs for merge safety instead of refreshing remote state before destructive cleanup decisions."
---

# RCA: Worktree cleanup helper blocked merged behind-only branch on stale upstream unpushed-guard

Date: 2026-04-15  
Status: Resolved in source, pending review/merge/deploy  
Context: beads `moltinger-tc52`, follow-up after worktree hygiene cleanup in canonical `main`

## Ошибка

Во время cleanup лишних worktree repo-owned helper:

```bash
scripts/worktree-ready.sh cleanup --path <worktree> --delete-branch
```

ложно вернул `cleanup_blocked` для clean branch/worktree, который уже был полностью поглощён `origin/main`.

Фактический manual proof был таким:

- `git rev-list --left-right --count origin/main...<branch>` показывал `behind-only`, `ahead=0`
- `git merge-base --is-ancestor <branch> origin/main` был истинным
- manual `git worktree remove` + `git branch -d` проходили успешно

Тем не менее helper остановился на сообщении вида:

```text
safety check failed: worktree has unpushed commits. Use --force to skip safety checks.
```

## Проверка прошлых уроков

Проверены:

- `rg -n "worktree-ready|cleanup_blocked|worktree cleanup|stale upstream" docs/rca docs/LESSONS-LEARNED.md -S`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые RCA:

1. `docs/rca/2026-03-28-worktree-create-helper-and-hook-bootstrap-source-drift.md`
   - уже фиксировал, что repo-owned worktree helper нельзя считать непререкаемым truth layer, если его source contract оказался уже реальности.
2. `docs/rca/2026-03-26-worktree-create-misread-local-ownership-as-runtime-ready.md`
   - уже показывал, что worktree workflow должен доуточнять состояние отдельными проверками, а не слепо склеивать один промежуточный verdict в окончательное решение.

Что оказалось новым:

- cleanup path по-прежнему считал ответ `bd worktree remove` окончательным verdict даже тогда, когда git ancestry уже доказывала merged-safe состояние branch/worktree;
- stale или `[gone]` upstream metadata в нижнем слое могла породить ложный `unpushed commits` guard и заблокировать весь cleanup flow;
- у helper не было controlled fallback на direct git removal для clean merged worktree.

## Evidence

Собранная evidence:

1. `scripts/worktree-ready.sh cleanup --path ... --delete-branch` вернул `cleanup_blocked` с warning про `unpushed commits`.
2. Branch был behind-only относительно `origin/main`, то есть:
   - `ahead = 0`
   - commit tip branch уже входил в `origin/main`
3. Manual cleanup через:
   - `git worktree remove <path>`
   - `git branch -d <branch>`
   прошёл без потери данных.
4. Повторная локальная репродукция в unit-тесте показала тот же класс сбоя:
   - fake `bd worktree remove` возвращает stale-upstream `unpushed commits`
   - branch/worktree clean
   - branch merged into `origin/main`
   - helper до фикса оставался blocked

## 5 Whys

| Why | Ответ | Доказательство |
| --- | --- | --- |
| 1 | Почему cleanup helper заблокировал safe merged worktree? | Потому что `bd worktree remove` вернул guard про `unpushed commits`, и helper принял его за окончательный blocker. | live cleanup output |
| 2 | Почему этот guard был ложным? | Потому что branch был не ahead, а behind-only: его tip уже был предком `origin/main`. | `git rev-list --left-right --count`, `git merge-base --is-ancestor` |
| 3 | Почему helper не смог отличить ложный guard от реального риска? | Потому что cleanup path не делал второй authoritative merge-safety check после отказа нижнего слоя. | `execute_cleanup_worktree_action()` до фикса |
| 4 | Почему при известном merged-safe состоянии не было fallback на direct git removal? | Потому что helper делегировал remove только через `bd worktree remove` и не имел controlled direct-git branch для clean merged worktree. | `scripts/worktree-ready.sh` до фикса |
| 5 | Почему это стало operator-visible дефектом? | Потому что repo-owned helper не содержал ложный negative из нижнего слоя и заставил оператора обходить cleanup вручную. | реальный cleanup cycle + ручной обход |

## Root Cause

Корневая причина была не в самом факте stale upstream metadata и не в git topology.

Корневая причина была в repo-owned `worktree-ready` cleanup contract:

- helper целиком доверял verdict `bd worktree remove`;
- helper не проверял, не является ли этот `unpushed commits` guard ложным negative для merged clean worktree;
- helper позволял raw CLI `--branch` пережить discovery об actual target worktree;
- helper не освежал remote refs перед merge proof и поэтому мог опираться на stale local branch state;
- helper не имел safe fallback на `git worktree remove`, когда authoritative merge proof уже доказывала отсутствие риска.

Именно поэтому stale/[gone] upstream state из нижнего слоя эскалировалась в operator-visible cleanup blocker.

## Fixes Applied

1. `scripts/worktree-ready.sh`
   - добавлен детектор stale-upstream false guard по output family `safety check failed` + `unpushed commit`
   - добавлена clean-worktree проверка через `git status --short`
   - добавлен controlled fallback:
     - сначала authoritative merge proof через `resolve_cleanup_merge_proof`
     - затем direct `git worktree remove <path>` только для clean merged worktree
   - cleanup теперь fail-closed блокирует конфликтующие `--path` + `--branch`, если они указывают на разные worktree/branch targets
   - `resolve_cleanup_merge_proof` теперь refreshes remote refs before git-proof, предпочитает live remote proof, использует local proof только когда live remote branch отсутствует и на GitHub-origin умеет спрашивать current branch head через `gh api`, если git refresh недоступен
2. `tests/unit/test_worktree_ready.sh`
   - добавлен positive regression:
     - merged clean worktree
     - fake `bd worktree remove` ложно падает с `unpushed commits`
     - helper завершает cleanup через direct git fallback
   - добавлен negative regression:
     - branch не merged
     - тот же fake `unpushed commits`
     - helper остаётся blocked и ничего не удаляет
   - добавлены safety regressions на:
      - dirty worktree
      - конфликт `--path`/`--branch`
      - stale remote branch, ушедшую вперёд в другом clone

## Prevention

1. Repo-owned cleanup helper не должен считать один stale lower-layer guard окончательной истиной, если git может дать более надёжный merged proof.
2. Для destructive-ish hygiene actions fallback допустим только после двух условий:
   - worktree clean
   - merged proof установлен авторитетно
3. Если user передал и `--path`, и `--branch`, helper должен доказывать, что они указывают на один и тот же target, иначе cleanup обязан fail-closed.
4. Negative regression обязательна рядом с positive fallback regression, чтобы workaround не превратился в unsafe bypass.

## Уроки

1. `unpushed commits` от нижнего слоя — это hypothesis, а не окончательная истина, если authoritative git ancestry уже говорит `behind-only`.
2. В worktree cleanup path merge proof важнее stale tracking metadata.
3. Если repo-owned helper даёт ложный blocker, это отдельный defect owning layer и его надо чинить в helper, а не считать ручной git cleanup “достаточным решением”.
