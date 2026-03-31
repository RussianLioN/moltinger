# Cline Kanban + Worktree for Moltinger

**Date**: 2026-04-01
**Type**: Research synthesis and applicability analysis
**Decision Target**: whether official Cline Worktrees and Kanban can replace the current `command-worktree`-centric workflow

## Scope

This document synthesizes:

- official Cline capabilities
- current `moltinger` worktree and branch contracts
- live local Kanban runtime behavior
- the practical limits of importing existing worktrees and branches into Kanban

## What The Official Cline Stack Gives Us

Official Cline provides a real foundation for the orchestration layer:

- Worktrees in the UI for isolated parallel sessions
- Workflows as slash-command based repeatable procedures
- Hooks for context injection and guardrails
- Memory Bank for durable session context
- Kanban for task orchestration and per-task worktrees

These are enough to simplify user experience around lane start, resume, and subtask execution.
They are **not** enough on their own to replace the repo's durable lifecycle contract.

## What The Current Project Already Requires

The current repository is stricter than stock Cline:

- durable sibling worktrees are part of the operating model
- branch and worktree naming are controlled
- durable lane creation routes through `scripts/worktree-ready.sh` and `scripts/worktree-phase-a.sh`
- post-close requests must be classified before reusing a lane
- topology publication is restricted to a single dedicated lane
- Beads uses worktree-local ownership and runtime repair rules

Those constraints are not decorative. They encode prior incidents and operational lessons.

## Main Finding

The right target state is:

- **Cline-native orchestration**
  - Workflows
  - Hooks
  - Memory Bank
- **Repo-native durable backend**
  - `scripts/worktree-ready.sh`
  - `scripts/worktree-phase-a.sh`
  - existing rules for topology and Beads
- **Kanban for subtask execution**
  - create tasks from the canonical project workspace
  - use `--base-ref <owning-branch>`
  - let Kanban create ephemeral task worktrees under `~/.cline/worktrees/<taskId>/<repo>`

## What Kanban Can And Cannot Do Here

### Supported well

Kanban is a good fit for:

- parent task plus child task decomposition
- short-lived parallel execution worktrees
- resumable task sessions
- a board-level view of backlog, in-progress, review, and trash
- continuing work from an existing branch commit using `--base-ref`

### Not supported as a first-class workflow

Kanban is not a clean owner for:

- importing an already existing durable sibling worktree as the Kanban object of record
- moving exact uncommitted state from an external authoritative worktree into a Kanban task automatically
- enforcing repo-specific topology publication restrictions by itself
- enforcing repo-specific Beads runtime ownership by itself

For existing durable lanes, the reliable bridge is a **mirror card**:

- keep the authoritative worktree where it is
- create a Kanban task from the main workspace
- point it at the owning branch with `--base-ref`
- include the authoritative worktree path and next steps in the task prompt

## Recommended Usage Patterns

### 1. Thin-wrapper migration

Use Cline Workflows as the preferred user interface, but route create and attach operations into the current scripts instead of duplicating logic.

### 2. Hook-injected context

On task start and resume, inject:

- `AGENTS.md`
- `MEMORY.md`
- `SESSION_SUMMARY.md`
- topology status
- current lane guardrails

This reduces the need for manual context re-explaining.

### 3. Durable lane plus Kanban subtasks

Keep the authoritative branch in a durable worktree, then create Kanban cards from that branch for bounded subtasks that can safely run in parallel.

### 4. Mirror-card adoption for legacy sibling worktrees

When a durable worktree already exists, do not try to "import the folder". Instead, create a Kanban card linked to the existing branch and describe the authoritative folder in the prompt.

### 5. Memory Bank as cross-session glue

Use Memory Bank or equivalent curated context files so Kanban sessions and durable lanes converge on the same session state.

### 6. Whitelist-only `.worktreeinclude`

If ignored files must be copied, maintain a small explicit whitelist. Never mirror `.gitignore` in this repository because it contains secrets and local runtime state.

## Retirement Decision For `command-worktree`

**Current decision**: do not retire it completely.

Safe path:

1. add Cline workflows and hooks
2. keep current scripts as the backend
3. keep `command-worktree` as compatibility fallback
4. run UAT for parity on create, attach, finish, cleanup, topology publish, and Beads-sensitive flows
5. only then reduce `command-worktree` to a thin compatibility shim

Unsafe path:

- reimplement durable lifecycle in generic workflows
- treat Kanban as the source of truth for authoritative lanes
- allow broad ignored-file copying

## Live Evidence From This Repository

The analysis was validated against the live local runtime:

- `git worktree list --porcelain` shows both durable sibling worktrees and Kanban-managed worktrees under `~/.cline/worktrees/`
- `kanban task create --help` exposes `--project-path` and `--base-ref`, but no import-existing-worktree option
- `kanban task start --help` confirms Kanban starts a task session from the workspace path
- `kanban task list --project-path /Users/rl/coding/moltinger/moltinger-main` confirms the repo is already registered in Kanban and active tasks exist

## Net Recommendation

Adopt the Cline stack as the **front door**.
Keep the repo scripts and rules as the **durable control plane**.
Use Kanban as the **parallel execution layer**.

That is the variant that fits the current project without losing the protections already encoded by previous RCA and rule documents.
