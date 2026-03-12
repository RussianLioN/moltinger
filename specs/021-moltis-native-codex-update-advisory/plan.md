# Implementation Plan: Moltis-Native Codex Update Advisory Flow

**Branch**: `021-moltis-native-codex-update-advisory` | **Date**: 2026-03-12 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/021-moltis-native-codex-update-advisory/spec.md`

## Summary

Retire the repo-side Codex bridge as a user-facing Telegram workflow and replace it with a Moltis-native advisory flow. Repo-side tooling remains responsible for upstream watching and recommendation preparation, but Moltis becomes the single owner of Telegram alert delivery, callback handling, consent state, and immediate follow-up recommendations.

## Technical Context

**Language/Version**: Repository-managed shell/docs/config integration plus Moltis runtime capabilities for Telegram ingress and callbacks  
**Primary Dependencies**: `scripts/codex-cli-upstream-watcher.sh`, `scripts/codex-cli-update-advisor.sh`, `config/moltis.toml`, Moltis Telegram ingress runtime, `scripts/telegram-bot-send.sh`, `.github/workflows/deploy.yml`  
**Storage**: Normalized advisory JSON/report, Moltis advisory state, Telegram audit records, docs, config  
**Testing**: Bash syntax checks for producer-side changes, component tests for contract generation, live or hermetic E2E for Moltis callback flow  
**Target Platform**: Moltis production runtime plus repo-managed producer scripts and deployment assets  
**Project Type**: Cross-boundary integration feature with one repo-side producer layer and one Moltis-native user-facing layer  
**Performance Goals**: Fresh advisory alert and accepted follow-up should complete quickly enough for conversational Telegram UX  
**Constraints**: One-consumer rule for Telegram ingress, all human-facing UX in Russian, no production reliance on text-command reply keyboards, preserve GitOps rollout discipline, degrade safely to one-way alerts  
**Scale/Scope**: Single repository, single Telegram bot runtime, one normalized advisory contract, one interactive advisory state machine

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (`009`, `012`, `017`, live logs, and consilium evidence were reviewed before opening `021`).
- Single Source of Truth: PASS (repo-side watcher/advisor remain the source of Codex update evidence; Moltis becomes the single source of Telegram dialogue state).
- Library-First Development: PASS (reuse existing watcher/advisor outputs and Moltis Telegram runtime instead of inventing another consumer).
- Code Reuse & DRY: PASS (no second pseudo-bot or duplicate Telegram dialog owner is planned).
- Strict Type Safety: PASS via contract/schema for advisory event and interaction records.
- Atomic Task Execution: PASS (retire old bridge -> define contract -> wire Moltis-native alert -> wire callback follow-up -> verify degrade mode).
- Quality Gates: PASS (sync checks, targeted contract validation, and live acceptance are planned before rollout).
- Progressive Specification: PASS (spec -> plan -> tasks now, then future analyze/tobeads/implement).

No gate violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/021-moltis-native-codex-update-advisory/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- advisory-event.schema.json
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Repository Integration Surface

```text
.claude/
|-- commands/
`-- skills/

scripts/
|-- codex-cli-upstream-watcher.sh
|-- codex-cli-update-advisor.sh
`-- telegram-bot-send.sh

config/
`-- moltis.toml

docs/
|-- codex-update-delivery.md
`-- codex-cli-upstream-watcher.md
```

**Structure Decision**: Keep watcher/advisor logic in the repository as producer-side tooling, but define a clean contract so Moltis can own the live Telegram advisory UX natively.

## Phase 0: Research Decisions (to `research.md`)

1. Keep repo-side watcher/advisor as `producer only`.
2. Make Moltis the single owner of Telegram alerting, callbacks, consent state, and follow-up delivery.
3. Use inline callback buttons as the primary UX and deep-link or tokenized recovery as fallback.
4. Remove the old Codex bridge from active discovery so users are not routed into a broken path.
5. Preserve one-way alert mode as the safe degraded production behavior until the Moltis-native interactive path is ready.

## Phase 1: Design Artifacts

- Stable advisory event schema from repo to Moltis.
- Data model for alert state, callback state, follow-up state, and degraded-mode records.
- Quickstart covering one-way mode, healthy callback mode, and degraded fallback.
- Tasks grouped by bridge retirement, producer contract, Moltis-native alerting, follow-up delivery, and verification.

## Phase 2: Execution Readiness

- Old Codex bridge entrypoints are retired and documented.
- Repo-side producer contract is explicit and testable.
- Moltis-native Telegram alert flow is the target user-facing replacement.
- Degraded one-way mode remains available until the interactive runtime path is verified live.
