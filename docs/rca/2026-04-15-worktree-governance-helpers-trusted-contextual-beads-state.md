---
title: "Worktree governance helpers trusted contextual Beads state instead of canonical ownership/runtime evidence"
date: 2026-04-15
severity: P1
category: process
tags: [worktree, beads, command-worktree, phase-a, runtime, governance, rca]
root_cause: "Repo-owned worktree governance helpers still trusted contextual proxy signals such as stale tracked `.beads/issues.jsonl`, current-cwd `bd worktree list` output, noisy `bd status`, and unsafe empty-array rendering, instead of canonical owner-layer import sources, direct runtime probes, and fail-closed renderer contracts."
---

# RCA: Worktree governance helpers trusted contextual Beads state instead of canonical ownership/runtime evidence

**Дата:** 2026-04-15  
**Статус:** Resolved in source  
**Влияние:** worktree/branch governance repeatedly produced false blockers, misleading ownership state, and unsafe cleanup/readiness decisions  
**Контекст:** beads `moltinger-crq6`, repo-owned `command-worktree` / `worktree-ready` / `worktree-phase-a` / Beads localization stack

## Ошибка

Ветка `moltinger-crq6` была заведена после серии governance-аномалий вокруг worktree lifecycle:

- fresh managed Phase A worktree не видел только что созданный canonical Beads issue;
- `beads-worktree-localize --check` и `worktree-ready doctor` могли ставить `runtime_bootstrap_required`, хотя live backlog уже открывался нормально;
- `worktree-ready plan/cleanup --format env` логически успешно завершались, но падали в финальном render path на пустых массивах под `set -u`;
- `bd worktree list --json` в non-main cwd контекстно помечал текущий worktree как `shared`, и repo-owned helper мог принять эту ложь за реальное ownership состояние.

Итог: инструменты branch/worktree governance выглядели “починенными” по отдельности, но в реальном цепочечном использовании снова срывались на source-contract drift.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag worktree`
- `./scripts/query-lessons.sh --tag beads`
- `./scripts/query-lessons.sh --tag topology`

**Релевантные прошлые RCA/уроки:**
1. `docs/rca/2026-03-26-beads-worktree-localize-used-stale-bootstrap-contract.md`  
   уже фиксировал, что owner-layer localize не должен materialize-ить stale runtime shell из неверного bootstrap path.
2. `docs/rca/2026-03-26-worktree-create-misread-local-ownership-as-runtime-ready.md`  
   уже фиксировал, что ownership и runtime health нужно проверять отдельно.
3. `docs/rca/2026-03-29-runtime-only-repair-contract-still-pointed-at-raw-bootstrap.md`  
   уже требовал не доверять bare CLI repair/noisy probes без managed helper path.
4. `docs/rca/2026-03-08-topology-child-worktree-identity-drift.md`  
   уже показывал, что worktree identity/state не должны зависеть от observer context.

**Что могло быть упущено без этой сверки:**
- можно было бы снова “починить” только поверхностный Phase A слой и оставить stale/localize drift в owner-layer helper-е;
- можно было бы принять `bd worktree list` из текущего cwd за truth и снова строить cleanup/doctor решения на ложном `shared`.

**Что в текущем инциденте действительно новое:**
- truthful canonical issue import пришлось пронести глубже, в `beads-worktree-localize` и `beads-resolve-db`, а не оставлять только в Phase A wrapper-е;
- `bd worktree list` оказался observer-dependent не только для main, но и для любого non-main cwd, поэтому repo-owned helper должен брать его из canonical root;
- renderer path сам стал blocker-ом: корректное решение ломалось в финальном env output из-за empty-array contract under `set -u`.

## Evidence

Подтверждённые факты из live repo/tooling:

1. fresh Phase A worktree из текущего repo initially не видел freshly created issue, пока canonical backlog не импортировался явно из live export;
2. `bash tests/unit/test_bd_dispatch.sh` после owner-layer fix проходит `28/28 PASS`;
3. `bash tests/unit/test_worktree_phase_a.sh` после canonical export plumbing проходит `10/10 PASS`;
4. `bash tests/unit/test_worktree_ready.sh` сначала падал на:
   - `items[@]: unbound variable` в env renderer;
   - false-negative readiness/cleanup paths;
5. отдельный live repro показал, что `bd worktree list --json` зависит от cwd:
   - из canonical `main` current feature worktree выглядел `local`;
   - из самого feature worktree тот же path выглядел `shared`;
6. после canonical-root sourcing и regression test `worktree-ready` проходит `43/43 PASS`.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему worktree governance продолжал давать ложные blocker-ы и неоднозначный cleanup state? | Потому что helper stack опирался на proxy-сигналы, которые менялись от слоя к слою и от observer context. | fresh Phase A repro, `bd worktree list --json` from different cwd |
| 2 | Почему proxy-сигналы были ненадёжными? | Потому что разные helper-ы брали разные “истины”: stale tracked `.beads/issues.jsonl`, noisy `bd status`, current-cwd `bd worktree list`, shell-render side effects under `set -u`. | unit failures, manual repro `items[@]: unbound variable`, contextual `shared` output |
| 3 | Почему это не было поймано раньше? | Потому что часть старых fixes закрывала только отдельный слой (например, Phase A), но не переносила truthful source contract в owner-layer helpers. | `worktree-phase-a.sh` had canonical export, but `beads-worktree-localize.sh` still defaulted to stale tracked foundation |
| 4 | Почему helper-ы снова путали ownership и runtime state? | Потому что repo stack по-прежнему принимал “что сказал ближайший probe/list” за truth, вместо приоритета canonical/root evidence + direct runtime proof. | `bd info` healthy while `bd status` noisy; `bd worktree list` current-cwd false-positive |
| 5 | Почему проблема стала системной, а не точечной? | Потому что contract drift жил сразу в нескольких owning layers: Phase A, localize, resolver, readiness helper и renderer. Пока они не были выровнены вместе, любой один частичный fix снова оставлял дыру. | combined fixes across `worktree-phase-a.sh`, `beads-worktree-localize.sh`, `beads-resolve-db.sh`, `worktree-ready.sh` and unit suites |

## Корневая причина

Корневая причина была не в одном конкретном shell баге, а в общем design drift worktree governance stack:

- owner-layer materialization всё ещё мог брать stale source вместо live canonical backlog;
- runtime health мог трактоваться через шумный probe, хотя direct `bd info` уже давал truth;
- readiness helper мог принимать observer-dependent `bd worktree list` за истинное ownership состояние;
- final env renderer не был fail-closed для пустых массивов under `set -u`.

Иными словами, stack доверял contextual proxy-state, а не canonical ownership/runtime evidence.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | fixes лежат в repo-owned shell helpers/tests |
| □ Systemic? | yes | defect span-ил несколько helper layers |
| □ Preventable? | yes | через owner-layer source-of-truth, canonical-root probing и regression coverage |

## Принятые меры

1. **Немедленное исправление**
   - `scripts/beads-worktree-localize.sh` получил explicit `--import-source` и теперь materialize-ит local runtime из truthful canonical export, если он передан.
   - `scripts/beads-resolve-db.sh localize` выровнен с тем же explicit import-source contract.
   - `scripts/worktree-phase-a.sh` теперь не только экспортирует live canonical backlog, но и пробрасывает этот source в owner-layer localization.
   - `scripts/worktree-ready.sh`:
     - использует canonical root для `bd worktree list --json`;
     - больше не падает на empty env arrays under `set -u`.
2. **Предотвращение**
   - добавлены regression tests:
     - explicit import source wins over stale tracked foundation;
     - fresh Phase A worktree sees live canonical backlog;
     - `worktree-ready` canonical-root `bd` lookup does not inherit current-cwd false `shared`;
     - env renderer stays safe on empty arrays.
3. **Документация**
   - этот RCA зафиксирован;
   - lessons index будет пересобран после landing пакета.

## Связанные обновления

- [x] Тесты добавлены
- [x] Индекс уроков будет пересобран
- [ ] Новый rule file не понадобился: контракт ужесточён в owning helpers и regression suites

## Уроки

1. **Owner-layer truth важнее wrapper-local truth.** Если truthful source живёт только в Phase A wrapper-е, drift обязательно вернётся через direct localize/repair path.
2. **`bd worktree list` нельзя читать буквально из произвольного cwd.** Для repo-owned governance helper-ов observer context должен быть canonicalized.
3. **Renderer тоже часть safety contract.** Если helper логически уже решил задачу, но падает на финальной сериализации, для оператора это всё ещё broken workflow.
4. **Worktree governance требует связанного покрытия.** Phase A, localize, resolver, readiness и cleanup нельзя чинить как независимые shell snippets.
