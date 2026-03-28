# Implementation Plan: Moltis Live Codex Update Telegram Runtime Gap

**Branch**: `035-moltis-live-codex-update-telegram-runtime-gap` | **Date**: 2026-03-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/035-moltis-live-codex-update-telegram-runtime-gap/spec.md`

## Summary

`035` продолжает deferred backlog из `034`, но смещает акцент с базового guardrail hardening на surface split:

- remote Telegram/user-facing path должен быть advisory/notification-only для `codex-update`;
- operator/local path может сохранять canonical runtime execution;
- authoritative Telegram UAT должен fail-closed не только на `false negative` и `Activity log`, но и на ответы, которые обещают не тот remote contract;
- residual live symptom должен быть описан как repo-owned carrier drift или upstream-owned runtime/transport gap, а не смешиваться в одну расплывчатую проблему.

## Technical Context

**Language/Version**: Bash, TOML, Markdown  
**Primary Dependencies**: `skills/codex-update/SKILL.md`, `config/moltis.toml`, `scripts/telegram-e2e-on-demand.sh`, shell-based component/static tests  
**Storage**: Spec/docs artifacts and existing runtime state paths only  
**Testing**: shell component/static tests plus optional authoritative live Telegram re-check  
**Target Platform**: Linux server with remote Moltis Telegram surface and local repo worktree  
**Project Type**: single repository / operations-heavy runtime integration  
**Performance Goals**: fast deterministic semantic verdicts for remote UAT and concise user-facing answers without tool-heavy drift  
**Constraints**: no feature-branch deploy as proof of correctness; hermetic tests cannot be treated as proof that live production is fixed; remote user-facing surfaces must stay advisory-only for `codex-update`  
**Scale/Scope**: one repo, one live Moltis Telegram runtime, one skill contract, one authoritative remote UAT wrapper

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS. Existing RCA, rules, live-evidence docs, config, skill prompt, and UAT wrapper were reviewed before planning.
- Single Source of Truth: PASS. Remote contract will be centralized in the spec package plus durable docs/skill/UAT carrier, not duplicated as conflicting ad hoc guidance.
- Library-First Development: PASS. No new custom subsystem or third-party library is required for this slice.
- Code Reuse & DRY: PASS. Work reuses existing `034` guardrails, `023` codex-update runtime, and current Telegram UAT wrapper rather than creating parallel flows.
- Strict Type Safety: PASS / N/A. No TypeScript surface is introduced.
- Atomic Task Execution: PASS. Tasks are structured as spec artifacts, then contract carrier, then verification.
- Quality Gates: PASS pending targeted shell tests and optional live re-check before completion.

## Project Structure

### Documentation (this feature)

```text
specs/035-moltis-live-codex-update-telegram-runtime-gap/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
skills/
└── codex-update/
    └── SKILL.md

config/
└── moltis.toml

scripts/
└── telegram-e2e-on-demand.sh

tests/
├── component/
│   └── test_telegram_remote_uat_contract.sh
└── static/
    └── test_config_validation.sh

docs/
├── moltis-codex-update-skill.md
└── telegram-e2e-on-demand.md
```

**Structure Decision**: This slice changes only the user-facing contract carrier and verification boundary. Canonical runtime scripts remain in place for trusted operator/local surfaces; remote Telegram behavior is corrected through the skill prompt, config guidance, docs, and semantic UAT enforcement.

## Complexity Tracking

No constitution violations are expected for this slice.
