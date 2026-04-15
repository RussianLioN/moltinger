---
title: "Worktree Phase A returned before local Beads runtime was ready and plain bd worktree list still depended on cwd"
date: 2026-04-15
severity: P1
category: process
tags: [worktree, beads, command-worktree, phase-a, runtime, governance, rca]
root_cause: "Repo-owned worktree helpers still treated post-bootstrap context as ready too early and let plain `bd worktree list` inherit observer cwd instead of forcing canonical-root routing."
---

# RCA: Worktree Phase A returned before local Beads runtime was ready and plain bd worktree list still depended on cwd

**Дата:** 2026-04-15  
**Статус:** Resolved in source  
**Влияние:** fresh issue-owned worktrees could report success before plain `bd status` was actually ready, and direct `bd worktree list` from a dedicated worktree could misreport ownership state  
**Контекст:** beads `moltinger-th0e`, repo-owned `command-worktree` / `worktree-phase-a` / `bin/bd` / `beads-resolve-db`

## Ошибка

После создания нового governed worktree из `origin/main` были подтверждены два остаточных дефекта branch/worktree tooling:

1. `scripts/worktree-phase-a.sh create-from-base` мог вернуть `created_from_base`, хотя plain `bd status` в только что созданном worktree ещё падал transient ошибкой `connect: connection refused`.
2. `bd worktree list` из dedicated worktree всё ещё зависел от observer cwd и в части окружений мог показывать текущий worktree как `shared`, хотя тот же объект из canonical root уже выглядел `local`.

Это были не независимые косметические баги, а остатки одного governance drift: readiness и ownership всё ещё зависели от контекстных прокси-сигналов после bootstrap.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `bash scripts/query-lessons.sh --tag worktree --tag phase-a --tag beads --tag command-worktree`

**Релевантные прошлые RCA/уроки:**
1. `docs/rca/2026-04-15-worktree-governance-helpers-trusted-contextual-beads-state.md` — уже требовал canonical ownership/runtime evidence вместо proxy-state.
2. `docs/rca/2026-03-09-command-worktree-followup-uat.md` — уже требовал честного cross-worktree UX и отсутствия observer-dependent ambiguity.

**Что могло быть упущено без этой сверки:**
- можно было бы снова принять `worktree-ready doctor` из canonical root за достаточное доказательство readiness и пропустить, что plain `bd status` в новом worktree ещё не готов;
- можно было бы считать, что canonical-root fix в `worktree-ready` автоматически чинит и direct `./bin/bd worktree list`, хотя это другой ownership layer.

**Что в текущем инциденте действительно новое:**
- readiness gap жил именно между завершением bootstrap/import path и первым usable plain `bd status`, то есть проблема была в честном completion contract Phase A;
- canonical-root routing нужно было спустить не только в `worktree-ready`, но и в прямой repo wrapper `bin/bd` через resolver decision для `worktree list`.

## Evidence

Подтверждённые факты:

1. Во fresh `moltinger-th0e` worktree один из первых `bd status` дал `failed to get statistics: dial tcp 127.0.0.1:55007: connect: connection refused`, а повторный вызов позже стал зелёным.
2. До фикса `bd worktree list` зависел от cwd:
   - из canonical root новый worktree выглядел `local`;
   - из самого dedicated worktree тот же объект мог выглядеть `shared`.
3. После source fix:
   - `bash tests/unit/test_worktree_phase_a.sh` → `10/10 PASS`
   - `bash tests/unit/test_bd_dispatch.sh` → `29/29 PASS`
4. Живой smoke после фикса:
   - `./bin/bd worktree list` из `moltinger-th0e` показывает согласованный `local`;
   - `./bin/bd status` из `moltinger-th0e` проходит успешно.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему fresh governed worktree мог считаться готовым слишком рано? | Потому что Phase A завершался после bootstrap/import, не дожидаясь успешного plain `bd status` в новом runtime. | live repro в `moltinger-th0e`, новый unit test `test_phase_a_create_waits_for_runtime_status_after_bootstrap` |
| 2 | Почему plain `bd status` ещё был неготов? | Потому что локальный named runtime после bootstrap мог кратковременно поднимать сервис/сокет позже, чем wrapper уже печатал success. | transient `connect: connection refused` сразу после create |
| 3 | Почему ownership list всё ещё зависел от cwd? | Потому что direct repo wrapper не canonicalize-ил `worktree list` к canonical root, и команда наследовала observer context. | live repro `bd worktree list` from root vs dedicated worktree |
| 4 | Почему это не было закрыто предыдущим fix-пакетом? | Потому что прошлый пакет чинил higher-level helper path (`worktree-ready`), но не прямой `bin/bd` dispatch и не honest completion gate в Phase A. | diff scope до `th0e`; новый fix затронул `bin/bd`, `beads-resolve-db.sh`, `worktree-phase-a.sh` |
| 5 | Почему проблема проявилась как governance drift, а не просто shell timing bug? | Потому что repo-owned tooling всё ещё принимал промежуточный post-bootstrap state за достаточную истину и не унифицировал direct wrapper path с canonical ownership contract. | combined fix across resolver + wrapper + Phase A readiness probe |

## Корневая причина

Корневая причина — неполное доведение canonical governance contract до всех owning layers:

- `worktree-phase-a.sh` считал bootstrap/import достаточным критерием готовности, хотя операторский контракт требует usable plain `bd status`;
- `beads-resolve-db.sh`/`bin/bd` не применяли canonical-root routing к `worktree list`, поэтому direct wrapper по-прежнему зависел от cwd.

Иными словами, higher-level helper уже знал правильную модель, но lower-level repo-owned entrypoints ещё не были доведены до той же истины.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | fixes находятся в repo-owned shell helpers/tests |
| □ Systemic? | yes | defect span-ил readiness gate и direct wrapper dispatch |
| □ Preventable? | yes | через explicit final plain-status gate и canonical-root dispatch regression coverage |

## Принятые меры

1. **Немедленное исправление**
   - `scripts/worktree-phase-a.sh` теперь после bootstrap/import ждёт успешный plain `bd status` с bounded retry loop и fail-closed error, если runtime так и не стал ready.
   - `scripts/beads-resolve-db.sh` получил отдельное решение `pass_through_canonical_root_readonly` для `worktree list`.
   - `bin/bd` теперь исполняет этот путь через `cd "${BEADS_RESOLVE_CANONICAL_ROOT}"` и direct system `bd`.
2. **Предотвращение**
   - добавлен unit test на post-bootstrap readiness wait;
   - добавлен unit test, что dedicated-worktree `bd worktree list` canonicalize-ится к root и не pin-ит local DB.
3. **Документация**
   - этот RCA добавлен в `docs/rca/`;
   - lessons index будет пересобран после landing пакета.

## Связанные обновления

- [x] Тесты добавлены
- [x] Индекс уроков будет пересобран
- [ ] Новый rule file не понадобился: дефект закрыт в owning helper layer

## Уроки

1. **Phase A не имеет права возвращать success раньше plain operator path.** Bootstrap/import недостаточны, если первый обычный `bd status` ещё не usable.
2. **Canonical-root routing нужно спускать до direct entrypoint.** Исправление только в orchestration helper-е не закрывает прямой `./bin/bd` path.
3. **Observer-dependent команды должны canonicalize-иться явно.** Если semantic truth зависит от cwd, repo wrapper обязан зафиксировать контекст сам.
4. **Readiness и ownership regression coverage должны жить рядом с owning layer.** Иначе один слой будет “починен”, а соседний entrypoint продолжит врать оператору.
