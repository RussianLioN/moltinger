# RCA Index

**Last Updated**: 2026-03-08
**Version**: 1.3.0

## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | 10 |
| Avg Resolution Time | N/A |
| This Month | 10 |

## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| generic | 4 | 40% |
| process | 3 | 30% |
| cicd | 1 | 10% |
| security | 1 | 10% |
| shell | 1 | 10% |

## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | 1 | Critical - blocks release |
| P1 | 1 | High - production impact |
| P2 | 3 | Medium - process issue |
| P3 | 4 | Low - minor issue |
| P4 | 1 | Backlog |

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-010 | 2026-03-08 | cicd | P1 | resolved | Deploy workflow wrote audit markers into repo root and then detected them as drift | moved markers to `data/` + static guard |
| RCA-009 | 2026-03-08 | process | P2 | resolved | No mandatory target-boundary check before local runtime actions | added runtime-target guardrail |
| RCA-008 | 2026-03-07 | process | P2 | resolved | No mandatory context-first lookup before asking for secret values | added context-first protocol |
| RCA-007 | 2026-03-07 | shell | P4 | resolved | Misinterpreted non-zero code from diagnostic command | protocol note added |
| RCA-006 | 2026-03-04 | security | P0 | resolved | Unsafe command handling path | manual guard + policy check |
| RCA-005 | 2026-03-04 | process | P2 | resolved | Instruction growth and duplication in sessions | optimization + guardrails |
| RCA-004 | 2026-03-03 | generic | P3 | resolved | Test scenario for QA validation | test passed |
| RCA-003 | 2026-03-03 | generic | P3 | resolved | Missing branch validation in Speckit flow | cherry-pick + rule |
| RCA-002 | 2026-03-03 | generic | P3 | resolved | Missing network validation in review flow | preflight-check |
| RCA-001 | 2026-03-03 | generic | P3 | resolved | Missing auto-trigger for RCA skill | skill created |

## Patterns Detected

⚠️ Warning: 4+ RCA in category `generic` - continue shifting fixes from ad-hoc notes to hard rules/checklists.

---

*This index is automatically updated by the RCA skill.*
