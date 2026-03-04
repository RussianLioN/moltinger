# RCA Index Contract

**Version**: 1.0.0
**Format**: Markdown with structured sections

## Required Sections

### 1. Header
```markdown
# RCA Index

**Last Updated**: YYYY-MM-DD
**Version**: X.Y.Z
```

### 2. Statistics
```markdown
## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | N |
| Avg Resolution Time | Xm Ys |
| This Month | N |
```

### 3. By Category
```markdown
## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| docker | N | X% |
| cicd | N | X% |
| shell | N | X% |
| data-loss | N | X% |
| generic | N | X% |
```

### 4. By Severity
```markdown
## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | N | Critical - blocks release |
| P1 | N | High - production impact |
| P2 | N | Medium - degraded service |
| P3 | N | Low - minor issue |
| P4 | N | Backlog |
```

### 5. Registry
```markdown
## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-NNN | YYYY-MM-DD | [category] | [severity] | [status] | [summary] | [commit or N/A] |
```

### 6. Patterns (Optional)
```markdown
## Patterns Detected

⚠️ **Warning**: N+ RCA in category "[category]" - consider systemic fix

**Trend**: [Description of pattern]
```

## Validation Rules

1. **Total Count**: Must match count of Registry entries
2. **Percentages**: Must sum to 100%
3. **ID Uniqueness**: Each ID must be unique
4. **Date Order**: Entries sorted by date (newest first)
5. **Status Valid**: Must be one of: draft, in_progress, resolved

## Update Triggers

INDEX.md MUST be updated when:
1. New RCA report created
2. RCA status changed
3. RCA deleted (rare)
4. Monthly statistics recalculation

## Automation

```bash
# Update INDEX.md
.claude/skills/rca-5-whys/lib/rca-index.sh update

# Validate INDEX.md
.claude/skills/rca-5-whys/lib/rca-index.sh validate

# Get next RCA ID
.claude/skills/rca-5-whys/lib/rca-index.sh next-id
```

## Example

```markdown
# RCA Index

**Last Updated**: 2026-03-03
**Version**: 1.0.0

## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | 5 |
| Avg Resolution Time | 15m 30s |
| This Month | 3 |

## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| docker | 3 | 60% |
| cicd | 1 | 20% |
| shell | 1 | 20% |
| data-loss | 0 | 0% |
| generic | 0 | 0% |

## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | 0 | Critical |
| P1 | 2 | High |
| P2 | 2 | Medium |
| P3 | 1 | Low |
| P4 | 0 | Backlog |

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-005 | 2026-03-03 | docker | P1 | resolved | Missing health check | a1b2c3d |
| RCA-004 | 2026-03-02 | cicd | P2 | resolved | YAML syntax error | d4e5f6g |
| RCA-003 | 2026-03-02 | docker | P2 | resolved | Volume permissions | g7h8i9j |
| RCA-002 | 2026-03-01 | shell | P3 | resolved | zsh/bash incompatibility | j0k1l2m |
| RCA-001 | 2026-02-28 | docker | P1 | resolved | Wrong network label | m3n4o5p |

## Patterns Detected

⚠️ **Warning**: 3+ RCA in category "docker" (60%) - consider systemic review

**Trend**: Docker network configuration issues are recurring
```
