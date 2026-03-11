# Implementation Plan: Production-Aware Remote UAT Hardening

**Branch**: `011-remote-uat-hardening` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-remote-uat-hardening/spec.md`

## Summary

Harden Moltinger’s production-aware remote UAT so operators get one decision-grade post-deploy verdict for the real Telegram user path. Reuse the existing Telegram Web probe, MTProto `real_user` path, and on-demand workflow, but promote Telegram Web to the primary verdict path, keep MTProto as an explicit secondary cross-check, enforce security and operational guardrails up front, and preserve polling mode plus manual-only execution.

## Implementation Delta Summary

This feature intentionally hardened existing runtime surfaces instead of introducing a new remote-UAT stack.

Delivered delta:

- `scripts/telegram-e2e-on-demand.sh` became the canonical authoritative wrapper with:
  - review-safe artifact output
  - restricted debug bundle separation
  - `recommended_action`
  - `fallback_assessment`
  - shared-target serialization
- `scripts/telegram-web-user-probe.mjs` now emits:
  - stable failure taxonomy
  - fail-closed attribution evidence
  - richer restricted debug for send-path RCA
  - normalized Telegram Web bubble parsing
  - hardened send strategy for Telegram Web UI interaction
- `.github/workflows/telegram-e2e-on-demand.yml` now runs the current branch logic against the remote target as one manual authoritative entrypoint
- MTProto remains available only as secondary diagnostics
- before/after review-safe acceptance evidence is now stored in `tests/fixtures/telegram-web/`

## Technical Context

**Language/Version**: Bash, Node.js ESM on Node `>=18`, Python 3 for optional MTProto diagnostics  
**Primary Dependencies**: Playwright, `@playwright/test`, `curl`, `jq`, GitHub Actions, optional Telethon for secondary diagnostics  
**Storage**: Operator-safe JSON artifacts, restricted debug bundles, Telegram Web state file, existing docs/spec artifacts  
**Testing**: `./tests/run.sh` (`component`, selected live/manual verification), `tests/component/test_telegram_web_probe_correlation.sh`, before/after artifact comparison  
**Target Platform**: Production-aware remote checks from GitHub Actions and operator shells against Linux-hosted Moltis production  
**Project Type**: Infrastructure/scripts + CI workflow + test harness + operator documentation  
**Performance Goals**: One deterministic verdict artifact per run within configured timeout budget plus browser/setup overhead; no ambiguous silent failures and no cross-run attribution corruption  
**Constraints**: Telegram Web is the primary verdict path; production stays on polling; no webhook migration; no automatic scheduler re-enable; no blocking PR/main CI promotion; outputs must remain review-safe and RCA-friendly; shared-target runs must be serialized or guarded  
**Scale/Scope**: One operator-initiated run at a time against one shared production target, with optional MTProto cross-check only after the primary verdict

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS. Existing Telegram Web probe, MTProto `real_user` path, on-demand harness, deploy workflow behavior, and runbooks were reviewed before planning.
- Single Source of Truth: PASS. The plan centers one primary Telegram Web verdict path, one canonical artifact contract, and one controlled secondary-diagnostics policy rather than parallel verdict systems.
- Library-First Development: PASS. Existing Playwright and optional Telethon surfaces already cover the required browser and fallback behaviors; no new major library is required for MVP planning.
- Code Reuse & DRY: PASS. Work is scoped to hardening the existing probe, harness, tests, workflows, and docs rather than introducing a second remote-UAT stack.
- Strict Type Safety: N/A for the main Bash/Node/Python script scope in this feature package.
- Atomic Task Execution: PASS. Planned work can be broken into reproducible artifact, probe, workflow, and documentation tasks.
- Quality Gates: PASS. Blocking PR/main CI remains hermetic-only; production-aware validation stays manual/live and therefore does not violate existing test-boundary policy.
- Progressive Specification: PASS. Spec, plan, tasks, and Beads import remain the required sequence.

No gate violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/011-remote-uat-hardening/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── remote-uat-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
├── telegram-web-user-probe.mjs
├── telegram-web-user-monitor.sh
├── telegram-e2e-on-demand.sh
├── telegram-real-user-e2e.py
└── setup-telegram-web-user-monitor.sh

tests/
├── run.sh
├── component/test_telegram_web_probe_correlation.sh
└── live_external/test_telegram_external_smoke.sh

.github/workflows/
├── telegram-e2e-on-demand.yml
├── deploy.yml
└── uat-gate.yml

docs/
├── TELEGRAM-WEB-USER-MONITOR.md
├── telegram-e2e-on-demand.md
└── CLEAN-DEPLOY-TELEGRAM-WEB-USER-MONITOR.md

systemd/
├── moltis-telegram-web-user-monitor.service
└── moltis-telegram-web-user-monitor.timer
```

**Structure Decision**: Keep the existing infra-script layout and harden the already-shipped Telegram Web, MTProto, and on-demand UAT surfaces in place. The feature does not build a new harness; it converts existing surfaces into one operator-facing verdict workflow with early security and operational controls.

## Phase 0: Research Decisions

1. **Baseline-first approach**: Freeze shipped `main` behavior and capture the current production-aware Telegram Web failure before implementation changes.
2. **Primary verdict path**: Keep Telegram Web as the canonical production-aware verdict path.
3. **Operational boundary**: Preserve manual/on-demand execution, keep blocking CI hermetic-only, and guard against shared-target concurrency issues.
4. **Reuse strategy**: Extend the existing Telegram Web probe, MTProto path, and on-demand harness rather than building a parallel remote-UAT implementation.
5. **Diagnostic model**: Convert current stage/correlation signals into a stable failure taxonomy with review-safe artifact output and operator next-step guidance.
6. **Fallback policy**: Treat MTProto as explicit secondary diagnostics and defer any production enablement decision until after Telegram Web remediation or root-cause narrowing.
7. **Security model**: Separate operator-safe artifacts from restricted debug diagnostics and narrow exposure of state and secrets.

## Phase 1: Design Artifacts

- **Research (`research.md`)**: Capture baseline review, primary-path choice, failure taxonomy design, reuse decisions, scheduler/CI boundaries, and fallback decision policy.
- **Data Model (`data-model.md`)**: Define `RemoteUATRun`, `DiagnosticArtifact`, `AttributionEvidence`, `FailureClassification`, and `FallbackAssessment`.
- **Contract (`contracts/remote-uat-contract.md`)**: Define manual trigger expectations, operator-safe artifact schema, restricted debug behavior, diagnostic categories, and fallback decision gate.
- **Quickstart (`quickstart.md`)**: Document the intended operator flow for baseline capture, failing-path reproduction, post-fix rerun, and evidence comparison.

## Phase 2: Execution Readiness

Implementation will proceed in this order:

1. Review and freeze the shipped baseline, then capture the current failing production-aware Telegram Web artifact.
2. Lock security and operational guardrails before promoting any authoritative path.
3. Convert the existing on-demand harness into one canonical operator verdict workflow with Telegram Web as the primary verdict path.
4. Harden DOM/send confirmation, deterministic failure classification, and fail-closed attribution in the Telegram Web path.
5. Update operator workflow, rerun procedure, and proof-of-value artifacts.
6. Evaluate MTProto only as a controlled secondary cross-check after the primary path is fixed or narrowed to root cause.

## Acceptance Proof

Acceptance for this feature is satisfied by the combination of local regression proof and live production-aware rerun proof:

- Local proof:
  - `./tests/run.sh --lane component --json`
  - targeted Telegram component regression for probe correlation, monitor debug propagation, and remote UAT contract
- Live proof:
  - failing baseline run `22976837805` on branch SHA `d08dbb1`
  - successful post-fix run `22977239309` on branch SHA `2924b12`
- Stored review-safe evidence:
  - [2026-03-11-before-send-failure-review-safe.json](/Users/rl/.codex/worktrees/remote-uat-hardening/tests/fixtures/telegram-web/2026-03-11-before-send-failure-review-safe.json)
  - [2026-03-11-after-pass-review-safe.json](/Users/rl/.codex/worktrees/remote-uat-hardening/tests/fixtures/telegram-web/2026-03-11-after-pass-review-safe.json)

The before/after pair proves the intended user value:

- the authoritative path remains Telegram Web
- production remains on polling
- the check remains manual/opt-in
- the operator can now get either a deterministic red verdict with RCA-grade evidence or a provable green result for the real Telegram user path

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | N/A |
