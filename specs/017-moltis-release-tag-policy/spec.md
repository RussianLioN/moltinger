# Feature Specification: Moltis Release-Tag Production Policy

**Feature Branch**: `017-moltis-release-tag-policy`  
**Created**: 2026-03-14  
**Status**: Draft  
**Input**: User description: "Оформи это как Speckit workflow и приступай к выполнению. Нужно перевести Moltis deploy UX от implicit latest к explicit release-tag-first policy, не ломая intentional dev/UAT exceptions и не обещая arbitrary-tag rollback."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Production Deploy Stops Defaulting To Hardcoded `latest` (Priority: P1)

Оператор запускает production deploy и workflow больше не подставляет `latest` просто потому, что так написано в CI. По умолчанию workflow должен брать tracked compose default из git или явный input, а не иметь свой скрытый hardcoded source of truth.

**Why this priority**: Пока deploy workflow сам по себе hardcodes `latest`, docs и runtime поведение расходятся, а production rollout остаётся недетерминированным даже после документального выравнивания.

**Independent Test**: Можно независимо проверить, что workflow version resolution использует helper/compose-tracked contract и больше не содержит hardcoded `VERSION="latest"` как production default.

**Acceptance Scenarios**:

1. **Given** manual production deploy without explicit `version`, **When** workflow resolves target image version, **Then** it uses the tracked compose default from git instead of hardcoded `latest`.
2. **Given** push/tag driven deploy, **When** workflow resolves target image version, **Then** the chosen version source is explicit and visible in workflow logs/summary.

---

### User Story 2 - Intentional `latest` Remains Possible But Explicit (Priority: P1)

Оператор всё ещё может намеренно протестировать `latest`, но production path требует явного acknowledgement вместо тихого implicit latest rollout. При этом non-production/manual validation flows не должны ломаться.

**Why this priority**: Полный запрет `latest` не требовался пользователем и не соответствует upstream quickstart, но implicit production latest тоже неприемлем.

**Independent Test**: Можно отдельно проверить, что workflow принимает explicit `latest` только при явном acknowledgement для production и не ломает intentional exception path.

**Acceptance Scenarios**:

1. **Given** manual production deploy with target `latest` and without explicit acknowledgement, **When** preflight resolves version policy, **Then** workflow fails with actionable guidance.
2. **Given** manual production deploy with target `latest` and explicit acknowledgement, **When** preflight runs, **Then** workflow continues and records that this was an intentional exception.

---

### User Story 3 - Repo Tooling And Guardrails Share One Version Contract (Priority: P2)

Разные repo entrypoints показывают одну и ту же правду: `Makefile`, workflow и tests понимают версию Moltis через один helper и одни правила, а не каждый по-своему.

**Why this priority**: Без общего helper и guardrails policy быстро снова расползётся между docs, workflow и operator commands.

**Independent Test**: Можно отдельно проверить helper, `make version-check` и static/component tests без реального production deploy.

**Acceptance Scenarios**:

1. **Given** compose files with matching Moltis image defaults, **When** helper resolves version, **Then** it returns one normalized source of truth.
2. **Given** compose files with mismatched Moltis image defaults, **When** helper resolves version, **Then** it fails before deploy UX can rely on ambiguous state.

### Edge Cases

- Что происходит, если tracked compose default всё ещё равен `latest`?
- Что происходит, если operator вручную передал explicit release tag, который отличается от tracked compose default?
- Что происходит, если `docker-compose.yml` и `docker-compose.prod.yml` расходятся по Moltis image default?
- Что происходит, если workflow запущен от git tag, а compose default другой?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide one repo-local helper that resolves the normalized Moltis image/version contract from `docker-compose.yml` and `docker-compose.prod.yml`.
- **FR-002**: The helper MUST fail if the two compose files do not resolve to the same Moltis image default.
- **FR-003**: Deploy workflow MUST stop using hardcoded `latest` as the implicit production default.
- **FR-004**: Deploy workflow MUST resolve version from one of: explicit workflow input, git tag, or tracked compose default.
- **FR-005**: Deploy workflow MUST make the resolved version source visible in logs or summary.
- **FR-006**: Manual production deploys that resolve to `latest` MUST require explicit acknowledgement.
- **FR-007**: Intentional `latest` exceptions MUST remain possible for operator-driven validation flows.
- **FR-008**: The repository MUST NOT describe rollback as rollback to an arbitrary operator-chosen version tag through this feature.
- **FR-009**: `make version-check` MUST reuse the same version-resolution contract instead of ad-hoc grep output.
- **FR-010**: Static and/or component tests MUST block regression to hardcoded production `latest` defaults.
- **FR-011**: The feature MUST preserve existing backup-safe rollback semantics: previous deployed image or verified restore.
- **FR-012**: User-facing workflow guidance MUST remain compatible with intentional dev/UAT exception paths.

### Key Entities *(include if feature involves data)*

- **Tracked Moltis Version Contract**: Normalized version/image derived from both compose files and treated as the repo’s source of truth for default rollout intent.
- **Deploy Version Source**: The origin of the version chosen for a deploy run: workflow input, git tag, or tracked compose default.
- **Production Latest Exception**: An explicit operator acknowledgement that allows `latest` for a production deploy despite release-tag-first policy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Production deploy workflow no longer contains hardcoded `VERSION="latest"` as the default resolution path.
- **SC-002**: In 100% of covered static/component scenarios, the helper either resolves one normalized version/image or fails on compose mismatch.
- **SC-003**: In 100% of covered workflow validation scenarios, production `latest` requires explicit acknowledgement.
- **SC-004**: `make version-check` and deploy workflow show the same normalized Moltis version contract.
- **SC-005**: Existing rollback language and behavior remain limited to previous deployed image or verified restore, with no new arbitrary-tag rollback promise introduced by this feature.
