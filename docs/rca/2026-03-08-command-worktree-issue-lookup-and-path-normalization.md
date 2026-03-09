# RCA: Command Worktree Issue Lookup And Path Normalization

Date: 2026-03-08
Feature: `006-git-topology-registry`
Context: second manual UAT pass from `uat/006-git-topology-registry`

## Error

Manual UAT exposed two additional workflow problems in the `command-worktree` start path:

1. `bd show <issue>` failed in some worktrees with SQLite errors such as readonly or unavailable database access.
2. Sibling worktree directories were created with duplicated repo prefix, for example `moltinger-moltinger-dmi-telegram-webhook-rollout`.

## 5 Whys

### Problem 1: issue lookup failed

1. Why did `bd show` fail?
   - Because the command tried to access the SQLite-backed Beads database directly in an environment where that DB path was readonly or otherwise unavailable.
2. Why did the workflow stop on that?
   - Because the documented flow assumed direct DB access would always work.
3. Why was that assumption wrong?
   - Because worktrees, sandboxes, and redirected `.beads` setups can still read issue data through JSONL-backed `--no-db` mode even when SQLite access fails.
4. Why did UAT still continue?
   - Because the operator improvised around the failure instead of following a documented fallback.
5. Why is that a real defect?
   - Because the documented workflow did not encode the proven fallback path for a common environment-specific failure mode.

### Problem 2: worktree directory names duplicated the repo slug

1. Why was the directory name duplicated?
   - Because the naming template used `../<repo>-<issue-lower>-<slug>`.
2. Why did that create `moltinger-moltinger-*`?
   - Because issue ids themselves already carried the `moltinger-` prefix.
3. Why was the template not normalizing that prefix?
   - Because the original workflow treated the issue id as a single reusable token for both branch and directory naming.
4. Why is that wrong?
   - Because branch names benefit from full issue ids, but sibling directory names become noisy and redundant when the repo slug is repeated.
5. Why is that a UX defect?
   - Because users immediately see awkward paths and lose confidence that the workflow is canonical.

## Root Cause

The command-worktree workflow reused a naive issue token in two places with different naming needs:

- branch naming wanted the full issue id
- directory naming wanted a repo-prefix-normalized short form

At the same time, the documented Beads lookup path lacked an explicit `--no-db` fallback for environments where direct SQLite access is not available.

## Fixes Applied

1. Updated `command-worktree` naming rules:
   - `issue-lower` keeps the full issue id for branch names
   - `issue-short` strips a leading `<repo>-` prefix for sibling worktree directories
2. Documented Beads fallback:
   - retry `bd show --no-db <ISSUE_ID>` when normal `bd show` fails
   - same fallback pattern for `bd update` and `bd close`

## Prevention

1. Do not reuse one issue token blindly across branch names, worktree paths, and display text.
2. When a workflow depends on Beads reads in mixed environments, always define a no-DB fallback path explicitly.
3. Future UAT should validate:
   - issue resolution
   - final branch name
   - final sibling directory name
   - issue status transition
