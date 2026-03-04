# RCA Report Contract

**Version**: 1.0.0
**Format**: Markdown with structured sections

## Required Sections

Every RCA report MUST contain these sections in order:

### 1. Header
```markdown
# RCA: [Title]

**ID**: RCA-NNN
**Date**: YYYY-MM-DD
**Status**: draft | in_progress | resolved
**Category**: docker | cicd | shell | data-loss | generic
**Severity**: P0 | P1 | P2 | P3 | P4
```

### 2. Error Description
```markdown
## Error

[Description of the symptom/manifestation]

```
Error message:
[Exact error text]
```
```

### 3. Context
```markdown
## Context

| Field | Value |
|-------|-------|
| Timestamp | [ISO datetime] |
| PWD | [working directory] |
| Git Branch | [branch name or N/A] |
| [Additional context fields] |
```

### 4. Five Whys Analysis
```markdown
## 5 Whys Analysis

| Level | Question | Answer | Evidence |
|-------|----------|--------|----------|
| 1 | Why [error]? | [answer] | [source] |
| 2 | Why [answer1]? | [answer] | [source] |
| 3 | Why [answer2]? | [answer] | [source] |
| 4 | Why [answer3]? | [answer] | [source] |
| 5 | Why [answer4]? | [answer] | [source] |
```

### 5. Root Cause
```markdown
## Root Cause

[Systemic cause - not individual blame]
```

### 6. Actions
```markdown
## Actions

1. **[IMMEDIATE]** [What was done to fix]
2. **[PREVENT]** [What changed to prevent recurrence]
3. **[DOCUMENT]** [What documentation was updated]
```

### 7. Related (Optional)
```markdown
## Related

- RCA-XXX: [Description of relation]
```

## Validation Rules

1. **ID Format**: Must match `RCA-\d{3}`
2. **Date Format**: ISO 8601 date (YYYY-MM-DD)
3. **Minimum Whys**: At least 3 levels required
4. **Root Cause**: Must be systemic (not "developer made mistake")
5. **Actions**: At least one action required

## Example

```markdown
# RCA: Docker Network Configuration Error

**ID**: RCA-001
**Date**: 2026-03-03
**Status**: resolved
**Category**: docker
**Severity**: P1

## Error

404 error when accessing moltis.ainetic.tech

```
Error: Traefik returned 404 for route to moltis container
```

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-03T12:00:00+03:00 |
| PWD | /Users/user/moltinger |
| Git Branch | main |
| Docker Version | 24.0.5 |
| Containers | traefik, moltis |

## 5 Whys Analysis

| Level | Question | Answer | Evidence |
|-------|----------|--------|----------|
| 1 | Why 404? | Traefik cannot find route to moltis | Traefik logs |
| 2 | Why no route? | Moltis in wrong network (traefik_proxy) | docker inspect |
| 3 | Why wrong network? | docker-compose.yml specifies traefik_proxy | git show |
| 4 | Why traefik_proxy? | Copy-paste from template | git blame |
| 5 | Why no validation? | No preflight check for networks | CI logs |

## Root Cause

Missing network configuration validation in deployment pipeline.

## Actions

1. **[IMMEDIATE]** Added traefik.docker.network=traefik-net label
2. **[PREVENT]** Added network check to preflight-check.sh
3. **[DOCUMENT]** Updated MEMORY.md with network topology

## Related

- RCA-000: Initial Docker deployment
```
