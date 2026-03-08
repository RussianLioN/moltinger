# Codex Rollout Rollback

Date: 2026-03-08

This runbook defines the preferred rollback path for the Codex operating-model rollout.

## Preferred Rollback Path

Use `git revert`, not manual file restoration.

Known rollout commits so far:

- `8cf5e25` `fix(docs): normalize lessons index generation`
- `8dd5d5a` `docs(rca): record codex github auth false failure`
- `8087ae8` `chore(codex): harden operating model enforcement`
- `f4e1c68` `docs(topology): register Codex rollout worktree`
- `6451abb` `docs(codex): add gpt-5.4 operating model and local AGENTS split`

If newer Codex-rollout follow-up commits exist, revert those first, then revert the commits above in reverse chronological order.

Example:

```bash
git checkout codex/gpt54-agents-split
git revert 8cf5e25
git revert 8dd5d5a
git revert 8087ae8
git revert f4e1c68
git revert 6451abb
```

If the rollout has already been merged, run the same `git revert` flow on the integration branch instead of restoring files manually.

## Merge Strategy Note

Preferred strategy: preserve the rollout commit history with a normal merge or a rebase merge.

If the rollout is squash-merged, rollback should target the single squash commit on the integration branch instead of the individual branch commits listed above.

## Verification After Revert

Run:

```bash
make instructions-check
make codex-check-ci
git status
```

Expected outcome:

- generated `AGENTS.md` is in sync
- Codex governance checks pass
- working tree is clean or only contains the expected revert commit

## Emergency Fallback

There is also a machine-local emergency archive from before the rollout:

```bash
/tmp/moltinger-artifact-archives/20260308T133527Z-pre-codex-operating-model.tar.gz
```

Use that only if normal `git revert` is unavailable. The archive is not the primary rollback mechanism and should not replace Git history.
