# RCA Index

**Last Updated**: 2026-03-07
**Version**: 1.1.0

## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | 7 |
| Avg Resolution Time | N/A |
| This Month | 7 |

## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| generic | 4 | 57% |
| process | 1 | 14% |
| security | 1 | 14% |
| shell | 1 | 14% |

## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | 1 | Critical - blocks release |
| P1 | 0 | High - production impact |
| P2 | 1 | Medium - process issue |
| P3 | 4 | Low - minor issue |
| P4 | 1 | Backlog |

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-007 | 2026-03-07 | shell | P4 | resolved | Misinterpreted non-zero code from diagnostic command | protocol note added |
| RCA-006 | 2026-03-04 | security | P0 | resolved | Unsafe command handling path | manual guard + policy check |
| RCA-005 | 2026-03-04 | process | P2 | resolved | Instruction growth and duplication in sessions | optimization + guardrails |
| RCA-004 | 2026-03-03 | generic | P3 | resolved | Test scenario for QA validation | test passed |
| RCA-003 | 2026-03-03 | generic | P3 | resolved | Missing branch validation in Speckit flow | cherry-pick + rule |
| RCA-002 | 2026-03-03 | generic | P3 | resolved | Missing network validation in review flow | preflight-check |
| RCA-001 | 2026-03-03 | generic | P3 | resolved | Missing auto-trigger for RCA skill | skill created |

## Patterns Detected

*No patterns detected yet - need 3+ RCA in same category*

---

*This index is automatically updated by the RCA skill.*
