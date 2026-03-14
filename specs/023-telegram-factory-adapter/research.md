# Research: Telegram Factory Adapter

**Feature**: `023-telegram-factory-adapter`  
**Date**: 2026-03-14  
**Status**: Complete  
**Purpose**: Capture the product and technical decisions needed to add the preserved follow-up Telegram adapter over the already implemented factory business-analyst runtime and downstream concept-pack pipeline.

## 1. Executive Summary

The repository now has the channel-neutral discovery runtime in `022-telegram-ba-intake`, the downstream concept-pack factory in `020-agent-factory-prototype`, and the new primary web-first demo path planning in `024-web-factory-demo-adapter`. This package remains the preserved follow-up Telegram adapter that lets an ordinary business user run the same flow in Telegram when that transport becomes the next priority.

This research resolves six planning decisions:

1. Telegram remains worth implementing as a follow-up live interface adapter, not as a separate agent identity.
2. The adapter should remain thin and reuse the existing discovery, intake, and artifact scripts.
3. Production-side transport should remain Bot API/webhook-compatible, aligned with the current Moltis Telegram channel ownership.
4. The adapter needs an explicit session-routing layer over discovery snapshots so a Telegram reply always maps to the correct project and brief version.
5. Concept-pack artifacts must be returned to the user through Telegram document delivery, not through repo-local paths.
6. Telethon/MTProto should remain a live validation tool, not the runtime transport for the bot itself.

## 2. Current Gap To Close

The current `022` slice proves that the factory business-analyst agent can:

- open a discovery session from a raw idea
- guide a requirements interview
- build and confirm a brief
- emit one canonical downstream handoff

But the user still cannot exercise that flow as a real end user in Telegram because:

- there is no adapter that accepts real Telegram updates and maps them into the discovery runtime
- there is no active project pointer that binds a Telegram chat to the current factory project
- there is no Bot API document-delivery step for the generated concept-pack artifacts

Planning impact:

- the missing feature is no longer discovery logic
- the missing feature is the Telegram transport and user-facing delivery layer on top of discovery
- the adapter must be explicitly scoped as transport/routing/presentation glue, not as a new business-analysis core

## 3. Repository Baseline

### What already exists and can be reused

#### Existing factory runtime

- `scripts/agent-factory-discovery.py`
- `scripts/agent-factory-intake.py`
- `scripts/agent-factory-artifacts.py`
- `scripts/agent_factory_common.py`
- `docs/runbooks/agent-factory-discovery.md`
- `docs/runbooks/agent-factory-prototype.md`
- `specs/022-telegram-ba-intake/`
- `specs/020-agent-factory-prototype/`

This means the repo already knows how to:

- guide the discovery conversation
- version and confirm a brief
- create a canonical handoff record
- normalize that handoff into the downstream concept-pack context
- generate the 3 downloadable artifacts

#### Existing Telegram operational surface

- `config/moltis.toml` already enables `channels.telegram`
- `scripts/telegram-bot-send.sh`
- `scripts/telegram-webhook-control.sh`
- `scripts/telegram-webhook-monitor.sh`
- `scripts/telegram-real-user-e2e.py`
- `scripts/telegram-user-send.py`
- `tests/live_external/test_telegram_external_smoke.sh`
- `specs/004-telegram-e2e-harness/spec.md`

This means the repo already has:

- real Telegram bot configuration in Moltis
- operational scripts for webhook control and monitoring
- a Bot API send helper for text messages
- MTProto-based live probes for real-user validation

### What is still missing

The repository does **not** yet contain:

- a dedicated Telegram adapter entrypoint that talks to the discovery runtime
- adapter-level state for `user/chat -> active project -> active brief`
- a Bot API file-delivery helper for the concept-pack artifacts
- Telegram-specific tests for routing, confirmation, downstream delivery, and resume/reopen behavior
- a Telegram adapter runbook for operators and pilot users

## 4. Official Telegram Constraints Relevant To This Slice

### 4.1 Webhook behavior

Official Telegram Bot API documentation states that:

- `setWebhook` is the mechanism for push delivery of updates to an HTTPS endpoint
- `secret_token` can be specified so each webhook request includes the `X-Telegram-Bot-Api-Secret-Token` header
- `getUpdates` cannot be used while a webhook is active

Planning impact:

- the adapter should be designed as webhook-compatible, not as a long-polling sidecar
- request verification should respect the existing webhook contract already signaled in `config/moltis.toml`
- the slice should not plan a second inbound mode that conflicts with the bot's current operational direction

### 4.2 Artifact delivery

Official Telegram Bot API documentation states that `sendDocument` supports file uploads using `multipart/form-data` and accepts general files.

Planning impact:

- delivery of `project doc`, `agent spec`, and `presentation` can stay inside Telegram
- artifact delivery does not require inventing a web download portal in this slice
- a dedicated helper should be added next to `telegram-bot-send.sh` rather than pushing file-delivery logic into the discovery core

## 5. Decision Log

### 5.1 Telegram As First Live Adapter, Not New Agent Identity

**Decision**: Keep the factory business-analyst agent on `Moltis` as the main actor and implement Telegram only as a follow-up live user interface adapter after the web-first pivot.

**Rationale**:

- The user explicitly clarified that the agent is the factory digital employee, not the messenger bot itself.
- `022` already makes the business-analysis logic channel-neutral.
- This keeps future Moltinger UI or other adapters possible without invalidating the core agent model.

### 5.2 Thin Adapter Over Existing Runtime

**Decision**: Add one adapter entrypoint that delegates to `scripts/agent-factory-discovery.py`, `scripts/agent-factory-intake.py`, and `scripts/agent-factory-artifacts.py` instead of rebuilding their logic.

**Rationale**:

- The repo already has the needed core behaviors.
- Reuse keeps the adapter easy to reason about and minimizes drift.
- This is the cleanest way to honor the `Telegram adapter, not Telegram-only agent` boundary.

### 5.3 Reuse Current Bot API Surface Instead Of Adding A New Bot Framework

**Decision**: Reuse the current Telegram Bot API operational surface and helper scripts rather than introducing a new framework such as `python-telegram-bot` or `aiogram`.

**Rationale**:

- The repo already has the actual bot transport and monitoring surface.
- A second framework would duplicate auth, webhook ownership, and operational behavior.
- The feature's value is in factory routing and user experience, not in framework migration.

**Alternatives considered**:

- `python-telegram-bot`: rejected because it would introduce a parallel app/runtime stack around an already working channel.
- `aiogram`: rejected for the same reason.
- direct MTProto runtime bot: rejected because the current bot path is Bot API-based, while MTProto is already used as a validation path only.

### 5.4 Active Project Pointer Is Mandatory

**Decision**: Introduce one adapter-level `ActiveProjectPointer` per Telegram user/chat context.

**Rationale**:

- Free-form user replies in a messenger need deterministic project routing.
- The adapter must know whether the next user message is answering a discovery question, correcting a brief, confirming a brief, or asking for status.
- Resume and reopen behavior become much simpler and more trustworthy with an explicit pointer.

### 5.5 Telegram Must Deliver The Result, Not Just Trigger The Backend

**Decision**: The adapter must return the generated concept-pack artifacts back to the user in Telegram as the visible outcome of a successful handoff.

**Rationale**:

- Otherwise the user still depends on operator-side file handling.
- Delivering the artifacts in the same chat is the first real proof that the adapter works for non-technical users.
- This is the natural continuation of the `no manual copy-paste` requirement.

### 5.6 Keep Telethon For Live Probes Only

**Decision**: Keep `telethon`/MTProto limited to live validation and operator probes.

**Rationale**:

- The repo already uses Telethon successfully for `real_user` E2E checks.
- That is valuable for UAT, but it should not become the normal runtime transport for the bot.
- Separating runtime transport from validation transport keeps the architecture cleaner and more operable.

## 6. Planning Inputs For The Next Phase

The planning and tasks phases should treat the following as required inputs:

- [spec.md](./spec.md)
- [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md)
- [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)
- [../../config/moltis.toml](../../config/moltis.toml)
- [../../docs/runbooks/agent-factory-discovery.md](../../docs/runbooks/agent-factory-discovery.md)
- [../../docs/runbooks/agent-factory-prototype.md](../../docs/runbooks/agent-factory-prototype.md)
- `scripts/agent-factory-discovery.py`
- `scripts/agent-factory-intake.py`
- `scripts/agent-factory-artifacts.py`
- `scripts/agent_factory_common.py`
- `scripts/telegram-bot-send.sh`
- `scripts/telegram-real-user-e2e.py`
- `tests/live_external/test_telegram_external_smoke.sh`

## 7. Research Outcome

No blocking clarification remains before `plan.md`, `data-model.md`, `contracts/`, `quickstart.md`, and `tasks.md`.

The feature can proceed with these working assumptions:

- Telegram remains a valid follow-up live user adapter for the existing factory business-analyst agent.
- The adapter must stay transport-focused and must not reimplement discovery or concept generation.
- Production-side delivery should stay Bot API/webhook-compatible.
- The adapter must return the generated concept-pack artifacts back to the user in Telegram.
- Live MTProto coverage remains important, but only as a validation path.

## 8. Primary Sources

- Telegram Bot API manual: https://core.telegram.org/bots/api
- Telegram webhook guide: https://core.telegram.org/bots/webhooks
