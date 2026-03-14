# Implementation Plan: Web Factory Demo Adapter

**Branch**: `024-web-factory-demo-adapter` | **Date**: 2026-03-14 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/024-web-factory-demo-adapter/spec.md`

## Summary

Add the primary web-first demo adapter for the factory business-analyst agent on `Moltis`. The adapter must expose a controlled browser-accessible demo surface on a dedicated subdomain such as `asc.ainetic.tech`, route browser turns into the existing `022` discovery runtime, let the user review and confirm the brief in a chat-like UI, automatically trigger `handoff -> intake -> concept pack`, and expose the resulting artifacts as browser downloads. Telegram stays preserved in `023` as a follow-up transport slice, not as the primary near-term demo path.

## Technical Context

**Language/Version**: Bash 5.x, Python 3.11+, HTML/CSS/vanilla JavaScript, JSON/TOML/Markdown contracts  
**Primary Dependencies**: Existing `scripts/agent-factory-discovery.py`, `scripts/agent-factory-intake.py`, `scripts/agent-factory-artifacts.py`, shared helpers in `scripts/agent_factory_common.py`, Docker Compose + Traefik same-host subdomain pattern, current `tests/run.sh` harness, current Playwright dependency from `package.json`, existing clawdiy same-host deploy/runbook patterns  
**Storage**: Git-tracked planning artifacts, repo-local JSON state under `data/agent-factory/discovery/` plus new adapter-local state under `data/agent-factory/web-demo/`, existing concept-pack artifact roots under the factory pipeline  
**Testing**: Shell-based `component` and `integration_local` suites, `e2e_browser` Playwright validation, optional `live_external` smoke for remote demo availability, prerequisite/topology checks  
**Target Platform**: Linux Docker-hosted same-host demo service behind Traefik on a dedicated HTTPS subdomain, reusing the current Moltis/factory core  
**Project Type**: Thin web adapter service with static browser UI assets over an existing script/config factory runtime  
**Performance Goals**: Each browser turn should produce one visible next-step response in the same request cycle; page refresh should recover the active session without forcing a restart; confirmed brief should acknowledge downstream launch immediately and surface downloads once available  
**Constraints**: Standard HTTPS browser access must work without Telegram dependency; core flow must not require websocket-only transport; no new heavy frontend build stack unless later evidence forces it; no concept-pack generation before explicit brief confirmation; no raw stack traces, repo paths, or secrets in user-facing UI; `023` Telegram scope must remain valid follow-up backlog  
**Scale/Scope**: Pilot-scale demo for a small set of business users and operators; tens of active browser sessions are acceptable; one active project pointer per browser session by default; broader production portal, SSO, and generalized multi-channel UI stay out of scope

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | PASS | Existing `022` discovery runtime, `020` factory pipeline, `023` Telegram follow-up scope, current compose/runbooks, and current browser-test baseline were reviewed before filling the plan. |
| II. Single Source of Truth | PASS | The web adapter reuses the canonical confirmed brief and canonical downstream handoff contracts from `022`/`020`. |
| III. Library-First Development | PASS | The design reuses the current factory scripts, current same-host Traefik/deploy patterns, and current Playwright/browser test tooling instead of inventing a separate stack first. |
| IV. Code Reuse & DRY | PASS | Discovery and concept generation stay in existing runtimes; the web slice only adds access, routing, rendering, and delivery glue. |
| V. Strict Type Safety | PASS | Explicit browser-session, request-envelope, and artifact-delivery contracts are defined before runtime changes. |
| VI. Atomic Task Execution | PASS | Work decomposes into setup, access/session plumbing, discovery UI, brief confirmation, downstream delivery, resume, and deployment validation slices. |
| VII. Quality Gates | PASS | The plan includes component, integration, browser, and targeted remote smoke validation plus final prerequisite/topology checks. |
| VIII. Progressive Specification | PASS | The feature is moving through spec -> research -> plan -> tasks on its dedicated branch and records the pivot from `023` as a clarification-driven decision. |
| IX. Error Handling | PASS | The adapter must fail closed for access, surface sanitized user-facing errors, and preserve operator-safe status visibility. |
| X. Observability | PASS | Browser session status, project pointer, handoff progress, and download readiness are planned as first-class outputs. |
| XI. Accessibility | PASS | The feature is text-first, Russian-first, browser-accessible, and optimized for non-technical business users in a constrained corporate environment. |

**Gate Status**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/024-web-factory-demo-adapter/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── web-session-access-contract.md
│   ├── web-discovery-turn-contract.md
│   ├── web-brief-confirmation-contract.md
│   └── web-artifact-delivery-contract.md
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
├── agent-factory-web-adapter.py         # new thin browser-facing adapter
├── agent_factory_common.py
├── manifest.json
└── deploy.sh                            # same-host demo target integration

web/
└── agent-factory-demo/
    ├── index.html
    ├── app.css
    └── app.js

docs/
└── runbooks/
    ├── agent-factory-discovery.md
    ├── agent-factory-prototype.md
    └── agent-factory-web-demo.md        # new operator/user runbook

tests/
├── component/
│   ├── test_agent_factory_web_access.sh
│   ├── test_agent_factory_web_discovery.sh
│   ├── test_agent_factory_web_brief.sh
│   └── test_agent_factory_web_delivery.sh
├── integration_local/
│   ├── test_agent_factory_web_flow.sh
│   ├── test_agent_factory_web_confirmation.sh
│   └── test_agent_factory_web_resume.sh
├── e2e_browser/
│   └── agent_factory_web_demo.mjs
├── live_external/
│   └── test_web_factory_demo_smoke.sh
└── fixtures/
    └── agent-factory/
        └── web-demo/
            ├── README.md
            ├── session-new.json
            ├── session-awaiting-confirmation.json
            └── session-download-ready.json

docker-compose.asc.yml

data/
└── agent-factory/
    ├── discovery/
    └── web-demo/
        ├── sessions/
        ├── access/
        └── history/
```

**Structure Decision**: Reuse the existing script/config/test layout and add one thin browser-facing adapter service plus static assets. The repo has no existing frontend application framework baseline beyond Playwright, so the initial design stays intentionally lean: static browser assets, Python/Bash adapter glue, same-host Docker Compose deployment, and existing test harness lanes.

## Complexity Tracking

No constitution violations are required for this feature.

## Research Decisions

### Decision 1: Web-First Demo Path Replaces Telegram As The Primary Near-Term Entry Surface

**Chosen design**: Make a browser-accessible subdomain such as `asc.ainetic.tech` the primary demo entrypoint and keep `023` as follow-up transport work.

**Rationale**:

- The user explicitly identified corporate/VPN friction as a likely blocker for Telegram demo access.
- The repository already contains a proven same-host subdomain pattern through `docker-compose.clawdiy.yml`.
- `022` discovery logic is already channel-neutral, so changing the primary adapter does not invalidate the core runtime.

**Alternatives considered**:

- Keep Telegram as primary demo path: rejected because channel access is less reliable in the target corporate contour.
- Wait for a bigger future UI platform: rejected because the user needs a near-term demonstrable path.

### Decision 2: Thin Web Adapter Over Existing Factory Runtime

**Chosen design**: Add one browser-facing adapter that only handles access gating, browser session state, rendering, and download delivery while delegating discovery and downstream generation to the existing scripts.

**Rationale**:

- `022` already owns business-analysis logic and brief lifecycle.
- `020` already owns downstream concept-pack generation.
- A thin adapter keeps the pivot small and preserves `023` as a later transport implementation.

### Decision 3: Standard HTTPS Request/Response Over Websocket-Only UX

**Chosen design**: The core web demo flow should work through ordinary HTTPS form/API requests and short polling where needed, not depend exclusively on persistent websocket channels.

**Rationale**:

- Corporate proxies and controlled browser environments often degrade websocket reliability.
- Chat-like UX can still be achieved through standard request/response patterns for pilot scale.
- This makes the demo easier to deploy and reason about in the same-host subdomain pattern.

### Decision 4: Static Browser Shell Instead Of New Frontend Build Stack

**Chosen design**: Start with static HTML/CSS/JS assets plus a thin adapter server instead of introducing a new React/Vite/Next.js stack into a repository that currently lacks a frontend app baseline.

**Rationale**:

- `package.json` currently contains only Playwright as a dev dependency, not a frontend application toolchain.
- The required UX is narrow: chat shell, brief review, status, and downloads.
- This keeps demo delivery fast and reduces operational surface.

### Decision 5: Browser Downloads Replace Bot Document Delivery On The Primary Path

**Chosen design**: Publish the generated artifacts back to the user as in-browser downloads or retrievable links from the same web session.

**Rationale**:

- This keeps the user inside the same UI and removes operator-side copy-paste.
- It mirrors the value expected from the Telegram adapter while fitting the browser environment naturally.
- Provenance can stay tied to the same confirmed brief and project pointer.

### Decision 6: Minimal Demo Access Gate Instead Of Full Enterprise Auth

**Chosen design**: Use a lightweight controlled access model for the demo surface and defer full IAM/SSO.

**Rationale**:

- The immediate need is controlled demo access, not enterprise identity rollout.
- Same-host subdomain deployment already introduces enough operational work without adding full auth scope.
- This keeps the slice demonstrable while still preventing accidental open access.

## Phase 0: Research Decisions

Phase 0 is complete in [research.md](./research.md).

### Finalized Research Output

1. The primary near-term demo path should move from Telegram-first to web-first.
2. The adapter must stay thin and reuse `022` plus `020`, not replace them.
3. Same-host subdomain deployment is the fastest reliable publish path already proven elsewhere in the repo.
4. The browser demo should prefer standard HTTPS request/response semantics over websocket-only assumptions.
5. A lightweight static UI shell is sufficient for this slice.
6. Telegram remains preserved in `023` as follow-up transport scope.

## Phase 1: Design Artifacts

### Data Model

Generate and maintain [data-model.md](./data-model.md) for:

- `DemoAccessGrant`
- `WebDemoSession`
- `BrowserProjectPointer`
- `WebConversationEnvelope`
- `WebReplyCard`
- `BriefDownloadArtifact`
- `WebDemoStatusSnapshot`
- `WebDemoAuditRecord`

### Contracts

Generate and maintain:

- [contracts/web-session-access-contract.md](./contracts/web-session-access-contract.md)
- [contracts/web-discovery-turn-contract.md](./contracts/web-discovery-turn-contract.md)
- [contracts/web-brief-confirmation-contract.md](./contracts/web-brief-confirmation-contract.md)
- [contracts/web-artifact-delivery-contract.md](./contracts/web-artifact-delivery-contract.md)

### Quickstart

Generate and maintain [quickstart.md](./quickstart.md) for:

- package integrity and pivot validation against `023`
- same-host subdomain deployment expectations
- browser discovery turns
- brief review and confirmation in the browser
- automatic handoff and artifact downloads
- resume/reopen expectations and remote demo smoke boundaries

### Agent Context Update

Do not auto-write `AGENTS.md` from `update-agent-context.sh` for this feature. The repository treats agent instructions as generated; the active planning context must remain in the Speckit package, runbooks, and runtime docs.

## Phase 2: Execution Readiness

### Stage 1: Demo Surface Foundations

- add web-demo anchors to `config/moltis.toml`
- introduce `docker-compose.asc.yml` using the existing same-host Traefik pattern
- add browser adapter entrypoints to `scripts/manifest.json`
- register fixtures and test suites for component, integration, browser, and live smoke coverage

### Stage 2: Live Browser Discovery

- implement access gate and browser session routing
- map browser turns into `scripts/agent-factory-discovery.py`
- render one next useful discovery card back to the user

### Stage 3: Brief Review And Confirmation

- render reviewable brief sections in the browser
- support corrections, explicit confirmation, and reopen actions
- keep versioned history aligned with `022`

### Stage 4: Automatic Handoff And Downloads

- trigger `intake -> artifacts` automatically after confirmation
- publish project doc, agent spec, and presentation as browser downloads
- preserve provenance and safe user-facing status

### Stage 5: Resume, Deploy, And Demo Validation

- persist resumable browser session state
- support same-host deployment and operator-visible health
- validate the demo with hermetic browser coverage and targeted remote smoke
