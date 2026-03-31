# Cline Kanban + Worktree: Research Index

**Research Date**: 2026-04-01
**Status**: Complete - operator guidance ready
**Scope**: how official Cline Worktrees, Workflows, Hooks, Memory Bank, and Kanban fit the current `moltinger` durable worktree model

## Executive Verdict

For `moltinger`, the correct target is a **hybrid model**:

- keep durable lane lifecycle in repo-native scripts and rules
- use Cline Workflows and Hooks as the user-facing orchestration layer
- use Cline Kanban only for task and subtask execution on top of an owning branch via `--base-ref`
- keep topology publish and Beads runtime rules outside generic Kanban happy-paths

This package records the source evidence, the plan review, and the operator workflow.

## Document Guide

| Document | Purpose | Audience | Read Time |
|----------|---------|----------|-----------|
| [Analysis](./cline-kanban-worktree-moltinger-analysis-2026-04-01.md) | Research synthesis, applicability, constraints, and migration target state | Leads, architects, operators | 20 min |
| [Consilium Review](../reports/consilium/2026-04-01-cline-kanban-worktree-plan-review.md) | Multi-expert review of the proposed plan and rollout risks | Decision makers | 15 min |
| [Runbook](../runbooks/cline-kanban-worktree-workflow.md) | Practical workflow for durable worktrees plus Kanban tasks/subtasks | Operators, contributors | 15 min |
| [Knowledge Pattern](../../knowledge/patterns/cline-kanban-hybrid-worktree.md) | Durable reusable mental model | Anyone returning to the topic later | 5 min |

## Quick Navigation

### If you need a decision

Read:

1. [Analysis](./cline-kanban-worktree-moltinger-analysis-2026-04-01.md)
2. [Consilium Review](../reports/consilium/2026-04-01-cline-kanban-worktree-plan-review.md)

### If you need to operate the workflow

Read:

1. [Runbook](../runbooks/cline-kanban-worktree-workflow.md)
2. [Knowledge Pattern](../../knowledge/patterns/cline-kanban-hybrid-worktree.md)

### If you need the short answer

- Do not retire `command-worktree` yet.
- Do not treat Kanban as the owner of durable lanes.
- Do use Kanban for subtask worktrees created from the main workspace with `--base-ref <owning-branch>`.
- Do keep topology publish in the dedicated publish lane only.
- Do keep `.worktreeinclude` whitelist-only.

## Source Set

### Official Cline References

- https://docs.cline.bot/features/worktrees
- https://docs.cline.bot/customization/overview
- https://docs.cline.bot/customization/hooks
- https://docs.cline.bot/features/slash-commands/workflows/quickstart
- https://docs.cline.bot/features/memory-bank

### Local Project Contracts

- [docs/CODEX-OPERATING-MODEL.md](../CODEX-OPERATING-MODEL.md)
- [docs/rules/post-close-task-classification-and-worktree-escalation.md](../rules/post-close-task-classification-and-worktree-escalation.md)
- [docs/rules/topology-registry-single-writer-publish-path.md](../rules/topology-registry-single-writer-publish-path.md)
- [.claude/commands/worktree.md](../../.claude/commands/worktree.md)

### Live Runtime Evidence Used In Research

- `git worktree list --porcelain`
- `kanban task create --help`
- `kanban task start --help`
- `kanban task list --help`
- `kanban task list --project-path /Users/rl/coding/moltinger/moltinger-main`

## Applicability Summary

The package is directly applicable to the current repository because:

- the repo already uses durable sibling worktrees for authoritative lanes
- the repo already has active Cline Kanban tasks under `~/.cline/worktrees/...`
- the repo already carries explicit guardrails for Beads, topology publish, and post-close task classification

It is **not** a generic "replace all worktree tooling with Kanban" package.
It is a repository-specific integration package.
