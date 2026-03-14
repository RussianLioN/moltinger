# Research: Web Factory Demo Adapter

**Feature**: `024-web-factory-demo-adapter`  
**Date**: 2026-03-14  
**Status**: Complete  
**Purpose**: Capture the product and technical decisions needed to pivot the near-term demo path from Telegram-first to web-first while preserving the already prepared Telegram transport scope as follow-up work.

## 1. Executive Summary

The repository already has:

- the channel-neutral discovery runtime in `022-telegram-ba-intake`
- the downstream concept-pack factory in `020-agent-factory-prototype`
- the planned Telegram transport slice in `023-telegram-factory-adapter`

What it does not yet have is a browser-accessible demo surface that business users can reliably open from a constrained corporate environment.

This research resolves six planning decisions:

1. The near-term primary demo path should move to a dedicated web subdomain.
2. The web surface should remain a thin adapter over the existing factory runtime.
3. Same-host subdomain deployment is the fastest reliable publish pattern already proven in the repo.
4. The browser flow should rely on ordinary HTTPS request/response semantics, not websocket-only assumptions.
5. A static browser shell plus thin adapter is a better fit than introducing a new frontend application stack.
6. Telegram should remain preserved in `023` as a follow-up transport slice, not be discarded.

## 2. Current Gap To Close

The current state after `022` and `020`:

- the factory can run a discovery interview
- generate and confirm a brief
- emit one canonical handoff
- create the 3 concept-pack artifacts downstream

The current gap is not in discovery logic or downstream artifact logic.

The gap is in the user-facing demo surface:

- ordinary business users still do not have a browser-based entrypoint
- Telegram may be awkward or unavailable in the target corporate contour
- no dedicated demo subdomain exists yet for the factory workflow itself

Planning impact:

- the next slice should solve accessibility and demo reliability first
- the adapter must remain transport/presentation glue, not a new factory core
- `023` should stay as preserved follow-up transport scope for later Telegram delivery

## 3. Repository Baseline

### 3.1 Existing factory runtime that can be reused

- `scripts/agent-factory-discovery.py`
- `scripts/agent-factory-intake.py`
- `scripts/agent-factory-artifacts.py`
- `scripts/agent_factory_common.py`
- `docs/runbooks/agent-factory-discovery.md`
- `docs/runbooks/agent-factory-prototype.md`
- `specs/022-telegram-ba-intake/`
- `specs/020-agent-factory-prototype/`

This means the repo already knows how to:

- guide discovery turns
- maintain topic progress
- version and confirm a brief
- emit one canonical handoff record
- generate the 3 downstream concept-pack artifacts

### 3.2 Existing deployment baseline that supports a dedicated subdomain

- `docker-compose.prod.yml` proves the primary Moltis service already runs behind Traefik.
- `docker-compose.clawdiy.yml` proves the repo already supports a second long-lived same-host service on its own subdomain with health check, Traefik labels, and dedicated state roots.
- `docs/runbooks/clawdiy-deploy.md` documents the same-host subdomain deployment flow and operational guardrails.
- `docs/INFRASTRUCTURE.md` documents the same-host runtime boundary and shared network expectations.

Planning impact:

- a dedicated `asc.ainetic.tech` demo surface fits a pattern the repo already uses
- there is no need to invent a brand-new deployment model for the demo slice
- same-host subdomain rollout is lower-risk than remote extraction for the first browser demo

### 3.3 Existing browser-test baseline

- `package.json` contains Playwright but no frontend app framework
- `tests/run.sh` already has the `e2e_browser` lane
- `tests/e2e_browser/chat_flow.mjs` proves the repo already validates browser UX through Playwright

Planning impact:

- browser validation is already a first-class test capability
- the repo does not currently justify a heavy frontend toolchain just to achieve the demo

### 3.4 Existing Telegram work that should not be lost

- `specs/023-telegram-factory-adapter/spec.md`
- `specs/023-telegram-factory-adapter/plan.md`
- `specs/023-telegram-factory-adapter/tasks.md`

Planning impact:

- `023` already captures useful transport/routing/delivery decisions
- the web pivot should not delete or invalidate that work
- the correct move is to change priority, not erase scope

## 4. Decision Log

### 4.1 Web-First Primary Demo Path

**Decision**: Make a browser-accessible subdomain such as `asc.ainetic.tech` the primary demo path for the next slice.

**Rationale**:

- The user explicitly called out possible Telegram difficulty inside a closed corporate contour without VPN.
- Opening a standard HTTPS URL in a browser is operationally simpler for demo stakeholders.
- The same-host subdomain pattern already exists in this repository and reduces planning uncertainty.

**Alternatives considered**:

- Keep Telegram as the primary demo path: rejected because access reliability is lower in the target environment.
- Wait for a future generalized UI platform: rejected because the user needs a near-term demonstration path.

### 4.2 Thin Browser Adapter Over Existing Runtime

**Decision**: Add one browser-facing adapter and keep discovery plus concept-pack generation in the existing runtimes.

**Rationale**:

- `022` already owns the business-analysis conversation model.
- `020` already owns the downstream concept-pack lifecycle.
- Reusing both keeps the pivot small and preserves transport neutrality.

### 4.3 Standard HTTPS Flow Over Websocket-Only Assumptions

**Decision**: The core browser demo flow should remain functional through standard HTTPS request/response patterns.

**Rationale**:

- Corporate networks often degrade or block websocket-heavy apps.
- The needed UI is a chat-like guided flow, not a low-latency collaborative editor.
- Request/response plus status refresh is sufficient for pilot-scale demo use.

### 4.4 Static Shell Instead Of New Frontend Stack

**Decision**: Plan a static browser shell with thin adapter-side rendering instead of introducing React/Vite/Next.js.

**Rationale**:

- The current repo has Playwright for testing, but no frontend build system.
- The required UI surface is narrow: chat input, message/status cards, brief review, and downloads.
- This minimizes both implementation and deployment complexity.

**Alternatives considered**:

- Introduce a new SPA stack immediately: rejected because it adds setup cost without solving the primary demo risk.
- Render everything as raw JSON in the browser: rejected because it is not suitable for business-user demos.

### 4.5 Browser Download Delivery

**Decision**: Deliver the concept-pack artifacts as browser downloads or retrievable links within the same web session.

**Rationale**:

- This matches the self-serve expectation already captured for Telegram in `023`.
- It keeps the user in one interface and removes operator copy-paste.
- Browser delivery is natural for documents and presentation files.

### 4.6 Preserve Telegram As Follow-Up Adapter

**Decision**: Keep `023-telegram-factory-adapter` as valid follow-up scope after the web-first demo path is ready.

**Rationale**:

- The prepared Telegram transport design still has value.
- The pivot changes priority, not architectural direction.
- Later the same discovery/factory core can power both browser and Telegram adapters.

## 5. Planning Inputs For The Next Phase

The planning and tasks phases should treat the following as required inputs:

- [spec.md](./spec.md)
- [../022-telegram-ba-intake/spec.md](../022-telegram-ba-intake/spec.md)
- [../020-agent-factory-prototype/spec.md](../020-agent-factory-prototype/spec.md)
- [../023-telegram-factory-adapter/spec.md](../023-telegram-factory-adapter/spec.md)
- [../../docker-compose.clawdiy.yml](../../docker-compose.clawdiy.yml)
- [../../docs/runbooks/clawdiy-deploy.md](../../docs/runbooks/clawdiy-deploy.md)
- [../../docs/INFRASTRUCTURE.md](../../docs/INFRASTRUCTURE.md)
- `scripts/agent-factory-discovery.py`
- `scripts/agent-factory-intake.py`
- `scripts/agent-factory-artifacts.py`
- `scripts/agent_factory_common.py`
- `tests/e2e_browser/chat_flow.mjs`
- `tests/run.sh`

## 6. Research Outcome

No blocking clarification remains before `plan.md`, `data-model.md`, `contracts/`, `quickstart.md`, and `tasks.md`.

The feature can proceed with these working assumptions:

- the near-term primary demo path is web-first
- the adapter must stay thin and reuse `022` plus `020`
- same-host subdomain rollout is the fastest reliable deployment path
- the browser experience should avoid websocket-only assumptions
- a static UI shell is sufficient for the slice
- Telegram remains preserved as follow-up scope in `023`
