# RCA: Codex Worktree UAT Bridge And Lock Contention

Date: 2026-03-08
Feature: `006-git-topology-registry`
Context: manual UAT from `uat/006-git-topology-registry`

## Error

Manual UAT of worktree creation in Codex CLI exposed two workflow failures:

1. The user tried `/worktree ...` and Codex CLI returned `Unrecognized command '/worktree'`.
2. The follow-up `command-worktree` flow created the new worktree, but topology reconciliation hit repeated lock timeouts and stopped before completing the full start workflow.

## 5 Whys

### Problem 1: `/worktree` failed in Codex CLI

1. Why did `/worktree` fail?
   - Because Codex CLI did not register `/worktree` as a native slash command.
2. Why did the user expect `/worktree` to work?
   - Because our docs and examples presented `/worktree` as the normal interface.
3. Why did docs present it that way?
   - Because `.claude/commands/worktree.md` was written in Claude-style command format.
4. Why was that not translated for Codex?
   - Because the Codex adapter documented the command bridge only partially and did not explicitly warn that bridged commands are usually invoked via `command-*` skills.
5. Why is that a real defect?
   - Because the user-facing contract in Codex was inaccurate and caused first-contact UX failure.

### Problem 2: topology refresh hit lock contention during `command-worktree`

1. Why did topology refresh time out on lock?
   - Because another topology operation was holding the shared lock in the common `.git` directory.
2. Why was another topology operation competing during worktree creation?
   - Because post-checkout/post-merge/post-rewrite hooks were invoking `doctor --prune`, which acquired the same exclusive reconcile lock.
3. Why were hooks invoking `doctor --prune`?
   - Because they were initially designed to produce recovery drafts automatically after out-of-band topology changes.
4. Why was that wrong for hook behavior?
   - Because hooks are supposed to be validation/backstop only; they should not contend with explicit reconcile operations during managed workflows.
5. Why did the workflow stop in a confusing place?
   - Because `command-worktree` also allowed the operator to drift into the canonical `main` worktree, where the topology script may not exist yet, and then attempted refresh from the wrong place.

## Root Cause

Two separate design gaps combined:

1. Codex-facing documentation did not accurately describe how bridged command workflows are invoked.
2. Backstop hooks were too heavy: they used an exclusive reconcile path (`doctor --prune`) instead of a read-only stale check, creating unnecessary lock contention during managed topology mutations.

## Fixes Applied

1. Updated Codex-facing docs and command artifacts to distinguish:
   - Claude-style slash commands
   - Codex `command-*` skill bridge or direct script usage
2. Changed `post-checkout`, `post-merge`, and `post-rewrite` hooks from `doctor --prune` to read-only `check`.
3. Updated `command-worktree` instructions to:
   - use read-only topology preflight
   - refresh `main` from canonical root without assuming the invoking worktree must switch
   - run topology refresh from the invoking or authoritative topology worktree
   - stop cleanly if reconcile lock remains blocked
4. Increased default lock wait tolerance and improved lock-timeout messaging in `scripts/git-topology-registry.sh`.

## Prevention

1. Any Codex-facing workflow doc must explicitly state whether it is:
   - a native slash command
   - a bridged `command-*` skill
   - or a direct script invocation
2. Hooks must stay read-only unless there is a very strong reason otherwise.
3. Managed topology mutations should reserve exclusive reconcile for explicit `refresh`/`doctor --write-doc`, not for passive hooks.
