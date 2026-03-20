# Feature Specification: Deterministic Beads Issues JSONL Ownership

**Feature Branch**: `028-beads-issues-jsonl-rca`  
**Created**: 2026-03-20  
**Status**: Draft  
**Input**: User description: "Запусти Speckit workflow для отдельной задачи RCA по molt-sbt:
цель — устранить корневую причину drift/шума .beads/issues.jsonl между ворктриями.

Контекст:
- Это отдельный поток, не смешивать с GPT-5.4 primary chain.
- Branch: 028-beads-issues-jsonl-rca
- Issue: molt-sbt

Сделай Phase A Speckit:
1) /speckit.specify — feature: \"beads-issues-jsonl-rca\"
2) /speckit.plan
3) /speckit.tasks
4) /speckit.analyze

Требования к артефактам:
- Явная deterministic ownership/sync модель для Beads в multi-worktree.
- RCA с воспроизводимыми шагами и логами.
- Guardrails/проверки против nondeterministic rewrites.
- План миграции без потери существующих issues.
- Отдельный rollout + rollback.
Пока без implementation — только качественные spec/plan/tasks/analyze."

## Executive Summary

В репозитории уже зафиксированы локальный ownership для `bd`, fail-closed защита от silent root fallback и нормализация части JSONL-шума, но этого оказалось недостаточно: в отдельных manual/mixed worktree сценариях `bd sync` и связанные tracked rewrites по-прежнему могут создавать drift, noise или leakage в `.beads/issues.jsonl`. Корневая причина выглядит не как один сломанный wrapper, а как неполный multi-worktree contract: отдельно описан runtime DB ownership, отдельно tracked JSONL behavior, но нет единой детерминированной модели того, кто именно и при каких условиях имеет право переписывать branch-local `.beads/issues.jsonl`.

Эта фича должна превратить `.beads/issues.jsonl` из неоднозначного побочного эффекта в явно управляемый branch-local artifact с детерминированной ownership/sync моделью. Решение обязано: воспроизводимо доказывать источник drift, отличать semantic updates от nondeterministic rewrite noise, блокировать неоднозначные мутации до записи, мигрировать уже существующие worktree без потери issues и выкатываться по отдельному rollout/rollback плану без смешения с canonical-root cleanup.

## Assumptions

- `.beads/beads.db` остается runtime-local mutable state текущей worktree, а `.beads/issues.jsonl` остается branch-local tracked artifact, который должен быть понятен Git и review-процессу.
- Canonical root `main` не должен использоваться как неявная шина синхронизации для sibling worktree и не должен автоматически собирать их issue-state.
- Наличие локального DB ownership само по себе недостаточно, если tracked JSONL rewrites не связаны с тем же ownership contract и могут выполняться из неоднозначного контекста.
- Root cleanup, batch recovery и prefix migration остаются отдельными задачами и не должны незаметно сливаться в этот поток.
- Для этого Phase A допустимы обоснованные продуктовые предположения; implementation и фактический rollout будут происходить позже по утвержденным артефактам.

## Explicit Product Answers

### Что считается корневой проблемой

Корневая проблема состоит не только в том, куда резолвится `beads.db`, а в отсутствии единого deterministic contract для tracked `.beads/issues.jsonl` в multi-worktree среде. Из-за этого разные запускные поверхности, ручные worktree-потоки, merge/rebase path и sync-команды могут порождать rewrite-шум или leakage, который не всегда совпадает с intended owner worktree.

### Что должно стать source of truth для ownership/sync

Source of truth должен однозначно связывать текущую worktree, ее runtime DB ownership, ее branch-local `.beads/issues.jsonl` и разрешенные mutating sync paths. Любая rewrite-операция обязана сначала доказать, что текущий контекст является intended owner этого tracked artifact.

### Как должна выглядеть ежедневная работа после исправления

Обычная работа агента и пользователя по-прежнему использует plain `bd`, но mutating sync path больше не должен silently переписывать `.beads/issues.jsonl`, если ownership или sync authority неоднозначны. При безопасном состоянии sync выполняется детерминированно; при небезопасном состоянии пользователь получает blocking explanation, RCA evidence и точный recovery/migration path.

### Что считается недопустимым noise

Недопустимым noise считается любой rewrite `.beads/issues.jsonl`, который не отражает реальное изменение issue semantics и возникает из-за недетерминированного порядка, branch/worktree mismatch, чужого ownership context, drift в serialization или смешения unrelated issue families.

### Что обязательно должно быть у migration path

Migration path должен сначала проводить audit/evidence pass, затем строить bounded plan по worktree, сохранять исходное состояние, различать safe, ambiguous и blocked cases, и ни в одном сценарии не терять уже существующие issues. Для ambiguous случаев требуется остановка с точным диагнозом, а не best-effort rewrite.

### Как должны быть разделены rollout и rollback

Rollout должен идти отдельными этапами с report-only и blocking phases, чтобы новый contract можно было включать постепенно. Rollback должен откатывать enforcement path и связанный routing без стирания собранной RCA evidence, snapshots и migration journals.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Daily Sync Uses One Deterministic Owner (Priority: P1)

Как maintainer или агент, работающий в dedicated worktree, я хочу, чтобы mutating Beads sync path либо детерминированно переписывал только мой branch-local `.beads/issues.jsonl`, либо fail-closed останавливался до записи, чтобы никакая другая worktree и canonical root не получали скрытый шум.

**Why this priority**: Это минимально полезный результат. Пока ownership/sync authority не детерминированы, любой RCA остается описанием проблемы без практического устранения первопричины.

**Independent Test**: На фикстуре с canonical root и несколькими sibling worktree mutating sync из dedicated worktree либо переписывает только принадлежащий ей `.beads/issues.jsonl`, либо блокируется с явным reason code и без изменений в чужих trackers.

**Acceptance Scenarios**:

1. **Given** dedicated worktree имеет подтвержденный local ownership и sync authority, **When** оператор запускает mutating Beads sync path, **Then** переписывается только `.beads/issues.jsonl` текущей worktree и rewrite имеет детерминированный byte-stable результат при повторном запуске без новых semantic changes.
2. **Given** dedicated worktree находится в ambiguous ownership или branch/worktree mismatch state, **When** оператор запускает mutating sync, **Then** система блокирует запись до мутации и сообщает, какой invariant нарушен.
3. **Given** команда запущена из dedicated worktree, но rewrite попытался бы коснуться canonical root или sibling tracker, **When** sync authority проверяется, **Then** операция запрещается как ownership violation.

---

### User Story 2 - RCA Reproduces Drift With Reviewable Evidence (Priority: P2)

Как investigator, я хочу воспроизводимо воспроизвести drift/шум `.beads/issues.jsonl`, снять машинно-читаемые логи и классифицировать тип нарушения, чтобы дальнейшее исправление опиралось на доказанную root cause, а не на разовые наблюдения.

**Why this priority**: Без воспроизводимого RCA проблема быстро возвращается под новой формой. Нужен durable evidence path, который можно гонять локально и в review.

**Independent Test**: На заранее подготовленной multi-worktree fixture investigator запускает RCA workflow и получает журнал, где зафиксированы входной topology context, resolved ownership, target JSONL paths, классификация drift и итоговый verdict без ручного чтения случайных diff’ов.

**Acceptance Scenarios**:

1. **Given** есть fixture со сценарием manual worktree leakage или noise-only rewrite, **When** investigator запускает RCA workflow, **Then** система сохраняет пошаговый журнал, в котором видно источник мутации, затронутый tracker и тип drift.
2. **Given** rewrite является только nondeterministic noise без semantic changes, **When** RCA workflow анализирует его, **Then** он классифицирует кейс отдельно от реальной issue mutation.
3. **Given** один и тот же reproduction сценарий запускается повторно без изменения fixture, **When** журнал формируется снова, **Then** verdict, ключевые classification codes и expected target paths совпадают.

---

### User Story 3 - Existing Worktrees Migrate Safely With Rollout And Rollback (Priority: P3)

Как operator, я хочу безопасно перевести уже существующие worktree на новую deterministic ownership/sync модель, не теряя issues и не смешивая migration с canonical-root cleanup, чтобы можно было включить enforcement поэтапно и откатить его при необходимости.

**Why this priority**: Даже правильный новый contract бесполезен, если его нельзя аккуратно применить к уже существующим worktree и безопасно откатить.

**Independent Test**: На наборе legacy/current/ambiguous worktree operator запускает audit-only migration plan, видит safe и blocked items, затем может применить rollout на safe subset и при необходимости откатить enforcement без потери snapshots и issue records.

**Acceptance Scenarios**:

1. **Given** набор worktree содержит current, legacy и ambiguous states, **When** operator запускает migration planning workflow, **Then** он получает deterministic plan с safe, blocked и manual-only cases по каждой worktree.
2. **Given** rollout включается для safe subset, **When** enforcement активируется, **Then** существующие issues сохраняются, blocked worktree не мутируются автоматически, а canonical-root cleanup остается отдельным follow-up.
3. **Given** после rollout требуется rollback, **When** operator выполняет rollback plan, **Then** enforcement path возвращается в предыдущее состояние без удаления collected evidence, snapshots и migration journals.

### Edge Cases

- Что происходит, если две worktree претендуют на один и тот же tracked `.beads/issues.jsonl` rewrite после branch rename, detach или ручного `git worktree add` path?
- Что происходит, если `bd sync` пытается выполнить semantic rewrite одновременно с order-only normalization или merge/rebase reconciliation?
- Как система различает реальное изменение issues и noise-only rewrite, вызванный serialization, dependency ordering или unstable field ordering?
- Что происходит, если legacy worktree содержит частичную local foundation, а canonical root уже имеет leaked copy тех же issues?
- Что происходит, если operator запускает recovery/migration из canonical root, но sibling worktree topology stale или неполна?
- Что происходит, если в одном migration batch часть worktree safe, часть ambiguous, а часть уже содержит дубликаты issue records?
- Что происходит, если rollback нужен после частично завершенного rollout, но некоторые worktree уже создали новые legitimate issue updates по новому contract?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Система ДОЛЖНА задать одну явную deterministic ownership/sync модель для Beads state в multi-worktree репозитории.
- **FR-002**: Модель ДОЛЖНА явно различать runtime-local `.beads/beads.db`, branch-local `.beads/issues.jsonl`, canonical root context и sibling worktree contexts.
- **FR-003**: Любой mutating sync path ДОЛЖЕН до записи вычислять authoritative owner текущего `.beads/issues.jsonl`.
- **FR-004**: Если authoritative owner не может быть определен однозначно, mutating sync ДОЛЖЕН fail-closed останавливаться до rewrite.
- **FR-005**: Система НЕ ДОЛЖНА позволять dedicated worktree неявно переписывать canonical root `.beads/issues.jsonl` или sibling tracker.
- **FR-006**: Система ДОЛЖНА классифицировать как отдельные состояния минимум: safe semantic rewrite, noise-only rewrite, ownership violation, legacy migration required, ambiguous migration blocked и explicit root-scoped operation.
- **FR-007**: Система ДОЛЖНА предоставлять воспроизводимый RCA workflow с детерминированными шагами, логами и classification output для drift/шума `.beads/issues.jsonl`.
- **FR-008**: RCA workflow ДОЛЖЕН сохранять достаточно evidence, чтобы reviewer мог увидеть topology context, ownership resolution, intended target path, фактический rewrite outcome и verdict без ручного восстановления истории.
- **FR-009**: Повторный запуск одного и того же RCA сценария на неизменной fixture ДОЛЖЕН давать одинаковые ключевые classification результаты.
- **FR-010**: Система ДОЛЖНА отличать noise-only rewrite от real semantic issue mutation и НЕ ДОЛЖНА смешивать их в одном verdict.
- **FR-011**: Guardrails ДОЛЖНЫ блокировать nondeterministic rewrites, которые не соответствуют authoritative owner или не несут подтвержденного semantic change.
- **FR-012**: Guardrails ДОЛЖНЫ предотвращать order-only, serialization-only и branch-misaligned rewrite noise, если такие rewrites не являются частью explicitly approved canonical form.
- **FR-013**: Если rewrite допустим, система ДОЛЖНА приводить `.beads/issues.jsonl` к одному deterministic каноническому виду.
- **FR-014**: Система ДОЛЖНА обеспечивать, что повторный допустимый sync без новых semantic changes оставляет `.beads/issues.jsonl` byte-stable.
- **FR-015**: Система ДОЛЖНА отделять routine sync enforcement от recovery/migration workflows.
- **FR-016**: Система ДОЛЖНА предоставлять audit-first migration path для уже существующих worktree, затронутых drift, leakage или legacy ownership residue.
- **FR-017**: Migration path ДОЛЖЕН строить bounded plan по worktree и issue families до начала мутаций.
- **FR-018**: Migration path ДОЛЖЕН сохранять snapshots или equivalent rollback evidence до любой corrective rewrite.
- **FR-019**: Migration path НЕ ДОЛЖЕН терять существующие issue records; safe duplicates, ambiguous duplicates и orphaned records должны быть явно классифицированы и отражены в плане.
- **FR-020**: Ambiguous или damaged migration cases ДОЛЖНЫ останавливаться с явным диагнозом и manual-only recovery path вместо best-effort rewrite.
- **FR-021**: Canonical root cleanup ДОЛЖЕН оставаться отдельным потоком и НЕ ДОЛЖЕН считаться обязательной частью routine sync fix или migration apply.
- **FR-022**: Rollout план ДОЛЖЕН включать как минимум audit/report-only stage, controlled enforcement stage и post-rollout verification stage.
- **FR-023**: Rollback план ДОЛЖЕН быть отдельным и ДОЛЖЕН описывать, как отключить enforcement path без удаления RCA evidence, snapshots и migration journals.
- **FR-024**: Docs, tests и static guardrails ДОЛЖНЫ быть обязательной частью решения, а не optional polish.
- **FR-025**: Regression coverage ДОЛЖНА ловить повторное появление canonical-root leakage, sibling rewrite noise, ambiguous ownership rewrites и nondeterministic serialization drift.
- **FR-026**: Пользовательский вывод ДОЛЖЕН различать: что блокирует текущую запись сейчас, какие evidence уже собраны, и нужно ли отдельно планировать root cleanup.

### Key Entities *(include if feature involves data)*

- **WorktreeSyncContext**: Нормализованное описание текущей worktree, branch, canonical root, topology state и разрешенного sync surface.
- **SyncAuthorityDecision**: Результат разрешения ownership/sync модели для конкретной mutating операции, включая allowed target, decision code и blocking reason.
- **JsonlRewriteEvidence**: Машинно-читаемый журнал, фиксирующий входной `.beads/issues.jsonl`, вычисленный target path, тип rewrite и итоговую классификацию.
- **RcaReproductionRun**: Повторяемый набор шагов, fixture inputs, expected outcomes и логов, доказывающий root cause определенного drift/noise сценария.
- **MigrationCandidate**: Worktree или issue-family, требующие выравнивания под новый contract, со статусом `safe`, `blocked`, `ambiguous` или `manual-only`.
- **MigrationJournal**: Audit/apply evidence по migration batch, включая snapshots, затронутые worktree и unresolved blockers.
- **RolloutCheckpoint**: Явный этап включения нового contract с критерием входа, критерием успеха и условием отката.
- **RollbackPackage**: Набор команд, артефактов и доказательств, достаточный для controlled disablement enforcement path без потери состояния расследования.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: В 100% покрытых dedicated-worktree сценариев mutating sync либо переписывает только принадлежащий текущей worktree `.beads/issues.jsonl`, либо блокируется до записи.
- **SC-002**: В 100% покрытых regression scenarios repeated safe sync без новых semantic changes оставляет `.beads/issues.jsonl` byte-identical.
- **SC-003**: В 100% покрытых canonical-root leakage scenarios система останавливает rewrite до мутации и выдает classification code, объясняющий запрет.
- **SC-004**: RCA workflow воспроизводит и классифицирует минимум один leakage case и минимум один noise-only rewrite case с одинаковым verdict при повторном прогоне на той же fixture.
- **SC-005**: Не менее 90% planned migration scenarios для current/legacy worktree попадают в deterministic `safe` или `blocked` categories без ручного форензик-анализа сырых diff’ов.
- **SC-006**: В 100% покрытых migration apply scenarios ни один существующий issue record не теряется бесследно; safe imports, duplicates и blocked records отражаются в журнале.
- **SC-007**: Rollout план содержит отдельные gates для audit/report-only, controlled enforcement и verification, а rollback план позволяет отключить enforcement без удаления evidence artifacts.
- **SC-008**: Regression suite и static guardrails ловят повторное появление nondeterministic rewrite noise, sibling ownership rewrites и смешения routine sync с canonical-root cleanup.
