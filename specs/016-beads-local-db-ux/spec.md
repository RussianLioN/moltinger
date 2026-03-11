# Feature Specification: UX-Safe Beads Local Ownership

**Feature Branch**: `016-beads-local-db-ux`
**Created**: 2026-03-12
**Status**: Draft
**Input**: User description: "Запусти Spekit workflow для feature `016-beads-local-db-ux`.

Нужно спроектировать и затем реализовать UX-safe исправление для работы с Beads в этом репо.

Проблема:
- сейчас уже есть безопасный временный guardrail через `scripts/bd-local.sh`
- но это плохой UX, потому что пользователь не должен вручную помнить, чем запускать команды: `bd` или `bd-local`
- корневая причина в том, что в Codex/App-сессиях `direnv` не гарантированно загружает `BEADS_DB`, и голый `bd` может тихо уйти в canonical root tracker
- раньше уже был исправлен redirect leakage path; возвращаться к shared redirect нельзя

Что нужно получить:
- Spekit spec / plan / tasks для решения, где пользователь не должен вручную выбирать wrapper
- решение должно сохранять worktree-local ownership для Beads
- решение должно быть fail-closed: лучше остановка с понятной ошибкой, чем тихая запись в root
- решение должно быть UX-friendly для обычной работы агента и пользователя
- нужно явно отделить:
  - intentional ownership model по worktree
  - migration / compatibility для уже существующих worktree
  - residual root cleanup, который не должен смешиваться с этой задачей

Ограничения:
- не чинить root `main` вручную
- не использовать blind stash / reset / pull hacks
- не ломать существующие worktree и branch
- не возвращать raw `bd worktree create`
- учитывать, что `direnv` может быть недоступен или не одобрен
- docs, tests и guardrails обязательны"

## Executive Summary

Внутри этого репо работа с Beads должна стать однозначной: пользователь и агент запускают обычный `bd`, а система сама либо безопасно привязывает команду к worktree-local tracker, либо fail-closed останавливает выполнение с понятной ошибкой и точным recovery path. Пользователь больше не должен помнить отдельный wrapper, состояние `direnv` или исторические recovery-команды, чтобы не записать данные в canonical root tracker.

Фича отделяет три разных слоя, которые нельзя смешивать: intentional ownership model по worktree, compatibility/migration для уже открытых worktree, и residual root cleanup как отдельный follow-up поток. Основная ценность MVP состоит не в ручном восстановлении root состояния, а в том, чтобы plain `bd` внутри dedicated worktree больше не мог молча уйти в чужой tracker.

## Assumptions

- Dedicated worktree для feature branch остается authoritative местом работы, как уже закреплено в git-topology и Codex operating model.
- В каждой рабочей линии должен существовать worktree-local Beads state, который можно определить без обязательной зависимости от `direnv`.
- Исторические redirected/shared схемы считаются legacy compatibility состояниями и не должны возвращаться как нормальный steady state.
- Root `main` и residual cleanup остаются отдельной operational responsibility; эта фича может только защищать от новых silent fallback и направлять в отдельный cleanup path.
- Explicit read-only troubleshooting flows могут существовать отдельно, но mutating поведение plain `bd` внутри dedicated worktree не должно зависеть от неявного fallback.

## Explicit Product Answers

### Какой должен быть конечный UX для пользователя

Пользователь и агент внутри этого репо используют обычный `bd` как единственный default entrypoint для ежедневной работы. Если worktree ownership безопасно определен, команда выполняется без дополнительного выбора wrapper. Если ownership не подтвержден, команда останавливается до мутации и сразу сообщает, что именно не так и как это исправить.

### Как plain `bd` должен вести себя внутри этого репо

В dedicated worktree plain `bd` должен работать только с tracker, принадлежащим этой worktree. В canonical root plain `bd` должен оставаться отдельным root-scoped поведением и не должен притворяться worktree-local командой. Если dedicated worktree находится в legacy, missing или ambiguous ownership state, plain `bd` должен fail-closed до записи.

### Где должен жить source of truth для выбора local Beads DB

Source of truth должен жить в repo-tracked, worktree-local ownership contract, доступном самой worktree даже без загруженного `direnv`. Переменные окружения, shell startup и другие convenience-mechanisms могут лишь отражать этот contract, но не заменять его.

### Как избежать silent fallback в canonical root

Любая mutating-команда plain `bd` в dedicated worktree должна сначала проверять ownership resolution и запрещать выполнение, если вместо worktree-local tracker обнаружен missing, redirected, unresolved или root-fallback state. Никакой неявный переход в canonical root tracker не допускается.

### Как мигрировать уже открытые worktree без ручной боли

Система должна auto-detect legacy worktree states и предлагать один managed compatibility path, который локализует ownership in place там, где это безопасно и однозначно. Пользователь не должен вручную выбирать между `bd`, `bd-local`, redirect recovery и root cleanup. Ручные шаги допустимы только для конфликтных или поврежденных состояний и должны быть минимальными и точными.

### Какие проверки и тесты должны блокировать регресс

Регресс должен блокироваться тестами и статическими guardrails, которые проверяют: plain `bd` не уходит в root молча, dedicated worktree fail-closed останавливается при missing/legacy ownership, docs не требуют ручного wrapper выбора, managed worktree UX не возвращает raw `bd worktree create`, а compatibility flows не смешиваются с residual root cleanup.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plain `bd` Works Safely In A Dedicated Worktree (Priority: P1)

Как пользователь или агент в dedicated worktree,
Я хочу запускать обычный `bd` без выбора специального wrapper,
Чтобы работать с Beads безопасно и не думать о скрытой маршрутизации tracker.

**Why this priority**: Это главный UX и safety outcome. Пока пользователь обязан помнить второй entrypoint, система остается хрупкой и допускает silent fallback в canonical root tracker.

**Independent Test**: Открыть dedicated worktree без подтвержденного `direnv`, выполнить типичные команды plain `bd`, и убедиться, что они либо используют local ownership, либо fail-closed останавливаются до мутации с понятным recovery path.

**Acceptance Scenarios**:

1. **Given** пользователь находится внутри dedicated worktree с валидным local ownership state, **When** он запускает plain `bd` для обычной работы, **Then** команда выполняется против tracker этой worktree без выбора wrapper.
2. **Given** пользователь находится внутри dedicated worktree, но ownership resolution небезопасен, **When** он запускает mutating plain `bd` command, **Then** выполнение останавливается до записи и сообщает точную причину блокировки.
3. **Given** `direnv` недоступен, не одобрен или не загрузил `BEADS_DB`, **When** пользователь запускает plain `bd`, **Then** поведение все равно остается детерминированным и не уходит молча в canonical root tracker.

---

### User Story 2 - Existing Worktrees Migrate Without Wrapper Lore (Priority: P1)

Как пользователь, возвращающийся в уже существующий worktree,
Я хочу, чтобы система сама определяла legacy compatibility state и давала managed recovery path,
Чтобы мне не приходилось помнить старые обходы, redirect схемы или отдельные helper-команды.

**Why this priority**: Даже идеальный новый UX не решает проблему, если уже открытые worktree продолжают требовать ручной памяти о legacy flow и создают риск записей в чужой tracker.

**Independent Test**: Подготовить несколько старых worktree states и убедиться, что система либо автоматически локализует ownership безопасным способом, либо блокирует работу с одной понятной recovery-инструкцией без ручного выбора wrapper.

**Acceptance Scenarios**:

1. **Given** worktree находится в legacy redirected или partially initialized state, **When** пользователь начинает работу через стандартный repo-local flow, **Then** система выявляет compatibility state и направляет в единый managed migration path.
2. **Given** existing worktree можно локализовать без неоднозначности, **When** запускается compatibility flow, **Then** migration проходит in place без поломки branch или worktree identity.
3. **Given** existing worktree поврежден или конфликтует с ownership contract, **When** запускается compatibility flow, **Then** система блокирует дальнейшую работу с точным сообщением, а не маскирует проблему через fallback.

---

### User Story 3 - Root Cleanup Stays Separate From Ownership Safety (Priority: P2)

Как maintainer этого репо,
Я хочу, чтобы root cleanup оставался отдельным потоком,
Чтобы ownership-safe UX fix не смешивался с ручной санацией canonical root и не создавал ложное впечатление, что root уже исправлен.

**Why this priority**: Смешивание safety-fix и root cleanup повышает риск разрушительных действий и путает фактический scope работы.

**Independent Test**: Пройти сценарий feature-worktree migration и убедиться, что фича не требует ручного root repair, не модифицирует root `main` в обход отдельного workflow и явно маркирует residual cleanup как вне scope текущего change set.

**Acceptance Scenarios**:

1. **Given** canonical root содержит residual cleanup work, **When** внедряется ownership-safe UX fix, **Then** dedicated worktree behavior исправляется без ручного восстановления root `main`.
2. **Given** compatibility flow обнаруживает root-related residue, **When** он сообщает результат, **Then** root cleanup обозначается как отдельный follow-up path, а не как часть обычного dedicated-worktree migration.
3. **Given** пользователь работает только в dedicated worktree, **When** он использует plain `bd`, **Then** корректность dedicated ownership не зависит от того, закрыт ли уже residual root cleanup.

---

### Edge Cases

- Что происходит, если `direnv` отсутствует, не одобрен или не может загрузить нужное окружение?
- Что происходит, если dedicated worktree содержит local `.beads` foundation files, но ownership contract считается неполным или устаревшим?
- Как система ведет себя, если обнаружен legacy redirected state из старой recovery-схемы?
- Что происходит, если пользователь запускает plain `bd` из unexpected context, где worktree ownership нельзя безопасно определить?
- Как система разделяет compatibility migration существующей worktree и residual root cleanup, если наблюдаются оба сигнала сразу?
- Что происходит, если документация или managed helper снова начинают подсказывать пользователю raw `bd worktree create` или ручной wrapper choice?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Система ДОЛЖНА сделать plain `bd` единственным default repo-local UX для ежедневной Beads-работы в dedicated worktree.
- **FR-002**: Система ДОЛЖНА сохранять intentional worktree-local ownership model для Beads и не допускать тихого перехода dedicated worktree в canonical root tracker.
- **FR-003**: Source of truth для выбора worktree-local tracker ДОЛЖЕН жить в repo-tracked worktree-local contract, который не зависит исключительно от `direnv`.
- **FR-004**: Mutating plain `bd` commands внутри dedicated worktree ДОЛЖНЫ валидировать ownership resolution до начала записи.
- **FR-005**: Если ownership resolution возвращает missing, redirected, unresolved, legacy-incompatible или root-fallback state, система ДОЛЖНА fail-closed остановить команду до мутации.
- **FR-006**: Fail-closed сообщение ДОЛЖНО явно говорить, что обнаружено: missing foundation, legacy redirect, unresolved ownership, unsupported context или другой блокирующий state.
- **FR-007**: Система НЕ ДОЛЖНА требовать от пользователя или агента вручную выбирать между `bd` и отдельным repo-local wrapper как нормальным способом ежедневной работы.
- **FR-008**: Решение ДОЛЖНО работать, даже если `direnv` недоступен, не одобрен или не загружен в текущую Codex/App-сессию.
- **FR-009**: `direnv` и другие environment conveniences МОГУТ ускорять happy path, но НЕ ДОЛЖНЫ быть единственным механизмом, от которого зависит безопасность plain `bd`.
- **FR-010**: Система ДОЛЖНА поддерживать managed compatibility path для уже существующих worktree с legacy ownership states.
- **FR-011**: Compatibility path ДОЛЖЕН auto-detect legacy/partial states и по возможности локализовать ownership in place без поломки branch или worktree identity.
- **FR-012**: Если safe in-place migration невозможна или неоднозначна, compatibility path ДОЛЖЕН останавливаться с точной инструкцией вместо silent fallback или частичного ремонта.
- **FR-013**: Compatibility/migration flow НЕ ДОЛЖЕН требовать от пользователя ручного знания redirect-схем, wrapper history или canonical root tracker details.
- **FR-014**: Система ДОЛЖНА явно отделять intentional ownership model по worktree от compatibility migration для старых worktree.
- **FR-015**: Система ДОЛЖНА явно отделять compatibility migration для старых worktree от residual root cleanup и НЕ ДОЛЖНА считать root cleanup обязательной частью текущей фичи.
- **FR-016**: Эта фича НЕ ДОЛЖНА вручную чинить root `main` и НЕ ДОЛЖНА маскировать root residue как завершенную cleanup-работу.
- **FR-017**: Managed user-facing flows и docs НЕ ДОЛЖНЫ возвращать raw `bd worktree create` как normal-path совет пользователю.
- **FR-018**: Managed flows и docs ДОЛЖНЫ показывать единый обычный user path для repo-local Beads usage вместо competing instructions.
- **FR-019**: Система ДОЛЖНА сохранять совместимость с существующими branch/worktree и НЕ ДОЛЖНА ломать их identity или требовать blind stash/reset/pull hacks.
- **FR-020**: Любая migration или repair-операция ДОЛЖНА быть bounded, predictable и idempotent для уже открытых worktree.
- **FR-021**: Read-only troubleshooting или explicit fallback flows МОГУТ существовать отдельно, но НЕ ДОЛЖНЫ быть неявным поведением mutating plain `bd` commands.
- **FR-022**: Docs, tests и static guardrails ДОЛЖНЫ быть обновлены как обязательная часть решения.
- **FR-023**: Regression suite ДОЛЖЕН блокировать повторное появление silent fallback в canonical root tracker для dedicated worktree.
- **FR-024**: Regression suite ДОЛЖЕН блокировать повторное появление docs/examples, где пользователь обязан вручную выбирать wrapper для обычной repo-local работы.
- **FR-025**: Regression suite ДОЛЖЕН блокировать повторное появление user-facing советов использовать raw `bd worktree create` как обход dedicated-worktree UX.
- **FR-026**: Система ДОЛЖНА различать ownership-safety failure и residual root-cleanup reminder, чтобы пользователю было понятно, что блокирует текущую работу прямо сейчас.

### Key Entities

- **Beads Ownership Contract**: Repo-tracked worktree-local agreement, который определяет, какой tracker принадлежит текущей worktree и как это безопасно проверить.
- **Beads Command Resolution**: Результат проверки plain `bd` в текущем контексте, включающий safe-local, blocked-missing, blocked-legacy, blocked-root-fallback и другие пользовательские состояния.
- **Compatibility Migration State**: Состояние существующей worktree, показывающее, нужно ли локализовать ownership, остановиться из-за legacy residue или подтвердить, что worktree уже безопасна.
- **Residual Root Cleanup Item**: Отдельный root-scoped follow-up, который может существовать параллельно, но не является частью normal dedicated-worktree ownership flow.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: В 100% покрытых dedicated-worktree сценариев mutating plain `bd` либо использует worktree-local ownership, либо fail-closed останавливается до записи.
- **SC-002**: В 100% покрытых сценариев dedicated worktree не выполняет silent fallback в canonical root tracker.
- **SC-003**: Обычный пользовательский quickstart внутри этого репо использует один default Beads entrypoint и не требует помнить `bd-local` или другой специальный wrapper.
- **SC-004**: Не менее 90% legacy worktree scenarios восстанавливаются через единый managed compatibility path без ручного изучения исторических recovery steps.
- **SC-005**: В 100% покрытых ambiguous или damaged worktree scenarios система выдает понятную blocking error и не выполняет частичную мутацию tracker state.
- **SC-006**: В 100% покрытых doc/command validation scenarios пользователю не предлагается raw `bd worktree create` как normal-path решение для daily work.
- **SC-007**: Root cleanup остается явно отделенным: ни один acceptance scenario этой фичи не требует ручного исправления root `main` для подтверждения dedicated-worktree safety.
- **SC-008**: Regression tests и static guardrails ловят повторное появление silent fallback, wrapper-choice UX drift и смешение ownership migration с residual root cleanup.
