# Implementation Plan: Project Remediation Blockers

**Branch**: `[fix/project-remediation-blockers]` | **Date**: 2026-04-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/041-project-remediation-blockers/spec.md`

## Summary

Сначала закрываем блокирующие дефекты, которые прямо бьют по user-facing Telegram, active provider/deploy contract и reliability of preflight/GitHub checks. Затем доказываем исправления targeted tests и narrow live/runtime evidence.

## Technical Context

**Language/Version**: Bash, TOML, YAML, Markdown
**Primary Dependencies**: `scripts/preflight-check.sh`, `scripts/telegram-safe-llm-guard.sh`, `config/moltis.toml`, `.github/workflows/*`, `tests/*`
**Storage**: repo files + runtime/deploy config
**Testing**: shell unit/component/static suites, preflight JSON, live/provider smoke where safe
**Target Platform**: macOS dev shell, Linux CI/production container
**Project Type**: shared runtime/deploy/test contracts
**Performance Goals**: deterministic Telegram-safe delivery; no false-negative config parsing; no noisy legacy provider drift
**Constraints**: не ломать explicit skill CRUD flow, не переписывать исторические RCA как будто они current config, не внедрять unproven provider aliasing
**Scale/Scope**: runtime guard, config, tests, workflows, active deploy surface

## Constitution Check

- Runtime target policy: pass. Repo fixes доказываются hermetic/static tests; live используется только для authoritative remote proof.
- Official-only setup rule: pass. Для provider/deploy contracts используем tracked repo truth и official provider assumptions из current runtime docs.
- Artifact-first clarification: pass. Новый Speckit package создан до runtime edits.
- Shared-contract rule: pass. Работа идёт в отдельной worktree/branch от `origin/main`.

## Project Structure

### Documentation (this feature)

```text
specs/041-project-remediation-blockers/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
config/
└── moltis.toml

scripts/
├── preflight-check.sh
├── telegram-safe-llm-guard.sh
├── prepare-moltis-runtime-config.sh
└── moltis-runtime-attestation.sh

.github/workflows/
├── deploy.yml
├── deploy-clawdiy.yml
└── moltis-update-proposal.yml

tests/
├── component/
├── static/
└── live_external/
```

**Structure Decision**: Правим существующие shared contracts in place. Отдельные compatibility/stale artifacts переводим либо в inactive/hygiene bucket, либо удаляем, если они still belong to active surface and violate the new provider policy.

## Phase 0: Baseline And Spec

1. Зафиксировать blocking surface в `041`: Telegram-safe maintenance, provider/failover contract, preflight/workflow drift.
2. Перечитать релевантные RCA/lessons и active repo evidence.

## Phase 1: Runtime And Provider Contract

1. Убрать active GLM/Z.ai drift из deploy/test/config/runtime surfaces.
2. Закрепить primary `openai-codex::gpt-5.4` + Ollama-only fallback contract.
3. Привести provider/live proof к проверке both primary and fallback.

## Phase 2: Telegram-safe Containment

1. Сверить Telegram-safe guard/tests/UAT against observed maintenance/debug leakage.
2. Устранить shared contract drift между guard, config, static checks and authoritative UAT.

## Phase 3: Preflight And Workflow Reliability

1. Заменить brittle TOML parsing in `preflight` на cross-platform helper.
2. Убрать active workflow noise from stale provider/deploy assumptions.
3. Довести targeted static/workflow checks до one-source-of-truth behavior.

## Phase 4: Verification

1. Запустить targeted component/static/unit checks.
2. Повторно прогнать `preflight` JSON.
3. Запустить narrow provider/live proof only where it answers live-surface questions.

## Post-Design Check

- Telegram-safe maintenance path terminalized: must be validated
- Primary provider + fallback chain explicit: yes
- Cross-platform preflight parsing explicit: yes
- Active GLM drift treated as blocker, not as documentation-only issue: yes
