# Rule: Speckit Artifact Reconciliation

## Purpose

Prevent drift between actual implementation and Speckit planning artifacts.

## Scope

Apply this rule whenever work references or depends on a Speckit feature folder:

- `specs/<feature>/spec.md`
- `specs/<feature>/plan.md`
- `specs/<feature>/tasks.md`
- `specs/<feature>/checklists/*`

## Required Steps

1. **Pre-implementation reconcile**
   - Run: `git status --short specs/<feature>/`
   - If key artifacts are untracked, add them to git before or alongside first implementation commit.

2. **Execution-time sync**
   - Update `tasks.md` checkboxes as work is completed.
   - Keep diagnosis artifacts (`.tmp/current/*`) mapped to task IDs.

3. **Pre-push verify**
   - Ensure no hidden untracked files remain in `specs/<feature>/`.
   - Confirm commit history reflects both:
     - implementation/config changes
     - corresponding Speckit artifact updates

## Failure Pattern This Prevents

- Runtime fixes are committed, but Speckit artifacts remain untracked or stale.
- Next session cannot trust `tasks.md` as source of truth.

## Related RCA

- `docs/rca/2026-03-06-browser-compat-speckit-desync.md`
