# GitOps Violation Prevention Research

**Incident**: #002 - GitOps Violation via scp (2026-02-27)
**Status**: ✅ Research Complete - Implementation Ready
**Priority**: High - Implement within 7 days

---

## Quick Start

**Have 5 minutes?** → Read [Summary](./gitops-recommendations-summary.md)
**Have 30 minutes?** → Read [Index](./gitops-prevention-index.md) + [Summary](./gitops-recommendations-summary.md)
**Have 2 hours?** → Implement Phase 1 (update AI instructions)

---

## Additional Research Tracks

| Topic | Documents | Status | Notes |
|-------|-----------|--------|-------|
| Codex CLI update monitoring | [Research](./codex-cli-update-monitoring-2026-03-09.md), [Speckit seed](../plans/codex-cli-update-monitoring-speckit-seed.md), [Feature spec](../../specs/007-codex-update-monitor/spec.md) | Feature package ready | Current local/latest CLI: `0.112.0`; Speckit package is prepared in `specs/007-codex-update-monitor/` for script-first implementation. |

---

## Document Guide

| Document | For Whom | Read Time | Purpose |
|----------|----------|-----------|---------|
| [Index](./gitops-prevention-index.md) | Everyone | 5 min | Navigation and overview |
| [Summary](./gitops-recommendations-summary.md) | Managers | 10 min | Executive summary |
| [Full Recommendations](./gitops-violation-prevention-recommendations.md) | Engineers | 45 min | Detailed analysis |
| [Pattern Library](./ai-gitops-instructions-patterns.md) | AI Trainers | 30 min | Instruction patterns |
| [Implementation Guide](./gitops-prevention-implementation-guide.md) | DevOps | 60 min | Step-by-step setup |

---

## What Happened

```bash
# ❌ WRONG (what happened):
scp test.sh root@server:/opt/moltinger/scripts/

# ✅ CORRECT (what should have happened):
git add test.sh
git commit -m "feat: add test script"
git push  # CI/CD deploys automatically
```

**Impact**: No audit trail, bypassed validation, configuration drift, no rollback.

---

## Solution: 3-Layer Defense

### Layer 1: AI Instructions (Prevents 95%+)
- Add mandatory pre-execution checklist
- Explicit negative constraints (no scp/ssh for changes)
- Decision tree for operations
- **Effort**: 22 minutes
- **Impact**: Prevents 95%+ of violations

### Layer 2: CI/CD Verification (Detects 100%)
- GitOps compliance checks in workflow
- Configuration drift detection
- Automated reconciliation
- **Effort**: 1 hour
- **Impact**: Detects all violations

### Layer 3: Process Changes (Systematic)
- Pre-commit validation hooks
- Script documentation standards
- Drift detection monitoring
- **Effort**: 4 hours
- **Impact**: Systematic prevention

---

## Implementation Timeline

### Phase 1: Today (2 hours)
- [ ] Update CLAUDE.md with GitOps sections
- [ ] Test AI compliance
- [ ] Commit changes

### Phase 2: This Week (4 hours)
- [ ] Implement CI/CD checks
- [ ] Enable pre-commit hooks
- [ ] Deploy drift detection

### Phase 3: This Month (8 hours)
- [ ] Complete infrastructure
- [ ] Train team
- [ ] Establish monitoring

**Total Effort**: 14 hours
**Expected Outcome**: Zero GitOps violations

---

## Quick Reference

### Allowed Operations

| Operation | Allowed? | Method |
|-----------|----------|--------|
| Read logs | ✅ Yes | `ssh server "docker logs"` |
| Check file | ✅ Yes | `ssh server "cat file"` |
| Deploy script | ❌ No | `git add → commit → push` |
| Modify config | ❌ No | Edit → commit → push |
| Delete file | ❌ No | `git rm → commit → push` |

### AI Instruction Template

```markdown
### GitOps Compliance (MANDATORY)

Before ANY ssh/scp command:
1. Does this change server state? → STOP if yes
2. Is file in git? → Add/commit/push first
3. Is there audit trail? → Must trace to commit
4. Use CI/CD workflow → Never bypass with scp/ssh

### Absolute Prohibitions

❌ NEVER: scp file server:/path/
❌ NEVER: ssh server "sed -i ..."
❌ NEVER: ssh server "echo ... >> file"

✅ ALWAYS: git add → commit → push → CI/CD
```

---

## Success Metrics

| Metric | Target | Timeline |
|--------|--------|----------|
| GitOps violations | 0 | 30 days |
| AI compliance rate | 100% | 7 days |
| Drift incidents | 0 | 30 days |

---

## Key Files

### Documentation
- [Index](./gitops-prevention-index.md) - Start here
- [Summary](./gitops-recommendations-summary.md) - Executive overview
- [Full Recommendations](./gitops-violation-prevention-recommendations.md) - Complete analysis
- [Pattern Library](./ai-gitops-instructions-patterns.md) - AI instruction patterns
- [Implementation Guide](./gitops-prevention-implementation-guide.md) - Setup steps

### Related Project Files
- [LESSONS-LEARNED.md](../LESSONS-LEARNED.md) - Incident details
- [CLAUDE.md](../CLAUDE.md) - AI instructions (to be updated)
- [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) - CI/CD config

---

## Get Started

1. **Read** [gitops-prevention-index.md](./gitops-prevention-index.md) (5 min)
2. **Review** [gitops-recommendations-summary.md](./gitops-recommendations-summary.md) (10 min)
3. **Implement** Phase 1 from [gitops-prevention-implementation-guide.md](./gitops-prevention-implementation-guide.md) (2 hours)
4. **Monitor** metrics weekly

---

## External References

- [Argo CD Self-Healing](https://github.com/argoproj/argo-cd/blob/master/docs/user-guide/auto_sync.md)
- [GitOps Principles](https://www.weave.works/technologies/gitops/)

---

## Support

**Questions?**
1. Check [Index](./gitops-prevention-index.md) for navigation
2. Review [Full Recommendations](./gitops-violation-prevention-recommendations.md) for details
3. Consult [Implementation Guide](./gitops-prevention-implementation-guide.md) for setup

**Status**: ✅ Research complete, implementation ready
**Priority**: High - Begin within 24 hours
