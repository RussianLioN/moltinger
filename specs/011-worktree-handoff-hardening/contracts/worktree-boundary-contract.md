# Contract: Worktree Boundary Contract

## Purpose

Define the authoritative Phase A / Phase B boundary for `command-worktree` create and attach flows.

## Contract Rules

- `command-worktree` create and attach flows are Phase A-only in the originating session.
- Phase A ends when the workflow emits a successful handoff or reports a blocked state.
- A successful Phase A flow must stop after handoff in the originating session.
- Mixed requests that include downstream work do not grant permission to continue Phase B locally.
- Automatic Codex or terminal handoff is valid only when explicitly requested.
- If automatic launch fails or is unavailable, the workflow must degrade to manual handoff and still stop after Phase A.

## Allowed Phase A Actions

- Resolve or reuse the target worktree and branch.
- Perform required create or attach workflow steps.
- Package deferred downstream intent for handoff.
- Emit the handoff contract or a blocked result.

## Forbidden Phase A Actions

- Continue downstream task execution in the originating session after handoff.
- Analyze or decompose deferred downstream work beyond packaging it for handoff.
- Create or update downstream artifacts such as Speckit specs, plans, tasks, Beads work items, or implementation notes.
- Weaken the stop boundary for manual handoff flows.

## Boundary Outcomes

- **Success / manual**: Emit handoff output and stop.
- **Success / automatic launch requested and succeeds**: Report the launched handoff and stop.
- **Success / automatic launch requested but fails**: Emit manual handoff fallback and stop.
- **Blocked**: Report the blocking reason and do not continue Phase B.
