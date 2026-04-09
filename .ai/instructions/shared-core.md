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
scripts/git-topology-registry.sh publish
scripts/git-topology-registry.sh check
scripts/git-topology-registry.sh status
scripts/git-topology-registry.sh refresh --write-doc
```

Use `check` when branch/worktree context matters or before cleanup actions.
`docs/GIT-TOPOLOGY-REGISTRY.md` is the tracked shared remote-governance snapshot; local worktrees and local-only branches remain live-only through `status`/`check`.
Use `publish` as the normal path to dispatch the official topology publish workflow.
Use `refresh --write-doc` only as the low-level manual publication path from the dedicated non-main publish worktree/branch, not from ordinary feature branches.
In Codex/App sessions, `refresh --write-doc` may require approval if the shared repo `.git` directory is outside the current writable boundary.
Rule: `docs/rules/topology-registry-single-writer-publish-path.md`

## Canonical Main Role

The canonical `main` worktree is for review and control-plane hygiene, not feature implementation.

- Use canonical `main` for triage, PR review, topology inspection, merge coordination, and close/cleanup flows.
- Do not implement new tasks directly in canonical `main`.
- If the task changes runtime behavior, CI, deploy, scripts, config, instructions, AGENTS, rules, skills, auth, topology, or any shared contract, create a dedicated branch/worktree from `main` first.
- Read-only inspection and explicit topology or cleanup maintenance may stay in canonical `main`.

## Post-Close Task Classification

If the active branch/worktree has already completed its planned tasks and the user brings a new task, do not continue in the same lane by default.

- First classify the request with `docs/rules/post-close-task-classification-and-worktree-escalation.md`.
- Default heuristic:
  - same root cause + same slice + same owning lane + no scope expansion => current lane may continue
  - otherwise => open a new lane
- If the slice is already logically closed or already merged, and the new task touches `rules`, `AGENTS.md`, `skills`, auth, CI, deploy, runtime, topology, or other shared contracts, you must use a fresh branch/worktree from `main`.
- Narrow fixes inside the same active, unmerged slice that already owns those files may stay in the current lane.
- If the criteria conflict or the risk is ambiguous, use the `consilium` skill/workflow before choosing the lane.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd status             # Inspect the current Beads state
bd bootstrap          # Initialize a local Dolt-backed clone; use localize helper for runtime-only repair
```

## Beads Worktree Ownership

Inside this repository, ordinary dedicated-worktree usage should run plain `bd`.

- The intended ownership model is worktree-local: the source of truth is the current worktree's `.beads/` state, not a shared redirect in canonical `main`.
- Do not treat a missing tracked `.beads/issues.jsonl` as proof that the Beads backlog is unavailable. After the Dolt migration and local-only cleanup, the backlog may live only in the local Dolt-backed Beads runtime.
- If tracked `.beads/issues.jsonl` is still present in a branch, treat it as a temporary compatibility/bootstrap artifact, not as the authoritative backlog source after the Dolt migration.
- Treat `config + local runtime + no tracked .beads/issues.jsonl` as the expected post-migration local-runtime state, not as an unexpected deletion. Continue with local `bd` read-only inspection first.
- Do not treat a bare `.beads/dolt/` directory as proof that the local runtime is healthy. If the named `beads` DB is missing, classify it as local runtime repair drift, run `/usr/local/bin/bd doctor --json` first, then repair with `./scripts/beads-worktree-localize.sh --path .` so the stale shell is quarantined and the newest compatibility backup can be re-imported when available; do not restore `.beads/issues.jsonl`.
- For ordinary read-only task inspection, use the local Beads database first: `bd status`, `bd list --limit <n>`, `bd ready`, `bd show <id>`.
- `bd sync` is retired in this repository. Use `bd status` for local inspection, and use `bd dolt push` / `bd dolt pull` only when this worktree is configured with a Dolt remote.
- If a preserved sibling worktree still reports incomplete local foundation after JSONL retirement, describe it as a local Beads repair problem, not as “bd is unavailable”. If ownership is already local but the runtime cannot open the named `beads` DB, run `/usr/local/bin/bd doctor --json` first and then `./scripts/beads-worktree-localize.sh --path .`. The helper must quarantine any stale runtime shell, rerun bootstrap, and import the newest compatibility backup when one exists.
- If a dedicated worktree reports missing, redirected, or legacy Beads state, use `./scripts/beads-worktree-localize.sh --path .` from that worktree. If ownership is already local but runtime health is broken, stop and repair the runtime instead of re-localizing ownership.
- Do not replace the Beads backlog with ad-hoc plan files just because `.beads/issues.jsonl` is absent; use plans only as supplemental execution context.
- Do not mix residual canonical-root cleanup into ordinary worktree recovery. Root cleanup, if still needed, belongs in a separate follow-up.

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
   If a Dolt remote is configured for the project, run `bd dolt push` before `git push`.
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
