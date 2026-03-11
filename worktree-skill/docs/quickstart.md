# Quickstart

## Goal

Install the portable worktree skill into a host project in 5-10 minutes.

## Option 1: Copy Files Manually

1. Copy `core/` into the host project root.
2. Copy one adapter from `adapters/claude-code/`, `adapters/codex-cli/`, or `adapters/opencode/`.
3. Optionally copy `bridge/speckit/` if the host project uses Speckit.
4. Run `install/verify.sh --target <host-project> --adapter <adapter>`.

## Option 2: Bootstrap

```bash
./install/bootstrap.sh --target /path/to/host-project --adapter claude-code
```

Add `--with-speckit` if needed.

## Optional Registration

- Claude Code: usually file placement is enough
- Codex CLI: run `install/register.sh --target <host-project> --adapter codex-cli`
- OpenCode: follow the adapter README and registration example

## Validation

Run:

```bash
./install/verify.sh --target /path/to/host-project --adapter claude-code
```

Expected result:

- core scripts exist
- selected adapter assets exist
- optional Speckit bridge is reported clearly if installed

## Failure Modes

- Missing adapter: install the adapter directory and rerun verification
- Missing registration: run `install/register.sh` if the adapter requires it
- Host path collisions: move conflicting host-only files aside or install into a staging branch first
- Optional issue tracker or topology registry unavailable: core flow still installs, but optional richer behavior remains disabled
