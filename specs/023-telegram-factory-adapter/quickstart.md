# Quickstart: Telegram Factory Adapter

## Purpose

This quickstart validates the first live Telegram adapter layer on top of the factory business-analyst runtime.

It confirms six things:

1. Telegram is implemented as the first live adapter, not as the agent identity
2. real Telegram messages can be routed into the existing discovery runtime
3. the user can review and confirm the brief inside Telegram
4. confirmation automatically launches the downstream factory pipeline
5. the 3 concept-pack artifacts return to the user through Telegram
6. resume, reopen, and live pilot boundaries remain explicit and traceable

## 1. Verify Package Integrity

Run:

```bash
git status --short specs/023-telegram-factory-adapter docs/GIT-TOPOLOGY-REGISTRY.md
.specify/scripts/bash/check-prerequisites.sh --json --include-tasks
rg -n "023-telegram-factory-adapter|Telegram Factory Adapter" \
  specs/023-telegram-factory-adapter/spec.md \
  specs/023-telegram-factory-adapter/plan.md \
  specs/023-telegram-factory-adapter/research.md \
  specs/023-telegram-factory-adapter/data-model.md \
  specs/023-telegram-factory-adapter/contracts \
  specs/023-telegram-factory-adapter/quickstart.md \
  specs/023-telegram-factory-adapter/tasks.md
```

Expected result:

- the Speckit package exists for `023-telegram-factory-adapter`
- planning artifacts clearly reference `022` as the upstream discovery runtime
- the package clearly references `020` as the downstream concept-pack pipeline

## 2. Validate Adapter Scope Against Existing Runtime

Use:

- [spec.md](./spec.md)
- [research.md](./research.md)
- [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md)
- [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)

Expected design boundary:

1. Telegram owns transport, session routing, user-facing rendering, and delivery.
2. `022` owns discovery, brief generation, confirmation history, and canonical handoff creation.
3. `020` owns concept-pack generation, defense, swarm, and playground packaging.

Validation questions:

- Does the adapter stay thin?
- Is the agent identity still factory-owned on `Moltis`?
- Are webhook and artifact-delivery concerns isolated from the discovery core?

## 3. Validate Telegram Message Routing

Use:

- [contracts/telegram-update-envelope-contract.md](./contracts/telegram-update-envelope-contract.md)
- [contracts/telegram-session-routing-contract.md](./contracts/telegram-session-routing-contract.md)

Target runtime command after implementation:

```bash
python3 scripts/agent-factory-telegram-adapter.py handle-update \
  --source tests/fixtures/agent-factory/telegram/update-new-project.json \
  --output /tmp/telegram-adapter-out.json
```

Expected result:

- the adapter creates or restores one active project pointer
- the first reply sent back to the user is the next useful discovery question
- no raw internal JSON is shown to the user

Validation questions:

- Can a raw Telegram message start a new factory project?
- Does the adapter preserve the chat/user context needed for resume?
- Does unsupported input get a polite fallback rather than silence?

## 4. Validate Brief Review And Confirmation In Telegram

Use:

- [contracts/telegram-brief-confirmation-contract.md](./contracts/telegram-brief-confirmation-contract.md)

Target runtime command after implementation:

```bash
python3 scripts/agent-factory-telegram-adapter.py handle-update \
  --source tests/fixtures/agent-factory/telegram/update-brief-confirm.json \
  --output /tmp/telegram-brief-confirm.json
```

Expected result:

- the brief is rendered into Telegram-readable chunks
- conversational correction requests are accepted and routed back to discovery
- explicit confirmation or reopen intent updates the linked brief version correctly

Validation questions:

- Does the user know exactly what is being confirmed?
- Can the user ask for corrections without leaving Telegram?
- Is reopen treated as versioned history rather than in-place mutation?

## 5. Validate Automatic Handoff And Artifact Delivery

Use:

- [contracts/telegram-delivery-handoff-contract.md](./contracts/telegram-delivery-handoff-contract.md)
- [../020-agent-factory-prototype/quickstart.md](../020-agent-factory-prototype/quickstart.md)

Target runtime chain after implementation:

```bash
python3 scripts/agent-factory-telegram-adapter.py handle-update \
  --source tests/fixtures/agent-factory/telegram/update-brief-confirm.json \
  --output /tmp/telegram-delivery-out.json
```

Expected result:

- the adapter acknowledges downstream launch in Telegram
- the existing handoff/intake/artifact chain runs without manual copy-paste
- the user receives:
  - project doc
  - agent spec
  - presentation

Validation questions:

- Is downstream generation blocked until the brief is confirmed?
- Do all 3 artifacts arrive back through Telegram?
- Can an operator trace artifact provenance back to the Telegram conversation and brief version?

## 6. Validate Resume And Reopen

Use:

- [contracts/telegram-session-routing-contract.md](./contracts/telegram-session-routing-contract.md)
- [data-model.md](./data-model.md)

Target runtime command after implementation:

```bash
python3 scripts/agent-factory-telegram-adapter.py handle-update \
  --source tests/fixtures/agent-factory/telegram/update-resume-status.json \
  --output /tmp/telegram-resume-out.json
```

Expected result:

- the adapter restores the active project pointer
- the user sees the pending question, pending clarification, or current downstream status
- reopen preserves prior confirmation and handoff history

Validation questions:

- Does resume continue the same project rather than starting over?
- Does `/status` show the current phase without mutating state?
- Does reopen create a new active version chain?

## 7. Validate Controlled Live Pilot Boundaries

Use:

- [../../tests/live_external/test_telegram_external_smoke.sh](../../tests/live_external/test_telegram_external_smoke.sh)
- [../../config/moltis.toml](../../config/moltis.toml)

Target live validation after implementation:

```bash
./tests/run.sh --lane telegram_live --live --filter telegram_external_smoke --json
```

Expected result:

- Telegram transport remains healthy
- live pilot checks can reach the bot
- real-user validation stays separate from normal runtime routing

Validation questions:

- Is the live pilot still operator-controlled and allowlisted?
- Do live artifacts remain sanitized?
- Does live validation avoid changing the normal bot ownership model?

## 8. Current Readiness Check

Confirm:

- [x] the feature has a complete spec package
- [x] the adapter scope is explicitly separated from `022` and `020`
- [x] Telegram is defined as the first live adapter, not as the agent identity
- [x] automatic downstream launch and in-chat artifact delivery are part of the contract
- [x] resume, reopen, and live pilot validation are first-class concerns

## 9. Handoff Rule

This feature is ready for implementation only when:

1. `tasks.md` exists and preserves the thin-adapter boundary
2. runtime work updates both this package and the upstream/downstream packages if shared contracts change
3. topology documentation is refreshed after branch or worktree mutations
4. the implementation adds matching fixtures and tests for routing, confirmation, delivery, and resume behavior

## 10. Clarification Guard

For this package, interpret `023-telegram-factory-adapter` as:

- first live Telegram adapter for the factory business-analyst agent on `Moltis`
- one interface layer over the existing discovery and factory runtimes
- a pilot-scale user-facing slice, not a new standalone bot product or a generalized multi-channel platform
