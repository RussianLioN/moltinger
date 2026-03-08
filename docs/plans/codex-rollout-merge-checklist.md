# Codex Rollout Merge Checklist

Date: 2026-03-08
Branch: `codex/gpt54-agents-split`

This document is the merge-prep summary for the Codex operating-model rollout.

## Recommended PR Title

`docs(codex): introduce repo-specific operating model and governance checks`

## PR Summary

This rollout adds a repo-specific Codex operating model for `moltinger`, splits local instructions by risk zone, introduces executable governance checks and launchers, and adds rollback and RCA documentation for safer day-to-day Codex usage.

## What Changes

1. Adds local `AGENTS.md` boundaries for `.ai`, `.beads`, `.claude`, `.github`, `.specify`, `config`, `docs`, `knowledge`, `scripts`, `specs`, and `tests`.
2. Introduces `docs/CODEX-OPERATING-MODEL.md` as the repo-specific source for Codex profiles, worktree policy, instruction precedence, and workflow selection.
3. Adds executable governance tooling:
   - `scripts/codex-check.sh`
   - `scripts/codex-profile-launch.sh`
   - `make codex-*` targets
   - `.github/workflows/codex-policy.yml`
4. Restores the root-level Speckit guard in generated `AGENTS.md`.
5. Adds rollback and RCA documentation:
   - `docs/plans/codex-rollout-rollback.md`
   - `docs/rca/2026-03-08-codex-github-auth-false-failure.md`
   - `docs/rules/codex-github-auth-debugging.md`
6. Normalizes the lessons index generator so the new RCA and future RCA files index cleanly.

## Reviewer Focus

Reviewers should pay attention to:

1. Whether the new local `AGENTS.md` boundaries match the repo's actual write scopes.
2. Whether `docs/CODEX-OPERATING-MODEL.md` is clear that `gpt-5.4` applies to local Codex sessions, not the active Moltis runtime provider stack.
3. Whether `scripts/codex-check.sh` and `.github/workflows/codex-policy.yml` are strict enough without being noisy.
4. Whether force-tracked `.beads/AGENTS.md` is acceptable despite `.beads/*` being generally ignored.
5. Whether the lessons-index fix in `scripts/build-lessons-index.sh` is acceptable as part of this rollout branch.

## Pre-Merge Checks

Run:

```bash
make instructions-check
make codex-check-ci
./scripts/build-lessons-index.sh
git diff --stat origin/main...HEAD
```

Expected result:

- generated `AGENTS.md` is in sync
- Codex governance checks pass
- lessons index rebuilds cleanly
- diff matches the scope of this rollout

## Merge Strategy

Preferred:

- merge commit
- or rebase merge

Reason:

- preserves the rollout history
- keeps rollback straightforward using `docs/plans/codex-rollout-rollback.md`

If squash merge is required, update rollback expectations to target the squash commit on the integration branch.

## Post-Merge Follow-Up

1. Verify `main` still passes `make codex-check-ci`.
2. Refresh `docs/GIT-TOPOLOGY-REGISTRY.md` if the rollout worktree lifecycle changes.
3. Decide whether `/tmp/moltinger-codex-gpt54-agents-split` should be retired or recreated as a sibling worktree.
4. If the team adopts the launchers, communicate:
   - `make codex-research`
   - `make codex-runtime`
   - `make codex-review`
5. If merge strategy was squash, update rollback notes accordingly.
