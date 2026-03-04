# Data Model: RCA Skill Enhancements

**Feature**: 001-rca-skill-upgrades
**Date**: 2026-03-03

## Entities Overview

```
┌─────────────────┐     ┌─────────────────┐
│   RCA Report    │────▶│   RCA Context   │
│   (Markdown)    │     │   (Collected)   │
└────────┬────────┘     └─────────────────┘
         │
         │ references
         ▼
┌─────────────────┐     ┌─────────────────┐
│   RCA Index     │────▶│  RCA Template   │
│   (Registry)    │     │   (Domain)      │
└─────────────────┘     └─────────────────┘
         │
         │ generates
         ▼
┌─────────────────┐
│   RCA Test      │
│   (Regression)  │
└─────────────────┘
```

---

## Entity: RCA Report

**Description**: Документ анализа ошибки, основной output навыка

**Location**: `docs/rca/YYYY-MM-DD-[topic].md`

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | ✅ | Unique identifier (RCA-NNN) |
| date | date | ✅ | ISO date (YYYY-MM-DD) |
| title | string | ✅ | Short description |
| status | enum | ✅ | `draft` \| `in_progress` \| `resolved` |
| category | enum | ✅ | `docker` \| `cicd` \| `shell` \| `data-loss` \| `generic` |
| severity | enum | ✅ | `P0` \| `P1` \| `P2` \| `P3` \| `P4` |
| error | string | ✅ | Error message/symptom |
| five_whys | array | ✅ | 5 Q&A pairs with evidence |
| root_cause | string | ✅ | Final systemic cause |
| actions | array | ✅ | List of actions taken |
| context | object | ✅ | Collected environment data |
| related | array | ⚪ | Related RCA IDs |
| test_file | string | ⚪ | Path to regression test |
| commit_fix | string | ⚪ | Git commit SHA |

**State Transitions**:
```
draft → in_progress → resolved
         ↑_______________|
         (if fix failed)
```

**Validation Rules**:
- ID must match pattern `RCA-\d{3}`
- Date must be valid ISO date
- 5 Whys must have minimum 3 levels
- Root cause must be systemic (not individual blame)
- At least one action required

---

## Entity: RCA Context

**Description**: Автоматически собранные данные окружения

**Fields**:

| Field | Type | Source |
|-------|------|--------|
| timestamp | datetime | `date -Iseconds` |
| pwd | string | `pwd` |
| shell | string | `$SHELL` |
| git_branch | string | `git branch --show-current` |
| git_status | string | `git status --short` |
| docker_version | string | `docker --version` |
| docker_containers | array | `docker ps` |
| disk_usage | string | `df -h` |
| memory_usage | string | `free -h` |
| error_type | enum | Pattern detection |

**Collection Triggers**:
- Any command with exit code != 0
- Manual trigger via `/rca-5-whys`

---

## Entity: RCA Index

**Description**: Реестр всех RCA с метаданными

**Location**: `docs/rca/INDEX.md`

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| total_count | number | Total RCA reports |
| by_category | object | Count per category |
| by_severity | object | Count per severity |
| avg_resolution_time | string | Average time to resolve |
| patterns | array | Detected patterns/warnings |
| registry | array | List of RCA entries |

**Index Entry Structure**:
```json
{
  "id": "RCA-001",
  "date": "2026-03-03",
  "category": "docker",
  "severity": "P1",
  "status": "resolved",
  "root_cause": "Wrong network label",
  "fix_commit": "abc123"
}
```

---

## Entity: RCA Template

**Description**: Доменно-специфичный шаблон для анализа

**Location**: `.claude/skills/rca-5-whys/templates/[domain].md`

**Types**:

| Template | Trigger Conditions |
|----------|-------------------|
| docker | Error contains: `docker`, `container`, `image`, `volume`, `network` |
| cicd | Error contains: `workflow`, `pipeline`, `github actions`, `ci` |
| data-loss | Error contains: `data loss`, `deleted`, `corrupted`, `backup` |
| generic | Default fallback |

**Template Structure**:
```markdown
# [Domain] RCA Template

## Trigger Conditions
[conditions]

## Layer Analysis
| Layer | Check | Status |
|-------|-------|--------|

## Domain-Specific 5 Whys
[questions]

## Required Actions
[checklist]
```

---

## Entity: RCA Test

**Description**: Regression test созданный из RCA

**Location**: `tests/rca/RCA-NNN.test.ts`

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| rca_id | string | Source RCA ID |
| description | string | Test description |
| given | string | Setup from RCA context |
| when | string | Action that caused error |
| then | string | Expected outcome |

**Test Structure**:
```typescript
describe('RCA-[ID]: [Description]', () => {
  it('should [expected behavior]', async () => {
    // Given: [setup]
    // When: [action]
    // Then: [assertion]
  });
});
```

---

## Entity: RCA Hypothesis

**Description**: Предположение о причине ошибки (CoT pattern)

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| id | string | H1, H2, H3 |
| description | string | Hypothesis text |
| confidence | number | 0-100% |
| evidence | array | Supporting evidence |
| validated | boolean | Whether proven |

**Usage**: Part of Chain-of-Thought RCA process

---

## Relationships

```
RCA Report
    ├── has one → RCA Context (collected at creation)
    ├── uses one → RCA Template (by category)
    ├── may generate → RCA Test (for code errors)
    ├── may reference → RCA Report (related RCA)
    └── tracked in → RCA Index (registry entry)
```

---

## File Naming Conventions

| Entity | Pattern | Example |
|--------|---------|---------|
| RCA Report | `YYYY-MM-DD-[topic].md` | `2026-03-03-docker-network.md` |
| RCA Test | `RCA-NNN.test.ts` | `RCA-001.test.ts` |
| RCA Template | `[domain].md` | `docker.md` |
| RCA Index | `INDEX.md` | `INDEX.md` |

---

## JSON Schema (for INDEX.md automation)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "total_count": { "type": "integer" },
    "by_category": {
      "type": "object",
      "additionalProperties": { "type": "integer" }
    },
    "registry": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": { "type": "string", "pattern": "^RCA-\\d{3}$" },
          "date": { "type": "string", "format": "date" },
          "category": { "type": "string" },
          "severity": { "type": "string" },
          "status": { "type": "string" },
          "root_cause": { "type": "string" },
          "fix_commit": { "type": "string" }
        },
        "required": ["id", "date", "category", "status"]
      }
    }
  }
}
```
