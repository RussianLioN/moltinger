# Implementation Plan: Telegram Skill CRUD UAT Hardening

**Branch**: `feat/moltinger-wdj0-telegram-skill-crud-uat` | **Date**: 2026-04-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/041-telegram-skill-crud-uat-hardening/spec.md`

## Summary

Authoritative Telegram remote UAT already proves `create + immediate follow-up visibility`, but it does not yet provide first-class live-proof semantics for `update` and `delete`. This slice extends the existing `scripts/telegram-e2e-on-demand.sh` semantic review so operator-safe artifacts can validate all native skill CRUD turns that are now supported by the deployed Telegram-safe runtime.

## Technical Context

**Language/Version**: Bash, existing shell-based test harness  
**Primary Dependencies**: `scripts/telegram-e2e-on-demand.sh`, `jq`, `curl`, current `/api/skills` runtime checks, component shell tests  
**Storage**: Review-safe JSON artifact emitted by the authoritative Telegram wrapper  
**Testing**: `tests/component/test_telegram_remote_uat_contract.sh`, targeted static/doc review  
**Target Platform**: Production-aware operator-driven Telegram remote UAT  
**Project Type**: Scripts + tests + operator docs  
**Constraints**: No hidden destructive automation on shared production; preserve review-safe artifact shape; avoid inventing a parallel UAT stack; keep docs aligned with real operator surface  
**Scale/Scope**: Extend existing mutation semantics from create-only to full native CRUD proof for update/delete

## Constitution Check

- Context-First Development: PASS. Existing authoritative UAT script, tests, and docs were inspected before planning changes.
- Single Source of Truth: PASS. The authoritative wrapper remains the only mutation-proof entrypoint; we are extending its semantic review rather than adding a second verifier.
- Code Reuse & DRY: PASS. Work stays inside the current `telegram-e2e-on-demand` contract and existing component tests.
- Quality Gates: PASS. Verification remains targeted and review-safe; no new blocking live CI gate is introduced.
- Progressive Specification: PASS. A dedicated Speckit package is created before runtime changes.

## Project Structure

### Documentation

```text
specs/041-telegram-skill-crud-uat-hardening/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code

```text
scripts/
└── telegram-e2e-on-demand.sh

tests/component/
└── test_telegram_remote_uat_contract.sh

docs/
└── telegram-e2e-on-demand.md
```

## Implementation Delta

1. Normalize mutation intent detection in `scripts/telegram-e2e-on-demand.sh` so semantic review can distinguish create vs update vs delete.
2. Reuse existing pre-send `/api/skills` baseline logic for update/delete, not just create.
3. Add deterministic post-reply verification:
   - update: target existed before send and still exists after reply
   - delete: target existed before send and is gone after reply
4. Add mutation-specific failure codes and diagnostic context.
5. Update operator docs to reflect actual mutation coverage.
6. Extend component tests for the new mutation verdicts and failure classes.

## Acceptance Proof

Acceptance for this slice is satisfied by:

- targeted component contract tests for update/delete mutation verdicts
- targeted script syntax validation
- updated operator docs that match the new runtime/UAT contract

No live production mutation should be executed implicitly as part of implementation proof in this slice.
