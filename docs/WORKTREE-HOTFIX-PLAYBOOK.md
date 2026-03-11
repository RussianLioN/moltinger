# Worktree Hotfix Playbook

Use this playbook if `command-worktree` is already merged, but a real session still shows a problem.

Examples:
- it creates the wrong branch name
- it continues work in the old session instead of stopping at handoff
- manual handoff loses structured downstream intent or prints both short and rich deferred payload blocks
- explicit terminal or Codex handoff does not fall back cleanly to manual handoff
- `doctor` suggests the wrong next step
- a readiness probe reports the wrong state
- a dedicated worktree falls back to the canonical root tracker instead of using its local `.beads/` ownership

## Core Rule

Do not fix `command-worktree` directly in `main`.

Always use a short-lived fix branch from fresh `main`.

## Simple Workflow

1. Reproduce the problem once.
2. Save the exact prompt and the exact output.
3. Create a follow-up issue in `bd`.
4. Create a fresh fix branch from `main`.
5. Add a regression test first.
6. Make the narrowest possible fix.
7. Run the focused checks.
8. Push and open a small follow-up PR.

## Step 1: Reproduce Cleanly

Capture:
- the exact prompt
- the branch and worktree where it happened
- what you expected
- what actually happened

Do not start fixing from a dirty branch or from a half-finished UAT worktree.

## Step 2: Create a Follow-Up Issue

Use `bd` and record:
- symptom
- reproduction steps
- expected behavior
- actual behavior
- whether the problem is in create, attach, doctor, finish, or cleanup

## Step 3: Create a Fresh Fix Branch

Preferred path:

```bash
cd /Users/rl/coding/moltinger
git pull --rebase
git worktree add ../moltinger-worktree-hotfix -b fix/worktree-<short-slug> main
cd ../moltinger-worktree-hotfix
```

Use this manual fallback if `command-worktree` itself is the thing that is broken.

## Step 4: Fix the Right Layer

Use the file that matches the real defect:

- workflow/orchestration behavior:
  - `./claude/commands/worktree.md`
- helper status, report, next steps:
  - `scripts/worktree-ready.sh`
- Beads ownership dispatch or localization:
  - `bin/bd`
  - `scripts/beads-resolve-db.sh`
  - `scripts/beads-worktree-localize.sh`
- deterministic create/start execution:
  - `scripts/worktree-phase-a.sh`
- topology reconcile, stale state, locks:
  - `scripts/git-topology-registry.sh`

If you are not sure, start with the helper and the unit tests. Most user-facing `command-worktree` bugs end there.

If the hotfix touches Beads ownership:
- keep plain `bd` as the only normal-path user command
- preserve worktree-local ownership and fail closed before canonical-root fallback
- treat residual canonical-root cleanup as a separate issue instead of folding it into the hotfix

## Step 5: Add a Regression Test First

Main test file:

```bash
tests/unit/test_worktree_ready.sh
```

If the bug is larger than helper output, add the smallest integration coverage that proves the failure.

For boundary and handoff regressions, verify the exact contract that broke:

- `Boundary: stop_after_create` or `Boundary: stop_after_attach` is still present
- `Pending` remains concise
- a structured request renders `Phase B Seed Payload (deferred, not executed)` instead of duplicating it alongside the short `Phase B only` block
- an explicit automatic handoff either reports `handoff_launched` or degrades to manual handoff and still stops

## Step 6: Run the Focused Checks

Minimum required set:

```bash
./tests/unit/test_worktree_ready.sh
make instructions-check
make codex-check
scripts/git-topology-registry.sh check
```

If topology changed:

```bash
scripts/git-topology-registry.sh refresh --write-doc
git status
```

## Step 7: Land the Fix

```bash
git add ...
git commit -m "fix(worktree): <short description>"
git pull --rebase
./scripts/bd-local.sh sync
git push
git status
```

`git status` must show that the branch is up to date with origin.

## What Not To Do

- do not fix directly in `main`
- do not use old source branches like `005-worktree-ready-flow` as the active fix branch
- do not merge raw topology snapshot commits from temporary UAT or micro-branches
- do not start a broad UAT cycle without a specific new hypothesis

## When To Use Consilium

Use `/consilium` only if the bug crosses multiple layers at once, for example:
- workflow text and helper output disagree
- Speckit branch allocation conflicts with create flow
- topology rules conflict with doctor or cleanup behavior

For ordinary bugfixes, use the small follow-up branch workflow above.
