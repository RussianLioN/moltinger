# Consilium Review: Cline Kanban + Worktree Plan

**Date**: 2026-04-01  
**Mode**: parallel expert review  
**Verdict**: viable with changes

## Experts Included

- GitOps and delivery
- DevOps and Cline workflow integration
- SRE and operational reliability
- Security
- QA and UAT
- Bash and runtime contract review
- Agent orchestration and Kanban semantics

## Decision

The plan is applicable to the current project only in the following form:

- Cline Workflows and Hooks become the preferred orchestration UX
- current shell scripts remain the source of truth for durable lane lifecycle
- Kanban is used for task and subtask execution, not as the owner of authoritative lanes

## Findings

### Critical

1. Full replacement of `command-worktree` is premature.
   The current repository has durable lifecycle rules that are stricter than stock Cline.

2. Kanban does not provide a documented first-class import flow for existing durable sibling worktrees.
   Branch-based continuation through `--base-ref` is workable; worktree import is not.

3. Topology publish cannot be absorbed into a general Kanban happy-path.
   It must remain in the dedicated publish lane only.

### High

1. Any workflow migration must call the existing shell backend instead of re-implementing create and cleanup logic.

2. `.worktreeinclude` must be whitelist-only.
   This repo cannot safely mirror `.gitignore` because ignored paths include secrets and runtime-local state.

3. Beads runtime and ownership rules must remain explicit.
   Generic Kanban flows will not enforce them automatically.

### Medium

1. Rollout must be staged.
   Thin orchestration migration first, retirement decisions later.

2. UAT must include parity checks for create, attach, finish, cleanup, and failure handling.

## Applicability To Current Project

The plan is a good fit because the repository already has:

- a strong worktree-based operating model
- live Kanban usage
- explicit rules for topology publishing
- explicit rules for Beads local ownership and repair
- prior RCA showing why the durable backend cannot be treated casually

The plan is a poor fit if it is interpreted as:

- "all work now starts in Kanban"
- "existing sibling worktrees should be imported directly"
- "project scripts can be replaced with generic workflow markdown"

## Recommended Rollout

### Phase 1

- create new Cline workflows for lane start, attach, finish, cleanup
- add hooks for context injection and guardrails
- keep backend behavior in current scripts

### Phase 2

- document the hybrid operating model
- direct new bounded subtasks into Kanban via `--base-ref`
- keep durable lanes outside Kanban ownership

### Phase 3

- run UAT and failure drills
- verify that the new workflow does not violate topology or Beads rules

### Phase 4

- reduce `command-worktree` to fallback or compatibility shim if parity is proven

## User Impact

Expected benefit is mostly orchestration efficiency:

- lower startup friction for new lanes
- lower resume friction for paused work
- better visibility for decomposed subtasks
- safer task distribution across isolated task worktrees

Expected improvement:

- about 10-25% faster for routine start and resume flows
- potentially 30-50% faster for work that cleanly decomposes into parallel subtasks

The gain is not uniform.
Governance-sensitive and dirty-lane scenarios remain constrained by the repo's existing safety contracts.
