---
title: "Cline Kanban Hybrid Worktree Pattern"
category: "pattern"
tags: ["cline", "kanban", "worktree", "git", "workflow"]
source: "docs.cline.bot + local moltinger operating model"
date: "2026-04-01"
confidence: "high"
---

# Cline Kanban Hybrid Worktree Pattern

## Summary

For `moltinger`, Cline Kanban works best as a task execution layer, not as the owner of durable lanes. The authoritative branch and durable worktree stay repo-native, while Kanban creates bounded subtask worktrees from the canonical workspace with `--base-ref`.

## Key Concepts

- **Durable lane**: the authoritative branch and worktree that own a slice end-to-end.
- **Kanban task lane**: an ephemeral execution worktree created by Kanban for a bounded task.
- **Mirror card**: a Kanban task created from an existing branch while the original durable worktree remains authoritative.

## Pattern

Use the hybrid model when all of the following are true:

1. the repository already has durable lifecycle rules for branches and worktrees
2. you want lower orchestration friction and task decomposition
3. you need safe parallel task worktrees without giving up repo-specific contracts

## Recommended Flow

1. Classify the request.
2. Start or reuse the authoritative durable lane.
3. Split only bounded parallel-safe slices into Kanban tasks.
4. Create Kanban tasks from the canonical workspace using `--base-ref <owning-branch>`.
5. Keep finish, cleanup, topology publish, and Beads-sensitive repair in the durable lane flow.

## When Not To Use

Do not use Kanban as the primary owner when:

- the task is governance-sensitive
- the durable worktree has important uncommitted state
- the slice needs topology publication
- the slice is really lane creation or lane closure rather than bounded implementation

## Operational Rule Of Thumb

- If the question is "who owns this branch and closes it?" -> durable lane.
- If the question is "can we run this bounded slice in parallel?" -> Kanban subtask.
- If the question is "can Kanban import this existing folder as-is?" -> assume no; use a mirror card with `--base-ref`.
