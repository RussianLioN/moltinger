# Cline Kanban + Worktree Workflow

**Status**: Operator runbook
**Scope**: how to use durable worktrees together with Cline Kanban in `moltinger`

## Purpose

This runbook explains how to combine:

- the repository's durable worktree model
- Cline Kanban task management
- bounded parallel subtask execution

Use this workflow when you want Cline Kanban without losing the repository's current branch, worktree, topology, and Beads contracts.

## Core Model

Treat the system as two layers:

- **Durable lane**
  - authoritative branch
  - authoritative worktree
  - repo-native create, attach, finish, cleanup rules
- **Kanban task lane**
  - short-lived execution task
  - created from the main project workspace
  - attached to an owning branch through `--base-ref`
  - stored in `~/.cline/worktrees/<taskId>/moltinger-main`

Kanban does not replace the durable lane.
Kanban runs bounded work on top of it.

## Preconditions

Before using this flow, confirm:

1. The canonical main workspace exists at `/Users/rl/coding/moltinger/moltinger-main`.
2. The current task is classified correctly under the post-close rule.
3. If the work touches topology publish, shared contracts, Beads runtime repair, auth, CI, deploy, or other governance-sensitive files, start from a fresh durable lane unless the active lane already owns that slice.

## Workflow A: Start A New Durable Lane

1. Classify the new request.
   Use the post-close rule before deciding whether to reuse the current lane.

2. Start the durable lane through the repo-native path.
   Today this means the current repo-native `command-worktree` flow or the shell backend directly.
   Preferred future UX is a Cline workflow that calls the same backend.

3. Land in the new authoritative worktree.
   This lane owns the branch and the worktree directory.

4. Do not create Kanban tasks yet unless the work really splits into bounded subtasks.

## Workflow B: Split A Durable Lane Into Kanban Subtasks

Use this when the durable lane is already established and the work now decomposes into independent slices.

### Step 1. Identify the owning branch

Example placeholder:

```bash
feat/remote-uat-hardening
```

### Step 2. Create tasks from the canonical project workspace

Always use the canonical workspace path, not the current Kanban task worktree path:

```bash
kanban task create \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --base-ref feat/remote-uat-hardening \
  --prompt "Parent: hardening UAT flow"
```

Create child tasks the same way:

```bash
kanban task create \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --base-ref feat/remote-uat-hardening \
  --prompt "Child: deploy smoke assertions"
```

```bash
kanban task create \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --base-ref feat/remote-uat-hardening \
  --prompt "Child: nginx probe fixes"
```

If the child tasks have a prerequisite relationship, link them explicitly:

```bash
kanban task link \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --task-id <waiting-task-id> \
  --linked-task-id <prerequisite-task-id>
```

Use `kanban task link` when one backlog task must wait for another.
If the subtasks are independent, do not link them.

### Step 3. Link dependencies explicitly when order matters

If one task must wait on another, create the dependency explicitly:

```bash
kanban task link \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --task-id <waiting-task-id> \
  --linked-task-id <prerequisite-task-id>
```

Meaning:

- `--task-id` is the waiting dependent task
- `--linked-task-id` is the prerequisite task it waits on

For a parent card that should stay blocked until a child slice is complete, the parent is the waiting task and the child is the prerequisite task.

### Step 4. Start the child task

```bash
kanban task start \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --task-id <child-task-id>
```

Kanban will create a task worktree under `~/.cline/worktrees/<taskId>/moltinger-main`.

### Step 5. Execute bounded work only

Inside the Kanban task worktree:

- keep the slice narrow
- do not take ownership of topology publish
- do not reinterpret Beads runtime rules
- do not widen scope into shared governance work unless the task is reclassified

### Step 6. Return results to the owning lane

After the child task is finished:

- complete review and commit flow as appropriate
- integrate the result back into the owning durable lane
- continue parent-level orchestration there

## Workflow C: Bring An Existing Branch Into Kanban

This is the supported bridge for pre-existing work.

1. Keep the existing authoritative durable worktree where it is.
2. Use its branch as the Kanban base ref.
3. Put the authoritative path and current context into the Kanban prompt.

Example:

```bash
kanban task create \
  --project-path /Users/rl/coding/moltinger/moltinger-main \
  --base-ref feat/moltinger-jb6-gpt54-primary \
  --prompt "Continue branch feat/moltinger-jb6-gpt54-primary. Authoritative worktree: /Users/rl/coding/moltinger/moltinger-jb6-gpt54-primary. Read AGENTS.md, MEMORY.md, and SESSION_SUMMARY.md before changing code."
```

This preserves branch continuity without pretending Kanban imported the old folder itself.

## Workflow D: Existing Durable Worktree With Uncommitted Changes

This is **not** a clean import case.

Choose one of these options:

1. Keep working in the durable worktree and do not move the slice into Kanban yet.
2. Commit the state, then create a Kanban task from the resulting branch via `--base-ref`.
3. Move changes via patch or stash only if you deliberately want a new execution surface.

Do not assume Kanban can ingest the exact live state of an external worktree automatically.

## Workflow E: Finish And Cleanup

Finish the durable lane through the repo-native lifecycle, not through generic Kanban deletion.

Rules:

- finish and cleanup stay with the authoritative lane workflow
- topology snapshot publication stays in `chore/topology-registry-publish`
- Kanban card trashing is not a replacement for durable lane closure

## Do And Don't

### Do

- use Kanban from the canonical project workspace
- use `--base-ref` to bridge existing branches into Kanban
- keep durable ownership in the authoritative lane
- keep prompts explicit about authoritative worktree path and scope
- keep task slices narrow and parallel-safe

### Don't

- don't import existing durable worktrees as if Kanban owns them
- don't create broad `.worktreeinclude` copies in this repo
- don't publish topology snapshots from ordinary feature or task worktrees
- don't use Kanban deletion as the durable cleanup mechanism

## Validated Commands

The following commands were validated against the local runtime during this research:

```bash
kanban --version
kanban task create --help
kanban task start --help
kanban task list --help
kanban task list --project-path /Users/rl/coding/moltinger/moltinger-main
git worktree list --porcelain
```

The `task create` and `task start` syntax documented above is derived from the local Kanban CLI help and the live workspace state.

## Read Next

- [Cline Kanban + Worktree analysis](../research/cline-kanban-worktree-moltinger-analysis-2026-04-01.md)
- [Consilium review](../reports/consilium/2026-04-01-cline-kanban-worktree-plan-review.md)
- [Hybrid worktree pattern](../../knowledge/patterns/cline-kanban-hybrid-worktree.md)
