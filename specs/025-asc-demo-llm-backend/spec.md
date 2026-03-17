# Feature Specification: ASC Demo LLM Backend (Fireworks/OpenAI-compatible)

**Feature Branch**: `024-web-factory-demo-adapter`  
**Created**: 2026-03-18  
**Status**: Draft  
**Input Plan**: [../../asc-demo/docs/plans/sleepy-munching-turing.md](../../asc-demo/docs/plans/sleepy-munching-turing.md)

## Context

Frontend shell `asc-demo/public/*` already exists and currently works with local mock logic in `mockAdapterTurn()` inside browser code.  
This slice introduces a real Node.js backend that serves the same UI contract and replaces mock responses with:

- controlled access gate
- guided discovery interview
- brief generation and correction
- deferred concept-pack handoff simulation
- downloadable artifacts
- one-page summary generated from demo client data via OpenAI-compatible API (Fireworks endpoint)

## Clarifications (Session 2026-03-18)

- LLM provider must be OpenAI-compatible with configurable base URL and model.
- Fireworks API credentials were provided by user for runtime usage; repository must keep only placeholders/examples.
- If provider is unavailable or credentials are invalid, backend must fail soft (fallback content), not crash.
- Missing product decisions should be implemented with safe placeholders and explicitly listed at handoff.

## Scope

### In Scope

- New backend runtime in `asc-demo/` (`server.js` + `src/*.js`).
- API contract compatibility with current frontend expectations for:
  - `POST /api/turn`
  - `GET /api/session`
  - `GET /api/download/:sessionId/:artifactKind`
- In-memory session state.
- Discovery flow for 7 topics.
- Brief generation and correction.
- Parallel generation of one-page summary sections using 4 prompt files.
- Generation of 4 downloadable artifacts:
  - `one_page_summary` (LLM result)
  - `project_doc` (template)
  - `agent_spec` (template)
  - `presentation` (template)
- Theatre/status messages for transitions.
- Fallback behavior when LLM errors happen.

### Out of Scope

- Production-grade persistent DB.
- Enterprise auth/SSO.
- Non-markdown binary presentation export (pptx/pdf).
- Full replacement of root-level `scripts/agent-factory-web-adapter.py`.

## User Stories

### US1 (P1): Discovery via browser with real backend

As a business user, I can open web demo, pass access gate, describe automation idea, and receive next discovery questions from backend.

Acceptance:
- Invalid token keeps user in `gate_pending`.
- Valid token opens discovery.
- `start_project`/`submit_turn` returns question/status in frontend-compatible JSON.

### US2 (P1): Brief review, correction, confirmation

As a business user, I can review generated brief, ask corrections, and confirm version.

Acceptance:
- After sufficient discovery coverage, backend moves to `awaiting_confirmation`.
- `request_brief_correction` updates brief and increments version.
- `confirm_brief` triggers deferred summary generation.

### US3 (P2): Artifacts and downloads

As a business user, I can receive and download 4 artifacts from same session.

Acceptance:
- `request_status` after `confirm_brief` eventually returns `downloads_ready`.
- All 4 artifacts include `download_url`.
- Download endpoint returns markdown attachment.

## Requirements

- **FR-001**: Backend MUST preserve mock response schema expected by `asc-demo/public/app.js`.
- **FR-002**: Backend MUST support OpenAI-compatible chat completions with configurable env.
- **FR-003**: Backend MUST keep service alive on LLM/provider errors and return fallback content.
- **FR-004**: Backend MUST include theatre/status cards in each response.
- **FR-005**: Backend MUST not hardcode secret API keys into tracked files.
- **FR-006**: Backend MUST keep per-session state in memory with cached `lastResponse`.

## Success Criteria

- **SC-001**: `npm run dev` starts and serves UI and API from one process.
- **SC-002**: Frontend can complete flow `gate -> discovery -> brief -> confirm -> downloads` without browser errors.
- **SC-003**: `one-page-summary.md` includes 4 sections from prompt files.
- **SC-004**: With invalid API key, backend remains functional using fallback generation.
