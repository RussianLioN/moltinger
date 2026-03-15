# Implementation Plan: Codex CLI Update Monitor

**Branch**: `007-codex-update-monitor` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-codex-update-monitor/spec.md`

## Summary

Deliver a script-first Codex CLI update monitor for this repository that compares local Codex state against official upstream releases and optional issue signals, maps upstream changes to repository workflow traits, emits deterministic JSON plus a concise Markdown summary, and optionally syncs a Beads follow-up when action is recommended.

## Technical Context

**Language/Version**: Bash (project-standard operational shell scripting)  
**Primary Dependencies**: `codex`, `curl`, `jq`, optional `bd`, GitHub Actions runners  
**Storage**: JSON report output, Markdown summary output, shell test fixtures, no persistent database  
**Testing**: Bash syntax checks plus targeted shell/component tests under `tests/`  
**Target Platform**: Linux/macOS shell and GitHub Actions Ubuntu runners  
**Project Type**: Infrastructure/scripts + documentation + optional manual workflow entrypoint  
**Performance Goals**: Baseline on-demand run completes in under 60 seconds when upstream sources respond normally  
**Constraints**: Default path is read-only, no automatic self-upgrade, tracker sync requires explicit flag, issue feeds are advisory, report contract must remain deterministic  
**Scale/Scope**: Single-run local and CI/manual execution for one repository, with reuse-friendly contract for future wrappers

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (seed plan, research note, existing monitor patterns, and local operating-model docs reviewed before package creation).
- Single Source of Truth: PASS (one monitor contract, one recommendation rubric, one optional tracker sync path).
- Library-First Development: PASS (existing shell toolchain covers v1; no new library justified for initial delivery).
- Code Reuse & DRY: PASS (design reuses repository monitor/report patterns instead of introducing a separate agent runtime).
- Strict Type Safety: N/A (Bash scope; JSON schema will carry contract discipline instead).
- Atomic Task Execution: PASS (tasks are grouped into setup, foundation, user stories, and validation checkpoints).
- Quality Gates: PASS (targeted shell validation and contract checks are planned before merge).
- Progressive Specification: PASS (seed -> spec -> plan -> tasks completed before implementation).

No gate violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/007-codex-update-monitor/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- monitor-report.schema.json
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Source Code (repository root)

```text
scripts/
|-- codex-cli-update-monitor.sh
`-- manifest.json

tests/
|-- component/
|   `-- test_codex_cli_update_monitor.sh
`-- fixtures/
    `-- codex-update-monitor/

docs/
`-- codex-cli-update-monitor.md

.github/workflows/
`-- codex-cli-update-monitor.yml
```

**Structure Decision**: Use the existing repository pattern for operational features: deterministic shell script as the core, targeted tests/fixtures beside it, a focused runbook in `docs/`, and an optional manual workflow entrypoint for CI-safe runs.

## Phase 0: Research Decisions (to `research.md`)

1. Use a script-first architecture instead of an agent-first or plugin-first design.
2. Treat official Codex release information as the primary source and issue feeds as opt-in secondary evidence.
3. Include both local on-demand execution and CI-safe manual automation in v1.
4. Keep Beads as the only tracker sink in v1, behind an explicit flag.
5. Preserve a wrapper-friendly contract so a future skill can call the script without parsing prose.

## Phase 1: Design Artifacts

- Data model defining local state, upstream evidence, recommendation decision, and issue action.
- JSON schema contract for the machine-readable report.
- Quickstart covering local usage, manual workflow execution, and opt-in Beads sync.
- Tasks grouped by user story so MVP delivery can stop after US1 if needed.

## Phase 2: Execution Readiness

- Implement one shell entrypoint with explicit output contracts.
- Validate both machine-readable and human-readable outputs with fixed fixtures.
- Keep tracker mutation opt-in and auditable.
- Reserve the skill wrapper as a thin later layer, not as a v1 dependency.
