# GitHub Actions: no indented heredocs for complex remote shell

## Rule

Do not embed complex remote shell fragments directly inside `.github/workflows/*.yml` as indented heredocs, especially inside:

- command substitution
- nested `if` blocks
- SSH calls used by deploy or rollback paths

## Required pattern

If a workflow step needs more than a few shell commands, move the logic into a versioned script under `scripts/` and call that script from the workflow.

## Why

Indented heredocs inside YAML-backed shell blocks are brittle and easy to break at parse time. In a production deploy workflow this can block the entire pipeline before backup, deploy, or rollback logic even starts.

## Minimum validation

After introducing or changing deploy-adjacent shell logic:

1. Run `bash -n` on the extracted script.
2. Add or update a targeted static test for the workflow contract.
3. Avoid keeping the remote repair body inline in the workflow.
