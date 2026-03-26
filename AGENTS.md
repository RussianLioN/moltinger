# Agent Instructions

> GENERATED FILE. DO NOT EDIT DIRECTLY.
> Source: `.ai/instructions/shared-core.md` + `.ai/instructions/codex-adapter.md`
> Regenerate with: `./scripts/sync-agent-instructions.sh --write`

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Communication Language (Mandatory)

- If the user writes in Russian or explicitly asks for Russian-only communication, respond only in Russian unless the user later asks to switch languages.
- Do not alternate between Russian and English in user-facing replies unless the user explicitly requests bilingual output or translation.

## Git Topology Reference

Current branch/worktree registry lives in:

```bash
docs/GIT-TOPOLOGY-REGISTRY.md
```

It is generated from live git topology plus reviewed intent sidecar.

```bash
scripts/git-topology-registry.sh check
scripts/git-topology-registry.sh refresh --write-doc
scripts/git-topology-registry.sh status
```

Use `check` when branch/worktree context matters or before cleanup actions.
Use `refresh --write-doc` only for explicit topology snapshot publication from a dedicated non-main publish worktree/branch, not from ordinary feature branches.
In Codex/App sessions, `refresh --write-doc` may require approval if the shared repo `.git` directory is outside the current writable boundary.
Rule: `docs/rules/topology-registry-single-writer-publish-path.md`

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd status             # Inspect the current Beads state
bd bootstrap          # Initialize or repair a local Dolt-backed clone safely
```

If the current worktree is in a Beads migration mode:
- `.beads/pilot-mode.json` means use `./scripts/beads-dolt-pilot.sh review` as the documented pilot review surface
- `.beads/cutover-mode.json` means use `./scripts/beads-dolt-rollout.sh verify --worktree .` as the documented cutover verification surface
- if no migration mode is active, the ordinary review path is `bd status` plus the narrowest read-only `bd` command you actually need

## Beads Worktree Ownership

Inside this repository, ordinary dedicated-worktree usage should run plain `bd`.

- The intended ownership model is worktree-local: the source of truth is the current worktree's `.beads/` state, not a shared redirect in canonical `main`.
- Do not treat a missing tracked `.beads/issues.jsonl` as proof that the Beads backlog is unavailable. After the Dolt migration and local-only cleanup, the backlog may live only in the local Dolt-backed Beads runtime.
- Treat `config + local runtime + no tracked .beads/issues.jsonl` as the expected post-migration local-runtime state, not as an unexpected deletion. Continue with local `bd` read-only inspection first.
- Do not treat a bare `.beads/dolt/` directory as proof that the local runtime is healthy. If the named `beads` DB is missing, classify it as local runtime repair drift and recover with `/usr/local/bin/bd doctor --json` followed by `bd bootstrap`; do not restore `.beads/issues.jsonl`.
- For ordinary read-only task inspection, use the local Beads database first: `bd status`, `bd list --limit <n>`, `bd ready`, `bd show <id>`.
- `bd sync` is retired in this repository. Use `bd status` for local inspection, and use `bd dolt push` / `bd dolt pull` only when this worktree is configured with a Dolt remote.
- If a preserved sibling worktree still reports incomplete local foundation after JSONL retirement, describe it as a local Beads repair problem, not as “bd is unavailable”. First run read-only diagnostics such as `/usr/local/bin/bd doctor --json`, then repair the local foundation with `./scripts/beads-worktree-localize.sh --path .` or `bd bootstrap` as appropriate.
- If a dedicated worktree reports missing or legacy Beads state, use `./scripts/beads-worktree-localize.sh --path .` from that worktree.
- Do not replace the Beads backlog with ad-hoc plan files just because `.beads/issues.jsonl` is absent; use plans only as supplemental execution context.
- Do not mix residual canonical-root cleanup into ordinary worktree recovery. Root cleanup, if still needed, belongs in a separate follow-up.

## Beads Migration Modes

When a dedicated worktree enters the Beads Dolt-native migration flow:

- `.beads/pilot-mode.json` enables the isolated pilot contract for one worktree
- `.beads/cutover-mode.json` enables the staged cutover contract for an already-ready worktree
- in either mode, treat legacy JSONL-first paths and the old sync-style workflow as blocked unless the active migration script explicitly says otherwise
- use `./scripts/beads-dolt-pilot.sh review` for pilot review
- use `./scripts/beads-dolt-rollout.sh verify --worktree .` for cutover verification

## Speckit Artifact Guard

If work is driven by a Speckit package (`specs/<feature>/`):

1. Before changing runtime code, reconcile spec artifacts:
   - `git status --short specs/<feature>/`
   - ensure `spec.md`, `plan.md`, and `tasks.md` are tracked and present in the branch
2. Update `specs/<feature>/tasks.md` checkboxes as tasks are completed.
3. Before push, verify implementation and spec artifacts are synchronized (no hidden untracked Speckit files).

## Context-First Rule (Mandatory)

Before asking the user for environment variables, secrets, paths, or deployment values, check local project context first:

1. `MEMORY.md`
2. `SESSION_SUMMARY.md`
3. `docs/SECRETS-MANAGEMENT.md`
4. `.github/workflows/deploy.yml` (`Generate .env from Secrets` step)

For this project specifically:
- Canonical source of secret values is **GitHub Secrets**
- Runtime copy on server is `/opt/moltinger/.env` (generated by CI/CD)

Ask the user only if required data is still missing or contradictory after these checks.

## Official-Only Setup Rule (Critical)

For any application, library, dependency, package, service, runtime integration, or provider setup:

- Follow the **official installation and configuration instructions first** from the official website, official documentation, or official GitHub repository.
- Treat the official source as the canonical path for install, upgrade, configuration, authentication bootstrap, migration, and runtime integration.
- Do **not** invent steps, infer setup flows, or substitute community recipes for the primary setup path when an official instruction exists.
- Use community posts, issues, forums, and discussions only as secondary evidence for troubleshooting gaps, known bugs, or operational caveats after the official path has been checked.
- If the official documentation is missing, contradictory, outdated, or provably broken, explicitly say so, cite the official source that was followed, and clearly mark any deviation from the official path as a justified exception.

## Runtime Target Rule (Mandatory)

Before launching local containers, local port-forwards, or a local app replica, verify whether the authoritative target for the task is a documented remote service or a local fixture stack.

- If the task targets a remote service, do not spin up a local replacement unless the user explicitly asked for local reproduction.
- If the task targets a local fixture stack, say so and use the hermetic local runtime intentionally.

### Test Target Policy (Mandatory)

Allowed:
- PR/main CI may use only hermetic blocking lanes and local fixture stacks.
- Remote smoke/UAT may be used only to answer whether the remote service works now.
- Hermetic fixtures may be used to answer whether a branch, refactor, or test contract is correct.
- Resilience or destructive checks may run only against an isolated remote target.

Forbidden:
- Do not treat hermetic local results as proof that the shared remote service works now.
- Do not treat remote smoke/UAT as the primary proof that a branch or refactor is correct.
- Do not run resilience or destructive checks against shared production.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd status
   git push
   git status  # MUST show "up to date with origin"
   ```
   If pilot mode is active, replace `bd status` with `./scripts/beads-dolt-pilot.sh review`.
   If cutover mode is active, replace `bd status` with `./scripts/beads-dolt-rollout.sh verify --worktree .`.
   If a Dolt remote is configured for the project, run `bd dolt push` before `git push`.
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## Codex Adapter

This file is Codex-specific and is merged into `AGENTS.md` by:

```bash
./scripts/sync-agent-instructions.sh --write
```

## Codex Operating Model

Repo-specific Codex profiles, worktree naming, and local instruction split are documented in:

```bash
docs/CODEX-OPERATING-MODEL.md
```

## Playwright MCP Index

When the task involves browser automation, UI inspection, screenshots, or the user explicitly mentions Playwright/MCP browser tools:

1. first read:

```bash
docs/rules/playwright-mcp-usage.md
```

2. then use the `playwright` skill as the workflow reference
3. do not repeatedly retry `mcp__playwright__browser_navigate` after persistent-context or stale-session launch failures; follow the rule above and stop after one cleanup attempt

When working inside scoped directories such as `config/`, `.github/`, `scripts/`, `specs/`, `tests/`, `docs/`, `.ai/`, `.claude/`, `knowledge/`, `.beads/`, or `.specify/`, follow the nearest local `AGENTS.md` in addition to the root file.

## Codex Governance Check

If you change Codex operating-model docs, source instructions, local `AGENTS.md` files, the skill bridge, or Codex launcher/check scripts, run:

```bash
make codex-check
```

## Claude Skill Bridge

Claude project skills are stored in:

```bash
.claude/skills/
```

Install or update them into Codex global skills:

```bash
./scripts/sync-claude-skills-to-codex.sh --install
```

Verify the bridge is up to date:

```bash
./scripts/sync-claude-skills-to-codex.sh --check
```

After installing or updating skills, restart Codex to refresh skill discovery.

## Scope Notes

- `.claude/skills/*` are imported as native Codex skills.
- `.claude/commands/*` are migrated into generated bridge skills under `$CODEX_HOME/skills/claude-bridge/commands/*`.
- `.claude/agents/*` are migrated into generated bridge skills under `$CODEX_HOME/skills/claude-bridge/agents/*`.
- When both a command and a skill describe the same workflow, prefer the skill.
- In Codex CLI, bridged Claude commands are usually invoked via `command-*` skills, not native slash commands.
- Example: use `command-worktree` and `command-session-summary` in Codex; do not assume `/worktree` or `/session-summary` are registered as CLI slash commands.
- If the user refers to the "worktree skill" in plain language, map that intent to `command-worktree`.
- Before resetting or fast-forwarding a UAT worktree, preserve any newer `docs/GIT-TOPOLOGY-REGISTRY.md` snapshot into the owning branch first; see `docs/rules/uat-registry-snapshot-preservation.md`.
