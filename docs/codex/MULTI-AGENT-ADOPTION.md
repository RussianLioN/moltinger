# Codex Multi-Agent Adoption Guide

Last verified: 2026-03-07

## What Codex Supports Today

1. Codex has experimental multi-agent support in CLI (`/experimental`, `/agent`).
2. Multi-agent config is available via `features.multi_agent` and `[agents]` settings.
3. In multi-agent mode, each agent runs in isolation with separate context.
4. Codex App supports parallel threads and worktree-based branching workflows.
5. Multi-agent visibility in App/IDE is not fully surfaced yet; use CLI for strict sub-agent orchestration.

## Practical Pattern

### Pattern A: Strict Isolated Experts (CLI)

Use for `consilium` and other high-signal orchestration tasks.

1. Enable multi-agent in `~/.codex/config.toml`.
2. Configure `[agents]` limits.
3. Run from CLI and orchestrate via `/agent`.
4. Keep one expert per isolated agent thread.

Example config fragment:

```toml
[features]
multi_agent = true

[agents]
max_threads = 20
max_depth = 3
job_max_runtime_seconds = 900
```

### Pattern B: Parallel Threads + Worktrees (App)

Use when working in Codex App.

1. Create one thread per role or workstream.
2. Create one worktree per thread.
3. Keep each thread focused on its role.
4. Aggregate outcomes in a lead thread.

### Pattern C: Single-Session Expert Matrix

Use only as fallback when A and B are unavailable.

## Skills That Benefit Most

1. `consilium`: strict expert panel, consensus building, architecture decisions.
2. `command-speckit-implement`: independent task groups (`[P]`) can run in parallel roles.
3. `health-bugs` / `security-health-inline`: split scan, fix, and verification across threads.
4. `deps-health-inline` / `reuse-health-inline`: parallelize detection and remediation tracks.
5. `process-issues` / `process-logs`: triage and classification in dedicated threads.

## Guardrails

1. Never claim isolated execution unless Mode A or B is actually used.
2. Always report missing/timed-out experts explicitly.
3. Keep a single lead thread responsible for final synthesis.
4. Use worktrees to prevent branch/state collisions.
