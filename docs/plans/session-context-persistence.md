# Plan: Session Context Persistence System

**Priority**: P0 (BLOCKING)
**Created**: 2026-02-17
**Status**: ✅ COMPLETED

---

## Problem

Between sessions, critical context is lost:
- Which secrets already exist in GitHub Secrets
- Server file locations (/opt/moltinger, etc.)
- Local file locations (config/, secrets/, .env)
- What was already done (commits, configurations)
- Current deployment status

This leads to:
- Suggesting already-completed work
- Re-adding existing secrets
- Lost time re-exploring known information

---

## Proposed Solution

### 1. SESSION_STATE.md Artifact

Location: `/Users/rl/coding/moltinger/SESSION_STATE.md`

Structure:
```markdown
# Session State

## Last Updated: YYYY-MM-DD HH:MM

## Secrets Status
| Secret | Status | Added Date |
|--------|--------|------------|
| GLM_API_KEY | ✅ EXISTS | 2026-01-15 |
| MOLTIS_PASSWORD | ✅ EXISTS | 2026-01-15 |
| BRAVE_API_KEY | ❌ NEEDED | - |
| ELEVENLABS_API_KEY | ❌ NEEDED | - |

## Server Paths
- Deploy path: /opt/moltinger
- Config: /opt/moltinger/config/
- Secrets: NOT ON SERVER (env vars only)
- Docker compose: /opt/moltinger/docker-compose.prod.yml

## Local Paths
- Config: ./config/moltis.toml
- Secrets: ./secrets/ (git-ignored)
- Env template: .env.example

## Recent Commits
| Date | Commit | Description |
|------|--------|-------------|
| 2026-02-17 | 5177c10 | docs: add secrets management policy |
| 2026-02-17 | b916ed5 | feat(moltis): update configuration |

## Deployment Status
- URL: https://moltis.ainetic.tech
- Version: 0.8.35
- Last deploy: 2026-02-16
- Status: ✅ Healthy

## Pending Tasks
- [ ] Add BRAVE_API_KEY to GitHub Secrets
- [ ] Add ELEVENLABS_API_KEY to GitHub Secrets
- [ ] Restart Moltis after secrets added
```

### 2. Session Start Hook

In CLAUDE.md, add to beginning:
```markdown
## ⚠️ MANDATORY: Read SESSION_STATE.md First!

**Before starting ANY work**, read the session state:
```bash
cat SESSION_STATE.md
```

This file contains:
- Current project status (secrets, deployment, paths)
- What was already done
- What is pending
```

### 3. Session End Hook

At session end, update SESSION_STATE.md:
- Update "Last Updated" timestamp
- Add new commits
- Update secrets status
- Update pending tasks

### 4. Agent for Auto-Update

Create a specialized agent or skill:
- **Name**: `session-summarizer` (already exists as skill!)
- **Trigger**: At session end OR manually via `/session-summary`
- **Actions**:
  - Read current SESSION_STATE.md
  - Query git log for new commits
  - Query gh secret list for secrets status
  - Update the file with current state

---

## Implementation Steps

1. [X] ~~Create SESSION_STATE.md with current known state~~ → Merged into SESSION_SUMMARY.md
2. [X] Update CLAUDE.md with mandatory read instruction
3. [X] Enhance /session-summary skill to track secrets status
4. [X] Update SESSION_SUMMARY.md with secrets tracking table
5. [X] Test: Start new session, verify context is loaded

---

## Known State (to populate SESSION_STATE.md)

### Secrets Already in GitHub
- GLM_API_KEY ✅
- MOLTIS_PASSWORD ✅

### Secrets Needed
- BRAVE_API_KEY ❌
- ELEVENLABS_API_KEY ❌
- ANTHROPIC_API_KEY ❌ (optional)
- OPENAI_API_KEY ❌ (optional)
- GROQ_API_KEY ❌ (optional)

### Server Paths
- Deploy: /opt/moltinger
- Config: /opt/moltinger/config/moltis.toml
- Docker: /opt/moltinger/docker-compose.prod.yml

### Local Paths
- Moltis config: config/moltis.toml
- Research reports: docs/reports/
- Secrets policy: docs/SECRETS-MANAGEMENT.md
- Env template: .env.example

### Recent Work
- 5177c10: Secrets management policy
- b916ed5: Moltis configuration update
- 5ecf531: Research reports

---

## Completed

2026-02-17: Session context persistence implemented.
- Merged SESSION_STATE.md concept into existing SESSION_SUMMARY.md
- Added secrets tracking table with ✅/❌ flags
- Updated CLAUDE.md with mandatory read instruction
- Enhanced /session-summary command to track secrets
