# Implementation Plan: On-Demand Telegram E2E Harness

**Branch**: `004-telegram-e2e-harness` | **Date**: 2026-03-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-telegram-e2e-harness/spec.md`

## Summary

Deliver an on-demand E2E harness for Telegram/Moltis debugging with two triggers (CLI and workflow dispatch), manual-verdict artifacts, and working `real_user` mode via MTProto test account. Keep production Telegram runtime unchanged.

## Technical Context

**Language/Version**: Bash (POSIX shell, project-standard Bash scripts)
**Primary Dependencies**: `curl`, `jq`, GitHub Actions runners
**Storage**: File artifact JSON/log output (repo and CI artifacts)
**Testing**: Existing shell test runners (`tests/run_unit.sh`, integration smoke)
**Target Platform**: Linux/macOS shell and GitHub Actions Ubuntu runners
**Project Type**: Infrastructure/scripts + CI workflow + docs
**Performance Goals**: Report emitted within `timeout + 5s` for synthetic mode
**Constraints**: No persistent runtime mode changes; secret redaction mandatory
**Scale/Scope**: On-demand single-run execution; no scheduler/cron in v1

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First: PASS (existing API endpoints and tests reviewed).
- Single Source of Truth: PASS (one script + one workflow + one report schema).
- Library-First: PASS (no new libraries required for MVP).
- Code Reuse: PASS (reuse existing `/api/auth/login` and `/api/v1/chat` patterns).
- Strict Type Safety: N/A (Bash scope).
- Atomic Task Execution: PASS (tasks defined atomically in `tasks.md`).
- Quality Gates: PASS (unit/integration checks required before merge).
- Progressive Specification: PASS (spec -> plan -> tasks -> beads -> implementation).

No gate violations require exception.

## Project Structure

### Documentation (this feature)

```text
specs/004-telegram-e2e-harness/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
.github/workflows/
docs/
tests/
```

**Structure Decision**: Single-project infra/scripts workflow using existing repository layout.

## Phase 0: Research Decisions (to `research.md`)

1. Transport for synthetic mode: use existing authenticated Moltis chat HTTP flow.
2. Manual verdict policy: artifact-centric, no semantic assert in MVP.
3. real_user policy: MTProto test-session transport with explicit prerequisite diagnostics.
4. Security policy: strict log redaction for passwords/tokens/cookies.

## Phase 1: Design Artifacts

- Data model: define `E2ETestRun`, `E2EReportArtifact`, and status enum.
- Contracts: define CLI args, workflow inputs, and JSON schema.
- Quickstart: define local and workflow on-demand commands.

## Phase 2: Execution Readiness

- Generate atomic tasks grouped by user story.
- Import into Beads as new Epic + phase/task hierarchy.
- Start MVP implementation from US1.
