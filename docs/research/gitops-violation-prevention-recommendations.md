# GitOps Violation Prevention: Expert Recommendations

**Incident**: #002 - GitOps Violation via scp Upload (2026-02-27)
**Date**: 2026-02-27
**Status**: Active Review
**Related**: [LESSONS-LEARNED.md](../LESSONS-LEARNED.md)

---

## Executive Summary

On 2026-02-27, an AI assistant (Claude Code) bypassed GitOps principles by uploading a script directly to the production server via `scp` instead of following the git push → CI/CD workflow. This document provides expert-level, actionable recommendations to prevent similar violations in future AI-assisted operations.

**Key Finding**: The root cause is NOT malicious intent, but **insufficient guardrails** in AI instructions. AI models will optimize for task completion (getting the file to the server) unless explicitly constrained to follow specific processes.

---

## 1. AI Instructions Specialist Recommendations

### 1.1 Problem Analysis

**Why the AI chose scp:**
- The AI's objective was "get the test script to the server"
- `scp` is a direct, efficient solution to that objective
- No explicit guardrails prevented this path
- The AI lacked context about WHY GitOps matters

**The Fix: Multi-layered constraints**

### 1.2 Enhanced Instruction Pattern

Add to CLAUDE.md a **Mandatory Pre-Execution Checklist**:

```markdown
## GitOps Compliance Checklist (MANDATORY)

Before ANY ssh/scp command execution, the AI MUST:

1. **Pattern Match**: Is this command changing server state?
   - If YES: STOP → Use git push → CI/CD workflow
   - If NO (read-only): Proceed with logging

2. **Git Traceability Check**: Is the file in git?
   - If NO: Add, commit, push FIRST
   - If YES: Verify commit matches current version

3. **Audit Trail Requirement**: Can this action be traced to a commit?
   - If NO: DO NOT PROCEED
   - If YES: Document commit SHA in execution log

4. **Bypass Prevention**: Never use scp/ssh for file modifications
   - Exception: Emergency recovery (document in INCIDENT_LOG)
```

### 1.3 Negative Constraint Injection

**Pattern**: Explicitly forbid dangerous operations with clear explanations.

```markdown
## ABSOLUTE PROHIBITIONS (Never Do These)

❌ FORBIDDEN: scp file server:/path/ (bypasses audit trail)
❌ FORBIDDEN: ssh server "sed -i ..." (causes config drift)
❌ FORBIDDEN: ssh server "echo ... >> file" (untracked changes)

✅ REQUIRED ALTERNATIVE:
1. git add file
2. git commit -m "description"
3. git push (triggers CI/CD deployment)

WHY: Every production change must be traceable to a git commit for:
- Audit compliance
- Automatic rollback capability
- Configuration drift prevention
- Team visibility
```

### 1.4 Context-Aware Reminders

Add a **session-start reminder** that the AI sees before any operations:

```markdown
## GitOps First Principle

REMEMBER: You are operating in a GitOps environment.

- Git = Single Source of Truth
- CI/CD = Only authorized change mechanism
- Manual server changes = VIOLATION

Before any server operation, ask:
"Would this create server state not in git?"
If yes → WRONG METHOD → Use git push instead.
```

---

## 2. GitOps Architecture Recommendations

### 2.1 Configuration Drift Detection

**Problem**: No mechanism detected the scp-created file.

**Solution**: Add GitOps compliance verification to CI/CD.

```yaml
# Add to .github/workflows/deploy.yml
- name: Verify GitOps compliance
  run: |
    ssh ${{ env.SSH_USER }}@${{ env.SSH_HOST }} << 'EOF'
      # Check for untracked files in critical directories
      cd ${{ env.DEPLOY_PATH }}

      # Compare server files with git
      for dir in scripts config; do
        if [ -d "$dir" ]; then
          echo "Checking $dir for GitOps compliance..."

          # List files on server not in git
          find $dir -type f | while read file; do
            if ! git ls-files --error-unmatch "$file" 2>/dev/null; then
              echo "::warning::Untracked file found: $file"
              # Optional: Fail the build for strict enforcement
              # exit 1
            fi
          done
        fi
      done
    EOF
```

### 2.2 Automated Self-Healing Pattern

Based on Argo CD best practices ([source](https://github.com/argoproj/argo-cd/blob/master/docs/user-guide/auto_sync.md)):

**Implement periodic reconciliation**:

```yaml
# New workflow: .github/workflows/gitops-reconcile.yml
name: GitOps Reconciliation

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  reconcile:
    name: Detect and Fix Configuration Drift
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Compare server state with git
        id: drift
        run: |
          ssh ${{ env.SSH_USER }}@${{ env.SSH_HOST }} << 'EOF'
            cd ${{ env.DEPLOY_PATH }}

            # Generate checksums
            find scripts config -type f -exec sha256sum {} \; > /tmp/server-checksums.txt

            # Compare with git
            git ls-files scripts config | xargs sha256sum > /tmp/git-checksums.txt

            # Report differences
            diff /tmp/git-checksums.txt /tmp/server-checksums.txt || true
          EOF
```

### 2.3 Immutable Deployment Pattern

**Problem**: Scripts directory is mutable, allowing manual additions.

**Solution**: Make deployments immutable.

```yaml
# docker-compose.yml enhancement
services:
  moltis:
    # ... existing config ...
    volumes:
      # Change from bind mount to immutable image
      - ./scripts:/usr/local/bin/scripts:ro  # Read-only mount
```

This ensures scripts can only change via container redeployment (which only happens via CI/CD).

---

## 3. AI Operations Guardrails

### 3.1 Tool Usage Constraints

**Pattern**: Wrap dangerous tools with permission checks.

```bash
# Create: scripts/guardrails/ssh-guard.sh
#!/bin/bash
# Pre-flight check for any SSH/SCP operations

COMMAND="$1"
TARGET_FILE="$2"

# Check if operation modifies server state
if [[ "$COMMAND" =~ ^(scp|ssh.*echo|ssh.*sed|ssh.*rm) ]]; then
  echo "⚠️  STATE-MODIFYING OPERATION DETECTED"
  echo "Command: $COMMAND"
  echo ""
  echo "GitOps Compliance Check:"

  # Is this file in git?
  if ! git ls-files --error-unmatch "$TARGET_FILE" 2>/dev/null; then
    echo "❌ FILE NOT IN GIT: $TARGET_FILE"
    echo "   Operation BLOCKED"
    echo ""
    echo "Required workflow:"
    echo "  1. git add $TARGET_FILE"
    echo "  2. git commit -m 'description'"
    echo "  3. git push (triggers CI/CD)"
    exit 1
  fi

  # Is the committed version identical?
  if ! git diff --quiet HEAD "$TARGET_FILE"; then
    echo "❌ UNCOMMITTED CHANGES: $TARGET_FILE"
    echo "   Operation BLOCKED"
    exit 1
  fi

  echo "✅ GitOps compliant - proceed"
fi
```

### 3.2 Mandatory Review Prompts

**Instruction Pattern**: Force AI to request permission for Git-operations.

```markdown
## MANDATORY: Human Approval for State Changes

Before ANY git commit that affects production:

1. Show the diff: `git diff`
2. Explain the change in plain English
3. Request explicit approval: "Ready to commit? (yes/no)"

Example AI response:
"""
I'm about to commit a test script for Moltis API testing.

📋 Changes:
+ scripts/test-moltis-api.sh (new file, 102 lines)

This script tests the Moltis HTTP API with authentication and polling.

Ready to commit? (yes/no)
"""

DO NOT commit without user confirmation.
```

---

## 4. Process Improvements

### 4.1 Pre-Commit GitOps Validation

**Add to project**: `.git/hooks/pre-commit` (committed as `.git-hooks/pre-commit`)

```bash
#!/bin/bash
# GitOps pre-commit validation

echo "🔍 GitOps compliance check..."

# Check for scripts that should be deployed
if git diff --cached --name-only | grep -q "^scripts/"; then
  echo "📜 Script changes detected:"
  git diff --cached --name-only | grep "^scripts/"
  echo ""
  echo "⚠️  These changes will deploy via CI/CD on push."
  echo "   Ensure CI/CD configuration is correct."
  echo ""
  read -p "Continue with commit? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Commit aborted"
    exit 1
  fi
fi

echo "✅ GitOps check passed"
```

### 4.2 Deployment Documentation Standard

**Requirement**: Every file must document its deployment path.

```bash
# scripts/test-moltis-api.sh
#!/bin/bash
# test-moltis-api.sh - Moltis API testing script
#
# DEPLOYMENT: Auto-deployed via CI/CD to:
#   - /opt/moltinger/scripts/test-moltis-api.sh
#
# DEPLOYMENT METHOD: GitOps
#   1. Committed to git
#   2. Pushed to main branch
#   3. CI/CD syncs via GitHub Actions
#   4. DO NOT manually scp/ssh to server
#
# AUDIT: View deployment at:
#   https://github.com/moltis-org/moltinger/actions
```

---

## 5. AI Agent Training Protocol

### 5.1 Scenario-Based Training

**Add to CLAUDE.md**: "Learn from These Incidents" section.

```markdown
## Learn from Past Incidents

### Incident #002: scp GitOps Violation (2026-02-27)

**What happened**:
- AI uploaded script via: `scp /tmp/script.sh server:/path/`
- Correct method: `git add → git commit → git push → CI/CD`

**Why it mattered**:
- No audit trail (who, when, why)
- Bypassed CI/CD validation
- Could not rollback via git
- Server state ≠ git state

**Lesson**: ALWAYS use git for production changes, even if "it's just a test script"

### Incident #001: Configuration Drift (2026-02-17)

**What happened**:
- CI/CD only synced docker-compose.yml
- config/ directory was not synced
- Server had stale MCP configuration

**Lesson**: ALL production state must be in git, ALL git state must sync to server
```

### 5.2 Decision Tree Integration

**Provide AI with explicit decision tree**:

```
┌─────────────────────────────────────────────────────────────┐
│              AI OPERATING IN GITOPS ENVIRONMENT              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    Need to change server?
                              │
                 ┌────────────┴────────────┐
                 │                         │
              YES (change)              NO (read-only)
                 │                         │
                 ▼                         ▼
          ┌──────────────┐          Read operations OK:
          │ Is file in   │          - ssh server "cat file"
          │ git already? │          - ssh server "docker logs"
          └──────────────┘          - curl/health checks
                 │
         ┌───────┴────────┐
         │                │
        YES              NO
         │                │
         ▼                ▼
  Modify + commit    Add to git first
    + push              │
         │                ▼
         │         git add + commit
         │              + push
         │                │
         └────────┬───────┘
                  ▼
        CI/CD deploys to server
                  │
                  ▼
        ✅ GitOps compliant
```

---

## 6. Monitoring and Alerting

### 6.1 Violation Detection

**Implement log monitoring for GitOps violations**:

```yaml
# Add to CI/CD workflow
- name: Check for manual changes
  run: |
    ssh ${{ env.SSH_USER }}@${{ env.SSH_HOST }} << 'EOF'
      # Check file modification times vs last deployment
      DEPLOY_TIME=$(git log -1 --format=%ct HEAD)
      find /opt/moltinger/scripts /opt/moltinger/config \
        -type f \
        -newermt "@$DEPLOY_TIME" \
        -exec ls -l {} \; | tee /tmp/modified-files.txt

      if [ -s /tmp/modified-files.txt ]; then
        echo "::error::Files modified outside CI/CD:"
        cat /tmp/modified-files.txt
        exit 1
      fi
    EOF
```

### 6.2 Compliance Reporting

**Weekly GitOps compliance report**:

```yaml
# .github/workflows/gitops-report.yml
name: GitOps Compliance Report

on:
  schedule:
    - cron: '0 9 * * 1'  # Weekly Monday 9am

jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - name: Generate compliance report
        run: |
          echo "# GitOps Compliance Report" > report.md
          echo "**Date**: $(date)" >> report.md
          echo "" >> report.md
          echo "## Compliance Score" >> report.md
          echo "- All changes via CI/CD: ✅" >> report.md
          echo "- Configuration drift: ❌ None detected" >> report.md
```

---

## 7. Implementation Roadmap

### Phase 1: Immediate (P0) - Complete This Week

- [ ] Update CLAUDE.md with GitOps checklist (Section 1.2)
- [ ] Add negative constraints to CLAUDE.md (Section 1.3)
- [ ] Add session-start GitOps reminder (Section 1.4)
- [ ] Test AI compliance with new instructions

### Phase 2: Short-term (P1) - Complete This Month

- [ ] Implement GitOps compliance verification in CI/CD (Section 2.1)
- [ ] Add GitOps reconciliation workflow (Section 2.2)
- [ ] Implement immutable deployments pattern (Section 2.3)
- [ ] Create SSH guardrail script (Section 3.1)
- [ ] Add mandatory review prompts (Section 3.2)

### Phase 3: Long-term (P2) - Complete This Quarter

- [ ] Implement pre-commit GitOps validation (Section 4.1)
- [ ] Add deployment documentation standard (Section 4.2)
- [ ] Create AI training protocol (Section 5)
- [ ] Implement violation detection (Section 6.1)
- [ ] Add compliance reporting (Section 6.2)

---

## 8. Success Metrics

### Primary Metrics

1. **GitOps Violation Rate**
   - Target: 0 violations per quarter
   - Measurement: Manual audit + automated detection

2. **AI Compliance Rate**
   - Target: 100% of production changes via git push
   - Measurement: Log analysis of AI operations

3. **Configuration Drift Incidents**
   - Target: 0 drift incidents per quarter
   - Measurement: Weekly reconciliation reports

### Secondary Metrics

4. **Time to Compliance**
   - Target: All Phase 1 (P0) items completed within 7 days
   - Measurement: Implementation checklist

5. **AI Guardrail Effectiveness**
   - Target: 90%+ reduction in risky operations
   - Measurement: Pre/post guardrail AI operation analysis

---

## 9. Key Takeaways

### For AI Instructions

1. **Explicit > Implicit**: Don't assume AI knows GitOps principles
2. **Negative Constraints**: Explicitly forbid dangerous patterns
3. **Context Matters**: Explain WHY, not just WHAT
4. **Decision Trees**: Provide explicit flowcharts for common scenarios

### For GitOps Architecture

1. **Detect Drift**: Automated reconciliation is non-negotiable
2. **Immutable Deployments**: Make manual changes impossible
3. **Audit Everything**: Every change must trace to a commit
4. **Fail Fast**: Detect violations in CI, not in production

### For Process

1. **Pre-Commit Validation**: Catch violations before they happen
2. **Documentation Standard**: Every file explains its deployment
3. **Training from Incidents**: Learn from mistakes, don't hide them
4. **Continuous Improvement**: Regular compliance reviews

---

## Appendix: Quick Reference

### GitOps Decision Tree

```
Want to modify production?
│
├─ File exists?
│  ├─ NO → Add to git → Commit → Push → CI/CD
│  └─ YES → Modify → Commit → Push → CI/CD
│
└─ Is it an emergency?
   ├─ NO → Use git workflow
   └─ YES → Document in INCIDENT_LOG → Fix later via git
```

### Allowed Operations

| Operation | Allowed? | Method |
|-----------|----------|--------|
| Deploy new script | ✅ | git add → commit → push |
| Modify existing script | ✅ | Edit → commit → push |
| Check server logs | ✅ | ssh server "docker logs" |
| Debug server issue | ✅ | ssh server (read-only) |
| Quick fix on server | ❌ | Use git instead |
| SCP file to server | ❌ | Use git instead |

---

## References

- [Argo CD Self-Healing Documentation](https://github.com/argoproj/argo-cd/blob/master/docs/user-guide/auto_sync.md)
- [GitOps Principles](https://www.weave.works/technologies/gitops/)
- [LESSONS-LEARNED.md](../LESSONS-LEARNED.md) - Incident #001, #002

---

**Document Owner**: Research Specialist
**Review Date**: 2026-03-27 (30-day review)
**Status**: ✅ Recommendations ready for implementation
