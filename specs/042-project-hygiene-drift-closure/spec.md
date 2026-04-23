# Feature Specification: Project Hygiene Drift Closure

**Feature Branch**: `[fix/project-remediation-blockers]`
**Created**: 2026-04-21
**Status**: Draft
**Input**: User description: "Сделай полное ревью проекта и запланируй speckit совместимые шаги по исправлению всех ошибок и реализуй их"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Active docs/specs do not contradict the current runtime contract (Priority: P1)

Как maintainer, я хочу, чтобы текущие Speckit packages, session summary и active docs описывали актуальный runtime/deploy/provider contract, а не старые GLM/Z.ai или stale topology assumptions.

**Why this priority**: Blocker fixes быстро деградируют снова, если durable docs/specs продолжают учить старому контракту.

**Independent Test**: targeted static/doc/spec consistency checks and manual review of active documentation surfaces.

**Acceptance Scenarios**:

1. **Given** current runtime contract after Wave 1, **When** maintainer читает active docs/specs, **Then** они не направляют его в GLM/Z.ai, Anthropic fallback или другие retired active paths.
2. **Given** stale or malformed Speckit package, **When** hygiene wave closes it, **Then** active planning surface больше не маскирует broken package as current source of truth.

---

### User Story 2 - Shared planning surfaces clearly separate active vs historical packages (Priority: P2)

Как maintainer, я хочу, чтобы broken/stale spec packages and historical summaries were explicitly classified, so new work doesn’t anchor to invalid planning artifacts.

**Why this priority**: В текущем baseline `031`, `002`, stale `SESSION_SUMMARY.md` и supersession drift already mislead future work.

**Independent Test**: manual review and spec artifact checks.

**Acceptance Scenarios**:

1. **Given** maintainer opens the specs tree, **When** package is stale/broken/historical, **Then** that state is obvious and active wave packages are clearly preferred.
2. **Given** operator asks for simple status, **When** summary/doc surfaces are refreshed, **Then** they reflect current provider/runtime/deploy reality instead of March-era assumptions.

## Edge Cases

- Historical RCA files must remain historical evidence; hygiene should update active docs/contracts, not rewrite incident history.
- Some stale packages may need classification rather than deletion if they still carry audit value.
- Session summary refresh must remain concise enough to stay readable.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Active documentation surfaces MUST reflect the current primary/fallback provider contract and Telegram-safe runtime behavior.
- **FR-002**: Broken or stale Speckit packages that could mislead active work MUST be explicitly classified, repaired, or archived.
- **FR-003**: `SESSION_SUMMARY.md` MUST stop presenting Z.ai/GLM as the current active provider baseline.
- **FR-004**: Supersession path for codex-update/Telegram hardening packages SHOULD be explicit enough to prevent planning drift.

### Key Entities

- **Active Documentation Surface**: docs/spec/session-summary files that guide present-day implementation or operations.
- **Historical Artifact**: file kept for audit/incident history but not authoritative for current planning.
- **Spec Hygiene Closure**: explicit repair/classification of malformed or misleading Speckit packages.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Active documentation no longer presents GLM/Z.ai or Anthropic fallback as the current contract.
- **SC-002**: Broken/stale planning artifacts are visibly classified or repaired.
- **SC-003**: `SESSION_SUMMARY.md` and new remediation specs point operators to the current runtime/provider truth.
