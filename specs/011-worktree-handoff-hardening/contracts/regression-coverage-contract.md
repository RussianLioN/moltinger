# Contract: Regression Coverage Contract

## Purpose

Define the minimum regression coverage required to protect the hardened boundary and handoff semantics.

## Required Coverage Areas

### Create Flow Boundary

- A mixed request that creates a worktree and includes downstream work
- Proof that the originating session stops after the handoff output
- Proof that no downstream artifacts are created during Phase A

### Attach Flow Boundary

- A mixed request that attaches to an existing branch and includes downstream work
- Proof that attach follows the same stop-after-Phase-A rule

### Rich Downstream Intent Preservation

- A long, structured downstream request such as Speckit startup
- Proof that the handoff preserves both a short pending summary and a richer downstream carrier when needed
- Proof that critical constraints survive the handoff

### Automatic Launch Fallback

- A request that explicitly asks for Codex or terminal launch
- Proof that success stops the originating session after reporting the launch
- Proof that failure degrades to manual handoff and still stops

## Failure Conditions

Regression coverage must fail if any covered scenario shows one of the following:

- downstream work continues in the originating session after a successful handoff
- the handoff preserves only a lossy one-line summary for a structured request
- helper output, command instructions, and expected boundary semantics diverge
- create and attach flows follow different boundary rules without explicit justification
