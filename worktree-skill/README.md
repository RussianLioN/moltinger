# worktree-skill

Portable worktree workflow assets extracted from a host project into a standalone repository shape.

## What This Repository Contains

- `core/`: portable prompts, helper scripts, templates, and defaults
- `adapters/`: IDE-specific install and discovery surfaces
- `bridge/speckit/`: optional Speckit coexistence guidance
- `install/`: bootstrap, register, and verify scripts
- `examples/`: greenfield and existing-project adoption examples
- `docs/`: quickstart, compatibility, migration, and release policy

## Install Models

- `copy-only`: copy `core/` and one adapter into a host project
- `copy-bootstrap`: run `install/bootstrap.sh` to materialize the same layout
- `copy-register`: install files, then run adapter-specific registration

## First-Release Scope

This repository prototype is intentionally conservative:

- portable core behavior is the priority
- IDE differences stay in `adapters/`
- Speckit remains optional and adjacent
- host-project governance, runtime config, secrets, and deploy logic stay outside

## Start Here

- Read [docs/quickstart.md](./docs/quickstart.md)
- Pick an adapter in `adapters/`
- If you use Speckit, read `bridge/speckit/README.md`
- Run `install/bootstrap.sh` or copy files manually
- Run `install/verify.sh`
