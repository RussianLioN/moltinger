---
name: lessons
description: Query and manage lessons learned from RCA reports. Natural language interface to query-lessons.sh and build-lessons-index.sh scripts. Use when searching for relevant lessons by severity, tag, category, or rebuilding the lessons index.
allowed-tools: Bash, Read, Grep
---

# Lessons Query Skill

## Overview

Natural language interface for querying and managing lessons learned from Root Cause Analysis (RCA) reports. This skill provides a user-friendly way to search, filter, and display lessons from the RCA knowledge base.

**Core principle**: Searchable lessons → Pattern recognition → Prevention of recurring issues

## Capabilities

| Capability | Description |
|------------|-------------|
| **Query by Severity** | Filter lessons by P0-P4 severity levels |
| **Query by Tag** | Search lessons by specific tags (docker, gitops, security, etc.) |
| **Query by Category** | Filter by category (deployment, process, docker, etc.) |
| **Rebuild Index** | Regenerate docs/LESSONS-LEARNED.md from all RCA reports |
| **Smart Suggestions** | Suggest relevant lessons based on error context |

## When to Use

**Use this skill when:**
- Searching for lessons related to a specific error or problem
- Need to understand past mistakes before starting work
- Want to rebuild the lessons index after adding new RCA reports
- Looking for patterns in recurring issues
- Integrating lessons into RCA workflow

## Commands

### Query Lessons

Natural language queries for lessons learned.

#### Query by Severity

**Patterns:**
- "show critical lessons"
- "what are P1 lessons?"
- "покажи критичные уроки"
- "high severity lessons"

**Maps to:**
```bash
./scripts/query-lessons.sh --severity P0
./scripts/query-lessons.sh --severity P1
```

**Severity Levels:**
- `P0` / `critical` - Critical issues
- `P1` / `high` - High priority
- `P2` / `medium` - Medium priority
- `P3` / `low` - Low priority
- `P4` - Backlog items

#### Query by Tag

**Patterns:**
- "show docker lessons"
- "lessons about gitops"
- "что есть уроки по docker?"
- "find cicd lessons"

**Maps to:**
```bash
./scripts/query-lessons.sh --tag docker
./scripts/query-lessons.sh --tag gitops
```

**Common Tags:**
- `docker` - Docker-related issues
- `gitops` - GitOps and deployment
- `security` - Security concerns
- `networking` - Network configuration
- `cicd` - CI/CD pipelines
- `traefik` - Traefik routing
- `testing` - Testing issues

#### Query by Category

**Patterns:**
- "show deployment lessons"
- "process related lessons"
- "уроки по процессам"

**Maps to:**
```bash
./scripts/query-lessons.sh --category deployment
./scripts/query-lessons.sh --category process
```

**Categories:**
- `docker` - Docker infrastructure
- `cicd` - CI/CD workflows
- `shell` - Shell scripting
- `data-loss` - Data loss incidents
- `process` - Process issues
- `generic` - General lessons

#### Show All Lessons

**Patterns:**
- "show all lessons"
- "list every lesson"
- "все уроки"
- "what lessons do we have?"

**Maps to:**
```bash
./scripts/query-lessons.sh --all
```

### Rebuild Index

Regenerate the lessons index file from all RCA reports.

**Patterns:**
- "rebuild lessons index"
- "update lessons index"
- "перестрой индекс уроков"
- "generate lessons index"

**Maps to:**
```bash
./scripts/build-lessons-index.sh
```

**Output:** `docs/LESSONS-LEARNED.md`

### Suggest Relevant Lessons

Suggest lessons based on error type or context.

**Patterns:**
- "suggest lessons for docker errors"
- "what lessons apply to this situation?"
- "relevant lessons for gitops issues"

**Process:**
1. Analyze error context or type
2. Map to relevant tags/categories
3. Query lessons with matching filters
4. Display top relevant lessons

## Output Format

Lessons are displayed in a structured format:

```markdown
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 File: docs/rca/2026-03-03-docker-network-issue.md
📅 Date: 2026-03-03
⚠️  Severity: P1
📂 Category: docker
🏷️  Tags: [docker, networking, traefik]

## Уроки

1. Always verify Docker network configuration before deployment
2. Use traefik.docker.network label for proper DNS resolution
3. Document network topology in MEMORY.md
```

## Integration with RCA Workflow

### Before RCA Analysis

When starting an RCA, check for similar past lessons:

```markdown
# Check for relevant lessons
query: "suggest lessons for docker errors"

# If similar lessons found:
# - Reference them in RCA report
# - Check if root cause is similar
# - Apply known solutions
```

### After RCA Completion

After completing an RCA:

1. **Create RCA report** in `docs/rca/`
2. **Add lessons section** to the report
3. **Rebuild lessons index:**
   ```bash
   ./scripts/build-lessons-index.sh
   ```
4. **Verify new lesson appears** in queries

### Continuous Improvement

**Pattern Detection:**
```markdown
# Query for patterns in specific domain
query: "show all docker lessons"

# Analyze results:
# - Are there recurring themes?
# - Should a systemic fix be implemented?
# - Are documentation updates needed?
```

## Error Handling

### No Lessons Found

**Response:**
```
No lessons found matching criteria

Try:
- ./scripts/query-lessons.sh --all
- Check different tags or categories
- Verify RCA reports have lessons sections
```

### Invalid Query Parameters

**Common Issues:**
- Unknown severity level → Use P0-P4
- Unknown tag → List available tags with `--all`
- Unknown category → Use available categories

### Index Build Failures

**Troubleshooting:**
1. Check `docs/rca/` directory exists
2. Verify RCA reports have valid YAML frontmatter
3. Ensure `## Уроки` section exists in reports

## Examples

### Example 1: Query Critical Docker Lessons

**Input:**
```
"show me critical docker lessons"
```

**Action:**
```bash
./scripts/query-lessons.sh --severity P0 | grep -A 20 "docker"
```

**Output:**
```
📁 File: docs/rca/2026-03-03-data-loss-incident.md
⚠️  Severity: P0
📂 Category: data-loss
🏷️  Tags: [docker, backup, critical]

## Уроки
1. NEVER run docker rm -v without verifying backup
2. Always test backup restoration before deletion
```

### Example 2: Natural Language Query

**Input:**
```
"what lessons do we have about gitops?"
```

**Action:**
```bash
./scripts/query-lessons.sh --tag gitops
```

**Output:**
```
Found 2 lesson(s)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Display lessons with gitops tag]
```

### Example 3: Rebuild Index

**Input:**
```
"rebuild the lessons index"
```

**Action:**
```bash
./scripts/build-lessons-index.sh
```

**Output:**
```
✓ Generated docs/LESSONS-LEARNED.md
  Total lessons: 5
  Categories: 3
  Tags: 12
```

### Example 4: Context-Aware Suggestions

**Input:**
```
"I'm getting a docker network error, what lessons apply?"
```

**Action:**
1. Detect keywords: "docker", "network"
2. Query: `./scripts/query-lessons.sh --tag docker`
3. Filter results for network-related lessons
4. Display relevant lessons

**Output:**
```
🎯 Relevant Lessons for Docker Network Issues:

📁 docs/rca/2026-03-03-docker-network-mismatch.md
⚠️  Severity: P1
## Уроки
1. Verify container networks match Traefik's network
2. Use traefik.docker.network label
```

## Related Skills

- **rca-5-whys** - Root Cause Analysis methodology
- **systematic-debugging** - Technical debugging process

## Quick Reference

```bash
# Query commands
./scripts/query-lessons.sh --severity P1
./scripts/query-lessons.sh --tag docker
./scripts/query-lessons.sh --category deployment
./scripts/query-lessons.sh --all

# Index management
./scripts/build-lessons-index.sh

# Files
docs/rca/                    # RCA reports
docs/LESSONS-LEARNED.md      # Generated index
scripts/query-lessons.sh     # Query script
scripts/build-lessons-index.sh  # Index builder
```

## Notes

- All RCA reports must have `## Уроки` section to be indexed
- YAML frontmatter must include: title, date, severity, category, tags
- Lessons index is auto-generated - do not edit manually
- Queries are case-insensitive for tags and categories
- Severity can be specified as P0-P4 or critical/high/medium/low

## Validation Checklist

- [ ] Skill can parse natural language queries
- [ ] Correctly maps to query-lessons.sh parameters
- [ ] Can rebuild lessons index
- [ ] Provides structured output format
- [ ] Integrates with rca-5-whys skill
- [ ] Handles edge cases (no results, invalid parameters)

---

**Version:** 1.0.0
**Related:** FR-027 to FR-031 (RCA Skill Enhancements)
