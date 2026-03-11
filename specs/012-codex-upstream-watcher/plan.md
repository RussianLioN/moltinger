# Implementation Plan: Codex Upstream Watcher

**Branch**: `012-codex-upstream-watcher` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/012-codex-upstream-watcher/spec.md`

## Summary

Add a dedicated upstream watcher layer that polls official Codex sources on a schedule, persists one stable upstream fingerprint, assigns a severity level, optionally batches non-critical events into a digest, and sends Russian Telegram alerts through Moltinger when a fresh upstream Codex state appears, without requiring a local Codex CLI on the watcher host. Extend the watcher with an opt-in advisor bridge so a user can explicitly ask for practical project recommendations after the alert.

## Technical Context

**Language/Version**: Bash plus existing repository operational scripts and cron automation  
**Primary Dependencies**: `bash`, `curl`, `jq`, `python3`, `scripts/telegram-bot-send.sh`, `scripts/codex-cli-update-monitor.sh`, `.github/workflows/deploy.yml`, `scripts/cron.d/`  
**Storage**: JSON watcher report, persisted watcher state file, shell fixtures, cron file, docs  
**Testing**: Bash syntax checks plus targeted component tests under `tests/component/`  
**Target Platform**: Linux shell on the Moltinger host for scheduled runs; optional local/manual dry runs and CI-safe fixture validation  
**Project Type**: Operational shell script + cron automation + Telegram alerting + docs  
**Performance Goals**: Scheduled run should finish quickly enough for cron use and never block unrelated services  
**Constraints**: Use official Codex sources as primary truth, keep upstream awareness separate from project advice until user consent is received, preserve GitOps install path, keep Telegram delivery duplicate-safe, degrade explicitly on partial or failed source evidence, keep all human-facing UX in Russian  
**Scale/Scope**: Single repository, one shared watcher state model, one Telegram delivery surface, one digest queue, one consent-follow-up path

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (`007-009` artifacts, deploy workflow, cron patterns, and Telegram sender were reviewed before planning `012`).
- Single Source of Truth: PASS (official Codex changelog remains primary source of release truth; repository-managed cron/deploy files remain the deployment source of truth).
- Library-First Development: PASS (existing shell + `curl`/`jq`/`python3` tooling and Telegram sender are sufficient for v1).
- Code Reuse & DRY: PASS (`012` reuses the existing Telegram transport and upstream parsing lessons from `007` rather than creating another notification stack).
- Strict Type Safety: N/A (Bash scope; JSON schema will enforce the report contract).
- Atomic Task Execution: PASS (tasks will land by manual run, scheduler alerting, then failure/recovery behavior).
- Quality Gates: PASS (syntax checks, fixture-backed component tests, and GitOps-safe validation are planned before push).
- Progressive Specification: PASS (spec, plan, tasks, analyze, Beads import, and implementation remain sequential).

No gate violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/012-codex-upstream-watcher/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- watcher-report.schema.json
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Source Code (repository root)

```text
scripts/
|-- codex-cli-update-monitor.sh
|-- codex-cli-upstream-watcher.sh
|-- telegram-bot-send.sh
|-- cron.d/
|   `-- moltis-codex-upstream-watcher
`-- manifest.json

tests/
|-- component/
|   `-- test_codex_cli_upstream_watcher.sh
`-- fixtures/
    `-- codex-upstream-watcher/

.github/
`-- workflows/
    `-- codex-cli-upstream-watcher.yml

docs/
`-- codex-cli-upstream-watcher.md
```

**Structure Decision**: Implement one dedicated watcher script for upstream-only polling and scheduler-safe Telegram alerts. Keep upstream awareness separate from local applicability by building project-facing recommendations only through an explicit advisor bridge and only sending them after user consent.

## Phase 0: Research Decisions (to `research.md`)

1. Keep the official Codex changelog as the primary upstream truth and optional issue signals as advisory only.
2. Install the scheduler through repository-managed cron files on the Moltinger host rather than inventing a manual server-only setup path.
3. Reuse the existing Moltinger Telegram sender for scheduled alerts instead of adding another transport.
4. Persist a watcher-specific fingerprint and delivery state so repeated cron runs remain duplicate-safe.
5. Keep local repo applicability separate from the main alert and expose it only through an explicit advisor bridge after user consent.
6. Add severity levels and a digest mode so the watcher can stay informative without becoming noisy.

## Phase 1: Design Artifacts

- Data model for upstream snapshot, upstream fingerprint, watcher state, watcher severity, digest queue, consent state, advisor bridge, Telegram target, and watcher run report.
- JSON schema for the watcher report.
- Quickstart showing manual run, scheduled run, and failure/recovery validation.
- Tasks grouped by manual run, scheduler alerting, digest/consent UX, and resilience behavior.

## Phase 2: Execution Readiness

- One upstream watcher script becomes the shared runtime entrypoint.
- Cron automation is installed through existing deploy/GitOps paths.
- Telegram delivery stays duplicate-safe, retry-aware, and can optionally ask whether the user wants practical project recommendations.
- The watcher report remains reusable by future integrations and now exposes a first bridge into the local advisor layer.
