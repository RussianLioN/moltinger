---
title: "PR2 docs carrier drifted because patch generation targeted the wrong base and ignored new docs"
date: 2026-03-26
severity: P3
category: process
tags: [carrier, patch, gitops, docs, process, rca, lessons]
root_cause: "Carrier generation reused branch-diff habits instead of building a worktree-to-target-base patch and therefore first targeted merge-base, then omitted untracked docs."
---

# RCA: PR2 carrier used the wrong diff base and dropped new docs

**Date:** 2026-03-26  
**Status:** Resolved  
**Severity:** P3  
**Category:** process  
**Impact:** The first materialized `PR2` docs-only carrier patch was not trustworthy because it targeted the wrong comparison boundary and omitted a newly created consilium report.

## Error

While materializing `specs/031-moltis-reliability-diagnostics/artifacts/pr2-main-docs-carrier.patch`, the first patch was generated from a merge-base-oriented diff and then from a commit-range diff that ignored new untracked docs. The result did not faithfully represent “apply this to verified `main`”.

## Lessons Pre-Check

Reviewed before running RCA:

- `./scripts/query-lessons.sh --tag gitops`
- `./scripts/query-lessons.sh --tag patch`
- `./scripts/query-lessons.sh --tag deployment`

Relevant prior lesson:

- `docs/rca/2026-03-24-moltis-embedding-runtime-config-and-ollama-env-drift.md`
  already established that remediation artifacts must be validated against the real target boundary instead of a convenient proxy.

What was new here:

- the failure happened in carrier generation, not in live deploy/runtime
- untracked docs required explicit inclusion via `--no-index`

## 5 Whys

### Why 1

Why was the first `PR2` carrier patch invalid?

Because `patch --dry-run` against a clean `origin/main` export showed reversed/already-applied behavior, and later the patch still omitted a newly created consilium report.

### Why 2

Why did `patch --dry-run` show reversed/already-applied behavior?

Because the first patch was generated with a `three-dot` diff, which targeted the merge base instead of the actual verified `origin/main` state.

### Why 3

Why was the second patch still incomplete after switching away from `three-dot`?

Because it used a commit-range diff against `origin/main..HEAD`, which still ignored newly created untracked files in the current worktree.

### Why 4

Why were those comparison modes chosen?

Because the carrier-generation step reused branch-diff habits instead of explicitly modeling the artifact as “patch current worktree onto target base”.

### Why 5

Why was that process ambiguity possible?

Because there was no explicit local rule stating that `main`-targeting carrier patches must be built against the real target base and must account for untracked docs before validation.

## Root Cause

Carrier generation lacked an explicit target-base rule, so branch-oriented diff habits (`three-dot`, then commit-range diff) were used instead of a true “worktree against verified target base” patch build.

## Resolution

The carrier was regenerated correctly with:

1. tracked changes diffed against `origin/main`
2. new docs added explicitly via `git diff --no-index -- /dev/null <new-file>`
3. `patch --dry-run` executed against a clean `git archive origin/main` export

## Lessons

1. A carrier patch meant for verified `main` must be generated against the actual target base, not the merge base.
2. New docs do not appear in ordinary `git diff <base>` output until tracked; docs-only carriers must include untracked files explicitly or stage them intentionally.
3. A carrier is not “validated” until it survives `patch --dry-run` on a clean export of the exact target branch.
