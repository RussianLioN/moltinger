# Feature Specification: Portable Worktree Skill Extraction

**Feature Branch**: `011-worktree-skill-extraction`  
**Created**: 2026-03-11  
**Status**: Draft  
**Input**: User description: "Спроектировать и подготовить реализацию отчуждения всех независимых от текущего проекта worktree-навыков в отдельный git-репозиторий с рабочим названием `worktree-skill`, чтобы пользователь мог скачать новый репозиторий, скопировать артефакты почти как есть, при необходимости запустить минимальный install/register script и сразу использовать навык в Claude Code, OpenCode и Codex CLI с полной совместимостью со Speckit и artifact-first workflow."

## Executive Summary

Нужно выделить из текущего репозитория переносимый, project-agnostic слой worktree workflow в отдельный репозиторий `worktree-skill`. Новый репозиторий должен поставлять единое core-поведение для создания dedicated worktree, topology-aware handoff, branch/worktree discipline и spec-driven feature work, а различия между Claude Code, OpenCode и Codex CLI должны оставаться только в install/registration surface и adapter-слое.

Итоговый пакет должен устанавливаться предсказуемо и быстро: пользователь скачивает репозиторий, копирует нужные папки в свой проект, при необходимости запускает минимальный bootstrap/register script и может сразу использовать одинаковый worktree flow рядом со `spec.md`, `plan.md`, `tasks.md`. Новое решение не должно тянуть Moltinger-специфичные runtime, deploy, secrets, production hostnames, issue ids или исторические ветки; такие привязки допускаются только как optional adapters, migration guidance или examples.

## Assumptions

- Первым релизом считается extraction design + repository skeleton + migration path, а не публикация готового пакета в registry.
- Базовое portable core должно работать даже в проектах без `bd`, GitHub Actions и Moltinger-specific CI/CD.
- `bd`-aware issue transitions, topology registry auto-refresh и IDE-specific registration допускаются как optional layers, если они не являются обязательной зависимостью для core flow.
- Speckit compatibility означает сосуществование с `spec.md`, `plan.md`, `tasks.md` и artifact-first workflow, а не форк Speckit или изменение `/speckit.spec`, `/speckit.plan`, `/speckit.tasks`.
- Рабочее имя репозитория остается `worktree-skill`, пока дальнейшее naming review не выявит более точный и не менее понятный вариант.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Claude Code Portable Install (Priority: P1)

Как пользователь Claude Code, я хочу скопировать skill в свой проект, зарегистрировать его и сразу создать dedicated worktree без Moltinger-specific ручной настройки, чтобы переносимый workflow был готов к использованию за один короткий setup.

**Why this priority**: Claude assets являются текущим исходным слоем для worktree workflow, поэтому extraction должен сначала доказать, что portable core можно установить и запустить без скрытой привязки к Moltinger.

**Independent Test**: В чистом тестовом проекте пользователь копирует portable core и Claude adapter, выполняет documented register step, затем вызывает worktree workflow и получает dedicated worktree, handoff и predictable verification без редактирования Moltinger-specific путей или секретов.

**Acceptance Scenarios**:

1. **Given** пользователь скачал `worktree-skill`, **When** он копирует portable core и Claude adapter в новый проект, **Then** установка завершается без ссылок на `moltinger`, production secrets или исторические branch names.
2. **Given** проект не содержит `bd` и project-local helpers, **When** пользователь активирует только portable core, **Then** базовый worktree flow остается работоспособным и не требует ручного удаления обязательных зависимостей.
3. **Given** Claude adapter установлен, **When** пользователь вызывает workflow для новой feature line, **Then** поведение core совпадает с documented branch/worktree contract и завершается handoff boundary.

---

### User Story 2 - Codex CLI Behavioral Parity (Priority: P1)

Как пользователь Codex CLI, я хочу использовать тот же worktree skill flow с теми же handoff и branch/worktree contracts, чтобы адаптация к другой IDE не меняла core behavior.

**Why this priority**: Extraction теряет ценность, если Codex получает отдельный сценарий с другой семантикой и другой дисциплиной branch/worktree.

**Independent Test**: Пользователь устанавливает Codex adapter поверх того же portable core и получает идентичные planning, handoff и verification semantics, отличающиеся только registration surface.

**Acceptance Scenarios**:

1. **Given** portable core уже установлен, **When** пользователь добавляет Codex adapter, **Then** skill discovery и invocation surface становятся Codex-compatible без дублирования core logic.
2. **Given** один и тот же запрос на создание worktree, **When** он выполняется через Claude Code и Codex CLI, **Then** branch naming, handoff boundary и verification outputs совпадают по смыслу.
3. **Given** Codex bridge требует install step, **When** этот step пропущен, **Then** пользователь получает ясную verification failure и точную corrective action.

---

### User Story 3 - OpenCode Compatible Adapter (Priority: P1)

Как пользователь OpenCode, я хочу установить совместимый adapter и получить тот же worktree сценарий, чтобы extraction был IDE-agnostic, а не Claude/Codex-only.

**Why this priority**: Требование переносимости неполно без третьей integration surface, в которой core reusable behavior остается тем же самым.

**Independent Test**: Пользователь на OpenCode устанавливает documented adapter, проходит activation flow и запускает worktree workflow без Moltinger-specific prompt surgery.

**Acceptance Scenarios**:

1. **Given** OpenCode требует собственный registration surface, **When** пользователь следует quickstart, **Then** adapter активируется без изменения portable core файлов вручную.
2. **Given** portable core обновился до новой версии, **When** OpenCode adapter остается на поддерживаемой версии контракта, **Then** workflow остается совместимым без forking core behavior.
3. **Given** OpenCode adapter недоступен или частично поддерживается, **When** пользователь читает compatibility docs, **Then** ограничения и manual fallback documented явно, а не скрыто в runtime.

---

### User Story 4 - Speckit-Safe Spec-First Workflow (Priority: P1)

Как пользователь Speckit, я хочу запускать spec-first workflow рядом с extracted worktree skill и быть уверенным, что skill не ломает `spec.md`, `plan.md`, `tasks.md`, уважает branch-spec alignment и поддерживает handoff в dedicated worktree.

**Why this priority**: В текущем репозитории именно spec-driven feature work определяет branch/worktree discipline, поэтому extracted repo обязан сохранить совместимость с artifact-first workflow.

**Independent Test**: В проекте со Speckit пользователь создает `spec.md`, `plan.md`, `tasks.md`, затем использует worktree skill для dedicated feature lane и получает handoff без изменения contract `/speckit.spec`, `/speckit.plan`, `/speckit.tasks`.

**Acceptance Scenarios**:

1. **Given** feature branch уже выровнена по шаблону `NNN-<slug>`, **When** Speckit user запускает worktree skill, **Then** skill не переводит flow обратно в project-specific legacy naming и не ломает branch-spec alignment.
2. **Given** в проекте уже существуют `spec.md`, `plan.md`, `tasks.md`, **When** worktree skill создает dedicated worktree, **Then** artifact-first workflow и handoff rules остаются согласованными.
3. **Given** Speckit bridge layer не установлен, **When** пользователь работает только с portable core, **Then** core не блокируется, но compatibility docs явно показывают, какие функции Speckit layer добавляет.

---

### User Story 5 - Independent Maintainer Release Surface (Priority: P2)

Как maintainer нового репозитория, я хочу выпускать `worktree-skill` независимо от Moltinger, документировать supported integration surfaces и управлять версиями отдельно от host project, чтобы extracted skill мог жить как самостоятельный продукт.

**Why this priority**: Без независимого release surface extraction останется внутренним переносом файлов, а не самостоятельным reusable repository.

**Independent Test**: Maintainer может собрать release notes, описать compatibility matrix, зафиксировать install and migration guidance и выпустить новую версию без ссылки на Moltinger runtime или его roadmap.

**Acceptance Scenarios**:

1. **Given** переносимые артефакты собраны в отдельном репозитории, **When** maintainer готовит релиз, **Then** versioning, changelog и supported adapters описываются в самом `worktree-skill`, а не в Moltinger-specific docs.
2. **Given** host project остается на старой версии, **When** maintainer выпускает новый worktree-skill release, **Then** migration guidance и compatibility boundaries документированы отдельно.
3. **Given** в текущем репозитории найдены конфликтующие или Moltinger-specific артефакты, **When** extraction plan утверждается, **Then** такие конфликты зафиксированы в spec/research до начала runtime refactor.

### Edge Cases

- Что происходит, если host project не использует `bd` и не имеет issue-tracking hooks?
- Что происходит, если проект использует не `main`, а другой default branch?
- Как ведет себя install flow, если пользователь копирует только core без adapters?
- Как совместить portable topology helpers с проектом, где уже есть свои worktree scripts или registry docs?
- Что происходит, если в исходных артефактах остались жёсткие ссылки на `moltinger`, абсолютные workstation paths или project-specific commands?
- Какой fallback допустим, если OpenCode adapter еще не имеет автоматической регистрации?
- Как обозначить частично поддерживаемые integration surfaces, не меняя core behavior?
- Как предотвратить silent drift между extracted repo и in-repo origin после первого релиза?

## Requirements *(mandatory)*

### Functional Requirements

#### Repository Structure and Portability

- **FR-001**: System MUST define a portable repository structure for `worktree-skill` that clearly separates `portable core`, IDE adapters, Speckit bridge layer, install helpers, docs, examples, and validation assets.
- **FR-002**: System MUST document the minimal portable artifact set required for first use: skill instructions, command or agent prompts, handoff templates, topology/worktree helper scripts, registry/install hooks, docs/quickstart, and Speckit-compatible templates when needed.
- **FR-003**: System MUST classify current repository assets into `portable core`, `optional adapter`, `Speckit bridge`, `host-project only`, or `needs templating/generalization`.
- **FR-004**: System MUST identify which current files can move as-is, which require renaming or templating, and which must stay in the host project.
- **FR-005**: System MUST define a canonical extracted repo layout that supports copy-as-is installation without forcing users to understand Moltinger internals.

#### Zero Project Coupling

- **FR-006**: System MUST enforce a zero-project-coupling goal for the extracted core, including removal of hard references to `moltinger`, product/domain assumptions, issue ids, production secrets, remote hostnames, and project-specific scripts.
- **FR-007**: System MUST treat `bd` integration, project-specific issue transitions, and host-project operational hooks as optional adapters rather than mandatory core dependencies.
- **FR-008**: System MUST surface any conflicting artifact that violates portability as a recorded research or planning finding before implementation.

#### Install and Activation Model

- **FR-009**: System MUST support a primary install model of copying portable artifacts into a host project largely as-is.
- **FR-010**: System MUST support an optional bootstrap or install script for users who prefer guided setup.
- **FR-011**: System MUST support an optional registry activation or registration step for IDE-specific discovery surfaces.
- **FR-012**: System MUST define a predictable post-install verification flow with explicit success and failure signals.
- **FR-013**: System MUST document installation for both greenfield and existing host projects.

#### Compatibility Contracts

- **FR-014**: System MUST define an IDE compatibility matrix covering Claude Code, OpenCode, and Codex CLI.
- **FR-015**: System MUST keep core behavior consistent across IDEs and limit differences to adapter surface, registration, and discovery mechanics.
- **FR-016**: System MUST define a compatibility contract for Claude Code that covers skill placement, registration, invocation surface, and verification.
- **FR-017**: System MUST define a compatibility contract for Codex CLI that covers bridge installation, invocation surface, and verification.
- **FR-018**: System MUST define a compatibility contract for OpenCode that covers adapter installation, discovery, supported capabilities, and fallback behavior.
- **FR-019**: System MUST define a Speckit compatibility contract stating that the extracted skill works alongside `spec.md`, `plan.md`, and `tasks.md`, preserves artifact-first workflow, respects branch-spec alignment, and supports dedicated worktree handoff for spec-driven feature work.

#### Worktree and Handoff Behavior

- **FR-020**: System MUST preserve a stable worktree creation and handoff contract that can be documented independently of any single host project.
- **FR-021**: System MUST define which topology or worktree helper scripts belong in portable core and which belong in adapters or host-project overlays.
- **FR-022**: System MUST define a manual registration fallback when automatic discovery is unavailable.
- **FR-023**: System MUST document safe default behavior when optional adapters or install hooks are missing.
- **FR-024**: System MUST define predictable naming conventions and paths for worktree-related assets in the extracted repo.

#### Migration and Release

- **FR-025**: System MUST provide migration guidance from the current in-repo skill to the extracted repository.
- **FR-026**: System MUST provide examples for adopting the skill in a greenfield project and in an existing project with pre-existing agent assets.
- **FR-027**: System MUST define how maintainers can version and release the new repository independently from the host project.
- **FR-028**: System MUST define acceptance criteria for the state `portable repo ready`.

### Non-Functional Requirements

- **NFR-001**: Install flow SHOULD require the minimum practical number of steps for a first successful run.
- **NFR-002**: Quickstart SHOULD be completable in 5-10 minutes by a developer who did not author the original Moltinger workflow.
- **NFR-003**: The extracted repo MUST avoid hidden dependencies and undocumented prerequisites.
- **NFR-004**: Paths, names, and directory boundaries MUST remain predictable and stable across releases.
- **NFR-005**: Default behavior MUST be safe and non-destructive.
- **NFR-006**: Boundaries between portable core and project adapters MUST be explicit and documented.
- **NFR-007**: Release and versioning strategy MUST support independent evolution from the host project.
- **NFR-008**: Compatibility documentation MUST distinguish supported, optional, and partial integration surfaces without changing core semantics.

### Key Entities

- **PortableSkillPackage**: Собранный набор переносимых артефактов, который можно скопировать в host project и активировать.
- **PortableCoreArtifact**: Инструкция, prompt, template, helper script или doc, не зависящие от Moltinger-specific runtime.
- **AdapterSurface**: IDE-specific слой для Claude Code, Codex CLI или OpenCode, который меняет только install/discovery/invocation surface.
- **SpeckitBridgeLayer**: Набор compatibility artifacts, позволяющих worktree skill жить рядом со Speckit workflow и уважать branch-spec contracts.
- **InstallProfile**: Определенный путь установки, например `copy-only`, `copy+bootstrap`, `copy+register`.
- **VerificationProbe**: Предсказуемая post-install проверка, подтверждающая, что core и нужный adapter активированы правильно.
- **InventoryRecord**: Классификация текущего артефакта репозитория как portable, adapter-only, host-only, templated, or conflict.
- **MigrationRecipe**: Документированная последовательность шагов для перехода от in-repo Moltinger skill к standalone `worktree-skill`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% обязательных portability boundaries для первого релиза зафиксированы в spec/plan/research до начала runtime extraction.
- **SC-002**: Первый quickstart описывает greenfield install и existing-project install не более чем в 10 минут каждый по documented path.
- **SC-003**: Portable core можно установить без обязательных ссылок на `moltinger`, production secrets, remote hostnames или исторические ветки.
- **SC-004**: Claude Code, Codex CLI и OpenCode представлены в единой compatibility matrix, где различия ограничены adapter/install surface.
- **SC-005**: Speckit compatibility contract явно подтверждает отсутствие вмешательства в `/speckit.spec`, `/speckit.plan`, `/speckit.tasks`.
- **SC-006**: Для состояния `portable repo ready` существует проверяемый acceptance checklist с install, registration, verification, migration и release criteria.
- **SC-007**: Инвентаризация исходных артефактов фиксирует, какие файлы относятся к portable core, какие остаются host-specific, а какие требуют templating or renaming.
- **SC-008**: Migration guidance покрывает как минимум один greenfield и один existing-project сценарий.
- **SC-009**: Release strategy определяет понятную semantic versioning схему и compatibility expectations для adapters и Speckit bridge.
- **SC-010**: Все конфликтующие артефакты, найденные в исходном репозитории, перечислены в research/plan до начала implementation work.
