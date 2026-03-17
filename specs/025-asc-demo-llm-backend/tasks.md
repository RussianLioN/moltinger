# Tasks: ASC Demo LLM Backend

**Input**: `/specs/025-asc-demo-llm-backend/{spec.md,plan.md}`  
**Source Plan**: `/asc-demo/docs/plans/sleepy-munching-turing.md`

## Phase 1: Setup

- [x] T001 Create `asc-demo/package.json` with ESM runtime and required dependencies/scripts
- [x] T002 Create `asc-demo/.env.example` for OpenAI-compatible + Fireworks defaults
- [x] T003 Create `asc-demo/src/demo-data/boku-do-manzh.json` from CSV
- [x] T004 Create prompt files in `asc-demo/src/prompts/*` including architect + 4 section prompts

## Phase 2: Core Modules

- [x] T005 Implement `asc-demo/src/llm.js` (chatCompletion + chatCompletionJSON with fence stripping)
- [x] T006 Implement `asc-demo/src/sessions.js` (in-memory session store and lifecycle helpers)
- [x] T007 Implement `asc-demo/src/response-builder.js` with full frontend-compatible response envelope

## Phase 3: Domain Flow

- [x] T008 Implement `asc-demo/src/discovery.js` with 7 topics, low-signal guard, LLM+fallback coverage
- [x] T009 Implement `asc-demo/src/brief.js` for generation/revision + fallback brief
- [x] T010 Implement `asc-demo/src/summary-generator.js` with 4 parallel section generations + artifact builders

## Phase 4: Integration

- [x] T011 Implement `asc-demo/src/router.js` route orchestration and deferred handoff/status flow
- [x] T012 Implement `asc-demo/server.js` (`/api/turn`, `/api/session`, `/api/download`, static UI)
- [x] T013 Update `asc-demo/CLAUDE.md` to OpenAI-compatible stack and env vars

## Phase 5: Validation

- [x] T014 Run syntax validation for backend modules (`node --check ...`)
- [x] T015 Run local API smoke for flow `gate -> discovery -> brief -> confirm -> downloads`
- [x] T016 Reconcile task checklist and session summary
