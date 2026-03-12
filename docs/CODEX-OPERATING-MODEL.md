# Codex Operating Model

Date: 2026-03-08

This document defines the repo-specific operating model for local Codex CLI sessions in `moltinger`.

## Scope

This policy sets the baseline for local Codex usage in this repository.

It does not change:

- the active Moltis runtime provider stack in `config/moltis.toml`
- any GitHub Actions or other automation that currently use different AI/model defaults

If those stacks migrate later, do that as a separate tracked change set.

## Default Model Policy

Use `gpt-5.4` as the default local Codex model baseline for this repository.

Different task types should usually vary by sandbox, approval mode, and write scope, not by model family.

## Instruction Precedence

1. Root generated `AGENTS.md`
2. Nearest local `AGENTS.md`
3. Referenced durable docs such as this file, `docs/GIT-TOPOLOGY-REGISTRY.md`, `MEMORY.md`, and `SESSION_SUMMARY.md`
4. Supporting scripts, skills, hooks, and command docs

If a scoped local instruction conflicts with a general repository rule, prefer the more specific scope unless the root file marks the rule as a cross-cutting guard.

## Recommended Profiles

Launchers for these profiles are available via:

```bash
make codex-research
make codex-docs
make codex-runtime
make codex-assets
make codex-review
make codex-hotfix
```

Override defaults when needed with `CODEX_MODEL=...` and `CODEX_BASE_BRANCH=...`.

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
- Use for: `.ai/`, `.claude/skills/`, `.claude/commands/`, `.claude/agents/`, instruction bridge, sync assets
- High-risk subareas: `.claude/hooks/`, `.claude/scripts/`, `.claude/settings*.json` should be treated like operational code and explicitly reviewed

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
7. `/tmp` worktrees are acceptable for disposable or emergency lanes, but the preferred long-lived pattern is the sibling path above.
8. If the topology registry disagrees with live `git` state, live `git` state wins.

## Beads Ownership Policy

1. Managed sibling worktrees in this repo must keep Beads tracker ownership local to the checked-out branch/worktree.
2. `.beads/issues.jsonl` and `.beads/config.yaml` are branch-local git state; `.beads/beads.db` must resolve to the current worktree, not the canonical root.
3. `.envrc` is a convenience bootstrap only: it should prepend the current worktree `bin/` directory to `PATH`, but dedicated-worktree safety must not depend solely on `direnv`.
4. The normal repo-local command is plain `bd`, provided by `bin/bd`; managed Codex/worktree handoff flows and tracked git hooks must also prepend the current worktree `bin/` directory so the repo-local shim wins even when `direnv` is inactive.
5. `./scripts/bd-local.sh` remains a compatibility/troubleshooting helper, not the normal daily entrypoint; if `.beads/redirect` is present, localize that worktree before resuming plain `bd`.
6. Do not use raw `bd worktree create` in this repository. It installs `.beads/redirect` to the canonical root and can silently route tracker writes into another worktree.
7. If one issue leaked only into the canonical root tracker, recover it from the owner worktree with `scripts/beads-recover-issue.sh --issue <id> --apply` after localizing that worktree.
8. For multi-issue leakage, run `scripts/beads-recovery-batch.sh audit` first, review the generated plan, and only then run `scripts/beads-recovery-batch.sh apply --plan ...`.
9. Ambiguous owner mappings belong in `docs/beads-recovery-ownership.json`; do not guess ownership during automatic recovery.
10. Canonical root cleanup is a separate gated action and must not happen in the same command that performs recovery apply.

### Preferred Branch Prefixes

- `NNN-<spec-slug>` for Speckit-linked implementation work
- `codex/<area>-<topic>` for bounded Codex streams
- `docs/<topic>` for docs-only work
- `fix/<topic>` for narrow runtime fixes
- `test/<topic>-YYYYMMDD-HHMM` for disposable probes

## Beads Local Ownership

For Beads in dedicated worktrees, ordinary work should use plain `bd`.

1. The ownership source of truth is the current worktree's local `.beads/` state.
2. The repo-local bootstrap path comes from `.envrc`, the managed worktree/Codex handoff, or tracked git-hook bootstrap, not from asking the user to choose a wrapper.
3. If a dedicated worktree has legacy redirect residue or a partial local foundation, recover it in place with `./scripts/beads-worktree-localize.sh --path <worktree>`.
4. Silent fallback to the canonical root tracker is not an acceptable recovery path.
5. Residual cleanup in canonical `main` is a separate follow-up and must not be mixed into day-to-day worktree recovery.

## Local Instruction Split

Use the nearest local `AGENTS.md` for directory-specific rules.

### Current Local Instruction Zones

- `.ai/`
- `.claude/`
- `.beads/`
- `.specify/`
- `config/`
- `.github/`
- `scripts/`
- `specs/`
- `tests/`
- `docs/`
- `knowledge/`

## When To Use What

### Config Or Runtime Change

1. Start with `make codex-research`.
2. Re-read `MEMORY.md`, `SESSION_SUMMARY.md`, and the relevant local `AGENTS.md`.
3. Move the change into a dedicated worktree.
4. Continue with `make codex-runtime`.
5. Validate the narrowest relevant runtime checks, then run `make codex-check` if Codex governance files also changed.

### Workflow Or Automation Change

1. Inspect the related files in `.github/`, `scripts/`, and `Makefile` together.
2. Use `make codex-runtime`.
3. Keep workflow, script, and documentation contracts aligned.
4. Finish with `make codex-check` plus any targeted workflow/script validation.

### Command-Worktree Follow-Up Fix

If `command-worktree` is already merged but a real session still exposes a bug:

1. Reproduce it once and capture the exact prompt plus output.
2. Open a follow-up issue.
3. Create a fresh fix branch from `main`.
4. Add a regression test before changing behavior.
5. Use the narrowest fix possible.
6. Follow `docs/WORKTREE-HOTFIX-PLAYBOOK.md`.

### GitHub Auth Or Push Failure

1. Record whether the failure happened inside the sandbox or outside it.
2. Do not treat sandbox-only auth failures as proof that host credentials are broken.
3. Re-run `ssh -T git@github.com`, `gh auth status`, and the relevant `git` transport command outside the sandbox before concluding root cause.
4. Follow `docs/rules/codex-github-auth-debugging.md`.

### Spec-Driven Feature Work

1. Reconcile `specs/<feature>/spec.md`, `plan.md`, and `tasks.md` before runtime edits.
2. Use a dedicated worktree and the profile that matches the actual write scope.
3. Update task checkboxes as implementation lands.
4. Before push, verify there are no hidden untracked Speckit artifacts.

### Docs, Reports, And Knowledge Work

1. Use `make codex-docs`.
2. Keep substantial content in dedicated files instead of bloating central docs.
3. Put RCA, reports, plans, and durable knowledge in the correct directory.
4. Run `make codex-check` when instruction docs or Codex governance artifacts changed.

## Operational Defaults

1. Start investigative work in a read-only profile.
2. Move runtime changes into a dedicated worktree before editing.
3. Keep `main` clean.
4. Use `codex review` as a separate final pass for risky changes.
5. Treat `config/`, `.github/`, `scripts/`, deploy-related artifacts, and `.claude/hooks/`, `.claude/scripts/`, `.claude/settings*.json` as production-adjacent.
6. Prefer small, reversible change sets.
7. Run `make codex-check` before landing the plane when Codex governance artifacts changed.
8. For GitHub auth incidents from Codex, compare sandbox and non-sandbox diagnostics before concluding user credentials are broken.
