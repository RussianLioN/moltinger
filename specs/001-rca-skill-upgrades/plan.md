# Implementation Plan: RCA Skill Enhancements

**Branch**: `001-rca-skill-upgrades` | **Date**: 2026-03-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-rca-skill-upgrades/spec.md`

## Summary

Улучшение навыка Root Cause Analysis (RCA) "5 Почему" на основе рекомендаций консилиума из 13 экспертов. Трансформация из изолированного инструмента в центральный узел системы анализа ошибок с:
- Автоматическим сбором контекста (git, docker, system)
- Доменно-специфичными шаблонами (Docker, CI/CD, Data Loss)
- Chain-of-Thought структурой рассуждений
- Генерацией regression тестов

**Технический подход**: Расширение существующего skill `.claude/skills/rca-5-whys/SKILL.md` с добавлением вспомогательных шаблонов, скриптов сбора контекста и интеграцией с `systematic-debugging` skill.

## Technical Context

**Language/Version**: Markdown (skill definitions) + Bash (context collection scripts)
**Primary Dependencies**: Claude Code Skills system, existing `rca-5-whys` skill, `systematic-debugging` skill
**Storage**: File-based (`docs/rca/`, `tests/rca/`)
**Testing**: Manual verification in new Claude Code session + regression test generation
**Target Platform**: Claude Code CLI (cross-platform)
**Project Type**: Single (skill enhancement)
**Performance Goals**: Auto-context collection < 5 seconds, RCA Index search < 10 seconds
**Constraints**: Must work within Claude Code sandbox restrictions
**Scale/Scope**: 5 user stories, 26 functional requirements, affecting all error handling workflows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | ✅ PASS | Existing `rca-5-whys` skill read, `systematic-debugging` analyzed |
| II. Single Source of Truth | ✅ PASS | RCA templates in single location, INDEX.md as registry |
| III. Library-First Development | ✅ PASS | Using existing Claude Code skills system, no new libraries needed |
| IV. Code Reuse & DRY | ✅ PASS | Extending existing skill, not creating new one |
| V. Strict Type Safety | ✅ N/A | Markdown/Bash - no TypeScript |
| VI. Atomic Task Execution | ✅ PASS | 6 atomic tasks defined in TODO |
| VII. Quality Gates | ✅ PASS | Manual testing in new session defined |
| VIII. Progressive Specification | ✅ PASS | Spec → Plan → Tasks → Implement workflow followed |

**Gate Status**: ✅ ALL PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/001-rca-skill-upgrades/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output - RCA entities
├── quickstart.md        # Phase 1 output - Usage guide
├── contracts/           # Phase 1 output - Template schemas
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
.claude/skills/
├── rca-5-whys/
│   ├── SKILL.md              # Main skill (enhanced)
│   ├── templates/
│   │   ├── docker.md         # Docker-specific RCA template
│   │   ├── cicd.md           # CI/CD-specific RCA template
│   │   ├── data-loss.md      # Data loss critical protocol
│   │   └── generic.md        # Generic 5-Why template
│   └── lib/
│       ├── context-collector.sh   # Auto-context collection
│       └── rca-index.sh           # INDEX.md management
│
└── systematic-debugging/
    └── SKILL.md              # Updated with RCA integration

docs/rca/
├── INDEX.md                  # RCA registry (new)
├── TEMPLATE.md               # Updated template
└── YYYY-MM-DD-*.md           # RCA reports

tests/rca/
└── RCA-NNN.test.ts           # Generated regression tests
```

**Structure Decision**: Single project structure with skill enhancement. All changes within `.claude/skills/` and `docs/rca/` directories.

## Complexity Tracking

> No violations - Constitution Check passed all gates.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
