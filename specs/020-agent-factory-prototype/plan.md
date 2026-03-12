# Implementation Plan: Agent Factory Prototype

**Branch**: `020-agent-factory-prototype` | **Date**: 2026-03-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/020-agent-factory-prototype/spec.md`

## Summary

Transform Moltinger into an MVP0 agent-factory coordinator that accepts an automation idea through Telegram, produces a synchronized concept pack of project documentation + specification + defense presentation, records the defense outcome, and only after explicit approval launches an internal production swarm that delivers a containerized playground bundle. The implementation should reuse the existing Moltinger/Clawdiy fleet control-plane, keep the ASC concept mirror inside this repository, and stop before production deployment.

## Technical Context

**Language/Version**: Bash 5.x, Python 3.11+, Node.js 20+/ESM helper scripts, JSON/TOML/YAML/Markdown artifacts  
**Primary Dependencies**: Moltis/Moltinger runtime, OpenClaw/Clawdiy runtime, Telegram Bot API, Docker Compose v2, GitHub Actions, existing fleet registry/policy, Marp-compatible Markdown presentation export flow  
**Storage**: Git-tracked planning artifacts, per-concept artifact bundles, append-only review-safe JSON evidence, per-run playground bundle metadata, container images  
**Testing**: Speckit artifact validation, shell/component/integration tests under `tests/`, fixture-based concept/review/swarm coverage, existing Telegram/UAT harness for ingress verification  
**Target Platform**: Linux Docker host on `ainetic.tech`, Telegram as the human-facing intake/delivery channel, same-host coordinator+coded-runtime baseline with future multi-role expansion
**Project Type**: Documentation-driven workflow + platform orchestration + artifact generation + swarm packaging  
**Performance Goals**: concept pack produced in one guided intake flow; approved concept can reach playground-ready state within 2 hours for at least one reference concept; blocker failures escalate before silent timeout  
**Constraints**: Russian-first user experience; GitOps-only repository changes; no MVP1 deployment in this feature; playground data must be synthetic/test only; current host baseline remains resource-constrained; ASC mirror must stay inside this repository  
**Scale/Scope**: one active prototype path from idea to playground; one coordinator runtime plus explicit production-stage roles for coder, tester, validator, auditor, and assembler; future permanent runtimes remain a follow-on expansion, not a blocker

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | PASS | Local project memory, session summary, existing plans, fleet configs, Telegram workflows, and mirrored ASC docs were reviewed before planning. |
| II. Single Source of Truth | PASS | The concept record and synchronized artifact set are planned as canonical state; ASC context now has an in-repo mirror with provenance. |
| III. Library-First Development | PASS | Planning reuses existing Moltinger/Clawdiy runtime surfaces and selects a Marp-compatible presentation approach instead of inventing a custom binary deck workflow. |
| IV. Code Reuse & DRY | PASS | The plan extends existing Telegram, Speckit, fleet, and artifact patterns instead of creating a parallel platform. |
| V. Strict Type Safety | PASS | JSON/TOML/Markdown contracts and explicit entity/state definitions are part of the design artifacts before runtime code is written. |
| VI. Atomic Task Execution | PASS | Implementation can be split cleanly by mirror/context, intake, defense loop, swarm orchestration, playground packaging, and audit/evidence slices. |
| VII. Quality Gates | PASS | The plan includes fixture-based tests, contract artifacts, quickstart validation, and repository consistency checks before implementation closeout. |
| VIII. Progressive Specification | PASS | The feature is moving through research -> spec -> plan -> tasks with no skipped phase. |
| IX. Error Handling | PASS | The design requires structured admin escalation, review-safe evidence, and terminal outcomes for both defense and production stages. |
| X. Observability | PASS | Audit trail, stage status, concept/version traceability, and evidence bundles are first-class outputs. |
| XI. Accessibility | N/A | No new end-user UI beyond Telegram and downloadable artifacts is designed in this feature package. |

**Gate Status**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/020-agent-factory-prototype/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── intake-session-contract.md
│   ├── defense-review-contract.md
│   ├── swarm-run-contract.md
│   └── playground-package-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
config/
├── moltis.toml
├── clawdiy/
│   └── openclaw.json
└── fleet/
    ├── agents-registry.json
    └── policy.json

scripts/
├── agent-factory-intake.py
├── agent-factory-artifacts.py
├── agent-factory-review.py
├── agent-factory-swarm.py
├── agent-factory-playground.py
├── telegram-e2e-on-demand.sh
├── telegram-real-user-e2e.py
└── clawdiy-smoke.sh

docs/
├── ASC-AI-FABRIQUE-MIRROR.md
├── asc-roadmap/
├── concept/
├── plans/
└── runbooks/
    └── agent-factory-prototype.md

docs/templates/
└── agent-factory/
    ├── project-doc.md
    ├── agent-spec.md
    └── presentation.md

.github/workflows/
├── deploy.yml
├── deploy-clawdiy.yml
├── telegram-e2e-on-demand.yml
└── test.yml

tests/
├── component/
│   ├── test_agent_factory_artifacts.sh
│   ├── test_agent_factory_escalation.sh
│   ├── test_agent_factory_playground.sh
│   └── test_agent_factory_context_mirror.sh
├── integration_local/
│   ├── test_agent_factory_intake.sh
│   ├── test_agent_factory_review.sh
│   └── test_agent_factory_swarm.sh
└── fixtures/
    └── agent-factory/
```

**Structure Decision**: Keep the prototype inside the existing configuration/scripts/tests documentation layout instead of introducing a new application tree. This lets the feature reuse current Moltinger, Telegram, and fleet control-plane artifacts while making future runtime extraction a later decision rather than a planning blocker.

## Critical Planning Decisions

### Decision 1: User-Facing Intake Path

**Chosen design**: Use Moltinger’s Telegram-facing experience as the primary path for collecting idea context and delivering concept artifacts.

**Rationale**:

- It directly matches the requested product flow.
- Telegram operator tooling and review-safe artifact handling already exist in this repo.
- It minimizes new user-surface scope for MVP0.

**Alternatives considered**:

- Separate web UI first: rejected as unnecessary expansion before proving the factory concept.
- CLI-only artifact generation: rejected because it would not satisfy the user-facing Telegram flow.

### Decision 2: Artifact Model

**Chosen design**: Maintain one canonical concept record that drives a synchronized artifact set of project documentation, agent specification, and presentation.

**Rationale**:

- Keeps all defense and approval materials aligned.
- Supports versioned rework after feedback.
- Mirrors upstream ASC emphasis on concept packaging before autonomous execution.

**Alternatives considered**:

- Single combined document: rejected because it weakens audience-specific clarity.
- Independent artifacts without shared concept state: rejected because drift would be guaranteed.

### Decision 3: Presentation Source Format

**Chosen design**: Use a Marp-compatible slide Markdown source as the planning baseline for the presentation artifact.

**Rationale**:

- Official Marp tooling supports export to HTML, PDF, and PowerPoint.
- Markdown sources are git-friendly and easy to regenerate.
- It satisfies the “working + downloadable artifact” requirement.

### Decision 4: Defense Gate

**Chosen design**: Introduce an explicit defense result state before any production swarm run can start.

**Rationale**:

- Upstream ASC docs treat defense and follow-up as formal stages.
- The user explicitly describes approval or feedback before production.
- It prevents stale concepts from triggering autonomous execution.

### Decision 5: Swarm Runtime Posture

**Chosen design**: Reuse the current fleet control-plane as the baseline and model coder, tester, validator, auditor, and assembler as explicit production-stage owners, even if some begin as logical contracts rather than independent permanent runtimes.

**Rationale**:

- The repo already has a coordinator+coded-runtime baseline.
- Future-role examples already exist in fleet configuration.
- It avoids blocking MVP0 on fully materializing every role as its own long-lived service.

### Decision 6: Prototype Terminal Output

**Chosen design**: End the prototype at a runnable playground package plus evidence bundle; deployment remains a later MVP1 concern.

**Rationale**:

- It matches the user’s scope boundary.
- It provides a demonstrable result for review and approval.
- It avoids entangling MVP0 with production rollout governance.

### Decision 7: Local Context Mirror

**Chosen design**: Treat the repo-local ASC mirror as part of the feature contract, not a side note.

**Rationale**:

- The user explicitly requested the documentation copy.
- Existing plans referenced external absolute paths.
- Future sessions need stable, in-repo context anchors.

## Phase 0: Research Decisions

Phase 0 is complete in [research.md](./research.md).

### Finalized Research Output

1. Telegram remains the authoritative human-facing intake and artifact delivery channel.
2. The concept pack is a mandatory synchronized artifact triad.
3. Defense outcome is an explicit gate before production swarm execution.
4. The current fleet registry/policy is sufficient as the initial control-plane baseline.
5. Presentation generation should be source-first and Marp-compatible.
6. MVP0 ends at playground packaging and evidence, not deployment.
7. The local ASC mirror is now versioned in this repo and must remain referenced by in-repo paths.

## Phase 1: Design Artifacts

### Data Model

Generate and maintain [data-model.md](./data-model.md) for:

- `ConceptRequest`
- `ConceptRecord`
- `ArtifactSet`
- `ArtifactVersion`
- `DefenseReview`
- `FeedbackItem`
- `ProductionApproval`
- `SwarmRun`
- `SwarmStageExecution`
- `PlaygroundPackage`
- `EscalationPacket`
- `KnowledgeMirrorRecord`

### Contracts

Generate and maintain:

- [contracts/intake-session-contract.md](./contracts/intake-session-contract.md)
- [contracts/defense-review-contract.md](./contracts/defense-review-contract.md)
- [contracts/swarm-run-contract.md](./contracts/swarm-run-contract.md)
- [contracts/playground-package-contract.md](./contracts/playground-package-contract.md)

### Quickstart

Generate and maintain [quickstart.md](./quickstart.md) for:

- mirror verification
- concept intake walkthrough
- concept pack validation
- defense decision handling
- swarm run expectations
- playground review and follow-up

### Agent Context Update

Do not auto-write `AGENTS.md` from `update-agent-context.sh` for this feature. The repository marks its agent instructions as generated, so the active planning context should remain inside the Speckit package and supporting docs.

## Phase 2: Execution Readiness

### Stage 1: Factory Context And Templates

- update Moltinger’s role/context for factory intake
- define artifact templates and mirror validation
- extend fleet contracts for future production-stage roles

### Stage 2: Concept Intake And Artifact Generation

- collect concept context through Telegram
- persist versioned concept records
- generate synchronized project-doc/spec/presentation artifacts
- expose download-ready outputs

### Stage 3: Defense State Machine

- record defense decisions
- store structured feedback
- regenerate affected artifacts
- gate production until approval

### Stage 4: Swarm Orchestration

- launch coder/tester/validator/auditor/assembler stages
- preserve stage evidence and traceability
- escalate only blocker failures to admin

### Stage 5: Playground Packaging And Follow-Up

- produce runnable container bundle
- document synthetic/test data posture
- capture playground review feedback
- hand off deployment boundary to MVP1
