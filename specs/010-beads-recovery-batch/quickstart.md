# Quickstart: Safe Batch Recovery of Leaked Beads Issues

## 1. Audit current leakage

Run the audit workflow and write a reviewable plan file:

```bash
scripts/beads-recovery-batch.sh audit \
  --output .tmp/current/beads-recovery-plan.json
```

Expected result:

- No tracker files are modified
- The plan lists `safe` and `blocked` candidates
- Any redirected target worktrees are marked for localization

## 2. Review blocked items

If the plan reports blocked candidates, inspect the reasons. Add or update explicit ownership overrides before applying any recovery.

Example:

```bash
sed -n '1,240p' .tmp/current/beads-recovery-plan.json
```

## 3. Apply only safe recoveries

Run apply using the exact audited plan:

```bash
scripts/beads-recovery-batch.sh apply \
  --plan .tmp/current/beads-recovery-plan.json \
  --journal-dir .tmp/current/beads-recovery-runs
```

Expected result:

- Only high-confidence items are touched
- Redirected owner worktrees are localized first
- A journal and per-worktree backups are created
- Canonical root cleanup remains prohibited if blocked items remain

## 4. Validate the result

Run the targeted validation set:

```bash
bash -n scripts/beads-recovery-batch.sh
tests/unit/test_beads_recover_issue.sh
tests/unit/test_beads_recovery_batch.sh
tests/static/test_beads_worktree_ownership.sh
make codex-check
```

## 5. Cleanup follow-up remains separate

Do not delete canonical root tracker entries as part of this workflow. Use the audit/journal output to drive a later, separately gated cleanup step.
