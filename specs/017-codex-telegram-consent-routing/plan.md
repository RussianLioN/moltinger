# Implementation Plan: Codex Telegram Consent Routing

**Branch**: `017-codex-telegram-consent-routing` | **Date**: 2026-03-12 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/017-codex-telegram-consent-routing/spec.md`

## Summary

Repair the Codex watcher Telegram UX by moving consent/follow-up routing into the authoritative Moltis Telegram ingress, replacing ambiguous free-text replies with correlated actions, and sending practical recommendations immediately after valid acceptance. The watcher remains the producer of alerts and prepared recommendation payloads, but it no longer acts like a second production consumer of Telegram updates.

## Technical Context

**Language/Version**: Bash operational scripts plus existing Moltis runtime/config surfaces  
**Primary Dependencies**: `bash`, `jq`, `python3`, `config/moltis.toml`, `scripts/codex-cli-upstream-watcher.sh`, `scripts/telegram-bot-send.sh`, `scripts/telegram-bot-send-remote.sh`, `scripts/telegram-e2e-on-demand.sh`, `.github/workflows/deploy.yml`  
**Storage**: Shared consent store JSON file, watcher report JSON, Telegram interaction artifacts, config and docs  
**Testing**: Bash syntax checks, targeted component tests, and live or hermetic Telegram E2E acceptance through the existing harness  
**Target Platform**: Moltis runtime on the server plus local/CI-safe fixture validation  
**Project Type**: Operational shell + Moltis runtime integration + Telegram UX + docs  
**Performance Goals**: Consent routing and follow-up delivery should complete fast enough to feel immediate to the user  
**Constraints**: One authoritative inbound owner, no second live Telegram consumer in production, Russian human-facing UX, GitOps-managed rollout, duplicate-safe and expiry-safe consent handling, MTProto reserved for validation rather than production routing  
**Scale/Scope**: One bot, one alert source (`012` watcher), one shared consent store, one live acceptance path

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (`012` watcher, Telegram docs, E2E harness, runtime config, and webhook/polling constraints were reviewed before planning).
- Single Source of Truth: PASS (main Moltis Telegram ingress becomes the authoritative owner of inbound consent events).
- Library-First Development: PASS (reuse existing Moltis runtime/config, Telegram sender, and E2E harness before inventing new infrastructure).
- Code Reuse & DRY: PASS (the watcher keeps preparing alert content while the main runtime handles inbound consent; no second reply-consumer should be introduced).
- Strict Type Safety: PASS via JSON contract for the shared consent record.
- Atomic Task Execution: PASS (deliver store + routing + follow-up + E2E in ordered slices).
- Quality Gates: PASS (syntax checks, component tests, and live acceptance are planned before push).
- Progressive Specification: PASS (this feature is being packaged after an incident-style consilium rather than coded ad hoc).

No constitution violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/017-codex-telegram-consent-routing/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- consent-store-record.schema.json
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Source Code (planned touch points)

```text
scripts/
|-- codex-cli-upstream-watcher.sh
|-- telegram-bot-send.sh
|-- telegram-bot-send-remote.sh
|-- telegram-e2e-on-demand.sh
|-- telegram-real-user-e2e.py
|-- moltis-codex-consent-router.sh            # planned
|-- codex-telegram-consent-store.sh           # planned
`-- manifest.json

tests/
|-- component/
|   |-- test_codex_cli_upstream_watcher.sh
|   |-- test_telegram_bot_send_remote.sh
|   `-- test_moltis_codex_consent_router.sh   # planned
`-- fixtures/
    `-- codex-telegram-consent-routing/       # planned

config/
`-- moltis.toml

docs/
|-- codex-cli-upstream-watcher.md
`-- telegram-e2e-on-demand.md
```

**Structure Decision**: Keep the watcher as an alert producer and recommendation preparer, but introduce a dedicated authoritative consent-routing layer attached to the main Moltis Telegram ingress. Prefer inline callback actions as the user-facing control, and keep a structured command fallback for constrained clients or degraded paths.

## Phase 0: Research Decisions (to `research.md`)

1. Make the main Moltis Telegram ingress the authoritative owner of Codex consent replies.
2. Prefer inline callback actions for consent UX, with a tokenized command fallback.
3. Store consent state in one shared, machine-readable record outside watcher-local state.
4. Remove watcher-side production reply polling from the happy path.
5. Send recommendations immediately after acceptance instead of waiting for a later scheduler run.
6. Keep MTProto/`real_user` for E2E validation only.
7. Fail safe to one-way alerts when authoritative consent routing is unavailable.

## Phase 1: Design Artifacts

- Data model for consent requests, decision routing, shared consent store, action tokens, and recommendation delivery outcomes.
- JSON schema for one authoritative consent-store record.
- Quickstart for manual validation, degraded fallback, and live acceptance.
- Tasks grouped by routing ownership, inline action UX, immediate follow-up delivery, and live acceptance.

## Phase 2: Execution Readiness

- One shared consent router becomes the only production owner of Codex Telegram consent replies.
- The watcher emits consent-capable alerts only when that router is available and healthy.
- The second message with practical recommendations is delivered from the authoritative runtime path.
- Live acceptance is validated through the existing Telegram E2E harness, not only through fixture files.
