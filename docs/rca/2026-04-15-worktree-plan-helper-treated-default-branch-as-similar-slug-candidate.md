---
title: "Worktree plan helper treated the default branch as a similar slug candidate"
date: 2026-04-15
severity: P2
category: tooling
tags: [worktree, planning, branches, default-branch, helpers, rca]
root_cause: "The repo-owned planning helper ran slug-similarity checks before initializing the default-branch context and allowed the default branch itself to participate in generic similarity matching, so slugs containing `main` produced false `needs_clarification` results."
---

# RCA: Worktree plan helper treated the default branch as a similar slug candidate

Date: 2026-04-15  
Status: Resolved in source, pending review/merge  
Context: beads `moltinger-th0e`, blocked continuation of canonical-main tail reconciliation `moltinger-b215`

## Ошибка

Во время старта dedicated lane для canonical-main tail:

```bash
scripts/worktree-ready.sh plan --issue moltinger-b215 --slug canonical-main-tail-reconciliation --format env
```

repo-owned helper возвращал:

```text
decision=needs_clarification
candidate_1=local-branch\tmain\t-\tsimilar-local-branch
candidate_2=remote-branch\torigin/main\t-\tsimilar-remote-branch
```

и одновременно засорял stderr repeated warning-ами:

```text
[worktree-ready] Branch name is required for path formatting
```

Это было ложным блокером:

- никакой реальной коллизии для `feat/moltinger-b215-canonical-main-tail-reconciliation` не было;
- helper сам превратил generic token `main` внутри slug в “похожую ветку”;
- continuation broader task была остановлена по правилу `abnormal-skill-helper-behavior-needs-root-cause-fix.md`.

## Проверка прошлых уроков

Проверены:

- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --all | rg -n "worktree-ready|needs_clarification|default branch|planning"`
- `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`

Релевантные прошлые RCA:

1. `docs/rca/2026-04-15-worktree-cleanup-helper-blocked-merged-behind-only-branch-on-stale-upstream-guard.md`
   - уже фиксировал class ошибок, где helper делал ложный blocking verdict на safe path.
2. `docs/rca/2026-04-15-worktree-cleanup-helper-treated-derived-branch-path-as-conflict.md`
   - уже закреплял правило, что synthetic/derived target нельзя трактовать как authoritative conflict without real discovery.
3. `docs/rca/2026-03-28-worktree-create-helper-and-hook-bootstrap-source-drift.md`
   - уже требовал честного Phase A contract и запрета на misleading helper behavior.

Что оказалось новым:

- ложный блокер возник не в cleanup/create path, а в `plan`;
- проблема состояла из двух частей сразу:
  - default branch `main` участвовал в generic similarity matching;
  - сам `plan` path не инициализировал `default_branch_name`, поэтому новая guard-логика сначала прошла через empty-context stderr leak.

## Evidence

1. Live reproduce до фикса:

```bash
scripts/worktree-ready.sh plan --issue moltinger-b215 --slug canonical-main-tail-reconciliation --format env
```

возвращал `decision=needs_clarification` и candidates `main` / `origin/main`.

2. Тот же live reproduce до второго патча печатал repeated warnings:

```text
[worktree-ready] Branch name is required for path formatting
```

3. Code inspection показал:
   - `candidate_matches_slug()` теперь использует default-branch guard;
   - но `prepare_plan_context()` до фикса не вызывал `resolve_default_branch_name()`.

4. Новый unit regression воспроизводит именно canonical slug:

```bash
canonical-main-tail-reconciliation
```

и требует:

- `Decision: create_clean`
- отсутствие `Decision: needs_clarification`
- отсутствие `name=main` / `name=origin/main`
- отсутствие warning-а `Branch name is required for path formatting`

5. Live reproduce после фикса:

```bash
scripts/worktree-ready.sh plan --issue moltinger-b215 --slug canonical-main-tail-reconciliation --format env
```

возвращает:

```text
decision=create_clean
candidate_count=0
```

6. Полный regression suite:

```bash
./tests/unit/test_worktree_ready.sh
```

завершился `61/61 PASS`.

## 5 Whys

| Why | Ответ | Доказательство |
| --- | --- | --- |
| 1 | Почему `plan` falsely returned `needs_clarification`? | Потому что helper посчитал `main` и `origin/main` похожими кандидатами для slug с токеном `main`. | live `plan --format env` output |
| 2 | Почему default branch участвовал в similarity matching? | Потому что generic slug matching не исключал default branch как специальный system branch. | pre-fix `candidate_matches_slug()` behavior |
| 3 | Почему fix сначала не устранил live symptom полностью? | Потому что guard сравнивал с пустым `default_branch_name`. | live stderr warnings + code path review |
| 4 | Почему `default_branch_name` был пустым именно в `plan` path? | Потому что `prepare_plan_context()` не вызывал `resolve_default_branch_name()`. | pre-fix `prepare_plan_context()` |
| 5 | Почему это не поймали tests раньше? | Потому что suite покрывал similar-branch ambiguity, но не canonical slug, содержащий generic token default branch, и не проверял отсутствие internal warning leak. | pre-fix `tests/unit/test_worktree_ready.sh` coverage |

## Корневая причина

Repo-owned `worktree-ready` planning contract не различал generic default branch и real similar candidates, а также не инициализировал default-branch context до similarity evaluation. В результате safe slug, содержащий token `main`, превращался в ложную ambiguity, а частичный fix initially leak-ал internal warning из-за пустого `default_branch_name`.

## Fixes Applied

1. `scripts/worktree-ready.sh`
   - добавлен `is_default_branch_similarity_key()`;
   - `candidate_matches_slug()` теперь исключает default branch из generic similarity matching;
   - `prepare_plan_context()` теперь всегда инициализирует `default_branch_name` через `resolve_default_branch_name()` до similarity discovery.
2. `tests/unit/test_worktree_ready.sh`
   - добавлен live-shaped regression для `canonical-main-tail-reconciliation`;
   - test теперь проверяет не только `create_clean`, но и отсутствие:
     - `needs_clarification`
     - candidates `main` / `origin/main`
     - warning leak `Branch name is required for path formatting`
3. Live replay
   - blocked canonical-tail planning command после фикса вернулся на `create_clean`.

## Prevention

1. Generic system branches (`main`, `origin/main`) нельзя подавать в human similarity heuristics как “похожие рабочие линии”.
2. Любой helper guard, зависящий от repo context, должен инициализировать этот context в owning mode до evaluation, а не рассчитывать на side effects других paths.
3. Regression tests для planning heuristics должны проверять не только exit code/decision, но и отсутствие internal stderr leaks.
4. Если repo-owned helper блокирует continuation broader task ложной ambiguity, это source-contract defect, а не повод обходить helper вручную.

## Уроки

1. Для worktree planning default branch — это control-plane baseline, а не кандидат в similarity clarification.
2. Частичный fix для helper heuristics недостаточен без live reproduction из реального blocked command path.
3. Если новый guard требует context (`default_branch_name`), этот context должен быть инициализирован прямо в owning mode (`plan`), а не имплицитно через другие workflows.
