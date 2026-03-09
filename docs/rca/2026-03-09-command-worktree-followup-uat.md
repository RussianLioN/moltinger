---
title: "Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps"
date: 2026-03-09
severity: P2
category: shell
tags: [git-worktree, topology-registry, command-worktree, ux, lock, rca]
root_cause: "The worktree workflow still left edge-case behavior implicit: attach naming reused raw branch strings, canonical main sync was specified too loosely, and missing lock metadata lacked actionable multi-worktree diagnostics."
---

# RCA: Command Worktree Follow-Up UAT Gaps

Date: 2026-03-09
Feature: `006-git-topology-registry`
Context: repeated manual UAT from `uat/006-git-topology-registry`

## Error

Follow-up UAT exposed three remaining workflow defects after the first round of hardening:

1. Existing feature-branch attach flow rendered an awkward preview such as `../moltinger-feat-remote-uat-hardening`.
2. The operator improvised `git pull --rebase origin main`, which is the wrong command shape for this workflow and failed with `Cannot rebase onto multiple branches`.
3. Topology lock timeouts still sometimes reported only `Lock owner metadata is unavailable`, which was accurate but not actionable enough when a sibling worktree or older script held the lock.

## 5 Whys

### Problem 1: attach preview looked non-canonical

1. Why did attach preview show `../moltinger-feat-...`?
   - Because preview formatting reused the raw branch name for directory rendering.
2. Why did that matter?
   - Because creation planning already normalized slug-only and issue-aware worktree names, so attach mode visibly disagreed with the create path.
3. Why did attach mode diverge?
   - Because `format_worktree_dirname` sanitized the whole branch string instead of stripping common prefixes such as `feat/` or repo-prefixed issue ids.
4. Why was that not caught earlier?
   - Because tests only covered plan output, not attach output for existing feature branches.
5. Why is that a real defect?
   - Because the user-facing contract of one-shot worktree naming must stay stable across create, attach, and reuse flows.

### Problem 2: canonical root sync used the wrong pull form

1. Why did the workflow run `git pull --rebase origin main`?
   - Because the operator had room to improvise from a high-level instruction instead of following one exact command shape.
2. Why was improvisation possible?
   - Because the workflow text described the intent but not the exact safe sequence strongly enough.
3. Why is that dangerous?
   - Because the command is executed in mutation-heavy create flows, where an avoidable sync failure adds noise and reduces trust.
4. Why was this visible in UAT?
   - Because the UAT intentionally exercised a real start flow rather than a curated happy path.
5. Why is that a process defect?
   - Because command workflows should minimize operator freedom at mutation boundaries and encode the exact canonical commands.

### Problem 3: missing lock metadata was still hard to diagnose

1. Why did timeout diagnostics stop at `metadata is unavailable`?
   - Because the lock diagnostics handled the missing-file case but did not explain likely causes or the exact safe recovery path.
2. Why can metadata be missing at all?
   - Because a sibling worktree may still be on an older topology script, or a previous process may exit after creating the lock directory but before writing `owner.env`.
3. Why did that confuse UAT?
   - Because the operator could not tell whether this was a live sibling refresh, an older script, or a stale orphaned lock.
4. Why is that a workflow problem?
   - Because topology refresh is a shared operation across sibling worktrees; poor diagnostics directly harms multi-session UX.
5. Why is this a root-cause issue rather than a cosmetic one?
   - Because the lock behavior itself was correct; the failure was that the operator lacked enough evidence to choose the next safe action confidently.

## Root Cause

The remaining gaps came from one common source: the workflow contract was still too implicit at the edges.

- helper output was not fully normalized across create and attach paths
- canonical root sync still relied on intent-level instructions instead of one exact command sequence
- shared lock diagnostics did not fully explain older-script or interrupted-process scenarios

## Fixes Applied

1. Normalized attach/reuse preview paths by deriving sibling worktree suffixes from stripped branch names rather than raw branch strings.
2. Tightened `command-worktree` instructions to require one exact canonical-root sync sequence and to forbid `git pull --rebase origin main`.
3. Expanded topology lock diagnostics to explain likely missing-metadata causes and print an exact safe cleanup path.
4. Added regression coverage for:
   - attach preview normalization
   - timeout without `owner.env`

## Prevention

1. Any user-visible naming rule must be tested across plan, create, and attach flows.
2. Mutation workflows should specify exact git command shapes, not just intent.
3. Shared-lock diagnostics must assume mixed-version sibling worktrees during rollout and provide actionable fallback text.

## Уроки

- When a workflow spans multiple worktrees, “technically correct” diagnostics are not enough; they must also identify likely cross-worktree version skew and the next safe operator action.
- If create and attach produce different names for the same target, users will read that as workflow instability even when the underlying git state is correct.
