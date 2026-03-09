# Implementation Plan: Codex CLI Update Advisor

**Branch**: `008-codex-update-advisor` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-codex-update-advisor/spec.md`

## Summary

Deliver a script-first advisor layer on top of the completed Codex CLI update monitor so operators receive low-noise notification decisions, repository-specific change suggestions, and an optional Beads implementation brief without duplicating the upstream evidence collection logic.

## Technical Context

**Language/Version**: Bash with existing shell helper patterns
**Primary Dependencies**: `bash`, `jq`, `python3`, existing `scripts/codex-cli-update-monitor.sh`, optional `bd`
**Storage**: JSON advisor report, Markdown summary, local advisor state file, shell fixtures
**Testing**: Bash syntax checks plus targeted component tests under `tests/component/`
**Target Platform**: Linux/macOS shell and CI/manual wrapper execution
**Project Type**: Operational shell script + documentation + tests
**Performance Goals**: Advisor run completes in under 60 seconds when the underlying monitor succeeds normally
**Constraints**: Keep `007` monitor as single source of truth, default path remains read-only, no external push channels in v1, deterministic suggestion mapping, stable wrapper-safe contract
**Scale/Scope**: Single repository, one advisor entrypoint, repeated local or scheduled runs using one persisted state file

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (`007` monitor artifacts, current runtime script, operating-model docs, and user-requested UX direction were reviewed before planning `008`).
- Single Source of Truth: PASS (`007` monitor contract remains the only source for release/relevance evidence; advisor adds notification and suggestion layers only).
- Library-First Development: PASS (existing shell toolchain and `bd` already cover the v1 scope; no new library is justified).
- Code Reuse & DRY: PASS (advisor wraps the existing monitor instead of duplicating monitor logic).
- Strict Type Safety: N/A (Bash scope; JSON schema will enforce contract discipline instead).
- Atomic Task Execution: PASS (tasks are split into setup, foundational work, user stories, and validation checkpoints).
- Quality Gates: PASS (syntax checks, fixture-backed component tests, and contract verification are planned before push).
- Progressive Specification: PASS (spec, plan, tasks, analyze, tracker import, and implementation remain sequential).

No gate violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/008-codex-update-advisor/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- advisor-report.schema.json
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Source Code (repository root)

```text
scripts/
|-- codex-cli-update-monitor.sh
|-- codex-cli-update-advisor.sh
`-- manifest.json

tests/
|-- component/
|   |-- test_codex_cli_update_monitor.sh
|   `-- test_codex_cli_update_advisor.sh
`-- fixtures/
    |-- codex-update-monitor/
    `-- codex-update-advisor/

docs/
|-- codex-cli-update-monitor.md
|-- codex-cli-update-advisor.md
`-- GIT-TOPOLOGY-REGISTRY.md
```

**Structure Decision**: Implement the advisor as a second shell entrypoint that wraps the completed monitor, keeps all evidence collection in `007`, adds local state and suggestion logic in `008`, and follows the repository's existing script + docs + fixture-test pattern.

## Phase 0: Research Decisions (to `research.md`)

1. Wrap the existing monitor contract instead of duplicating release parsing and relevance scoring.
2. Use a local state file plus stable fingerprinting for low-noise notification behavior.
3. Generate project change suggestions from deterministic heuristics tied to repository workflow traits and impacted paths.
4. Reuse Beads as the only tracker sink, but create richer implementation briefs than the underlying monitor currently produces.
5. Preserve wrapper-safe behavior so schedulers or thin skills can adopt the advisor later.

## Phase 1: Design Artifacts

- Data model covering monitor snapshot input, advisor state, notification decision, project suggestions, implementation brief, and issue action.
- JSON schema contract for the advisor report.
- Quickstart showing first-run notification, repeat-run suppression, and explicit Beads handoff.
- Tasks grouped by user story so the feature can be implemented incrementally starting with low-noise notification behavior.

## Phase 2: Execution Readiness

- One shell entrypoint consumes the existing monitor contract or invokes the monitor directly.
- Component tests cover both first-run and repeated-run behavior using fixed fixtures and state files.
- Beads mutation stays opt-in and auditable.
- The advisor report remains suitable for future wrappers and schedulers without free-form scraping.
