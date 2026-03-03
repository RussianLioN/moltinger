# Research: RCA Skill Enhancements

**Feature**: 001-rca-skill-upgrades
**Date**: 2026-03-03
**Status**: Complete

## Research Summary

Исследование проведено на основе консилиума 13 экспертов. Все технические решения основаны на рекомендациях специалистов и анализе существующего кода.

---

## Decision 1: Auto-Context Collection

**Вопрос**: Как автоматически собирать контекст при ошибках?

**Решение**: Bash-скрипт `context-collector.sh` с модульной структурой для разных типов ошибок.

**Rationale**:
- Bash уже используется в проекте (scripts/)
- Совместимость с Claude Code sandbox
- Быстрое выполнение (< 5 сек)
- Не требует внешних зависимостей

**Alternatives Considered**:
| Альтернатива | Почему отклонена |
|--------------|------------------|
| Python script | Требует Python, медленнее для простых операций |
| Node.js script | Требует Node, избыточно для системного контекста |
| Pure LLM prompt | Не гарантирует полноту, зависит от контекста |

**Implementation**:
```bash
# .claude/skills/rca-5-whys/lib/context-collector.sh
collect_context() {
    local error_type="$1"

    echo "🔍 AUTO-CONTEXT COLLECTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Base context (always collected)
    echo "Timestamp: $(date -Iseconds)"
    echo "PWD: $(pwd)"
    echo "Shell: ${SHELL:-unknown}"

    # Git context (if available)
    if git rev-parse --git-dir &>/dev/null; then
        echo "Git Branch: $(git branch --show-current)"
        echo "Git Status: $(git status --short | head -5)"
    fi

    # Docker context (if docker error)
    if [[ "$error_type" == "docker" ]]; then
        echo "Docker Version: $(docker --version 2>/dev/null || echo 'N/A')"
        echo "Containers: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
    fi

    # System context
    echo "Disk: $(df -h . | tail -1 | awk '{print $5}')"
    echo "Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $3 "/" $2}' || echo 'N/A')"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
```

---

## Decision 2: Domain-Specific Templates

**Вопрос**: Как структурировать доменно-специфичные шаблоны?

**Решение**: Отдельные Markdown файлы в `templates/` директории с единым интерфейсом.

**Rationale**:
- LLM может читать конкретный шаблон по типу ошибки
- Легко добавлять новые домены
- Консистентный формат для всех шаблонов

**Template Structure**:
```markdown
# [Domain] RCA Template

## Trigger Conditions
- Condition 1
- Condition 2

## Layer Analysis
| Layer | Check | Status |
|-------|-------|--------|
| ... | ... | ❓ |

## Domain-Specific 5 Whys
1. Почему [domain error]? → ...
2. ...

## Required Actions
- [ ] Action 1
- [ ] Action 2
```

**Templates to Create**:
1. `docker.md` - Layer Analysis (Image → Container → Network → Volume → Runtime)
2. `cicd.md` - Pipeline Analysis (Workflow → Job → Step → Action)
3. `data-loss.md` - Critical Protocol (STOP → SNAPSHOT → ASSESS → RESTORE → ANALYZE)
4. `generic.md` - Standard 5-Why (fallback)

---

## Decision 3: RCA Hub Architecture

**Вопрос**: Как организовать INDEX.md и связи между RCA?

**Решение**: Markdown INDEX с JSON frontmatter для метаданных и скрипт для автообновления.

**Rationale**:
- Git-versioned (GitOps compliance)
- Human-readable
- LLM-parseable
- No external database needed

**INDEX.md Structure**:
```markdown
# RCA Registry

## Statistics
- **Total RCA**: N
- **By Category**: docker (X), cicd (Y), shell (Z)
- **Avg Resolution**: Xm Ys

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-001 | 2026-03-03 | docker | P1 | ✅ Fixed | Wrong network | Commit: abc123 |

## Patterns Detected
⚠️ 3+ RCA in category "docker" - consider systemic fix
```

**ID Format**: `RCA-NNN` (sequential, per-project)

---

## Decision 4: Chain-of-Thought Pattern

**Вопрос**: Как интегрировать CoT в RCA процесс?

**Решение**: Добавить структурированные секции в SKILL.md с пошаговым процессом.

**CoT Structure**:
```
1. Error Classification
   - Type: [infra | code | config | process | communication]
   - Confidence: [high | medium | low]
   - Context Quality: [sufficient | partial | insufficient]

2. Hypothesis Generation
   - H1: [cause] (confidence: X%)
   - H2: [cause] (confidence: Y%)
   - H3: [cause] (confidence: Z%)

3. 5 Whys with Evidence
   - Q1: Why? → A1 (evidence: [source])
   - ...

4. Root Cause Validation
   - Actionable? [yes/no]
   - Systemic? [yes/no]
   - Preventable? [yes/no]
```

**Rationale**: Улучшает качество рассуждений LLM без внешних зависимостей.

---

## Decision 5: Test Generation

**Вопрос**: Как генерировать regression тесты из RCA?

**Решение**: Шаблон теста в SKILL.md с Given/When/Then структурой из RCA контекста.

**Test Template**:
```typescript
describe('RCA-[ID]: [Short Description]', () => {
  it('should [expected behavior]', async () => {
    // Given: [setup from RCA context]
    // When: [action that caused error]
    // Then: [expected outcome, not error]
  });
});
```

**Constraints**:
- Только для code-ошибок (не infra/process)
- Требует подтверждения пользователя
- Директория: `tests/rca/`

---

## Library Decisions

| Library | Decision | Rationale |
|---------|----------|-----------|
| External RCA tools | ❌ NOT USED | Claude Code native skills sufficient |
| JSON Schema validation | ❌ NOT NEEDED | Markdown-based, LLM validates structure |
| Test framework | ✅ Vitest (existing) | Project already uses Vitest |

---

## Open Questions (Resolved)

| Question | Resolution |
|----------|------------|
| Как определять тип ошибки? | Pattern matching в error message (docker, npm, git, etc.) |
| Где хранить INDEX.md? | `docs/rca/INDEX.md` (GitOps-compliant) |
| Как обрабатывать sandbox ограничения? | Bash скрипты с fallback для недоступных команд |
| Нужен ли JSON формат? | Нет, Markdown достаточно для LLM |

---

## Implementation Priority

Based on User Story priorities:

1. **P1 - Auto-Context Collection** (Task #1)
   - Core functionality, affects all RCA
   - Dependencies: None

2. **P1 - Domain-Specific Templates** (Task #2)
   - Quality improvement for common error types
   - Dependencies: Template structure defined

3. **P2 - RCA Hub Architecture** (Task #3)
   - Strategic improvement, enables analytics
   - Dependencies: None

4. **P2 - Chain-of-Thought Pattern** (Task #4)
   - Quality improvement for reasoning
   - Dependencies: None

5. **P3 - Test Generation** (Task #5)
   - Nice-to-have, requires test infrastructure
   - Dependencies: Vitest setup

6. **Integration** (Task #6)
   - Final step, connect all components
   - Dependencies: All above
