# Quickstart: Agent Factory Prototype

## Purpose

This quickstart is for validation and continued implementation handoff of the MVP0 factory prototype.

It confirms three things:

1. the ASC context mirror is available in this repository
2. the concept pack flow is clearly bounded
3. the swarm output stops at a playground bundle, not deployment

## 1. Verify Context Integrity

Run:

```bash
git status --short docs/asc-roadmap docs/concept specs/020-agent-factory-prototype
.specify/scripts/bash/check-prerequisites.sh --json
rg -n "coding/ASC-AI-agent-fabrique" \
  docs/ASC-AI-FABRIQUE-MIRROR.md \
  docs/plans/parallel-doodling-coral.md \
  docs/research/openclaw-moltis-research.md \
  specs/020-agent-factory-prototype/spec.md \
  specs/020-agent-factory-prototype/plan.md \
  specs/020-agent-factory-prototype/research.md \
  specs/020-agent-factory-prototype/data-model.md \
  specs/020-agent-factory-prototype/tasks.md \
  specs/020-agent-factory-prototype/contracts
```

Expected result:

- the Speckit package exists for `020-agent-factory-prototype`
- the local ASC mirror is present under `docs/asc-roadmap/` and `docs/concept/`
- no active planning artifacts still depend on a workstation-specific ASC path

Recommended reading order for session recovery:

1. [docs/ASC-AI-FABRIQUE-MIRROR.md](../../docs/ASC-AI-FABRIQUE-MIRROR.md)
2. [docs/asc-roadmap/INDEX.md](../../docs/asc-roadmap/INDEX.md)
3. [docs/concept/INDEX.md](../../docs/concept/INDEX.md)
4. [docs/plans/parallel-doodling-coral.md](../../docs/plans/parallel-doodling-coral.md)
5. [docs/plans/agent-factory-lifecycle.md](../../docs/plans/agent-factory-lifecycle.md)
6. [spec.md](./spec.md)
7. [tasks.md](./tasks.md)
8. [docs/runbooks/agent-factory-prototype.md](../../docs/runbooks/agent-factory-prototype.md)

## 2. Validate The Concept Intake Path

Use the feature spec as the acceptance source:

- [spec.md](./spec.md)
- [contracts/intake-session-contract.md](./contracts/intake-session-contract.md)

Expected prototype flow:

1. User enters an automation idea through Telegram.
2. Moltinger asks clarifying questions until the concept is sufficiently structured.
3. The system creates one versioned concept record.
4. The system emits three aligned artifacts:
   - project documentation
   - agent specification
   - presentation

Validation questions:

- Are goals, scope, metrics, assumptions, and risks aligned across all three artifacts?
- Can each artifact be both edited and downloaded?
- Is the output explicitly Russian-first?

## 3. Validate The Defense Gate

Use:

- [contracts/defense-review-contract.md](./contracts/defense-review-contract.md)

Expected prototype behavior:

1. Defense result is recorded as `approved`, `rework_requested`, `rejected`, or `pending_decision`.
2. Feedback items are mapped to the affected artifacts.
3. No production swarm starts without explicit approval.

Validation questions:

- Can the same concept version be traced from intake to defense?
- Does rework preserve previous versions?
- Is approval clearly separated from deployment?

## 4. Validate The Swarm Output Contract

Use:

- [contracts/swarm-run-contract.md](./contracts/swarm-run-contract.md)
- [contracts/playground-package-contract.md](./contracts/playground-package-contract.md)

Expected prototype behavior:

1. Approved concept triggers coder/tester/validator/auditor/assembler stages.
2. The swarm publishes evidence for stage outcomes.
3. Successful execution produces a runnable playground package.
4. Playground uses only synthetic or test data.
5. Blocker failures escalate to admin instead of silently stalling.
6. A published status snapshot always distinguishes `production`, `playground_ready`, and `needs_admin_attention`.

Validation questions:

- Is every stage traceable to the approved concept version?
- Can the user review the resulting playground without server-shell access?
- Can the operator tell the difference between happy path and blocker failure from one status snapshot?
- Does the process stop before production deployment?

## 5. Current Readiness Check

Confirm:

- [x] ASC mirror exists inside this repo
- [x] spec/research/plan artifacts exist for this feature
- [x] design contracts exist for intake, defense, swarm, and playground
- [x] mirror navigation is recoverable from repo paths only
- [x] implementation tasks are generated and ordered
- [x] topology drift from branch creation is reconciled before landing
- [x] User Stories 1-5 are implemented with local validation coverage

## 6. Handoff Rule

This feature is ready for continued implementation only when:

1. `tasks.md` is reconciled with completed implementation work
2. the topology registry is refreshed after branch or worktree mutations
3. all planning artifacts reference in-repo context paths
4. each new user story adds matching validation commands to the runbook
