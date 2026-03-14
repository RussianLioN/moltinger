# Implementation Plan: Telegram Factory Adapter

**Branch**: `023-telegram-factory-adapter` | **Date**: 2026-03-14 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/023-telegram-factory-adapter/spec.md`

## Summary

Add the first live Telegram interface adapter for the factory business-analyst agent on `Moltis`. The adapter must turn real Telegram messages into `022` discovery-runtime turns, keep one active factory project per user/chat context, let the user review and confirm the brief inside Telegram, automatically trigger `handoff -> intake -> concept pack`, and deliver the resulting artifacts back in the same Telegram conversation without exposing repo paths, raw JSON, or internal errors.

## Technical Context

**Language/Version**: Bash 5.x, Python 3.11+, JSON/TOML/Markdown contracts  
**Primary Dependencies**: Moltis runtime with current Telegram channel config, existing `scripts/agent-factory-discovery.py`, `scripts/agent-factory-intake.py`, `scripts/agent-factory-artifacts.py`, shared helpers in `scripts/agent_factory_common.py`, current Bot API helper in `scripts/telegram-bot-send.sh`, official Telegram Bot API webhook/sendDocument behavior, MTProto helper scripts retained for live validation only  
**Storage**: Git-tracked planning artifacts, repo-local JSON state under `data/agent-factory/discovery/` plus new adapter-local state under `data/agent-factory/telegram/`, downstream concept-pack outputs under the existing factory output roots  
**Testing**: Shell-based `component`, `integration_local`, and `live_external` suites under `tests/`, fixture-driven Telegram adapter flows, existing static config validation, and downstream agent-factory compatibility tests  
**Target Platform**: Linux Docker-hosted Moltis runtime with Telegram bot as the first live interface adapter for the factory business-analyst agent  
**Project Type**: Documentation-driven script/config orchestration with a thin transport adapter layer  
**Performance Goals**: Each inbound Telegram message should produce one user-visible next-step response within the same adapter cycle; `confirmed brief` should immediately acknowledge downstream launch in-chat; concept-pack delivery should start automatically within the same orchestration chain that generated the artifacts  
**Constraints**: Russian-first user messaging; webhook-compatible transport semantics; no duplicate business-analysis logic outside `022`; no concept-pack generation before explicit brief confirmation; no filesystem paths, stack traces, or secrets in Telegram replies; Telegram remains the first live adapter, not the agent identity; pilot traffic is allowlisted and operator-controlled  
**Scale/Scope**: Pilot-scale usage for a small set of business users and operators; tens of active Telegram sessions are acceptable; one active project pointer per user by default; broader multi-channel abstraction stays out of this slice

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | PASS | Existing `022` discovery runtime, `020` downstream factory flow, current Telegram scripts, and current Moltis channel config were reviewed before filling the plan. |
| II. Single Source of Truth | PASS | The Telegram adapter is planned as a thin transport layer over the canonical discovery brief and canonical downstream handoff contracts. |
| III. Library-First Development | PASS | The design reuses the current Moltis Telegram channel, current Bot API helpers, and current MTProto live probes instead of introducing a separate bot framework stack. |
| IV. Code Reuse & DRY | PASS | Existing discovery, intake, artifacts, and helper modules stay authoritative; Telegram-specific behavior is limited to routing, rendering, and delivery glue. |
| V. Strict Type Safety | PASS | The plan defines explicit adapter entities, contracts, and state transitions before runtime changes. |
| VI. Atomic Task Execution | PASS | Work decomposes into setup, routing, confirmation, downstream delivery, recovery, and final validation slices. |
| VII. Quality Gates | PASS | The plan includes component, integration, and live validation tasks plus final prerequisite/topology checks. |
| VIII. Progressive Specification | PASS | The feature is moving through spec -> research -> plan -> tasks on its own dedicated branch. |
| IX. Error Handling | PASS | The adapter must return sanitized user-facing failures and preserve operator-visible provenance without leaking internal details. |
| X. Observability | PASS | Session routing, active project pointer, handoff state, and artifact delivery receipts are planned as first-class outputs. |
| XI. Accessibility | PASS | The feature is text-first, Russian-first, and optimized for non-technical business users inside an ordinary messenger chat. |

**Gate Status**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/023-telegram-factory-adapter/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── telegram-update-envelope-contract.md
│   ├── telegram-session-routing-contract.md
│   ├── telegram-brief-confirmation-contract.md
│   └── telegram-delivery-handoff-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
config/
└── moltis.toml

scripts/
├── agent-factory-discovery.py
├── agent-factory-intake.py
├── agent-factory-artifacts.py
├── agent-factory-telegram-adapter.py      # new thin Telegram adapter entrypoint
├── agent_factory_common.py
├── telegram-bot-send.sh
├── telegram-bot-send-document.sh          # new Bot API artifact delivery helper
├── telegram-real-user-e2e.py
└── manifest.json

docs/
└── runbooks/
    ├── agent-factory-discovery.md
    ├── agent-factory-prototype.md
    └── agent-factory-telegram-adapter.md  # new operator/user runbook

tests/
├── component/
│   ├── test_agent_factory_telegram_routing.sh
│   ├── test_agent_factory_telegram_intents.sh
│   ├── test_agent_factory_telegram_brief.sh
│   └── test_agent_factory_telegram_delivery.sh
├── integration_local/
│   ├── test_agent_factory_telegram_flow.sh
│   ├── test_agent_factory_telegram_discovery.sh
│   ├── test_agent_factory_telegram_confirmation.sh
│   ├── test_agent_factory_telegram_handoff.sh
│   └── test_agent_factory_telegram_resume.sh
├── live_external/
│   └── test_telegram_external_smoke.sh
└── fixtures/
    └── agent-factory/
        └── telegram/
            ├── README.md
            ├── update-new-project.json
            ├── update-discovery-answer.json
            ├── update-brief-confirm.json
            └── update-resume-status.json

data/
└── agent-factory/
    ├── discovery/
    └── telegram/
        ├── sessions/
        ├── deliveries/
        └── history/
```

**Structure Decision**: Reuse the existing script/config/test layout because the adapter is a transport and orchestration layer on top of already implemented factory runtimes, not a standalone application.

## Complexity Tracking

No constitution violations are required for this feature.

## Research Decisions

### Decision 1: Thin Telegram Adapter Over Existing Factory Runtime

**Chosen design**: Add one new adapter entrypoint that only normalizes Telegram updates, routes state, renders user-facing replies, and triggers the existing discovery/downstream scripts.

**Rationale**:

- `022` already owns conversational business-analysis logic.
- `020` already owns downstream concept-pack generation.
- A thin adapter keeps transport concerns isolated from the business-analysis and factory-generation core.

**Alternatives considered**:

- Rebuild discovery directly inside a Telegram bot service: rejected because it duplicates `022`.
- Add Telegram-only branches inside downstream scripts: rejected because it pollutes channel-neutral runtime logic with transport behavior.

### Decision 2: Webhook-Compatible Bot API As The Production-Side Delivery Path

**Chosen design**: Keep runtime delivery on the current Telegram Bot API path and design the adapter for webhook-compatible semantics.

**Rationale**:

- `config/moltis.toml` already keeps Telegram enabled and documents controlled webhook rollout.
- Official Telegram Bot API docs state that `setWebhook` pushes JSON updates to an HTTPS endpoint and can include a `secret_token` header for verification.
- The same official docs note that webhook mode and `getUpdates` cannot be used together, so the adapter should respect webhook-first ownership rather than inventing a polling side path.

**Alternatives considered**:

- Polling-first adapter: rejected because it conflicts with the repo's webhook rollout direction.
- Separate external queue bridge: rejected because it adds operational surface without solving a current repo constraint.

### Decision 3: Explicit Active Project Pointer Per Telegram User

**Chosen design**: Introduce one adapter-level `ActiveProjectPointer` so the user can start, continue, inspect, or reopen the current factory project from the same chat.

**Rationale**:

- Discovery and concept creation span many messages and may pause between sessions.
- The adapter needs a deterministic way to know which project or brief a free-form Telegram reply belongs to.
- This is the minimum viable session layer before any future multi-project UX.

### Decision 4: Bot API File Delivery For Concept-Pack Artifacts

**Chosen design**: Deliver the project doc, agent spec, and presentation back through Telegram using Bot API document delivery.

**Rationale**:

- Official Telegram Bot API docs state that `sendDocument` accepts uploaded files using `multipart/form-data`, which is sufficient for generated `.md`, `.pdf`, or archive-style user artifacts.
- The existing repo already has `telegram-bot-send.sh` for text delivery; a sibling helper keeps file delivery explicit and testable.
- This keeps the user in the same chat and removes operator copy-paste.

**Alternatives considered**:

- Return only links to repo paths: rejected because it is not a real user-facing experience and leaks internal storage assumptions.
- Deliver artifacts manually through operator scripts: rejected because it breaks the no-copy-paste requirement.

### Decision 5: Keep Telethon/MTProto Strictly For Live Validation

**Chosen design**: Reuse the existing Telethon-based scripts only for live smoke and real-user validation, not for the production adapter path.

**Rationale**:

- The repo already uses Bot API for the actual bot and Telethon/MTProto for `real_user` probes.
- Production adapter behavior should stay aligned with the real bot transport, while live tests can keep exercising the end-to-end user path.
- This avoids mixing operator test tooling with normal bot delivery semantics.

**Alternatives considered**:

- Use Telethon for the runtime adapter itself: rejected because it would shift the production path away from the current bot ownership model.
- Introduce `python-telegram-bot` or `aiogram`: rejected because the repo already has the needed channel ownership and helper surface.

## Phase 0: Research Decisions

Phase 0 is complete in [research.md](./research.md).

### Finalized Research Output

1. The new slice should be a Telegram adapter over the existing factory business-analyst runtime, not a new agent identity.
2. The adapter must stay webhook-compatible and Bot API-based for production-side delivery.
3. The adapter needs explicit session routing and active project pointers on top of the `022` discovery snapshot.
4. The user must stay inside Telegram for both brief confirmation and concept-pack delivery.
5. Live MTProto coverage should remain a validation tool, not the runtime transport.

## Phase 1: Design Artifacts

### Data Model

Generate and maintain [data-model.md](./data-model.md) for:

- `TelegramUpdateEnvelope`
- `TelegramAdapterSession`
- `ActiveProjectPointer`
- `TelegramIntent`
- `TelegramReplyPayload`
- `TelegramArtifactDelivery`
- `TelegramAdapterAuditRecord`
- `TelegramResumeSnapshot`

### Contracts

Generate and maintain:

- [contracts/telegram-update-envelope-contract.md](./contracts/telegram-update-envelope-contract.md)
- [contracts/telegram-session-routing-contract.md](./contracts/telegram-session-routing-contract.md)
- [contracts/telegram-brief-confirmation-contract.md](./contracts/telegram-brief-confirmation-contract.md)
- [contracts/telegram-delivery-handoff-contract.md](./contracts/telegram-delivery-handoff-contract.md)

### Quickstart

Generate and maintain [quickstart.md](./quickstart.md) for:

- adapter package validation
- Telegram message routing and discovery delegation
- brief review and confirmation inside Telegram
- automatic downstream handoff and artifact delivery
- resume, reopen, and live pilot validation boundaries

### Agent Context Update

Do not auto-write `AGENTS.md` from `update-agent-context.sh` for this feature. The repository treats agent instructions as generated; the active planning context must remain in the Speckit package, runbooks, and runtime docs.

## Phase 2: Execution Readiness

### Stage 1: Adapter Foundations

- point `config/moltis.toml` at the active Telegram adapter spec and storage roots
- add adapter entrypoints to `scripts/manifest.json`
- add Telegram adapter fixtures and test registrations

### Stage 2: Live Discovery Loop

- implement Telegram update normalization and active project routing
- map free-form Telegram answers into `scripts/agent-factory-discovery.py`
- render one next useful discovery message back to the user

### Stage 3: Brief Review And Confirmation

- render brief summaries into Telegram-friendly chunks
- support conversational corrections, explicit confirmation, and reopen actions
- keep confirmed brief versions aligned with `022` history rules

### Stage 4: Automatic Handoff And Delivery

- trigger `handoff -> intake -> artifacts` automatically after confirmed brief
- publish downstream status back into the same Telegram chat
- deliver the 3 concept-pack artifacts as Telegram documents

### Stage 5: Recovery And Pilot Validation

- resume interrupted Telegram sessions and preserve the active project pointer
- support brief reopen/status commands without losing provenance
- validate the adapter in local suites plus controlled live Telegram smoke
