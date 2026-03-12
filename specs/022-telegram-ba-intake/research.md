# Research: Telegram Business Analyst Intake

**Feature**: `022-telegram-ba-intake`  
**Date**: 2026-03-13  
**Status**: Complete  
**Purpose**: Capture the product and technical decisions needed to add a conversational Telegram business-analyst layer ahead of the existing `020-agent-factory-prototype` concept-pack flow.

## 1. Executive Summary

The repository already contains the downstream factory prototype, Telegram channel ownership, and artifact-generation logic, but it still lacks the upstream conversational discovery layer that the user actually expects.

This research resolves six planning decisions:

1. The new slice must start from a real Telegram discovery session, not from a pre-filled JSON request.
2. The output of discovery must be a confirmed requirements brief, not immediate concept artifacts.
3. The confirmed brief becomes the new single source of truth between user dialogue and concept-pack generation.
4. The feature should reuse existing Moltis Telegram ownership and current agent-factory scripts instead of introducing a second bot stack.
5. The slice should be text-first, Russian-first, and safe-data-first.
6. Resume, reopen, and versioning are mandatory because business discovery is iterative by nature.

## 2. Current Gap To Close

The current `020-agent-factory-prototype` slice already states that intake should happen through a multi-turn Telegram dialogue, but the implemented runtime only normalizes a supplied payload and returns `follow_up_questions` if critical fields are missing.

Planning impact:

- the missing product capability is not downstream swarm orchestration
- the missing product capability is the conversational business-analyst frontend
- the new feature should prepare and confirm requirements before the existing concept-pack pipeline begins

## 3. Repository Baseline

### What already exists and can be reused

#### Telegram runtime ownership

- `config/moltis.toml` already contains the active Telegram channel configuration for Moltinger.
- `scripts/telegram-bot-send.sh`, `scripts/telegram-user-send.py`, `scripts/telegram-user-probe.py`, and `scripts/telegram-real-user-e2e.py` already prove there is an established transport and UAT surface.
- Existing Telegram monitoring scripts and tests mean this feature does not need to invent a new delivery/auth path.

#### Existing downstream factory flow

- `scripts/agent-factory-intake.py`
- `scripts/agent-factory-artifacts.py`
- `scripts/agent-factory-review.py`
- `scripts/agent-factory-swarm.py`
- `scripts/agent-factory-playground.py`
- `docs/runbooks/agent-factory-prototype.md`
- `specs/020-agent-factory-prototype/`

This means the repo already knows how to:

- normalize a structured request
- generate concept artifacts
- gate review and approval
- run a prototype swarm
- publish a playground bundle

The missing piece is the upstream guided discovery layer that produces a trustworthy input for these stages.

### What is still missing

The repository does **not** yet contain:

- a persistent discovery-session state model
- a topic-by-topic business interview flow for Telegram
- a confirmed requirements brief separate from later concept artifacts
- a handoff contract from discovery into the existing concept-pack generator
- recovery semantics for interrupted discovery or reopened confirmed briefs

## 4. Decision Log

### 4.1 Discovery Starts Before Intake Normalization

**Decision**: Add a new discovery-session workflow before the current intake normalization step.

**Rationale**:

- The user explicitly expects the agent to ask guiding questions like a business analyst.
- The current intake script is useful as a normalization bridge, but not as the full user experience.
- Discovery must stay conversational until the user confirms the brief.

**Alternatives considered**:

- Extend the current intake JSON fixture only: rejected because it still depends on off-platform preparation.
- Ask the user to fill a form first: rejected because it does not match the intended Telegram dialogue model.

### 4.2 Confirmed Brief As New Canonical Boundary

**Decision**: Introduce a confirmed requirements brief as the canonical upstream artifact for the factory.

**Rationale**:

- Free-form dialogue is too unstable to act as a direct production input.
- A confirmed brief gives the user one understandable review surface before concept artifacts are generated.
- Downstream concept pack, defense, and swarm stages can then remain unchanged in principle.

### 4.3 Reuse Existing Telegram Ownership

**Decision**: Reuse the existing Moltis Telegram channel instead of adopting a second bot framework or separate service.

**Rationale**:

- Telegram ownership, auth, and observability already exist in the current repo.
- A separate bot runtime would fragment transport semantics and operator tooling.
- The value here is the discovery logic, not transport reinvention.

**Alternatives considered**:

- Separate Python Telegram service: rejected because it duplicates auth, monitoring, and deployment ownership.
- Web UI first: rejected because it delays the requested Telegram-first experience.

### 4.4 Text-First, Safe-Data Discovery MVP

**Decision**: The discovery slice should start with text answers and manually provided examples, while explicitly discouraging live sensitive business data.

**Rationale**:

- Text-only is enough to validate the business-analyst interaction model.
- It keeps the first implementation focused on state, clarification quality, and confirmation.
- It aligns with the prototype’s existing synthetic/sanitized-data posture.

### 4.5 Resume And Reopen Are Mandatory

**Decision**: Treat interrupted sessions and reopened confirmed briefs as planned states, not exceptional recovery flows.

**Rationale**:

- Real business discovery often spans multiple conversations.
- Users need to check process details internally and come back with corrections.
- Hiding this under manual recovery would weaken trust and traceability.

### 4.6 No Blocking Clarifications Remain

**Decision**: Planning can proceed without pausing for further clarification.

**Rationale**:

- The user made the main intent explicit: the first agent is a business analyst that elicits requirements and forms a technical assignment.
- The repo already contains a downstream concept-pack flow to hand off into.
- The correct scope boundary is now clear: discovery, confirmation, and handoff, but not defense/swarm/deploy.

## 5. Planning Inputs For The Next Phase

The planning and tasks phases should treat the following as required inputs:

- [spec.md](./spec.md)
- [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)
- [../../docs/runbooks/agent-factory-prototype.md](../../docs/runbooks/agent-factory-prototype.md)
- [../../config/moltis.toml](../../config/moltis.toml)
- `scripts/agent-factory-intake.py`
- `scripts/agent-factory-artifacts.py`
- `scripts/agent_factory_common.py`
- existing Telegram transport and probe scripts under `scripts/telegram-*`

## 6. Research Outcome

No blocking clarification is required before `plan.md` and `tasks.md`.

The feature can proceed with these working assumptions:

- the first user-facing value is a guided business interview in Telegram
- the canonical output of that interview is a confirmed requirements brief
- the confirmed brief feeds the already existing concept-pack pipeline
- the feature should extend the current repo’s script/config/test layout rather than create a parallel application
