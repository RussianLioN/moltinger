# Implementation Plan: Telegram Skill Detail Hardening

**Branch**: `[040-telegram-skill-detail-hardening]` | **Date**: 2026-04-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/040-telegram-skill-detail-hardening/spec.md`

## Summary

Нужно превратить Telegram `skill_detail` из набора эвристических fixes в общий контракт. Для этого делаем две вещи: терминализируем `skill_detail` как no-tool mode в runtime guard и унифицируем frontmatter contract у repo-managed user-facing skills, чтобы user-facing summary не зависел от operator-heavy body `SKILL.md`.

## Technical Context

**Language/Version**: Bash, Markdown, JSON hooks  
**Primary Dependencies**: `scripts/telegram-safe-llm-guard.sh`, repo `skills/*/SKILL.md`, shell component/static tests  
**Storage**: repo files + live runtime-discovered skills  
**Testing**: shell component tests, static validation, authoritative Telegram UAT  
**Target Platform**: Linux production container + local macOS dev shell  
**Project Type**: Telegram runtime guard + skill authoring contract  
**Performance Goals**: deterministic single skill-detail reply without tool dispatch/tail leakage  
**Constraints**: не ломать existing visibility/create/template flows; сохранить Tavily allowlist для non-skill-detail research turns  
**Scale/Scope**: runtime guard, 2 repo skills, docs, specs, RCA, live UAT

## Constitution Check

- Runtime-first verification: pass. Live Telegram UAT остаётся обязательным.
- Official-first setup rule: pass. OpenClaw official docs/issues используются как primary evidence.
- Artifact-first clarification: pass. Новый Speckit package создаётся под новый lane.
- Test target policy: pass. Component/static suites доказывают branch correctness; authoritative Telegram UAT доказывает live behavior.

## Project Structure

### Documentation (this feature)

```text
specs/040-telegram-skill-detail-hardening/
├── plan.md
├── research.md
├── tasks.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
skills/
├── codex-update/
│   └── SKILL.md
├── post-close-task-classifier/
│   └── SKILL.md
├── telegram-learner/
│   └── SKILL.md
└── openclaw-improvement-learner/
    └── SKILL.md

scripts/
└── telegram-safe-llm-guard.sh

tests/
├── component/
│   └── test_telegram_safe_llm_guard.sh
└── static/
    └── test_config_validation.sh
```

**Structure Decision**: Изменения остаются в текущем runtime guard и в repo-managed skills. Новый package фиксирует уже не learner-only, а общий skill-detail hardening scope.

## Phase 0: Research

1. Подтвердить official skill contract по OpenClaw docs.
2. Сверить релевантные upstream issues по Telegram delivery / tool ordering / skill regressions.
3. Собрать consilium findings в ranked improvement set.

## Phase 1: Runtime Contract

1. Считать `skill_detail` terminal mode после классификации turn.
2. Подавить tool dispatch в BeforeToolCall даже для allowlisted Tavily, если intent уже `skill_detail`.
3. Сохранить allowlisted Tavily path только для non-skill-detail research turns.

## Phase 2: Authoring Contract

1. Унифицировать frontmatter у repo-managed user-facing skills.
2. Зафиксировать этот contract в authoring guide.
3. Проверять contract статически, а не только через runtime component tests.

## Phase 3: Verification

1. Расширить component coverage на additional skills.
2. Добавить coverage на persisted `skill_detail` + blocked Tavily.
3. Прогнать static suite.
4. Прогнать authoritative Telegram UAT.

## Post-Design Check

- Terminal skill-detail mode explicit: yes
- Shared frontmatter contract explicit: yes
- Existing non-skill-detail Tavily research path preserved: must be validated in tests
- Live Telegram behavior still requires authoritative UAT: yes
