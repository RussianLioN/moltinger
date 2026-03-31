# Codex Operating Model

Date: 2026-03-08

This document defines the repo-specific operating model for local Codex CLI sessions in `moltinger`.

## Scope

This policy sets the baseline for local Codex usage in this repository.

If the task is about adding, migrating, or reviewing Moltis skills/agents, read [docs/moltis-skill-agent-authoring.md](./moltis-skill-agent-authoring.md) before editing `skills/`, `config/moltis.toml`, workspace prompt files, or migration docs.

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

1. `/Users/rl/coding/moltinger/moltinger-main` is the canonical `main` worktree.
2. Any substantial change should use a dedicated worktree and branch.
3. Preferred worktree path pattern:

```bash
/Users/rl/coding/moltinger/moltinger-<branch-slug>
```

4. `branch-slug` should be the branch name with `/` replaced by `-`.
5. If a branch has a dedicated worktree, edits belong there and not in the canonical `main` directory.
6. Inspect topology state with `status`/`check` during ordinary worktree flows.
7. Publish `docs/GIT-TOPOLOGY-REGISTRY.md` only from the dedicated non-main branch `chore/topology-registry-publish` in its own publish worktree.
8. Do not treat canonical `main` or an ordinary feature branch as the default publish path for topology snapshots.
9. `/tmp` worktrees are acceptable for disposable or emergency lanes, but the preferred long-lived pattern is the sibling path above.
10. If the topology registry disagrees with live `git` state, live `git` state wins.

### Path Relocation Recovery

If main/worktree directories were moved manually and `codex resume` stops showing expected sessions without `--all`, run:

```bash
scripts/codex-session-path-repair.sh --apply --repair-git-worktrees
```

This updates Codex session CWD metadata (`~/.codex/state_5.sqlite` + archived session headers + live rollout session headers under `~/.codex/sessions/**`) and repairs git worktree links for the relocated directories.

## Beads Ownership Policy

1. Managed sibling worktrees in this repo must keep Beads tracker ownership local to the checked-out branch/worktree.
2. `.beads/config.yaml` remains branch-local git state; `.beads/beads.db` or `.beads/dolt/` must resolve to the current worktree, not the canonical root.
3. If tracked `.beads/issues.jsonl` is still present in a branch, treat it as a temporary compatibility/bootstrap artifact rather than the authoritative backlog source. Until the compatibility layer is fully retired, keep its dependency arrays in deterministic canonical order and do not hand-edit reorder-only noise.
4. After the Dolt migration and local-only cleanup, an intentionally missing tracked `.beads/issues.jsonl` does not mean the backlog is gone; the operational source of truth may live only in the local Dolt-backed Beads runtime.
5. Treat `config + local runtime + no tracked .beads/issues.jsonl` as the expected post-migration local-runtime state, not as an unexpected deletion or proof that the backlog is unavailable.
6. When that happens, agents should keep using the local Beads database for read-only task inspection (`bd status`, `bd list`, `bd ready`, `bd show`) and describe any failure as a local Beads repair problem rather than falling back to ad-hoc plan files as the primary backlog.
7. If a preserved sibling worktree still cannot open its local Beads state after JSONL retirement, split the diagnosis: if ownership is already local but the runtime cannot open the named `beads` DB, run read-only diagnostics first (`/usr/local/bin/bd doctor --json`) and then `./scripts/beads-worktree-localize.sh --path <worktree>` so stale runtime artifacts are quarantined before bootstrap/import; if ownership is missing, redirected, or legacy, use the same helper for ownership recovery.
8. A bare `.beads/dolt/` directory is not enough to call the local runtime healthy; if the named `beads` DB is missing, treat that as local runtime repair drift and recover with the managed localization/repair helper rather than restoring `.beads/issues.jsonl`.
9. `.envrc` is a convenience bootstrap only: it should prepend the current worktree `bin/` directory to `PATH`, but dedicated-worktree safety must not depend solely on `direnv`.
10. The normal repo-local command is plain `bd`, provided by `bin/bd`; managed Codex/worktree handoff flows and tracked git hooks must also prepend the current worktree `bin/` directory so the repo-local shim wins even when `direnv` is inactive.
11. In the canonical root, plain `bd` is read-mostly by default: safe inspection commands may pass through, but mutating commands must not auto-discover or silently reuse the root tracker.
12. Intentional canonical-root Beads mutation must be explicit. Use an explicit target such as `bd --db <canonical-root>/.beads/beads.db ...` (or another deliberate troubleshooting path) when root-scoped admin work is truly intended.
13. The normal daily entrypoint is plain `bd` (via `bin/bd`); `./scripts/bd-local.sh` is deprecated and should not be used. If `.beads/redirect` is present, localize that worktree with `scripts/beads-worktree-localize.sh` before resuming plain `bd`.
14. Do not use raw `bd worktree create` in this repository. It installs `.beads/redirect` to the canonical root and can silently route tracker writes into another worktree.
15. If one issue leaked only into the canonical root tracker, recover it from the owner worktree with `scripts/beads-recover-issue.sh --issue <id> --apply` after localizing that worktree.
16. For multi-issue leakage, run `scripts/beads-recovery-batch.sh audit` first, review the generated plan, and only then run `scripts/beads-recovery-batch.sh apply --plan ...`.
17. Ambiguous owner mappings belong in `docs/beads-recovery-ownership.json`; do not guess ownership during automatic recovery.
18. Canonical root cleanup is a separate gated action and must not happen in the same command that performs recovery apply.

### Preferred Branch Prefixes

- `NNN-<spec-slug>` for Speckit-linked implementation work
- `chore/<topic>` for operational publish lanes and controlled maintenance paths
- `codex/<area>-<topic>` for bounded Codex streams
- `docs/<topic>` for docs-only work
- `fix/<topic>` for narrow runtime fixes
- `test/<topic>-YYYYMMDD-HHMM` for disposable probes

## Beads Local Ownership

For Beads in dedicated worktrees, ordinary work should use plain `bd`.

1. The ownership source of truth is the current worktree's local `.beads/` state.
2. The repo-local bootstrap path comes from `.envrc`, the managed worktree/Codex handoff, or tracked git-hook bootstrap, not from asking the user to choose a wrapper.
3. If a dedicated worktree has legacy redirect residue or a partial local foundation, recover it in place with `./scripts/beads-worktree-localize.sh --path <worktree>`.
4. If ownership is already local but the runtime still cannot open the named `beads` DB, classify it as `runtime_bootstrap_required`: run `/usr/local/bin/bd doctor --json`, then `./scripts/beads-worktree-localize.sh --path .`, and do not reintroduce `.beads/issues.jsonl`. The helper must quarantine stale runtime shells and import the newest compatibility backup when one exists.
5. Silent fallback to the canonical root tracker is not an acceptable recovery path.
6. Canonical-root mutating `bd` commands are blocked by default unless the operator supplies an explicit root target on purpose.
7. Residual cleanup in canonical `main` is a separate follow-up and must not be mixed into day-to-day worktree recovery.

### Historical Migration Note

The dedicated Beads Dolt migration helper scripts lived only in the migration branches that introduced the cutover. Ordinary branches created from `main` should use the ordinary plain-`bd` contract unless a branch explicitly ships its own branch-local migration helpers and instructions.

Treat `029-beads-dolt-native-migration` as the historical migration/reference lane for the Beads Dolt cutover. New generic worktree/Beads helper fixes must land in `main` first and only be backported into `029` when the migration/reference branch still needs the same contract update.

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
