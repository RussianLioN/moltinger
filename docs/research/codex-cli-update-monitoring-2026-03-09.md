# Codex CLI Update Monitoring Research

Date: 2026-03-09
Issue: `molt-1`
Branch Context: `uat/006-git-topology-registry`

This note captures the current Codex CLI state, recent upstream capabilities, and the recommended shape for a future repository workflow that monitors Codex CLI updates and turns them into actionable upgrade guidance.

## Verified Current State

- Local installed version: `codex-cli 0.112.0`
- Latest official changelog entry checked on 2026-03-09: `0.112.0` dated 2026-03-08
- Local user config already has:
  - `check_for_update_on_startup = true`
  - `multi_agent = true`
  - `js_repl = true`
  - `prevent_idle_sleep = true`
  - `service_tier = "fast"`
- Repository-local operating model already standardizes:
  - `gpt-5.4` as the default Codex baseline
  - profile launchers via `scripts/codex-profile-launch.sh`
  - generated `AGENTS.md` plus local `AGENTS.md` boundaries

Conclusion: the local CLI is current, but the repo has no durable workflow that answers the harder questions:

1. Which new Codex CLI changes are relevant to this repository?
2. Which of them justify an upgrade or workflow change now?
3. How should follow-up work be tracked?

## Recent Upstream Changes That Matter

### `0.112.0` (2026-03-08)

Official changelog highlights:

- experimental approval profiles
- broader web-search source coverage
- `@plugin` mentions from the prompt
- improved model-selection flow when the CLI launches without a fixed model

Assessment for this repo:

- `@plugin` mentions are low immediate value because the repo currently leans on bridged skills plus configured MCP servers, not a plugin-first workflow.
- approval-profile work is medium value because this repo relies on strict write-scope and approval boundaries across docs, runtime, and assets lanes.
- expanded web search is low-to-medium value because repository workflows already rely heavily on local context first and web only when needed.

### `0.111.0` (2026-03-06)

Official changelog highlights:

- local images in plan mode
- child worktree creation from `/new`
- local dynamic imports in `js_repl`
- plugin discovery at session start
- `codex resume` preserving git context and apps
- persisted `/fast` mode
- warnings when search-generated patches are filtered by `.gitignore`

Assessment for this repo:

- child worktree creation is high value because this repository already treats dedicated worktrees as the normal lane for substantial change.
- `js_repl` local imports are medium-to-high value because the repo already documents `js_repl` use and has Playwright-heavy and script-heavy workflows.
- preserved git context on resume is medium value for long-running sessions and handoffs.
- `.gitignore` patch warnings are medium value for this repo because generated and ignored operational files are common.

### `0.110.0` (2026-03-03)

Official changelog highlights:

- plugin system
- improved multi-agent task splitting
- session notifications when waiting for approval at launch
- project docs updates no longer require a restart

Assessment for this repo:

- improved multi-agent support is high value because research, review, and implementation here regularly benefit from parallel delegated work.
- no-restart project-doc refresh is high value because this repo intentionally evolves `AGENTS.md`, local instruction zones, and Codex governance docs.
- plugin system is medium value only if the team wants a universal cross-repo package; it is not the best first delivery for this repo.

## Capabilities Already Present In `0.112.0` That Enable A Monitor

These are not merely release-note items; they are the stable building blocks for a real monitoring workflow:

- `codex exec --json` for machine-readable event streams
- `codex exec --output-schema <file>` for structured final output
- `codex exec -o <file>` for durable final-message capture
- `codex exec resume` for two-stage workflows
- `codex --profile <name>` and config profiles for repeatable execution lanes
- `AGENTS.md` plus local instruction zones for repository-specific behavior
- skills with optional `scripts/`, `resources/`, and `agents/openai.yaml`

These features make it practical to build a deterministic collector and a thin Codex wrapper without depending on a long-running autonomous agent.

## What Is Actually Useful For Moltinger

### High Value

1. Non-interactive structured runs via `codex exec --json` and `--output-schema`
   - Best basis for a scheduled or on-demand update monitor.
   - Allows the monitor to emit a stable JSON contract that can be checked into CI artifacts or fed into Beads follow-up logic.

2. Multi-agent improvements
   - Useful when a follow-up analysis needs separate lanes for release-note parsing, repo-impact mapping, and issue triage.
   - This is already compatible with the current local config, which has `multi_agent = true`.

3. Worktree-aware flows and resume behavior
   - Direct fit for a repository that already enforces dedicated worktrees and topology checks.
   - Relevant both for monitor runs that propose a new worktree and for follow-up implementation sessions.

4. Hot-reload style behavior for project docs
   - Important in a repo where `AGENTS.md`, `docs/CODEX-OPERATING-MODEL.md`, and bridged skills are active workflow surfaces.

### Medium Value

1. Approval-profile improvements
   - Relevant for safer skill and script orchestration, especially if a future monitor triggers optional issue creation or file writes.

2. `js_repl` local imports
   - Helpful if the monitor later grows a richer analysis layer or needs to reuse local JavaScript helpers.

3. Plugin system
   - Useful only if the team wants distribution across multiple repositories with minimal setup.
   - Not the shortest path to value inside this repository.

### Low Value For Now

1. TUI model-selection polish
2. Additional web-search source coverage
3. Prompt-level `@plugin` mentions without an adopted plugin package

These are nice-to-have improvements, not primary drivers for new repo automation.

## Skill Or Agent?

### Recommended: Script-First Hybrid

Recommended v1 shape:

1. deterministic script collects facts
2. thin skill or command wrapper interprets them
3. optional non-interactive Codex run produces a recommendation summary
4. explicit flag creates or updates a backlog item

Why this fits the repository:

- It matches existing repo patterns such as `scripts/health-monitor.sh` and `scripts/telegram-webhook-monitor.sh`.
- It matches the existing Speckit precedent in `specs/006-git-topology-registry/`, which deliberately chose script-first over agent-first.
- It is easier to test, cache, diff, and run from CI than a long-running agent.

### Not Recommended For V1: Long-Running Update Agent

Reasons:

- too opaque as a source of truth
- harder to reproduce and review
- unnecessary when upstream facts are discrete and document-based
- likely to duplicate logic that belongs in a collector script and a recommendation rubric

### Best Universal Packaging Candidate

If this needs to work across multiple repos, the best order is:

1. repository-local collector script and report contract
2. reusable skill wrapping that contract
3. optional plugin packaging only if cross-repo adoption becomes real

This keeps the first delivery simple and reversible while leaving room for broader reuse later.

## Proposed Architecture For Future Work

### Collector

Candidate path:

```bash
scripts/codex-cli-update-monitor.sh
```

Responsibilities:

- detect local installed `codex` version
- detect local enabled features and important config toggles
- compare against latest official Codex changelog entries
- optionally inspect selected upstream issue feeds
- emit JSON with status, evidence, and recommendation fields

### Report Layer

Candidate shapes:

- `docs/reports/codex-cli-update-report-YYYY-MM-DD.md`
- `codex exec --output-schema` result for machine use
- optional Beads issue payload when recommendation crosses a threshold

### Reusable UX Layer

Candidate shapes:

- repo skill: `.claude/skills/codex-update-monitor/`
- Codex bridge exposure via `./scripts/sync-claude-skills-to-codex.sh --install`
- optional future plugin only after the local skill proves useful

### Optional Issue Triage Extension

A second phase can monitor:

- OpenAI Codex CLI issues
- known regressions affecting worktrees, approvals, MCP, or non-interactive runs
- repo-local gaps between new features and current operating model docs

This extension should remain opt-in and should not block the base monitor.

## Reusable Repo Patterns

Most relevant local precedents:

- `scripts/health-monitor.sh`
- `scripts/telegram-webhook-monitor.sh`
- `.claude/skills/lessons/SKILL.md`
- `specs/006-git-topology-registry/research.md`
- `specs/006-git-topology-registry/plan.md`
- `docs/plans/codex-rollout-rollback.md`

Common pattern across them:

```text
deterministic script -> thin orchestration layer -> durable report/runbook/spec artifact -> optional follow-up issue
```

That is the most defensible shape for Codex CLI update monitoring in this repository.

## Recommendation

Proceed with a future Speckit feature that targets:

- on-demand and CI-safe Codex CLI update monitoring
- structured JSON output
- repo-specific recommendation logic
- optional issue creation
- skill-first reuse, not agent-first autonomy

Do not start with:

- automatic self-upgrade
- a daemon
- a plugin-only delivery
- automatic rewrites of repo instructions

## Official Sources

- Codex changelog: <https://developers.openai.com/codex/changelog>
- Codex CLI: <https://developers.openai.com/codex/cli>
- Non-interactive execution: <https://developers.openai.com/codex/cli/noninteractive>
- Agent approval modes: <https://developers.openai.com/codex/cli/agent-approval-modes>
- Config reference: <https://developers.openai.com/codex/cli/config>
- AGENTS.md guide: <https://developers.openai.com/codex/cli/agents-md>
- Skills guide: <https://developers.openai.com/codex/cli/skills>
