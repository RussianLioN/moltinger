# Implementation Plan: Codex Update Delivery UX

**Branch**: `009-codex-update-delivery-ux` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-codex-update-delivery-ux/spec.md`

## Summary

Deliver the user-facing delivery layer on top of the completed advisor so users can ask for Codex update status in plain language, see a short alert when launching Codex through the repo launcher, and optionally receive Telegram notifications through the existing Moltinger bot path.

## Technical Context

**Language/Version**: Bash plus existing repository command and launcher docs
**Primary Dependencies**: `bash`, `jq`, `python3`, `scripts/codex-cli-update-advisor.sh`, `scripts/codex-profile-launch.sh`, `scripts/telegram-bot-send.sh`
**Storage**: JSON delivery report, per-surface delivery state file, shell fixtures, command or skill docs
**Testing**: Bash syntax checks plus targeted component tests under `tests/component/`
**Target Platform**: Linux/macOS shell for local launch flows and Telegram bot delivery through existing repo automation
**Project Type**: Operational shell script + launcher integration + command or skill surface + docs
**Performance Goals**: Launch-time check should complete fast enough to show a short alert without materially delaying Codex startup under normal conditions
**Constraints**: Reuse `008` advisor as single source of truth, launch-time path must fail open, Telegram delivery remains opt-in, no in-session TUI patching in v1, shared delivery state must stay deterministic
**Scale/Scope**: Single repository, one shared delivery state model, three initial surfaces: on-demand text request, launcher alert, Telegram

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (`008` advisor, launcher script, Telegram sender, and repo command surfaces were reviewed before planning `009`).
- Single Source of Truth: PASS (`008` advisor remains the only source for recommendation and repo-suggestion logic; `009` adds delivery only).
- Library-First Development: PASS (existing shell and repo delivery primitives cover v1 scope; no new library is required).
- Code Reuse & DRY: PASS (delivery will wrap existing advisor and existing Telegram sender rather than duplicating them).
- Strict Type Safety: N/A (Bash scope; JSON schema will carry contract discipline instead).
- Atomic Task Execution: PASS (tasks will be grouped by setup, foundations, and independently testable delivery surfaces).
- Quality Gates: PASS (syntax checks, fixture-backed component tests, and launcher-safe validation are planned before push).
- Progressive Specification: PASS (spec, plan, tasks, analyze, Beads import, and implementation stay sequential).

No gate violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/009-codex-update-delivery-ux/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- delivery-report.schema.json
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Source Code (repository root)

```text
scripts/
|-- codex-cli-update-advisor.sh
|-- codex-cli-update-delivery.sh
|-- codex-profile-launch.sh
|-- telegram-bot-send.sh
`-- manifest.json

.claude/
|-- commands/
|   `-- codex-update.md
`-- skills/
    `-- codex-update-delivery/

tests/
|-- component/
|   `-- test_codex_cli_update_delivery.sh
`-- fixtures/
    `-- codex-update-delivery/

docs/
`-- codex-update-delivery.md
```

**Structure Decision**: Implement one delivery script that wraps the advisor, then connect it to three repo-native surfaces: Codex-facing command or skill docs, launcher preflight alert, and Telegram send through the existing bot sender.

## Phase 0: Research Decisions (to `research.md`)

1. Use the completed advisor as the only recommendation source and add delivery logic on top.
2. Support natural-language Codex usage through a repo command or skill wrapper instead of raw script flags.
3. Hook launch-time alerts into `scripts/codex-profile-launch.sh` as a non-blocking pre-session check.
4. Reuse `scripts/telegram-bot-send.sh` and existing Moltinger bot configuration for Telegram delivery.
5. Keep one shared delivery state model so on-demand, launcher, and Telegram surfaces do not spam independently.

## Phase 1: Design Artifacts

- Data model for advisor snapshot input, delivery fingerprint, per-surface delivery state, and Telegram target configuration.
- JSON schema for the delivery report.
- Quickstart showing on-demand text UX, launcher alert, and Telegram delivery behavior.
- Tasks grouped by delivery surface so implementation can land incrementally.

## Phase 2: Execution Readiness

- One delivery script becomes the shared runtime entrypoint.
- Launcher integration stays fail-open and does not block Codex startup.
- Telegram delivery stays opt-in and state-aware.
- Command or skill docs provide a user-facing plain-language entrypoint instead of forcing direct script use.
