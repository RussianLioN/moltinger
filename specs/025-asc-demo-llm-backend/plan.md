# Implementation Plan: ASC Demo LLM Backend

**Branch**: `024-web-factory-demo-adapter` | **Date**: 2026-03-18 | **Spec**: [spec.md](./spec.md)  
**Input**: [../../asc-demo/docs/plans/sleepy-munching-turing.md](../../asc-demo/docs/plans/sleepy-munching-turing.md)

## Summary

Implement standalone Node backend inside `asc-demo/` that matches existing frontend response contract and upgrades mock conversation to real LLM-driven discovery/brief/summary with Fireworks (OpenAI-compatible) support and resilient fallback behavior.

## Technical Context

**Language/Version**: Node.js 20+, ESM  
**Primary Dependencies**: `express`, `openai`, `dotenv`, `cors`, `uuid`  
**Storage**: In-memory sessions + runtime artifact payloads in process memory  
**Testing**: local smoke via node checks + scripted API scenario  
**Target Platform**: local demo service on `PORT` (default 3000), target public domain `demo.ainetic.tech`

## Project Structure

```text
asc-demo/
├── package.json
├── .env.example
├── server.js
├── src/
│   ├── llm.js
│   ├── sessions.js
│   ├── response-builder.js
│   ├── router.js
│   ├── discovery.js
│   ├── brief.js
│   ├── summary-generator.js
│   ├── prompts/
│   │   ├── architect-system.md
│   │   ├── client-info.md
│   │   ├── deal-info.md
│   │   ├── pricing-info.md
│   │   └── cooperation-info.md
│   └── demo-data/
│       └── boku-do-manzh.json
└── public/
    ├── index.html
    ├── app.css
    └── app.js
```

## Execution Plan

1. Bootstrap runtime (`package.json`, `.env.example`) and data assets (`boku-do-manzh.json`, prompts).
2. Implement core backend modules (`llm`, `sessions`, `response-builder`).
3. Implement domain flow (`discovery`, `brief`, `summary-generator`).
4. Implement router orchestration + deferred generation.
5. Implement Express server endpoints and download handler.
6. Update `asc-demo/CLAUDE.md` for OpenAI-compatible stack and Fireworks settings.
7. Validate with local end-to-end API scenario and syntax checks.

## Risks and Mitigations

- LLM JSON output drift -> strict sanitizer + fallback heuristics.
- Invalid credentials -> fail-soft fallback for discovery/brief/summary.
- Frontend contract mismatch -> mimic `mockAdapterTurn()` envelope and field names.

## Done Criteria

- Full browser flow works against live backend (without mock fallback path).
- 4 artifacts are produced and downloadable.
- Plan tasks are checked and synchronized with implementation.
