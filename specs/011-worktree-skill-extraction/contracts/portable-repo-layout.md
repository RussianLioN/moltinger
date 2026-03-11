# Contract: Portable Repository Layout

## Purpose

Define the minimum required structure for the standalone repository `worktree-skill`.

## Required Directories

- `core/`
- `adapters/claude-code/`
- `adapters/codex-cli/`
- `adapters/opencode/`
- `bridge/speckit/`
- `install/`
- `examples/greenfield/`
- `examples/existing-project/`
- `docs/`
- `tests/`

## Required Core Artifacts

- Worktree workflow instructions or command prompts
- Handoff and session-summary templates that are portable
- Topology or worktree helper scripts
- Generic config example or defaults file
- Quickstart and verification documentation

## Boundary Rules

- `core/` must not require any adapter to function at baseline level.
- Adapters may add registration or discovery behavior, but may not change core semantics.
- `bridge/speckit/` may document coexistence or provide templates, but may not override Speckit commands.
- Host-project governance, secrets, deploy configs, and product runtime artifacts are outside this contract.

## Portable Repo Ready Signals

- Required directories exist.
- Every required directory has at least one documented artifact or explicit placeholder for first release.
- Core and adapters are separately copyable.
- Docs explain which directories are required and which are optional.
