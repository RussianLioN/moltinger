# RCA Index

**Last Updated**: 2026-03-03
**Version**: 1.1.0

## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | 4 |
| Avg Resolution Time | N/A |
| This Month | 4 |

## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| docker | 1 | 25% |
| cicd | 0 | 0% |
| shell | 1 | 25% |
| data-loss | 0 | 0% |
| generic | 1 | 25% |
| process | 1 | 25% |

## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | 0 | Critical - blocks release |
| P1 | 1 | High - production impact |
| P2 | 1 | Medium - process issue |
| P3 | 2 | Low - minor issue |
| P4 | 0 | Backlog |

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-004 | 2026-03-03 | shell | P3 | resolved | Test scenario for QA validation | test passed |
| RCA-003 | 2026-03-03 | process | P2 | resolved | No branch validation in speckit | cherry-pick + rule |
| RCA-002 | 2026-03-03 | docker | P1 | resolved | Missing network validation | preflight-check |
| RCA-001 | 2026-03-03 | generic | P3 | resolved | Missing auto-trigger for RCA skill | skill created |

## Patterns Detected

*No patterns detected yet - need 3+ RCA in same category*

---

*This index is automatically updated by the RCA skill.*
