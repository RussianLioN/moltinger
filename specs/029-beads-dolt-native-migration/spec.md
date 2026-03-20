# Feature Specification: Beads Dolt-Native Migration

**Feature Branch**: `029-beads-dolt-native-migration`  
**Created**: 2026-03-20  
**Status**: Draft  
**Input**: User description: "А раз уже официальный beads уже ушел дальше, давай мы проанализируем новшество, изучим issues на эту тему и внедрим это новшество в наш проект, сразу адаптировав его под новый beads. Что на это сказала бы группа релевантных экспертов? Собери /consilium из релевантных задаче экспертов и прими консолидированное решение"

## Executive Summary

Официальный `beads` сместился в Dolt-native модель хранения и синхронизации, а tracked JSONL в актуальной документации выглядит скорее как export/backup/portability слой, чем как primary sync transport. В этом репозитории при этом еще живут repo-local wrapper-пути, hooks, operator guidance и multi-worktree практики, завязанные на legacy `bd sync` и tracked `.beads/issues.jsonl`.

Эта фича должна адаптировать проект к новому `beads`, но не через risky одномоментный cutover. Решение должно дать staged migration path: сначала зафиксировать целевой Dolt-native contract и обнаружить legacy surfaces, затем перевести один pilot worktree без mixed mode, затем выполнить controlled rollout и иметь отдельный rollback без потери issue-state и без неявного возврата к старому JSONL-driven workflow.

## Assumptions

- Целевым направлением считается текущая официальная upstream модель `beads`, где Dolt-native storage/sync является primary path.
- Локально установленный `bd` и repo-local workflow могут отставать от latest upstream semantics, поэтому миграция должна быть staged и evidence-driven.
- Mixed mode, в котором часть worktree живет по legacy JSONL path, а часть по новому Dolt-native path, считается недопустимым steady state.
- Existing issues and operator history должны сохраняться или явно переноситься; миграция не может основываться на молчаливом удалении legacy data.
- Текущий RCA-поток по `.beads/issues.jsonl` остается отдельной стабилизацией legacy path и не должен растворяться внутри migration feature.

## Explicit Product Answers

### Что считается целевым состоянием

Целевое состояние — проект работает на одном явном Beads contract, совместимом с текущим upstream direction: issue-state больше не зависит от tracked `.beads/issues.jsonl` как primary source of truth, а routine operator flow, docs и repo-local tooling больше не вводят пользователей в legacy JSONL mental model.

### Почему нельзя делать мгновенный cutover

Мгновенный cutover рискован, потому что репозиторий уже содержит repo-local bootstrap, hooks, docs и review-практики, завязанные на legacy behavior. Без inventory, pilot и rollback это создаст двойной source of truth и новые drift-сценарии вместо устранения старых.

### Что считается допустимой промежуточной стратегией

Допустимой считается только staged migration с report-only compatibility layer, явным readiness gate, pilot worktree и последующим controlled rollout. Недопустимо оставлять проект в долгоживущем mixed mode.

### Что должно случиться с tracked `.beads/issues.jsonl`

Tracked `.beads/issues.jsonl` больше не должен проектироваться как долгосрочный primary sync path. Migration должна либо безопасно вывести его из truth flow, либо подчинить его новой роли export/backup artifact с явным ownership и без участия в everyday sync reasoning.

### Что должно стать заменой привычному review surface

Migration обязана определить новый reviewable operator surface для issue-state, чтобы проект не потерял наблюдаемость и контролируемость при уходе от JSONL-first workflow. Это может быть другой artifact, отчет, команда обзора или иной стабильный path, но замена должна быть явной и понятной.

### Как должны быть разделены migration и rollback

Migration должен идти по stage-gates и никогда не смешиваться с rollback внутри одной команды или одного implicit workflow. Rollback должен откатывать новый contract и operator path без потери snapshots, migration evidence и возможности повторно оценить readiness.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Legacy Surfaces Are Inventoried Before Cutover (Priority: P1)

Как operator репозитория, я хочу получить полный и reviewable inventory всех legacy `beads` surfaces, завязанных на `bd sync`, tracked `.beads/issues.jsonl`, repo-local wrappers, hooks и docs, чтобы не начать migration вслепую и не оставить hidden mixed mode.

**Why this priority**: Это минимально полезный результат. Пока проект не знает, какие именно поверхности живут по legacy model, любой cutover будет угадыванием.

**Independent Test**: На текущем репозитории migration workflow выдает deterministic report, который перечисляет legacy surfaces, классифицирует их как `must-migrate`, `can-bridge`, `can-remove` или `already-compatible`, и блокирует cutover при unresolved critical items.

**Acceptance Scenarios**:

1. **Given** репозиторий содержит repo-local `beads` wrappers, hooks, docs и tracked artifacts, **When** operator запускает migration inventory, **Then** он получает полный список surfaces и их compatibility status.
2. **Given** в репозитории найдено использование legacy JSONL-first workflow, **When** readiness report строится, **Then** такие surfaces помечаются как blockers для full cutover.
3. **Given** inventory запускается повторно без изменения репозитория, **When** report формируется снова, **Then** ключевые classifications и readiness verdict остаются одинаковыми.

---

### User Story 2 - One Pilot Worktree Uses The New Beads Contract Safely (Priority: P2)

Как maintainer, я хочу перевести один pilot worktree на новый Beads contract и проверить обычный issue lifecycle без зависимости от legacy JSONL path, чтобы доказать совместимость нового режима до массового rollout.

**Why this priority**: Pilot нужен, чтобы доказать реальный operational path, а не ограничиться docs-исследованием и общими обещаниями.

**Independent Test**: В одном isolated worktree оператор проходит create/update/close/sync workflow по новому contract, не получает legacy JSONL drift и не вызывает repo-local surfaces, помеченные как removed or incompatible.

**Acceptance Scenarios**:

1. **Given** pilot worktree прошел readiness checks, **When** operator выполняет типичный issue lifecycle по новому contract, **Then** workflow завершается без возврата к legacy JSONL-first behavior.
2. **Given** operator случайно вызывает legacy-only surface в pilot mode, **When** compatibility layer перехватывает это, **Then** система блокирует или перенаправляет действие с явным объяснением.
3. **Given** pilot workflow отрабатывает успешно, **When** review проводится после цикла, **Then** проект имеет новый понятный operator/review surface вместо старого JSONL-first diff reasoning.

---

### User Story 3 - Remaining Worktrees Cut Over With Rollout And Rollback (Priority: P3)

Как platform owner, я хочу перевести остальные worktree на новый Beads contract поэтапно и иметь отдельный rollback path, чтобы адаптация проекта к upstream прошла без потери issues, без mixed mode и без скрытого operational drift.

**Why this priority**: Ценность migration появляется только тогда, когда новый contract можно применить ко всему проекту, а не только к pilot worktree.

**Independent Test**: На наборе current worktrees оператор проходит report-only, pilot-verified rollout, controlled cutover и documented rollback, сохраняя issue-state consistency и не оставляя legacy-only workflow в active use.

**Acceptance Scenarios**:

1. **Given** pilot завершен успешно и rollout prerequisites выполнены, **When** controlled cutover включается для remaining worktrees, **Then** проект переходит на один новый contract без mixed mode.
2. **Given** отдельная worktree не готова к cutover, **When** rollout reaches it, **Then** она остается blocked с явным reason code, а не переходит частично.
3. **Given** после частичного rollout требуется откат, **When** operator выполняет rollback plan, **Then** новый contract отключается контролируемо и issue-state остается согласованным и обозримым.

### Edge Cases

- Что происходит, если pilot worktree совместим с новым `beads`, а sibling worktree все еще использует legacy `bd sync` и tracked `.beads/issues.jsonl`?
- Как migration ведет себя, если repo-local docs и hooks уже не совпадают с фактическим runtime mode локально установленного `bd`?
- Что происходит, если новый upstream contract требует upgrade `bd`, а часть worktree или агентов запускается со старой версией?
- Как migration различает допустимый export/backup JSONL artifact и запрещенный возврат к JSONL-first operational workflow?
- Что происходит, если rollback нужен после того, как часть docs и agent guidance уже обновлена под новый contract?
- Что происходит, если operator пытается cutover’ить canonical root и sibling worktrees одновременно без pilot verification?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Система ДОЛЖНА зафиксировать один целевой repo-level Beads contract, совместимый с текущим официальным upstream direction.
- **FR-002**: Migration design ДОЛЖЕН явно различать target contract, legacy contract и временный compatibility layer.
- **FR-003**: Система ДОЛЖНА построить полный inventory repo-local surfaces, завязанных на `bd sync`, tracked `.beads/issues.jsonl`, repo-local wrappers, hooks, docs и related operator workflows.
- **FR-004**: Каждый найденный surface ДОЛЖЕН быть классифицирован как минимум в одну из категорий: `must-migrate`, `can-bridge`, `can-remove`, `already-compatible`, `blocked`.
- **FR-005**: Migration plan ДОЛЖЕН определять readiness criteria до pilot cutover.
- **FR-006**: Migration plan НЕ ДОЛЖЕН допускать long-lived mixed mode между legacy JSONL-first workflow и новым Beads contract.
- **FR-007**: Compatibility layer ДОЛЖЕН обнаруживать и явно маркировать попытки использовать legacy-only surfaces после начала migration.
- **FR-008**: Pilot stage ДОЛЖЕН позволять пройти типичный issue lifecycle по новому contract в одной isolated worktree.
- **FR-009**: Pilot stage ДОЛЖЕН иметь явный success verdict и явный fail verdict до массового rollout.
- **FR-010**: Pilot stage НЕ ДОЛЖЕН silently возвращаться к legacy JSONL-first path.
- **FR-011**: Migration design ДОЛЖЕН определить новый operator-visible review surface для issue-state после ухода от JSONL-first workflow.
- **FR-012**: Новый review surface ДОЛЖЕН быть понятен для человека и агента и не должен требовать чтения скрытого внутреннего состояния Dolt без documented procedure.
- **FR-013**: Rollout plan ДОЛЖЕН включать как минимум `report-only`, `pilot`, `controlled cutover` и `post-cutover verification` stages.
- **FR-014**: Каждая worktree ДОЛЖНА проходить readiness check до cutover.
- **FR-015**: Worktree, не прошедшая readiness check, ДОЛЖНА оставаться blocked и не ДОЛЖНА переходить частично.
- **FR-016**: Rollback plan ДОЛЖЕН быть отдельным от rollout и ДОЛЖЕН включать snapshot/evidence preservation.
- **FR-017**: Rollback НЕ ДОЛЖЕН терять существующие issues, migration journals или operator evidence.
- **FR-018**: Migration design ДОЛЖЕН определить, какая судьба у tracked `.beads/issues.jsonl`: remove from truth flow, retain as export/backup artifact, or other explicitly bounded role.
- **FR-019**: Repo-local docs, AGENTS, skills и operator guidance ДОЛЖНЫ быть приведены в соответствие новому contract к моменту full cutover.
- **FR-020**: Repo-local wrappers, hooks и automation surfaces ДОЛЖНЫ быть либо удалены, либо явно адаптированы под новый contract.
- **FR-021**: Migration plan ДОЛЖЕН учитывать multi-worktree topology и branch-local workflows как first-class constraint.
- **FR-022**: Migration plan ДОЛЖЕН учитывать несовпадение между локально установленной версией `bd` и latest upstream docs/release model.
- **FR-023**: Система ДОЛЖНА предоставлять reproducible validation matrix минимум для canonical root, pilot worktree, sibling worktree, bootstrap variance и hook-enabled repo scenarios.
- **FR-024**: Full cutover НЕ ДОЛЖЕН начинаться, пока inventory, pilot verdict, docs alignment и rollback package не готовы.

### Key Entities *(include if feature involves data)*

- **BeadsTargetContract**: Явное описание целевого repo-level поведения для нового `beads`, включая storage model, operator flow и sync expectations.
- **LegacySurfaceInventoryItem**: Одна repo-local поверхность, связанная с legacy `beads` behavior, с owner, classification и required migration action.
- **MigrationReadinessReport**: Детерминированный отчет, который определяет, готов ли репозиторий или конкретная worktree к следующему stage migration.
- **PilotCutoverRun**: Проверяемый прогон нового contract в одной isolated worktree с зафиксированными действиями, outcome и fallback verdict.
- **OperatorReviewSurface**: Явно определенный способ review/inspection issue-state после ухода от JSONL-first reasoning.
- **WorktreeCutoverStatus**: Статус конкретной worktree в migration lifecycle (`report-only`, `ready`, `pilot`, `cutover`, `blocked`, `rolled-back`).
- **RollbackPackage**: Набор snapshot/evidence/instructions, достаточный для контролируемого отката migration stage.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Inventory report покрывает 100% известных repo-local `beads` surfaces, обнаруженных в code/docs/hooks/automation, и дает каждой surface explicit migration classification.
- **SC-002**: Повторный запуск inventory на неизменном репозитории дает тот же readiness verdict и те же critical blockers.
- **SC-003**: Pilot worktree проходит типичный issue lifecycle по новому contract без возврата к legacy JSONL-first operator path.
- **SC-004**: В 100% покрытых pilot scenarios compatibility layer обнаруживает вызовы legacy-only surfaces и выдает explicit guidance instead of silent fallback.
- **SC-005**: Full cutover начинается только после того, как readiness report не содержит unresolved critical blockers.
- **SC-006**: В 100% покрытых rollout scenarios ни одна worktree не остается в скрытом mixed mode между legacy и новым contract.
- **SC-007**: Rollback package позволяет отключить новый contract после pilot или partial rollout без потери issue-state evidence.
- **SC-008**: Repo-local docs and agent guidance к моменту full cutover описывают только один актуальный everyday workflow для `beads`.
