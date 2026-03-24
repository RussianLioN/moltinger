# Rule: Production Branch Block Means Promote, Not Replay

## Purpose

When a production workflow blocks on branch/ref policy, that block is the decision.
It must not be interpreted as permission to manually replay the same deploy steps over `ssh`, `scp`, or repo scripts.

## Required Behavior

If production deploy is blocked because the ref is not `main` or an approved release tag:

1. Stop the production path immediately.
2. Use `.github/workflows/feature-diagnostics.yml` if you need read-only evidence from the live target.
3. Promote the change through git review into `main`.
4. Run the canonical production deploy workflow from the sanctioned ref.

## Forbidden Behavior

- Do not reproduce production deploy steps manually from a feature branch.
- Do not `scp` tracked files to production as a substitute for CI.
- Do not run remote checkout/sync/deploy scripts by hand after the workflow has already refused the ref.
- Do not treat dry-run evidence as permission to mutate the host.

## Rationale

Branch guards are part of the fail-closed GitOps contract. Replaying the same steps manually reintroduces the exact drift and audit-gap failure mode that the guard is intended to prevent.
