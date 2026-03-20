# Contract: Migration Rollout

## Purpose

Определить bounded migration path, staged rollout и отдельный rollback для новой deterministic ownership/sync модели.

## Migration Modes

| Mode | Description | Writes Allowed |
|------|-------------|----------------|
| `audit` | Classify worktrees and build migration plan | No |
| `apply` | Apply only safe migration actions with snapshots | Yes |
| `verify` | Confirm post-apply invariants and unresolved blockers | No |
| `rollback` | Restore enforcement/configuration path using preserved evidence | Yes |

## Candidate States

| State | Meaning | Default Handling |
|-------|---------|------------------|
| `current` | Already compatible with new contract | No migration needed |
| `legacy` | Known old ownership residue, safely recoverable | Safe apply candidate |
| `partial` | Missing part of local foundation | Block unless bounded repair is defined |
| `ambiguous` | More than one plausible owner or target | Manual-only |
| `damaged` | Missing or conflicting state that risks issue loss | Manual-only |

## Required Guarantees

1. Audit mode must classify candidates before any mutation.
2. Apply mode must snapshot affected state before rewrite.
3. No apply step may drop an issue record without journal evidence and explicit classification.
4. Canonical-root cleanup is excluded from the migration contract.
5. Rollout stages must be reportable independently from cleanup and recovery.
6. Rollback must preserve RCA and migration evidence.

## Rollout Stages

1. `report_only`: observe and classify without blocking existing writes
2. `controlled_enforcement`: block only clearly unsafe rewrites on scoped surfaces
3. `verification`: prove byte-stable safe sync and absence of leakage/noise in covered scenarios

## Rollback Triggers

- false-positive blocking in a covered safe sync path
- unexpected issue loss risk
- inability to reproduce RCA evidence after rollout
- operator-confirmed need to return to previous enforcement mode while preserving evidence
