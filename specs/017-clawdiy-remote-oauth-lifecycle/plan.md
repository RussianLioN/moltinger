# Implementation Plan: Clawdiy Remote OAuth Runtime Lifecycle

**Branch**: `017-clawdiy-remote-oauth-lifecycle` | **Date**: 2026-03-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/017-clawdiy-remote-oauth-lifecycle/spec.md`

## Summary

Clawdiy is already live, so this plan does not solve “how to deploy Clawdiy.” It solves a narrower and currently missing contract: how `openai-codex` / `gpt-5.4` becomes a real runtime capability for the live OpenClaw container instead of a metadata-only promise.

The recommended practical-now design is:

1. keep `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` as metadata gate and policy evidence;
2. define a real persistent runtime auth store for Clawdiy;
3. bootstrap OAuth against that exact target store;
4. explicitly activate `models.providers.openai-codex`;
5. add fail-closed validation that distinguishes metadata-only from runtime-ready;
6. require post-auth canary evidence before promotion.

The plan also leaves a target-state path for future version-matched workstation bootstrap plus managed auth-artifact delivery, but that is not the MVP.

## Technical Context

**Language/Version**: Bash shell, JSON config, GitHub Actions YAML, Markdown docs  
**Primary Dependencies**: OpenClaw runtime config, `deploy-clawdiy.yml`, `scripts/clawdiy-auth-check.sh`, `scripts/clawdiy-smoke.sh`, GitHub Secrets metadata rendering  
**Storage**: `/opt/moltinger/clawdiy/.env` for metadata mirror, persistent Clawdiy runtime state/auth path for real provider auth artifact, audit evidence under `data/clawdiy/audit`  
**Testing**: static validation, security/auth checks, live smoke, post-auth canary  
**Target Platform**: remote VDS `ainetic.tech`, Docker Compose, Traefik-routed Clawdiy stack  
**Project Type**: infra/runtime auth lifecycle hardening for an already deployed service  
**Constraints**: no runtime OAuth tokens in git, baseline Clawdiy health must survive provider failure, current upstream remote OAuth UX is brittle, provider activation must be explicit, docs/tests/workflows must agree

## Constitution Check

*GATE: Must pass before implementation tasks.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | PASS | Design is based on current live Clawdiy runtime state, repo docs, and fresh official/community evidence. |
| II. Single Source of Truth | PASS | Plan separates metadata gate, runtime auth store, and post-auth canary instead of collapsing them into one pseudo-secret. |
| III. Library-First Development | PASS | Reuses existing OpenClaw auth behavior, deploy workflow, validation scripts, and docs rather than inventing a new auth system. |
| IV. Code Reuse & DRY | PASS | Extends existing Clawdiy scripts and workflow surfaces instead of creating parallel auth tooling. |
| V. Strict Type Safety | N/A | Primary implementation surface is shell, YAML, JSON, and Markdown. |
| VI. Atomic Task Execution | PASS | Tasks split config/runtime, docs, tests, and canary into reviewable slices. |
| VII. Quality Gates | PASS | Validation requires static checks, auth boundary checks, smoke, and canary evidence. |
| VIII. Progressive Specification | PASS | Spec, research, plan, contracts, and tasks are defined before runtime edits. |

## Project Structure

### Documentation

```text
specs/017-clawdiy-remote-oauth-lifecycle/
├── spec.md
├── research.md
├── plan.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── runtime-auth-store-contract.md
│   └── provider-activation-contract.md
└── tasks.md
```

### Implementation Surfaces

```text
config/clawdiy/openclaw.json
.github/workflows/deploy-clawdiy.yml
docs/runbooks/clawdiy-repeat-auth.md
docs/SECRETS-MANAGEMENT.md
scripts/clawdiy-auth-check.sh
scripts/clawdiy-smoke.sh
tests/security_api/test_clawdiy_auth_boundaries.sh
tests/static/test_config_validation.sh
tests/live_external/test_clawdiy_deploy_smoke.sh
```

## Phase 0: Research Decisions

1. **Practical-now bootstrap method**: target the actual live runtime auth store.
2. **Target-state method**: later support version-matched workstation bootstrap plus controlled auth-artifact delivery.
3. **Metadata vs runtime**: keep both, but never confuse them.
4. **Explicit provider activation**: required because auth-store presence alone may not activate `openai-codex`.
5. **Post-auth canary**: mandatory for promotion.
6. **Fail-closed quarantine**: provider failures must not bring Clawdiy down.

## Phase 1: Design Outcomes

Phase 1 artifacts define:

- the runtime/auth lifecycle entities in [data-model.md](./data-model.md)
- the runtime auth store boundary in [contracts/runtime-auth-store-contract.md](./contracts/runtime-auth-store-contract.md)
- explicit provider activation and canary semantics in [contracts/provider-activation-contract.md](./contracts/provider-activation-contract.md)
- operator validation flow in [quickstart.md](./quickstart.md)

## Implementation Strategy

### MVP

1. Teach the repo and runtime to recognize a real Clawdiy runtime auth store.
2. Make `clawdiy-auth-check.sh` and smoke distinguish metadata-only from runtime-ready.
3. Add explicit `openai-codex` provider activation to Clawdiy runtime config.
4. Update runbooks and secrets docs to explain the real lifecycle.
5. Add post-auth canary evidence and quarantine logic.

### Phase-2 Target State

1. Formalize a managed delivery lifecycle for the runtime auth artifact.
2. Support version-matched trusted-workstation bootstrap with controlled import into the live runtime store.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Manual bootstrap remains in the short term | Upstream does not yet expose a robust first-class remote gateway auth flow | Pretending metadata-only state proves runtime readiness is operationally false |
