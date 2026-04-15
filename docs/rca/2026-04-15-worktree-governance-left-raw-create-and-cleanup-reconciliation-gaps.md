---
title: "Worktree governance left raw create and cleanup reconciliation gaps"
date: 2026-04-15
severity: P2
category: process
tags: [worktree, branches, cleanup, beads, governance, rca]
root_cause: "Repo-owned worktree governance still allowed unmanaged raw `bd worktree create`, did not audit branch-only drift, treated cleanup close/reporting as secondary instead of first-class governance reconciliation, and left the shipped compatibility wrapper out of sync with resolver decisions."
---

# RCA: Worktree governance left raw create and cleanup reconciliation gaps

**Дата:** 2026-04-15  
**Статус:** Resolved in source  
**Влияние:** non-topology worktree/branch hygiene could drift back into unmanaged state even after prior hardening, leaving stale lane ownership and incomplete cleanup reconciliation  
**Контекст:** beads `moltinger-crq6`, follow-up non-topology worktree/branch governance repair

## Ошибка

Во время завершающего cleanup non-topology lane-ов всплыло сразу несколько связанных дефектов в repo-owned governance stack:

1. raw `bd worktree create moltinger-crq6` из canonical repo создал nested worktree внутри repo root и Beads redirect/shared ownership вместо managed local-runtime lane;
2. `scripts/beads-worktree-audit.sh` видел linked worktree drift, но не видел branch-only local drift;
3. `scripts/worktree-ready.sh cleanup --branch ... --delete-branch --close-issue` сперва ложноположительно блокировался на synthetic path conflict, а после source fix ещё и не отражал successful close step в cleanup report;
4. deprecated compatibility wrapper `scripts/bd-local.sh` не сопровождал новые resolver decision states (`block_repo_worktree_create`, canonical-root pass-through paths) и падал в `unsupported resolution state ...` вместо корректного fail-closed/pass-through поведения.

Итог: инструменты, которые должны были закрыть governance cycle, сами оставляли дыры в ownership и operator evidence.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `rg -n "worktree governance|raw bd worktree create|cleanup helper|branch-only drift" docs/rca docs/LESSONS-LEARNED.md -S`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

**Релевантные прошлые RCA/уроки:**
1. `docs/rca/2026-04-15-worktree-governance-helpers-trusted-contextual-beads-state.md`
   - уже требовал не доверять contextual proxy-state при worktree governance.
2. `docs/rca/2026-04-15-worktree-cleanup-helper-blocked-merged-behind-only-branch-on-stale-upstream-guard.md`
   - уже показал, что cleanup helper нельзя считать корректным без explicit regression coverage по live hygiene path.
3. `docs/rca/2026-04-15-worktree-cleanup-helper-treated-derived-branch-path-as-conflict.md`
   - уже зафиксировал один branch-only cleanup defect, но не покрывал close/reporting path и raw create entrypoint.

**Что могло быть упущено без этой сверки:**
- можно было бы снова “дочистить руками” branch/worktree topology и не исправить управляющие helper-ы;
- можно было бы считать cleanup успешным, хотя Beads issue-close/report contract оставался частично broken.

**Что в текущем инциденте действительно новое:**
- raw `bd worktree create` сам по себе оказался запрещённым entrypoint для этого репозитория;
- branch-only drift нужно аудировать не только по worktree, но и по branch без worktree;
- cleanup governance считается незавершённым, если helper не умеет завершить issue reconciliation и отразить это в operator-facing report.

## Evidence

Подтверждённые факты:

1. Live вызов `bd worktree create moltinger-crq6` создал nested worktree внутри `/Users/rl/coding/moltinger/moltinger-main/moltinger-crq6` с redirected/shared Beads ownership.
2. `git worktree list --porcelain` и `bd worktree list` после cleanup показали, что реальных non-topology worktree уже почти не осталось, но governance stack всё ещё позволял unsafe raw create.
3. `git branch --format='%(refname:short)'` показал branch-only local drift (`feat/remote-uat-hardening-v2`) без связанного worktree; до фикса audit helper этого не подсвечивал.
4. Repro для `run_worktree_cleanup ... --close-issue` до фикса:
   - возвращал `cleanup_blocked` из-за synthetic path conflict, хотя user передал только `--branch`;
   - после устранения conflict helper успешно выполнял `bd --db <repo>/.beads/beads.db close ...`, но human cleanup report не печатал `Close: closed`.
5. Review replay через compatibility path показал, что `scripts/bd-local.sh` не обрабатывает `block_repo_worktree_create`, `pass_through_canonical_root_readonly` и `pass_through_root_cleanup_admin`, хотя resolver уже выдаёт эти states.
6. После source fixes:
   - `bash tests/unit/test_bd_dispatch.sh` → `30/30 PASS`
   - `bash tests/unit/test_beads_worktree_audit.sh` → `9/9 PASS`
   - `bash tests/unit/test_worktree_ready.sh` → `60/60 PASS`
   - `bash tests/unit/test_bd_local.sh` → green with explicit coverage for raw create block and canonical-root pass-through compatibility

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему governance cleanup оставлял незавершённые хвосты? | Потому что repo-owned helper-ы покрывали linked worktree happy-path, но не весь lifecycle governance. | live cleanup cycle, failing unit regressions |
| 2 | Почему lifecycle был неполным? | Потому что raw create entrypoint, branch-only drift и issue-close reconciliation рассматривались как второстепенные. | raw `bd worktree create` repro, pre-fix audit output, missing `Close: closed` |
| 3 | Почему raw create был опасным именно здесь? | Потому что этот репозиторий использует managed worktree model, а plain `bd worktree create` materialized redirect/shared ownership, несовместимую с repo contract. | nested `/moltinger-main/moltinger-crq6`, redirected Beads state |
| 4 | Почему audit, cleanup и compatibility wrapper не поймали это как source-level defect раньше? | Потому что тесты были сосредоточены на linked worktree paths и основном dispatch path, но не покрывали branch-only governance drift, close/report path и deprecated wrapper compatibility surface. | pre-fix coverage in `test_beads_worktree_audit.sh`, `test_worktree_ready.sh`, `test_bd_local.sh` |
| 5 | Почему это дошло до operator-visible confusion? | Потому что governance helper-ы не fail-closed на unsafe entrypoint, не доводили cleanup contract до полного operator-facing reconciliation и оставляли shipped compatibility wrapper вне синхронизации с resolver. | raw create repro, blocked cleanup, missing close signal in report, `unsupported resolution state` in `bd-local.sh` |

## Корневая причина

Repo-owned worktree governance stack всё ещё мыслил cleanup как набор разрозненных shell-операций, а не как единый lifecycle contract.

Из-за этого:
- unsafe raw create entrypoint оставался доступен;
- branch-only branch drift выпадал из аудита;
- cleanup считался “почти завершённым” даже без issue-close reconciliation и явного operator-facing evidence;
- shipped compatibility entrypoint не считался обязательной частью того же governance contract.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | все fixes находятся в repo-owned shell helpers/tests |
| □ Systemic? | yes | defect span-ил dispatch, audit и cleanup/report layers |
| □ Preventable? | yes | через explicit entrypoint guard, wider audit scope и reconciliation regressions |

## Принятые меры

1. **Немедленное исправление**
   - `bin/bd` + `scripts/beads-resolve-db.sh`: raw `bd worktree create` fail-closed blocked в этом репозитории с явной managed-worktree guidance.
   - `scripts/beads-worktree-audit.sh`: добавлен branch-only drift audit для local branches без worktree.
   - `scripts/worktree-ready.sh`: cleanup close path доведён до explicit `bd --db ... close ...`, branch-only synthetic conflict corrected, cleanup report теперь печатает `Issue` и `Close`.
2. **Предотвращение**
   - добавлены regressions:
     - raw `bd worktree create` must block;
     - audit warns for branch-only merged local branch;
     - cleanup with attached branch-only worktree must not false-conflict;
     - cleanup `--close-issue` must close the issue and report it;
     - `bd-local` must mirror raw-create block and canonical-root readonly/admin pass-through states.
3. **Документация**
   - этот RCA зафиксирован;
   - lessons index будет пересобран после landing.

## Связанные обновления

- [x] Тесты добавлены
- [x] Индекс уроков будет пересобран
- [ ] Новый rule file не понадобился

## Уроки

1. В репозитории с managed worktree model raw lower-level create entrypoint должен быть либо доказанно совместим, либо fail-closed заблокирован.
2. Worktree governance audit должен видеть не только worktree, но и branch-only drift.
3. Cleanup не считается завершённым, пока helper не завершил issue reconciliation и не показал это в отчёте.
4. Operator-facing report — часть safety contract, а не косметика после успешной shell-логики.
5. Deprecated compatibility wrapper тоже остаётся owning layer: если resolver расширился, wrapper обязан быть синхронизирован и покрыт тестом.
