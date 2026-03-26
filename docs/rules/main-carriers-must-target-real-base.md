# Rule: Main Carriers Must Target The Real Base

When preparing a carrier patch intended to be applied to the current `main` state:

1. Generate tracked-file changes against the real target base, not the merge base.
   Use the equivalent of `git diff origin/main -- <paths>`, not `git diff origin/main...HEAD -- <paths>`.
2. If the carrier includes newly created files, include them explicitly.
   One safe path is `git diff --no-index -- /dev/null <new-file>`.
3. Validate the carrier with `patch --dry-run` against a clean export of the exact target branch before calling it ready.

Why:

- merge-base diffs describe branch history, not the current target branch surface
- plain diffs omit untracked files
- carrier patches are operational artifacts and must reflect the exact landing base
