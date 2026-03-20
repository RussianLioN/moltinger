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
- Beads migration mode guards and staged rollout:
  - `scripts/beads-dolt-pilot.sh`
  - `scripts/beads-dolt-rollout.sh`
  - `scripts/beads-normalize-issues-jsonl.sh`
- deterministic create/start execution:
  - `scripts/worktree-phase-a.sh`
- topology reconcile, stale state, locks:
  - `scripts/git-topology-registry.sh`

If you are not sure, start with the helper and the unit tests. Most user-facing `command-worktree` bugs end there.

If the hotfix touches Beads ownership:
- keep plain `bd` as the only normal-path user command
- preserve worktree-local ownership and fail closed before canonical-root fallback
- treat canonical-root mutation as a separate explicit override path; do not allow plain mutating `bd` or helper scripts to auto-select the root tracker
- if a helper script passes `--db` directly, route it through the ownership contract or require an explicit operator-supplied DB target
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
scripts/git-topology-registry.sh check
git status
```

If the hotfix also requires publishing a tracked topology snapshot, do that as a separate explicit step from a dedicated non-main topology-publish worktree/branch.

If the hotfix touches Beads migration modes, also run:

```bash
bash tests/unit/test_beads_dolt_pilot.sh
bash tests/unit/test_beads_dolt_rollout.sh
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

If the affected worktree is in pilot mode, replace the sync step with `./scripts/beads-dolt-pilot.sh review`.
If the affected worktree is in cutover mode, replace the sync step with `./scripts/beads-dolt-rollout.sh verify --worktree .`.
If the ordinary repo-local wrapper sync path hangs, fall back to direct system `bd --no-daemon --db "$PWD/.beads/beads.db" sync`.

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
