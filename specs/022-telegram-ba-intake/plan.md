# Implementation Plan: Telegram Business Analyst Intake

**Branch**: `022-telegram-ba-intake` | **Date**: 2026-03-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/022-telegram-ba-intake/spec.md`

## Summary

Add a new discovery-first slice to the factory so Moltinger behaves as a Telegram business analyst before the existing concept-pack flow starts. The implementation should guide a non-technical business user through a multi-turn interview, collect and structure requirements, generate a reviewable requirements brief, require explicit confirmation, and then hand off one canonical confirmed brief into the already existing `020-agent-factory-prototype` concept-pack pipeline.

## Technical Context

**Language/Version**: Bash 5.x, Python 3.11+, JSON/TOML/Markdown artifacts  
**Primary Dependencies**: Moltis/Moltinger Telegram channel, existing `agent_factory_common.py` helpers, current `agent-factory-intake.py` and `agent-factory-artifacts.py` downstream flow, repo-local runbooks/specs/tests  
**Storage**: Git-tracked planning artifacts, repo-local JSON state under `data/agent-factory/`, versioned discovery/brief/handoff manifests, existing concept-pack artifact directories  
**Testing**: Shell/component/integration tests under `tests/`, fixture-driven discovery session coverage, existing static config validation, existing agent-factory downstream tests for handoff compatibility  
**Target Platform**: Linux Docker-hosted Moltis runtime with Telegram as the primary human-facing channel
**Project Type**: Documentation-driven workflow + script/config orchestration + stateful discovery contracts  
**Performance Goals**: A user can complete one guided discovery flow in a single Telegram conversation; the system can produce an updated draft brief in the same conversation loop after corrections; confirmed brief handoff must not require manual copy-paste between stages  
**Constraints**: Russian-first UX; non-technical user language only; no concept-pack generation before explicit brief confirmation; no duplicate Telegram transport stack outside existing Moltis channel ownership; examples must stay sanitized/synthetic for prototype safety; downstream `020` factory flow remains the single source of truth after handoff  
**Scale/Scope**: Pilot-scale discovery for one organization-facing coordinator; tens of active discovery sessions are acceptable; one confirmed brief per concept version; downstream swarm/deploy concerns remain outside this feature package

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | PASS | Existing `020` spec/runbook, current Telegram config, and current agent-factory scripts were reviewed before creating the new slice. |
| II. Single Source of Truth | PASS | The confirmed requirements brief is planned as the only valid upstream input for downstream concept-pack generation. |
| III. Library-First Development | PASS | Planning reuses the existing Moltis Telegram channel and current agent-factory scripts instead of introducing a second bot runtime. |
| IV. Code Reuse & DRY | PASS | The design extends `agent_factory_common.py`, `agent-factory-intake.py`, and existing tests rather than building a separate application tree. |
| V. Strict Type Safety | PASS | Explicit JSON contracts and state/entity definitions are captured before runtime changes. |
| VI. Atomic Task Execution | PASS | Work decomposes cleanly into discovery session state, brief confirmation, example handling, handoff, recovery, and validation slices. |
| VII. Quality Gates | PASS | The plan includes fixture-based tests, contract docs, quickstart validation, and final prerequisite checks. |
| VIII. Progressive Specification | PASS | The feature is moving through spec -> research -> plan -> tasks without skipping phases. |
| IX. Error Handling | PASS | The design requires contradiction detection, unresolved-topic exposure, and explicit confirmation gating instead of silent failure. |
| X. Observability | PASS | Discovery status, brief versions, handoff provenance, and operator-visible next actions are first-class outputs. |
| XI. Accessibility | PASS | The slice is text-first and explicitly optimized for non-technical business users working through Telegram. |

**Gate Status**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/022-telegram-ba-intake/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── discovery-session-contract.md
│   ├── clarification-loop-contract.md
│   ├── requirements-brief-contract.md
│   └── factory-handoff-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
config/
└── moltis.toml

scripts/
├── agent-factory-discovery.py          # new discovery/session orchestrator
├── agent-factory-intake.py             # existing downstream normalization bridge
├── agent-factory-artifacts.py          # existing concept-pack generator
├── agent_factory_common.py             # shared state/normalization helpers
├── telegram-bot-send.sh
├── telegram-user-probe.py
└── telegram-real-user-e2e.py

docs/
├── runbooks/
│   ├── agent-factory-prototype.md
│   └── agent-factory-discovery.md      # new runbook for this slice
└── templates/
    └── agent-factory/
        └── requirements-brief.md       # new brief template

tests/
├── component/
│   ├── test_agent_factory_discovery.sh
│   ├── test_agent_factory_brief.sh
│   └── test_agent_factory_handoff.sh
├── integration_local/
│   ├── test_agent_factory_discovery_flow.sh
│   ├── test_agent_factory_confirmation.sh
│   └── test_agent_factory_resume.sh
└── fixtures/
    └── agent-factory/
        └── discovery/
```

**Structure Decision**: Keep the new feature inside the repository’s existing `config/`, `scripts/`, `docs/`, and `tests/` layout. This avoids inventing a parallel service tree and keeps discovery tightly coupled to the already implemented `020` concept-pack pipeline.

## Critical Planning Decisions

### Decision 1: Discovery Must Become A First-Class Workflow

**Chosen design**: Introduce a dedicated discovery-session layer ahead of concept-pack generation instead of continuing to rely on a pre-filled JSON payload.

**Rationale**:

- The user’s primary expectation is a guided Telegram dialogue with an AI business analyst.
- The current `020` slice already assumes follow-up questions but does not yet embody a real multi-turn session.
- A stateful discovery layer is the missing product frontend for the factory.

**Alternatives considered**:

- Keep the current prefilled JSON intake only: rejected because it still requires the user to prepare the brief outside the agent.
- Ask the user to fill a form or document first: rejected because it breaks the conversational business-analyst experience.

### Decision 2: Confirmed Brief Is The New Upstream SSOT

**Chosen design**: Create one confirmed requirements brief as the canonical handoff object between conversational discovery and the downstream concept-pack pipeline.

**Rationale**:

- The conversation itself is too noisy to be the direct production input.
- Downstream concept-pack generation needs stable, versioned, user-confirmed content.
- The confirmed brief cleanly separates “business discovery” from “factory production”.

### Decision 3: Reuse Existing Telegram Ownership

**Chosen design**: Reuse the existing Moltis Telegram channel and operator tooling instead of introducing a second Telegram runtime or alternate bot framework.

**Rationale**:

- `config/moltis.toml` already defines the Telegram bot channel.
- Existing scripts and UAT tooling already validate Telegram send/probe behavior.
- A second transport stack would create drift in auth, monitoring, and delivery semantics.

**Alternatives considered**:

- Separate Python bot service: rejected because it duplicates transport ownership and operational surface.
- Separate web UI first: rejected because it delays the intended Telegram-first experience.

### Decision 4: Text-First Discovery MVP

**Chosen design**: Plan the discovery slice as text-first, with free-form answers and manually provided examples, while keeping multimodal inputs optional for later.

**Rationale**:

- It matches the current repo’s Telegram baseline.
- It is enough to validate the business-analyst interaction pattern.
- It keeps implementation scope focused on dialogue quality, state, and handoff.

### Decision 5: Confirmation Is Separate From Concept Approval

**Chosen design**: Treat brief confirmation as a pre-concept gate distinct from the existing `approved / rework_requested / rejected / pending_decision` defense states.

**Rationale**:

- The user must first confirm “this is what I meant”.
- Concept approval belongs to the later defense process already covered in `020`.
- Combining these two gates would blur business-discovery completion and concept governance.

### Decision 6: Recovery And Reopen Are Mandatory

**Chosen design**: Support interrupted sessions and reopened confirmed briefs as first-class states rather than edge-case manual recovery.

**Rationale**:

- Business discovery rarely finishes in one uninterrupted sitting.
- Users often validate details with colleagues and then come back with corrections.
- Versioned reopen behavior preserves trust and traceability for downstream concept generation.

## Phase 0: Research Decisions

Phase 0 is complete in [research.md](./research.md).

### Finalized Research Output

1. The current `020` factory slice is a downstream consumer, not the right home for the user-facing discovery experience.
2. A dedicated discovery session, confirmed brief, and handoff record are required as new first-class entities.
3. Existing Moltis Telegram ownership should be reused rather than replaced.
4. The safest prototype posture is text-first, Russian-first, and sanitized-example-first.
5. The existing `agent-factory-intake.py` should become a bridge from confirmed brief to concept-pack generation, not the full conversational runtime.

## Phase 1: Design Artifacts

### Data Model

Generate and maintain [data-model.md](./data-model.md) for:

- `DiscoverySession`
- `ConversationTurn`
- `RequirementTopic`
- `ClarificationItem`
- `ExampleCase`
- `RequirementBrief`
- `BriefRevision`
- `ConfirmationSnapshot`
- `FactoryHandoffRecord`

### Contracts

Generate and maintain:

- [contracts/discovery-session-contract.md](./contracts/discovery-session-contract.md)
- [contracts/clarification-loop-contract.md](./contracts/clarification-loop-contract.md)
- [contracts/requirements-brief-contract.md](./contracts/requirements-brief-contract.md)
- [contracts/factory-handoff-contract.md](./contracts/factory-handoff-contract.md)

### Quickstart

Generate and maintain [quickstart.md](./quickstart.md) for:

- discovery-session validation
- summary and confirmation behavior
- example/exception capture
- handoff into the existing concept-pack pipeline
- session resume and reopen expectations

### Agent Context Update

Do not auto-write `AGENTS.md` from `update-agent-context.sh` for this feature. The repository treats its agent instructions as generated; the active planning context should remain in the Speckit package and runtime docs.

## Phase 2: Execution Readiness

### Stage 1: Discovery Foundations

- extend Moltinger identity and env contract in `config/moltis.toml`
- add a new `requirements-brief.md` template under `docs/templates/agent-factory/`
- add discovery fixtures and umbrella test wiring

### Stage 2: Guided Interview MVP

- implement discovery session orchestration and next-question logic
- persist topic progress and unresolved questions
- expose a draft brief before confirmation

### Stage 3: Confirmation And Example Grounding

- version draft and confirmed briefs
- support corrections, contradiction handling, and example-driven clarification
- separate confirmation from downstream defense approval

### Stage 4: Handoff And Recovery

- adapt confirmed brief into one canonical handoff record
- bridge handoff into existing concept-pack generation
- support resume and reopen without losing provenance

### Stage 5: Validation And Handoff

- validate the discovery slice with component and integration tests
- document the operator and user-facing runbook
- reconcile topology, quickstart, and session summary before landing
