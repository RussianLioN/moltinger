# Implementation Plan: Telegram Learner Hardening

**Branch**: `[036-telegram-learner-hardening]` | **Date**: 2026-04-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/036-telegram-learner-hardening/spec.md`

## Summary

Нужно убрать дизайн-долг из `telegram-learner`: превратить его из operator-heavy handbook в thin learner-skill contract, перевести `skill_detail` ответы на value-first Telegram-safe style, добавить похожий learner skill для regression coverage и оформить guidance artifact с official/community evidence. Технический центр изменений: `skills/telegram-learner/SKILL.md`, `scripts/telegram-safe-llm-guard.sh`, component tests и новые docs/spec artifacts.

## Technical Context

**Language/Version**: Bash, Markdown, JSON hooks  
**Primary Dependencies**: `scripts/telegram-safe-llm-guard.sh`, component shell tests, runtime `SKILL.md` files  
**Storage**: repo files and live runtime-discovered skill files  
**Testing**: shell component tests, Telegram authoritative UAT, static diff checks  
**Target Platform**: Linux production container + local macOS dev shell  
**Project Type**: Infrastructure/runtime guard + skill authoring docs  
**Performance Goals**: deterministic single reply for learner-skill detail turns  
**Constraints**: Telegram-safe flows must remain text-only and fail-closed; no regression of existing skill visibility/create/template flows  
**Scale/Scope**: `telegram-learner`, one similar learner skill, docs, tests, research artifact

## Constitution Check

- Runtime-first verification: pass. Live Telegram/UAT remains required after repo changes.
- Official-first setup rule: pass. Existing project guide and upstream issues/docs must be cited before community heuristics.
- Artifact-first clarification: pass. A dedicated Speckit package is created before runtime edits.
- Test target policy: pass. Component tests validate branch correctness; remote Telegram UAT validates live runtime behavior.

## Project Structure

### Documentation (this feature)

```text
specs/036-telegram-learner-hardening/
├── plan.md
├── research.md
├── tasks.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
skills/
├── telegram-learner/
│   └── SKILL.md
└── openclaw-improvement-learner/
    └── SKILL.md

scripts/
└── telegram-safe-llm-guard.sh

tests/
└── component/
    └── test_telegram_safe_llm_guard.sh

docs/
├── moltis-skill-agent-authoring.md
└── research/
    └── 2026-04-02-telegram-learner-official-community-guidance.md
```

**Structure Decision**: Оставляем изменения внутри текущих runtime guard/docs/skills путей. Новый similar learner skill живёт рядом с `telegram-learner`, а research artifact фиксируется в `docs/research/`.

## Phase 0: Research

1. Зафиксировать official sources:
   - project guide `docs/moltis-skill-agent-authoring.md`
   - project self-learning artifact `docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md`
   - relevant OpenClaw official docs/issues on Telegram ordering and skill/tool regressions
2. Свести экспертный консилиум в минимум 7 конкретных улучшений навыка.
3. Выбрать первые 5 улучшений для немедленного внедрения.

## Phase 1: Design

1. Thin-contract redesign для `telegram-learner`:
   - dedicated Telegram-safe summary
   - official-first sourcing order
   - canonical runtime boundary
   - degraded mode
2. Generic learner-detail response design:
   - 2-3 предложения
   - value-first
   - no internal workflow markup
   - typo resolution stays silent
3. Similar learner skill:
   - focused on OpenClaw improvements/news
   - same thin-contract shape
   - suitable for regression tests

## Phase 2: Verification

1. Update component tests around learner skill detail.
2. Run shell/static checks.
3. Run live Telegram authoritative UAT for `telegram-learner` detail path.

## Post-Design Check

- Thin skill wrapper preserved: yes
- Canonical runtime boundary explicit: yes
- Official-first sourcing encoded: yes
- User-facing Telegram-safe output remains deterministic: must be validated in tests/UAT
