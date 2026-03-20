# Quickstart: Deterministic Beads Issues JSONL Ownership

> Phase A note: the commands below describe the planned operator contract for implementation. They are not all available yet in the current branch.

## Scenario 1: Reproduce a Known Leakage Case

Goal: prove that a manual or ambiguous worktree path would have rewritten the wrong `.beads/issues.jsonl`.

```bash
./scripts/beads-issues-jsonl-rca.sh reproduce \
  --scenario manual-hotfix-root-leak \
  --format human
```

Expected outcome:

- run log shows current worktree, canonical root, intended JSONL target
- verdict is `leakage`
- output includes a blocking authority decision code
- no tracked JSONL file is mutated during reproduction

## Scenario 2: Confirm a Safe Semantic Sync Is Byte-Stable

Goal: ensure one safe worktree may sync only its own JSONL and a rerun without semantic changes produces no additional rewrite.

```bash
./scripts/beads-issues-jsonl-rca.sh verify-safe-sync \
  --scenario dedicated-safe-sync \
  --rerun-check
```

Expected outcome:

- first pass may report a semantic rewrite
- rerun reports no new semantic delta
- resulting `.beads/issues.jsonl` hash remains unchanged on rerun

## Scenario 3: Block Ambiguous Ownership Before Write

Goal: demonstrate fail-closed behavior when the target JSONL authority is not unique.

```bash
./scripts/beads-issues-jsonl-rca.sh reproduce \
  --scenario ambiguous-owner \
  --format human
```

Expected outcome:

- verdict is `ambiguous`
- write is denied before mutation
- output includes a specific recovery hint instead of best-effort rewrite

## Scenario 4: Audit Migration Readiness

Goal: classify existing worktrees without mutating them.

```bash
./scripts/beads-sync-migration.sh audit --format human
```

Expected outcome:

- worktrees are grouped into `current`, `legacy`, `partial`, `ambiguous`, or `damaged`
- safe candidates and blocked candidates are listed separately
- journal records that canonical-root cleanup is still separate

## Scenario 5: Controlled Rollout

Goal: enable the new contract gradually.

```bash
./scripts/beads-sync-migration.sh rollout --stage report_only
./scripts/beads-sync-migration.sh rollout --stage controlled_enforcement
./scripts/beads-sync-migration.sh verify
```

Expected outcome:

- report-only stage produces evidence without blocking
- controlled enforcement blocks only covered unsafe rewrites
- verify stage confirms covered safe sync paths remain byte-stable

## Scenario 6: Rollback

Goal: disable the new enforcement path without deleting evidence or migration journals.

```bash
./scripts/beads-sync-migration.sh rollback --to previous-mode
```

Expected outcome:

- enforcement mode returns to the prior known-good state
- collected RCA logs and migration evidence remain available
- rollback summary explains what was restored and what still requires manual review
