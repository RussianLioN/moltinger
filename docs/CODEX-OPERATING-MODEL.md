# Codex Operating Model

Date: 2026-03-08

This document defines the repo-specific operating model for Codex in `moltinger`.

## Default Model Policy

Use `gpt-5.4` as the default Codex model baseline for this repository.

Different task types should usually vary by sandbox, approval mode, and write scope, not by model family.

## Recommended Profiles

### `molt-research`

- Model: `gpt-5.4`
- Sandbox: `read-only`
- Approval: `never`
- Use for: RCA, docs reading, topology analysis, issue triage, architecture mapping

### `molt-docs`

- Model: `gpt-5.4`
- Sandbox: `workspace-write`
- Approval: `on-request`
- Use for: `docs/`, `knowledge/`, `prompts/`, research, reports, release notes

### `molt-runtime`

- Model: `gpt-5.4`
- Sandbox: `workspace-write`
- Approval: `on-request`
- Use for: `config/`, `docker-compose*.yml`, `systemd/`, `.github/workflows/`, `scripts/`, `Makefile`

### `molt-assets`

- Model: `gpt-5.4`
- Sandbox: `workspace-write`
- Approval: `on-request`
- Use for: `.ai/`, `.claude/`, `skills/`, instruction bridge, sync assets

### `molt-review`

- Model: `gpt-5.4`
- Sandbox: `read-only`
- Approval: `never`
- Use for: `codex review`, diff validation, merge readiness

### `molt-hotfix`

- Model: `gpt-5.4`
- Sandbox: `workspace-write`
- Approval: `on-request`
- Use for: bounded incident and hotfix work in a dedicated branch

## Worktree Naming Policy

1. `/Users/rl/coding/moltinger` remains the canonical `main` worktree.
2. Any substantial change should use a dedicated worktree and branch.
3. Preferred worktree path pattern:

```bash
/Users/rl/coding/moltinger-<branch-slug>
```

4. `branch-slug` should be the branch name with `/` replaced by `-`.
5. If a branch has a dedicated worktree, edits belong there and not in the canonical `main` directory.
6. Update `docs/GIT-TOPOLOGY-REGISTRY.md` when worktree topology changes.

### Preferred Branch Prefixes

- `NNN-<spec-slug>` for Speckit-linked implementation work
- `codex/<area>-<topic>` for bounded Codex streams
- `docs/<topic>` for docs-only work
- `fix/<topic>` for narrow runtime fixes
- `test/<topic>-YYYYMMDD-HHMM` for disposable probes

## Local Instruction Split

Use the nearest local `AGENTS.md` for directory-specific rules.

### Current Local Instruction Zones

- `.ai/`
- `.claude/`
- `config/`
- `.github/`
- `scripts/`
- `specs/`
- `tests/`
- `docs/`
- `knowledge/`

## Operational Defaults

1. Start investigative work in a read-only profile.
2. Move runtime changes into a dedicated worktree before editing.
3. Keep `main` clean.
4. Use `codex review` as a separate final pass for risky changes.
5. Treat `config/`, `.github/`, `scripts/`, and deploy-related artifacts as production-adjacent.
6. Prefer small, reversible change sets.
