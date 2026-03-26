# RCA: prod-mutation-guard denied canonical main deploy because it required `/user` on `github.token`

Date: 2026-03-26  
Scope: canonical `Deploy Moltis` workflow from `main`  
Triggering run: `23616874000`

## Summary

The canonical production deploy from `main` failed before rollout even began. The failure happened inside `scripts/prod-mutation-guard.sh` during `align-server-checkout`, where the guard tried to verify `github.token` by calling `GET https://api.github.com/user`.

That assumption was wrong for the actual GitHub Actions runtime. The same token could successfully read the current Actions run metadata, but the `/user` endpoint was not a reliable identity check for this token shape. The guard therefore fail-closed on a legitimate `main` deploy.

## Impact

- `Deploy Moltis` run `23616874000` stopped before any production mutation.
- The Telegram activity-leak fix merged to `main` but did not become live.
- Operators saw a false branch-policy-style denial even though the workflow really was the canonical `main` deploy.

## What Happened

1. PR `#105` with the Telegram activity-leak hardening was merged into `main`.
2. `Deploy Moltis` auto-started from the `main` push.
3. `Pre-flight Checks`, `GitOps Compliance Check`, `Pre-deployment Tests`, and `Backup Current State` all succeeded.
4. `Deploy to Production` failed in `Align server git checkout before sync`.
5. The failing guard output was:
   - `Production mutation denied for action 'align-server-checkout'.`
   - `Unable to verify GitHub token identity.`

## Root Cause

`prod-mutation-guard.sh` required two different proofs:

- read current run metadata from `repos/<repo>/actions/runs/<run_id>`
- read `GET /user` and confirm `login == github-actions[bot]`

The second proof was overfit to an incorrect model of `github.token`. In this workflow, the token had enough permission to read the current run metadata but not to satisfy the `/user`-based identity check reliably.

The guard therefore rejected a legitimate canonical deploy.

## Why It Escaped

- Unit tests modeled the happy path with a fake `/user` response, so they preserved the invalid assumption.
- The first real canonical deploy after introducing this stricter check exposed the mismatch.

## Fix

- Remove the hard requirement on `GET /user`.
- Keep the fail-closed run-based verification:
  - repository
  - workflow name
  - event
  - branch/tag
  - SHA
- Add a repository match check from the run payload so the guard still verifies the run against the expected repo.
- Update unit tests so the sanctioned happy path no longer depends on `/user`.

## Prevention

- Do not treat `github.token` as a user token unless the official GitHub Actions contract guarantees that behavior.
- Prefer verifying immutable run metadata over trying to infer “who the token is”.
- For new GitHub Actions guards, add at least one test where `/user` is unavailable but the run API still succeeds.

## Lessons

- Security/production guards can be wrong in ways that look like policy violations but are actually contract mismatches with the CI runtime.
- When a guard protects production mutation, validate it against the real canonical workflow path, not only local mocks.
