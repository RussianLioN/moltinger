# Generic RCA Template

**Тип ошибки:** General / Unknown

## Standard 5-Why Analysis

```
Ошибка (симптом)
    ↓
Вопрос 1: Почему это произошло?
    ↓
Ответ 1 → Причина уровня 1
    ↓
Вопрос 2: Почему [Ответ 1]?
    ↓
Ответ 2 → Причина уровня 2
    ↓
Вопрос 3: Почему [Ответ 2]?
    ↓
Ответ 3 → Причина уровня 3
    ↓
Вопрос 4: Почему [Ответ 3]?
    ↓
Ответ 4 → Причина уровня 4
    ↓
Вопрос 5: Почему [Ответ 4]?
    ↓
Ответ 5 → КОРНЕВАЯ ПРИЧИНА
```

## 5 Whys Framework

### Why 1: Symptom
**Почему [ошибка произошла?]**
- Что именно случилось?
- Когда это случилось?
- Где это случилось?
- Как это проявилось?

→ Причина уровня 1: _______________

### Why 2: Direct Cause
**Почему [Причина 1]?**
- Какое событие привело к этому?
- Что было непосредственно перед этим?
- Какая система/процесс задействована?

→ Причина уровня 2: _______________

### Why 3: Contributing Factor
**Почему [Причина 2]?**
- Какие условия способствовали?
- Какая конфигурация/настройка?
- Какое окружение?

→ Причина уровня 3: _______________

### Why 4: Process/Design
**Почему [Причина 3]?**
- Какой процесс не сработал?
- Какое проектное решение?
- Какое предположение было неверным?

→ Причина уровня 4: _______________

### Why 5: Root Cause
**Почему [Причина 4]?**
- Это системная проблема?
- Это проблема обучения?
- Это проблема инструментов?
- Это проблема культуры?

→ **КОРНЕВАЯ ПРИЧИНА:** _______________

## Root Cause Categories

| Category | Examples | Fix Type |
|----------|----------|----------|
| **Process** | Missing step, wrong order | Update procedure |
| **Tooling** | Missing tool, misconfigured | Add/fix tool |
| **Training** | Knowledge gap, skill gap | Documentation, training |
| **Design** | Architecture flaw, bad pattern | Redesign |
| **Culture** | Incentives, priorities | Policy change |

## Validation Checklist

Перед тем как принять корневую причину:

- [ ] **Actionable?** - Можно ли на это повлиять?
- [ ] **Systemic?** - Это системная проблема (не ошибка человека)?
- [ ] **Preventable?** - Можно ли предотвратить в будущем?
- [ ] **Specific?** - Причина конкретна, не расплывчата?
- [ ] **Evidence-based?** - Есть доказательства?

## Generic RCA Example

```
❌ ОШИБКА: npm install fails with EACCES error

📝 Q1: Почему npm install падает?
   → Permission denied writing to node_modules

📝 Q2: Почему нет прав на запись?
   → Directory owned by root user

📝 Q3: Почему владелец root?
   → Previous sudo npm install changed ownership

📝 Q4: Почему использовали sudo?
   → Initial install failed without sudo

📝 Q5: Почему первоначальный install failed?
   → npm global prefix points to system directory
   → No user-level npm configuration

🎯 КОРНЕВАЯ ПРИЧИНА:
   Missing npm prefix configuration causes permission issues

📋 ДЕЙСТВИЯ:
   1. Fix directory ownership: sudo chown -R $USER node_modules
   2. Configure npm prefix: npm config set prefix ~/.npm-global
   3. Add to PATH in .bashrc/.zshrc
   4. Document in project README
```

## Quick Analysis Template

```
┌─────────────────────────────────────────┐
│  ERROR: [one-line description]          │
├─────────────────────────────────────────┤
│  IMPACT: [who/what affected]            │
├─────────────────────────────────────────┤
│  TIMELINE: [when it started/ended]      │
├─────────────────────────────────────────┤
│  ROOT CAUSE: [5th why answer]           │
├─────────────────────────────────────────┤
│  FIX: [what was done]                   │
├─────────────────────────────────────────┤
│  PREVENTION: [how to avoid]             │
└─────────────────────────────────────────┘
```

---
*Универсальный шаблон для RCA анализа*
