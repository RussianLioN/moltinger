# Beads Recovery Owner Branch Snapshot Check

**Status:** Active
**Effective date:** 2026-03-12
**Scope:** `scripts/beads-recovery-batch.sh` audit and related forensic cleanup workflows

## Rule

Before classifying a recovery candidate as `missing_worktree`, the audit must check whether the issue is already present in the owner branch snapshot:

```bash
git show <branch>:.beads/issues.jsonl
```

If the issue exists there, the candidate must be reported as `already_present_in_owner_branch`, not `missing_worktree`.

## Why

`missing_worktree` means ownership evidence is absent from the current topology.
An owner branch snapshot containing the issue is already ownership evidence, even if no sibling worktree is currently attached.

## Expected Outcome

- forensic audits distinguish unresolved leakage from already localized branch state;
- blocked candidates remain fail-closed for `apply`;
- operators can focus manual follow-up only on genuinely unresolved ownership cases.
