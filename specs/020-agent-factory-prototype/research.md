# Research: Agent Factory Prototype

**Feature**: `020-agent-factory-prototype`  
**Date**: 2026-03-12  
**Status**: Complete  
**Purpose**: Capture the upstream ASC concept baseline, the current Moltinger platform baseline, and the concrete planning decisions required to start MVP0 prototype work without repeating discovery.

## 1. Executive Summary

The current repository already contains enough platform primitives to plan an AI agent factory prototype, but not enough product logic to claim the prototype exists yet.

The research resolves five planning decisions:

1. The prototype should start from **Telegram idea intake** inside Moltinger, not from a separate portal or local-only script.
2. The output of the intake stage must be a **synchronized concept pack** of three artifacts: project documentation, specification, and defense presentation.
3. The jump from concept to implementation must be protected by an explicit **defense decision gate**.
4. The production stage should reuse the existing **fleet control-plane baseline** and treat coder, tester, validator, auditor, and assembler as explicit stage owners, even if some roles begin as logical contracts before becoming permanent runtimes.
5. The current repository needed an in-repo **ASC documentation mirror** to avoid context loss and workstation-specific dependencies; that mirror has now been added.

## 2. Upstream ASC Baseline

The local mirror under `docs/asc-roadmap/` and `docs/concept/` was refreshed from upstream `ASC-AI-agent-fabrique` commit `54f359495b8926887dc8c632b74f95fee523b959`.

### Key planning evidence from mirrored docs

| Mirrored source | Key evidence | Planning impact |
|---|---|---|
| `docs/asc-roadmap/strategic_roadmap.md` | ASC frames work as a staged evolution from MVP0 prototype to scaling and only later to broader autonomy. | The current feature must stay inside MVP0 scope and stop before production deployment. |
| `docs/asc-roadmap/defense_poc_template.md` | Defense is a first-class pattern with preparation, artifact creation, presentation, feedback capture, and follow-up. | Concept approval needs its own explicit state machine and artifact versioning. |
| `docs/asc-roadmap/self_referential_mapping.md` | ASC explicitly maps separate roles for research, architecture, coding, testing, documentation, presentation, and agent development. | The prototype should model production as a specialized swarm, not as one generic “builder” step. |
| `docs/asc-roadmap/meta_block_registry.md` | Reusable patterns and dependencies matter as much as code generation itself. | The concept pack must preserve assumptions, risks, and applied factory patterns. |
| `docs/concept/ASC AI Fabrique 2.0 - Концепция фабрики развития.md` | The newer concept shifts from “just make an agent” toward “turn an idea into a governed initiative with measurable result.” | The intake stage must capture business ownership, effect expectations, and approval state, not only technical requirements. |
| `docs/concept/ASC AI Fabrique - Концепция автономной фабрики цифровых сотрудников.md` | The original concept still centers on autonomous specialized swarms, defense packaging, and containerized outputs. | The prototype still needs a demonstrable runnable result after approval, not just documents. |
| `docs/concept/ASC AI Fabrique 2.0 - План двухстраничной инфографической презентации для руководства.md` | The presentation should clearly communicate idea, value, constraints, and decision request without relying on unverified financial claims. | The prototype presentation contract should be defense-ready and decision-oriented by default. |

## 3. Current Repository Baseline

### What already exists and can be reused

#### Telegram-facing user/channel baseline

- `config/moltis.toml` already defines Moltinger as the user-facing runtime.
- `scripts/telegram-bot-send.sh`, `scripts/telegram-user-send.py`, `scripts/telegram-user-probe.py`, `scripts/telegram-real-user-e2e.py`, `scripts/telegram-web-user-probe.mjs`, and `scripts/telegram-e2e-on-demand.sh` already prove there is an operational Telegram ingress and evidence discipline.
- `.github/workflows/telegram-e2e-on-demand.yml` and `docs/telegram-e2e-on-demand.md` already define review-safe artifact handling around Telegram interactions.

#### Speckit and documentation workflow baseline

- `.specify/scripts/bash/create-new-feature.sh`
- `.specify/scripts/bash/setup-plan.sh`
- `.specify/scripts/bash/check-prerequisites.sh`
- `.specify/templates/spec-template.md`
- `.specify/templates/plan-template.md`
- `.specify/templates/tasks-template.md`
- existing `specs/*` packages across the repository

This means the repo already uses Speckit as an implementation contract and can support a full research/spec/plan/tasks cycle without new tooling.

#### Fleet control-plane baseline

- `config/fleet/agents-registry.json`
- `config/fleet/policy.json`
- `config/clawdiy/openclaw.json`
- `scripts/clawdiy-smoke.sh`
- `tests/integration_local/test_clawdiy_handoff.sh`
- `tests/integration_local/test_clawdiy_extraction_readiness.sh`
- `.github/workflows/deploy-clawdiy.yml`

This proves the repo already has:

- a coordinator runtime (`moltinger`)
- an existing coder runtime (`clawdiy`)
- an explicit handoff policy surface
- same-host and future-node topology awareness

### What is still missing

The repository does **not** yet contain:

- a runtime pipeline from Telegram dialogue to a three-artifact concept pack
- a defense outcome state machine for concept approval and rework
- a dedicated product-layer orchestration service for coder/tester/validator/auditor/assembler swarm execution
- a user-facing artifact download surface for concept pack plus playground bundle
- a Moltinger identity prompt that already positions the running assistant as an agent factory rather than primarily a DevOps assistant

## 4. Supporting Official Product Evidence

### Telegram Bot API

The official Telegram Bot API describes itself as an HTTP-based interface for building bots and documents file-delivery methods such as `sendDocument`. This is enough to treat Telegram as a viable delivery channel for downloadable artifacts without inventing a separate MVP0 portal.

Planning impact:

- user-facing artifact download can stay inside Telegram
- downloadable files are a supported requirement, not an ad hoc workaround

### Marp Markdown Presentation Ecosystem

The official Marp site documents a Markdown-first slide workflow and direct export to HTML, PDF, and PowerPoint. That makes Marp-compatible slide Markdown the best planning baseline for the defense presentation artifact because it preserves:

- editable source form
- exportable review format
- low-friction diffability inside git

Planning impact:

- treat the presentation artifact as source-first Markdown with exportable outputs
- avoid locking MVP0 to a binary-first presentation workflow

## 5. Decision Log

### 5.1 Intake Channel

**Decision**: Use Moltinger’s Telegram-facing experience as the primary intake path for concept creation.

**Rationale**:

- It matches the user request.
- The repository already has Telegram UAT, review-safe artifact handling, and operator workflows.
- It minimizes new surface area compared with building a separate UI first.

**Alternatives considered**:

- Separate web portal first: rejected as unnecessary scope expansion for MVP0.
- Local CLI-only prototype: rejected because it would not satisfy the user-facing Telegram requirement.

### 5.2 Artifact Bundle Model

**Decision**: Use a source-first artifact bundle consisting of project documentation, agent specification, and presentation, kept synchronized through one canonical concept record.

**Rationale**:

- Keeps concept, scope, and approval discussion aligned.
- Supports versioning and rework.
- Matches ASC emphasis on concept packaging before autonomous execution.

**Alternatives considered**:

- Single all-in-one document: rejected because defense, specification, and project framing have different audiences.
- Binary-first office artifacts only: rejected because they are hard to diff, version, and regenerate.

### 5.3 Presentation Export Posture

**Decision**: Plan around a Marp-compatible Markdown slide source for the presentation artifact.

**Rationale**:

- The official Marp toolchain supports export to HTML, PDF, and PowerPoint.
- Markdown source fits the repo’s documentation-first workflow.
- It preserves both editability and downloadability.

**Alternatives considered**:

- Hand-authored PPTX only: rejected because it weakens traceability and source control ergonomics.
- HTML-only deck: rejected because defense workflows often require downloadable presentation files.

### 5.4 Approval Gate

**Decision**: Insert an explicit defense decision gate between concept-pack creation and swarm execution.

**Rationale**:

- The upstream ASC defense template makes approval and feedback a formal control point.
- The user explicitly describes protection before “command on production” and later MVP1 deploy.
- It prevents outdated or weak concepts from triggering autonomous production.

### 5.5 Production Swarm Posture

**Decision**: Model coder, tester, validator, auditor, and assembler as explicit production-stage owners. Reuse the current fleet registry/policy as the initial control-plane baseline.

**Rationale**:

- The repo already has a coordinator+coder baseline.
- Future-role examples already exist in `config/fleet/agents-registry.json`.
- This lets the prototype start with contractual stage semantics even before every role becomes its own long-lived runtime.

### 5.6 Prototype Terminal Output

**Decision**: The terminal output of MVP0 is a runnable playground package and evidence bundle, not production deployment.

**Rationale**:

- The user explicitly says deployment belongs to MVP1.
- The upstream ASC material treats demonstrable packaging and defense readiness as legitimate MVP proof.
- This keeps the prototype bounded and demonstrable.

### 5.7 Context Mirror

**Decision**: Keep a curated local mirror of relevant ASC roadmap/concept docs inside this repository and record provenance in `docs/ASC-AI-FABRIQUE-MIRROR.md`.

**Rationale**:

- The user explicitly requested a project-local copy.
- Existing plans were still referencing `/Users/.../ASC-AI-agent-fabrique`.
- Future planning sessions need stable in-repo paths.

## 6. Planning Inputs For The Next Phase

The plan and tasks phases should treat the following as required inputs:

- [spec.md](./spec.md)
- [../../docs/ASC-AI-FABRIQUE-MIRROR.md](../../docs/ASC-AI-FABRIQUE-MIRROR.md)
- [../../docs/plans/parallel-doodling-coral.md](../../docs/plans/parallel-doodling-coral.md)
- [../../docs/plans/agent-factory-lifecycle.md](../../docs/plans/agent-factory-lifecycle.md)
- [../../config/moltis.toml](../../config/moltis.toml)
- [../../config/fleet/agents-registry.json](../../config/fleet/agents-registry.json)
- [../../config/fleet/policy.json](../../config/fleet/policy.json)
- [../../config/clawdiy/openclaw.json](../../config/clawdiy/openclaw.json)
- [../../docs/telegram-e2e-on-demand.md](../../docs/telegram-e2e-on-demand.md)

## 7. Research Outcome

No blocking clarification is required to continue into `plan.md` and `tasks.md`.

The feature can proceed with these working assumptions:

- Telegram is the intake and delivery channel.
- The concept pack is the mandatory gateway output.
- Approval is explicit before swarm execution.
- The swarm ends at a playground package, not deployment.
- The repo-local ASC mirror is now part of the implementation contract.
