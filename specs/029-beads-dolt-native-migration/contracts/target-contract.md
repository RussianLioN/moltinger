# Contract: Target Beads Contract

## Purpose

Define the target repo-level Beads contract that this migration is moving toward.

## Required Invariants

- The repo has one active Beads operating model for everyday work.
- The target model aligns with current official upstream Dolt-native direction.
- Tracked `.beads/issues.jsonl` is not treated as the primary operational truth after full cutover.
- Human and agent workflows use one documented operator path.
- Worktree behavior is deterministic and compatible with the active contract.

## Forbidden States

- Long-lived mixed mode between legacy JSONL-first and new target contract
- Silent fallback from target contract to legacy JSONL-first behavior
- Hidden dependence on legacy docs or hooks after full cutover
