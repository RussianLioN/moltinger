# Contract: JSONL Rewrite Guard

## Purpose

Определить, как система отличает допустимый semantic rewrite `.beads/issues.jsonl` от nondeterministic noise и ownership violations.

## Classification Categories

| Category | Description | Expected Action |
|----------|-------------|-----------------|
| `semantic` | Реальное изменение issue payload или dependency semantics | Allow only if ownership contract passes |
| `noise_only` | Serialization/order-only drift without semantic delta | Do not rewrite tracked file |
| `ownership_violation` | Rewrite target does not belong to current authority | Block before write |
| `migration_rewrite` | Controlled corrective rewrite inside approved migration flow | Allow only through migration contract |
| `rollback_restore` | Restore to last known-good state during rollback | Allow only through rollback contract |

## Canonical Form Rules

1. Repeated safe sync on unchanged semantic content must yield byte-stable output.
2. Approved canonicalization rules must be deterministic and documented.
3. Noise-only classification must be based on semantic comparison, not just textual diff size.
4. A rewrite that changes issue families outside the current worktree scope is not canonicalization; it is an ownership violation.

## Required Evidence

Every attempted rewrite must be able to report:

- before hash
- after hash or “not written”
- classification result
- changed issue IDs, if any
- target JSONL path
- authority decision code

## Blocking Conditions

- no single authoritative target
- sibling or canonical-root incidental rewrite from dedicated worktree
- order-only or serialization-only delta without approved semantic change
- migration-required state outside the migration workflow
