# Scripts Instructions

This directory contains operational automation. Changes here can affect deploys, CI, backups, Telegram flows, and GitOps checks.

## Scope

Key areas:
- deploy and backup automation
- GitOps guard scripts
- CI helper scripts
- Telegram automation
- lessons and RCA helpers
- rate monitoring and health monitoring

## Rules

1. Keep scripts deterministic and composable.
   Prefer small, single-purpose scripts over one-off wrappers.
2. Do not add manual-production-bypass scripts.
   No local-to-production shortcuts that violate GitOps rules.
3. Preserve shell safety.
   Use strict shell modes where appropriate:
   `set -euo pipefail`
4. Preserve compatibility with callers.
   Before changing a script, check whether it is referenced by:
   - `Makefile`
   - `.github/workflows/`
   - tests
   - docs
   - hooks
   - skills or command docs
5. Do not silently change output contracts.
   If a script is used by CI or another script, keep stdout, stderr, and exit-code behavior intentional.
6. Prefer updating the source of truth rather than layering hacks.
   If a script workaround exists because another file is stale, fix the stale source too.

## Validation

After changes, run the narrowest relevant checks:

- `bash -n <script>`
- direct script help or dry-run if available
- targeted tests from `tests/`
- any consuming workflow or Make target that depends on the script

If you change a script used by CI, mention that explicitly in your handoff.

## Special Cases

- `scripts/manifest.json` is treated as an integrity artifact for script inventory. Keep it in sync when script lifecycle rules require it.
- Telegram scripts and deploy scripts are higher risk than reporting helpers. Treat them accordingly.
