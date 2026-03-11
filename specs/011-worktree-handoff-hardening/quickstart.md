# Quickstart: Worktree Handoff Hardening

## Scenario 1: Create flow stops at manual handoff

1. Run a mixed request that creates a new worktree and also asks for downstream work in that worktree.
2. Expect:
   - the create flow completes Phase A successfully
   - the response ends at the handoff block
   - the originating session does not continue Phase B locally

## Scenario 2: Attach flow follows the same hard boundary

1. Run a mixed request that attaches to an existing branch and also asks for downstream work.
2. Expect:
   - the attach flow returns handoff output
   - the originating session stops after handoff
   - no special attach-only exception allows local downstream execution

## Scenario 3: Structured Speckit startup survives manual handoff

1. Run a mixed request where the downstream work is a structured Speckit startup task with explicit defaults and boundaries.
2. Expect:
   - the handoff still stops after Phase A
   - a short pending summary is present
   - a richer Phase B seed payload or equivalent carrier preserves the feature description, scope boundaries, defaults, and stop conditions

## Scenario 4: Automatic launch remains opt-in and safe

1. Run a create or attach request that explicitly asks for terminal or Codex launch.
2. Expect:
   - launch occurs only because it was explicitly requested
   - if launch succeeds, the originating session reports it and stops
   - if launch fails, the workflow degrades to manual handoff and still stops

## Scenario 5: Simple requests stay concise

1. Run a create or attach request with a short downstream task.
2. Expect:
   - the manual handoff remains concise
   - the workflow does not add unnecessary extra payload
   - the stop-after-Phase-A rule still holds

## Validation Evidence

- 2026-03-11:
  - `bash -n scripts/worktree-ready.sh`
  - `bash -n tests/unit/test_worktree_ready.sh`
  - `./tests/unit/test_worktree_ready.sh`
- Observed:
  - full unit suite passed (`24/24`)
  - create and attach flows both preserve hard stop-after-Phase-A boundary output
  - structured downstream requests preserve concise `Pending` plus separate rich `Phase B Seed Payload`
  - automatic terminal launch remains opt-in, and failed codex launch falls back to manual handoff without crossing the boundary
