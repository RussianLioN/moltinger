# RCA Index

**Last Updated**: 2026-03-14
**Version**: 1.7.0

## Statistics

| Metric | Value |
|--------|-------|
| Total RCA | 14 |
| Avg Resolution Time | N/A |
| This Month | 14 |

## By Category

| Category | Count | Percentage |
|----------|-------|------------|
| generic | 4 | 31% |
| process | 7 | 50% |
| cicd | 1 | 8% |
| security | 1 | 8% |
| shell | 1 | 8% |

## By Severity

| Severity | Count | Description |
|----------|-------|-------------|
| P0 | 1 | Critical - blocks release |
| P1 | 2 | High - production impact |
| P2 | 6 | Medium - process issue |
| P3 | 4 | Low - minor issue |
| P4 | 1 | Backlog |

## Registry

| ID | Date | Category | Severity | Status | Root Cause | Fix |
|----|------|----------|----------|--------|------------|-----|
| RCA-014 | 2026-03-14 | process | P2 | resolved | Clawdiy preflight treated deploy-target runtime-home materialization as a CI checkout prerequisite | made runtime-home preflight target-aware for CI vs deploy target |
| RCA-013 | 2026-03-13 | process | P1 | mitigating | Clawdiy deploy contract mounted read-only `openclaw.json` instead of writable `~/.openclaw` required by the official OpenClaw wizard | switched to writable runtime-home mount + ownership normalization + preflight/backup/smoke guards |
| RCA-012 | 2026-03-12 | process | P2 | resolved | Clawdiy browser bootstrap was documented as Settings/OAuth flow instead of verified dashboard token/pairing bootstrap | added browser-bootstrap runbook + rule + doc corrections |
| RCA-011 | 2026-03-12 | process | P2 | resolved | Hosted Clawdiy UI used password auth modeled as server-side secret presence instead of browser-facing token flow | switched gateway auth to token + legacy fallback + rule |
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

⚠️ Warning: 5+ RCA in category `process` - continue turning recurring operator mistakes into explicit rules/checklists.

---

*This index is automatically updated by the RCA skill.*
