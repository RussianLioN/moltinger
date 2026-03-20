# Rule: Beads Dolt-Native Contract

## Purpose

Define the repo-level Beads invariants that the migration is moving toward, even while Phase B remains inventory-first.

## Required Invariants

- The repo operates with one active Beads operating model for everyday work.
- The active model follows the upstream Dolt-native direction.
- Tracked `.beads/issues.jsonl` is not the long-term primary operational truth.
- Human and agent operators have one documented review path.
- Readiness must be proven before pilot cutover.

## Forbidden States

- Long-lived mixed mode between legacy JSONL-first behavior and the target contract.
- Silent fallback from target behavior back to legacy JSONL-first reasoning.
- Hidden dependence on legacy docs, hooks, or wrappers after cutover.
- Mixing migration with canonical-root cleanup inside one implicit workflow.

## Phase B Boundary

- Inventory/readiness may detect blockers and compatibility bridges.
- Inventory/readiness may not perform pilot, rollout, or rollback mutations.
- Pilot cutover remains blocked until the readiness report has no unresolved blockers.
