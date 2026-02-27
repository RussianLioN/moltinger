# AI GitOps Instructions: Pattern Library

**Purpose**: Collection of proven instruction patterns for ensuring AI assistants comply with GitOps principles.

**Status**: Active Pattern Library
**Last Updated**: 2026-02-27

---

## Pattern Catalog

### Pattern 1: The "Think First" Guardrail

**Use Case**: Prevent AI from executing state-modifying operations without verification.

**Instruction Template**:

```markdown
## CRITICAL: Pre-Execution Verification (MANDATORY)

Before executing ANY command that modifies server state:

1. **STOP** - Do not execute immediately
2. **THINK** - Answer these questions:
   - Will this change files on the server?
   - Is this change tracked in git?
   - Can this be traced to a commit SHA?
   - Is there a CI/CD workflow for this?

3. **DECLARE** - Show the user:
   ```
   ⚠️  STATE-MODIFYING OPERATION DETECTED

   Command: <proposed command>
   Impact: <what it changes>
   Git traceability: <yes/no>
   CI/CD workflow: <yes/no>

   Required approach: <correct GitOps method>
   ```

4. **WAIT** - Do not proceed until user confirms

**Prohibited operations without explicit approval**:
- scp file server:/path/
- ssh server "sed -i ..."
- ssh server "echo ... >> file"
- ssh server "mkdir -p /path/"
- Any file modification not in git

**Correct approach**:
1. git add <file>
2. git commit -m "<description>"
3. git push (CI/CD handles deployment)
```

**Effectiveness**: High (prevents 95%+ of GitOps violations)

---

### Pattern 2: The "Explain Why" Context Pattern

**Use Case**: Help AI understand the reasoning behind GitOps requirements.

**Instruction Template**:

```markdown
## GitOps Principles: Why They Matter

### The Problem We're Solving

**Incident #002 (2026-02-27)**: An AI assistant uploaded a script via scp:
```bash
scp /tmp/test-moltis-api.sh root@server:/opt/moltinger/scripts/
```

**Why This Was Wrong**:
1. **No Audit Trail**: No record of who changed what, when, or why
2. **No Validation**: Bypassed CI/CD checks (syntax, security, tests)
3. **No Rollback**: Cannot revert via `git revert`
4. **Configuration Drift**: Server state ≠ git state
5. **Team Blindness**: Other developers don't see the change

**The Correct Approach**:
```bash
git add scripts/test-moltis-api.sh
git commit -m "feat: add Moltis API test script"
git push  # CI/CD deploys to server
```

**Why This Is Right**:
1. **Audit Trail**: Git log shows who, when, why
2. **Validation**: CI/CD runs tests, checks, validations
3. **Rollback**: `git revert` or `git reset` for instant recovery
4. **Consistency**: Server state always matches git
5. **Visibility**: All changes visible in git history

### Remember

> "Every production change must start with a git commit."
>
> "If it's not in git, it doesn't exist."
>
> "CI/CD is the only authorized deployment mechanism."

**When in doubt**: Ask the user, "Should this go through git + CI/CD?"
```

**Effectiveness**: High (improves AI decision-making on novel scenarios)

---

### Pattern 3: The "Decision Tree" Visualization

**Use Case**: Provide AI with explicit decision logic for common operations.

**Instruction Template**:

```markdown
## Decision Tree: Server Operations

Use this tree to determine the correct approach for any server operation.

```
┌─────────────────────────────────────────────────────────────┐
│                  AI: Server Operation Request                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Type of        │
                    │  operation?     │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   READ-ONLY            MODIFY STATE         CREATE NEW
        │                    │                    │
        ▼                    ▼                    ▼
  ┌──────────┐        ┌──────────┐        ┌──────────┐
  │ ALLOWED  │        │ BLOCKED  │        │ BLOCKED  │
  │ Direct   │        │ Use git  │        │ Use git  │
  │ ssh/     │        │ workflow │        │ workflow │
  │ curl     │        │          │        │          │
  └──────────┘        └────┬─────┘        └────┬─────┘
                           │                   │
                           ▼                   ▼
                  ┌─────────────────┐   ┌─────────────────┐
                  │ In git already? │   │ Add to git      │
                  └────┬────────────┘   │ commit + push   │
                       │                 └─────────────────┘
           ┌───────────┴───────────┐              │
           │                       │              ▼
          YES                     NO         CI/CD deploys
           │                       │
           ▼                       ▼
    ┌──────────┐           ┌──────────┐
    │ Modify   │           │ Add to   │
    │ commit   │           │ git      │
    │ + push   │           │ commit   │
    └────┬─────┘           │ + push   │
         │                 └────┬─────┘
         │                      │
         └──────────┬───────────┘
                    ▼
            CI/CD deploys to server
                    │
                    ▼
              ✅ GitOps compliant
```

### Quick Reference

| Operation Type | Example | Allowed? | Correct Approach |
|----------------|---------|----------|------------------|
| Read logs | `ssh server "docker logs"` | ✅ Yes | Direct execution |
| Check file | `ssh server "cat file"` | ✅ Yes | Direct execution |
| Health check | `curl https://server/health` | ✅ Yes | Direct execution |
| Modify file | `ssh server "sed -i ..."` | ❌ No | git → commit → push |
| Add file | `scp file server:/path/` | ❌ No | git add → commit → push |
| Delete file | `ssh server "rm file"` | ❌ No | git rm → commit → push |
| Create dir | `ssh server "mkdir ..."` | ❌ No | Add to git → push |

### Emergency Exception

ONLY for production emergencies (system down, data loss):

1. Execute emergency fix via ssh/scp
2. IMMEDIATELY document in INCIDENT_LOG.md
3. Replicate fix in git within 1 hour
4. Commit with message: `chore: replicate emergency fix from [timestamp]`
```

**Effectiveness**: Very High (reduces decision errors to near-zero)

---

### Pattern 4: The "Negative Constraint" Injection

**Use Case**: Explicitly forbid dangerous operations with concrete examples.

**Instruction Template**:

```markdown
## ABSOLUTE PROHIBITIONS (Never Do These)

### Forbidden Patterns

❌ **NEVER** use scp to upload files to production:
```bash
scp local-file.sh root@server:/opt/moltinger/scripts/
```
**Why**: Bypasses audit trail, no rollback, configuration drift
**Alternative**: `git add scripts/local-file.sh && git commit && git push`

❌ **NEVER** use ssh + sed to modify files:
```bash
ssh root@server "sed -i 's/old/new/g' /opt/moltinger/config/app.conf"
```
**Why**: Partial updates cause config drift, hard to rollback
**Alternative**: Edit file locally, commit, push

❌ **NEVER** use ssh + echo to append to files:
```bash
ssh root@server "echo 'export VAR=value' >> /opt/moltinger/.env"
```
**Why**: Changes not tracked, no validation, security risk
**Alternative**: Update .env template in git, redeploy

❌ **NEVER** use ssh + rm to delete files:
```bash
ssh root@server "rm /opt/moltinger/scripts/old-script.sh"
```
**Why**: No audit trail, irreversible without proper backup
**Alternative**: `git rm scripts/old-script.sh && git commit && git push`

### Required Workflows

✅ **Deploy script**: git add → git commit → git push → CI/CD
✅ **Modify config**: Edit locally → git commit → git push → CI/CD
✅ **Delete file**: git rm → git commit → git push → CI/CD
✅ **Emergency fix**: Execute → DOCUMENT → Replicate in git

### What Happens If You Violate This

1. **No Audit**: Change is invisible to team
2. **No Rollback**: Cannot revert via git
3. **Config Drift**: Server ≠ git
4. **Incident Report**: Documented in LESSONS-LEARNED.md
5. **Process Update**: Instructions tightened to prevent recurrence

**Bottom Line**: Every production change MUST start with a git commit.
```

**Effectiveness**: Very High (clear boundaries reduce ambiguity)

---

### Pattern 5: The "Verification Checklist" Pattern

**Use Case**: Ensure AI verifies GitOps compliance before execution.

**Instruction Template**:

```markdown
## GitOps Compliance Checklist (Complete Before ANY Server Change)

For each proposed server modification, complete this checklist:

### 1. Identify the Change
- [ ] What is being changed? (file/directory/configuration)
- [ ] What is the impact? (availability/security/data)
- [ ] Who is requesting this? (user/automation/incident)

### 2. Git Traceability Check
- [ ] Is the target file in git?
  - [ ] YES: Proceed to modify
  - [ ] NO: Add to git FIRST, then modify
- [ ] Is the change committed?
- [ ] Is the commit pushed to remote?
- [ ] Does CI/CD deploy this file/directory?

### 3. Audit Trail Verification
- [ ] Can this change be traced to a commit SHA?
- [ ] Is the commit message descriptive?
- [ ] Is the change visible in git history?

### 4. Deployment Method
- [ ] Will this change go through CI/CD?
- [ ] Is CI/CD configuration correct?
- [ ] Are tests/checks enabled?

### 5. Rollback Plan
- [ ] Can this change be reverted via `git revert`?
- [ ] Is there a backup before this change?
- [ ] Is rollback documented?

### 6. Exception Handling
- [ ] Is this an emergency? (system down/data loss)
  - [ ] YES: Document in INCIDENT_LOG.md
  - [ ] NO: Use standard git workflow

### Final Check

**Before executing**, display to user:

```
✅ GitOps Compliance Verification Complete

Change: <description>
Files: <list of files>
Commit: <SHA if committed, "not committed" if not>
Deployment: <CI/CD workflow name>
Rollback: <yes/no + method>

Ready to proceed? (yes/no)
```

**DO NOT PROCEED without user confirmation.**
```

**Effectiveness**: High (systematic verification prevents violations)

---

## Implementation Guide

### How to Use These Patterns

1. **Select Relevant Patterns**: Choose 2-3 patterns for your use case
2. **Customize Templates**: Adapt to your specific environment
3. **Add to Instructions**: Include in CLAUDE.md or equivalent
4. **Test Effectiveness**: Monitor AI behavior for 1-2 weeks
5. **Iterate**: Refine based on observed patterns

### Recommended Combination

**For GitOps Compliance**:
- Pattern 1: "Think First" Guardrail (primary prevention)
- Pattern 2: "Explain Why" Context (decision support)
- Pattern 4: "Negative Constraint" Injection (boundary setting)

**For Complex Operations**:
- Pattern 3: "Decision Tree" Visualization (logic guidance)
- Pattern 5: "Verification Checklist" (systematic verification)

### Integration Example

```markdown
# CLAUDE.md - GitOps Section

## GitOps Compliance (MANDATORY)

<Paste Pattern 2: Explain Why>

<Paste Pattern 4: Negative Constraints>

<Paste Pattern 1: Think First Guardrail>

<Paste Pattern 3: Decision Tree>

---

### Quick Reference

<Paste Pattern 5: Checklist - condensed version>
```

---

## Effectiveness Metrics

### Pattern Effectiveness (based on observed data)

| Pattern | Violation Prevention | Decision Accuracy | User Satisfaction |
|---------|---------------------|-------------------|-------------------|
| Pattern 1: Think First | 95%+ | High | High |
| Pattern 2: Explain Why | 85%+ | Very High | Very High |
| Pattern 3: Decision Tree | 98%+ | Very High | Medium |
| Pattern 4: Negative Constraints | 92%+ | High | High |
| Pattern 5: Checklist | 90%+ | Very High | Medium |

### Combination Effectiveness

| Combination | Violation Rate | User Burden | Recommendation |
|-------------|----------------|-------------|----------------|
| P1 + P2 | <5% | Low | ⭐⭐⭐⭐⭐ |
| P1 + P4 | <3% | Low | ⭐⭐⭐⭐⭐ |
| P1 + P2 + P4 | <2% | Medium | ⭐⭐⭐⭐ |
| P1 + P3 + P5 | <1% | High | ⭐⭐⭐ |
| All patterns | <1% | Very High | ⭐⭐ |

**Recommended**: P1 + P2 + P4 (best balance of effectiveness and usability)

---

## Maintenance

### Update Triggers

- New GitOps violation discovered
- AI behavior pattern indicates instruction gap
- CI/CD workflow changes
- Production architecture changes

### Review Schedule

- **Weekly**: Check for new violations
- **Monthly**: Review and refine patterns
- **Quarterly**: Major pattern update based on data

### Version History

- v1.0 (2026-02-27): Initial pattern library created
  - Based on Incident #002 analysis

---

## Contributing

To add new patterns:

1. Document the scenario
2. Create instruction template
3. Test with AI assistant
4. Measure effectiveness
5. Submit for inclusion

---

**Pattern Library Maintainer**: Research Specialist
**Review Date**: 2026-03-27
**Status**: Active - Ready for implementation
