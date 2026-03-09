# Implementation Plan: Clawdiy Agent Platform

**Branch**: `001-clawdiy-agent-platform` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-clawdiy-agent-platform/spec.md`

## Summary

Deploy Clawdiy as a second permanent OpenClaw-based platform agent alongside Moltinger, with separate runtime/state/auth boundaries, explicit inter-agent handoff, and a rollout path from same-host deployment to future separate-node placement. Phase 1 will use a private authenticated HTTP JSON handoff path, a Git-managed static registry, long-polling Telegram for human ingress, and stage-gated OpenAI Codex OAuth rather than making Codex auth a platform MVP blocker.

## Technical Context

**Language/Version**: Bash 5.x, YAML 1.2, JSON configuration/schema, TOML 1.0 for existing Moltinger-side integration  
**Primary Dependencies**: Docker Compose v2, OpenClaw runtime container, existing Moltis/Moltinger runtime, Traefik, GitHub Actions, Prometheus, AlertManager  
**Storage**: Per-agent bind mounts/named volumes, GitHub Secrets generated env files, append-only JSONL audit/event artifacts in agent state roots  
**Testing**: `docker compose config --quiet`, existing shell test runners (`tests/run.sh` lanes), same-host smoke scripts, live-only Telegram/provider validation, rollback drill validation  
**Target Platform**: Linux Docker host on `ainetic.tech` now, separate Linux node/VM later without protocol rewrite
**Project Type**: Infrastructure/platform deployment + runtime configuration + contracts + runbooks  
**Performance Goals**: handoff delivery acknowledgement <10s, agent rollback <15min, single-agent restore <30min, Clawdiy same-host restart without Moltinger regression  
**Constraints**: current host budget is 2 CPU / 8 GB RAM; GitOps-only deployment; separate state/auth boundaries; no Moltinger downtime/regression; authoritative inter-agent transport must not depend on Telegram behavior  
**Scale/Scope**: 2 permanent agents in phase 1, path to 5+ named permanent roles, same-host first rollout with explicit future-node extraction path

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First Development | PASS | Spec, research, protocol, deploy baseline, secrets policy, topology registry, and existing OpenClaw planning notes reviewed before design. |
| II. Single Source of Truth | PASS | Canonical agent registry, protocol contract, and per-agent secrets/state boundaries are centralized in feature artifacts. |
| III. Library-First Development | PASS | Phase 1 reuses existing platform primitives: OpenClaw/Moltis HTTP surfaces, Docker Compose, Traefik, GitHub Actions, Prometheus. No custom broker introduced. |
| IV. Code Reuse & DRY | PASS | Plan extends existing deploy/monitoring/test/runbook patterns instead of creating a parallel platform framework. |
| V. Strict Type Safety | N/A | This feature phase is infrastructure/contracts planning; JSON schema and explicit envelope examples are provided for later typed implementation. |
| VI. Atomic Task Execution | PASS | Future tasks can be split into topology, runtime, protocol, auth, rollout, and validation slices. |
| VII. Quality Gates | PASS | Compose validation, smoke checks, lane-based tests, and rollback drills are planned as blocking gates. |
| VIII. Progressive Specification | PASS | Flow is spec -> plan -> tasks -> implementation, with no skipped phase. |
| IX. Error Handling | PASS | Protocol and runtime contracts require explicit reject/timeout/failure states and operator escalation. |
| X. Observability | PASS | Audit trail, per-agent health, alert ownership, and correlation IDs are first-class requirements. |
| XI. Accessibility | N/A | This phase focuses on backend/platform rollout, not UI redesign. Existing human-facing surfaces remain intact. |

**Gate Status**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/001-clawdiy-agent-platform/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── protocol.md
├── contracts/
│   ├── agent-handoff-contract.md
│   ├── registry-contract.md
│   ├── runtime-boundary.md
│   └── sample-handoff-submit.json
└── tasks.md
```

### Source Code (repository root)

```text
docker-compose.prod.yml
docker-compose.clawdiy.yml            # new same-host Clawdiy stack

config/
├── moltis.toml
├── clawdiy/
│   └── openclaw.json                # new Clawdiy runtime config
├── fleet/
│   ├── agents-registry.json         # new canonical agent registry
│   └── policy.json                  # new inter-agent auth/allowlist policy
├── prometheus/
│   ├── prometheus.yml
│   └── alert-rules.yml
└── alertmanager/
    └── alertmanager.yml

scripts/
├── deploy.sh
├── preflight-check.sh
├── health-monitor.sh
├── clawdiy-smoke.sh                 # new rollout verification script
├── clawdiy-auth-check.sh            # new provider/service-auth verification
└── gitops-guards.sh

.github/workflows/
├── deploy.yml
├── rollback-drill.yml
└── deploy-clawdiy.yml               # new isolated Clawdiy deployment workflow

docs/
├── SECRETS-MANAGEMENT.md
├── GIT-TOPOLOGY-REGISTRY.md
├── disaster-recovery.md
└── runbooks/
    ├── clawdiy-deploy.md
    ├── clawdiy-repeat-auth.md
    ├── clawdiy-rollback.md
    └── fleet-handoff-incident.md

tests/
├── component/
├── integration_local/
├── security_api/
└── live_external/
```

**Structure Decision**: Keep one repository and reuse existing GitOps/deploy/test infrastructure, but add a Clawdiy-specific runtime subtree plus fleet-level registry/policy files. This preserves same-host rollout speed while keeping extraction to a separate node mostly a deployment-path change.

## Critical Planning Decisions

### Decision 1: Authoritative Inter-Agent Transport

**Chosen design**: Use a private authenticated HTTP JSON handoff path between permanent agents over internal endpoints, not Telegram, as the authoritative machine-to-machine transport.

**Rationale**:
- The spec already forbids relying on ad hoc chat behavior for authoritative handoff.
- Research shows fresh Telegram issues around duplicate delivery, missed completion signaling, and polling loops.
- HTTP JSON handoff supports explicit acknowledgement, correlation IDs, idempotency keys, and timeouts without introducing a broker in phase 1.

**Alternatives considered**:
- Telegram as authoritative transport: rejected because delivery semantics are user-facing and operationally noisy.
- Shared database queue: rejected for phase 1 because it introduces new stateful infrastructure and migration complexity.
- External broker (Redis/NATS/etc.): rejected for phase 1 because it exceeds MVP topology needs on the current host budget.

**Scope-change trigger**: If planning reveals that private HTTP JSON cannot satisfy same-host now and remote-node later without adding a broker, stop and run a narrow `speckit.clarify` on transport posture only.

### Decision 2: Initial Telegram Mode For Clawdiy

**Chosen design**: Start Clawdiy in long-polling mode for human ingress in phase 1; stage webhook mode as a later rollout gate after platform baseline health and handoff verification.

**Rationale**:
- Phase 1 already has a new subdomain, new agent runtime, new registry, and new auth boundary; adding public webhook rollout on day one compounds risk.
- The authoritative inter-agent transport is not Telegram, so Telegram can start in the operationally simpler mode.
- Existing repo patterns already treat webhook rollout as controlled and optional.

**Alternatives considered**:
- Webhook from day one: rejected because it adds public ingress coupling and secret/rotation overhead before baseline stability is proven.
- No Telegram in phase 1: rejected because user explicitly wants a dedicated Clawdiy bot identity.

**Scope-change trigger**: If user-visible requirements later mandate webhook-only behavior for MVP, stop and run a narrow `speckit.clarify` on Telegram mode only.

### Decision 3: OpenAI Codex OAuth Criticality

**Chosen design**: Treat OpenAI Codex OAuth as rollout-gated capability, not as a platform MVP blocker. Clawdiy platform deployment and inter-agent topology must succeed without it.

**Rationale**:
- Research captured fresh official-repo evidence of OAuth scope and login instability for `openai-codex`.
- The user wants a durable second platform agent, not a control plane that only works when one auth path is healthy.
- This preserves a path to GPT-5.4 suitability while keeping initial deployment and protocol rollout resilient.

**Alternatives considered**:
- Make Codex OAuth mandatory for MVP: rejected because a single flaky provider path would block the whole platform rollout.
- Exclude Codex OAuth entirely: rejected because GPT-5.4 / Codex-backed workflows remain part of target capability.

**Scope-change trigger**: If user later states that Clawdiy must ship day-one with Codex-backed coding role enabled, run a narrow `speckit.clarify` only on MVP-critical provider posture.

### Decision 4: Registry and Discovery Model

**Chosen design**: Use a version-controlled static registry file deployed read-only with each runtime in phase 1.

**Rationale**:
- Matches GitOps principles already enforced in this repository.
- Keeps discovery auditable and easy to promote from same-host to future-node deployment.
- Avoids introducing service discovery infrastructure before agent count justifies it.

### Decision 5: Internal Auth and Trust Mechanism

**Chosen design**: Separate human auth from service auth. Use per-agent service bearer secrets on private network paths, with allowlisted caller/recipient policy in the fleet registry and policy file.

**Rationale**:
- Same-host implicit trust is too weak for a long-lived fleet.
- mTLS can be deferred until remote-node extraction or higher agent count demands it.
- This keeps auth semantics stable when moving from same-host private network to private overlay networking later.

## Phase 0: Research Decisions

Phase 0 is already complete in [research.md](./research.md). The research record resolves the planning questions without unresolved user-intent blockers.

### Finalized Research Output

1. Separate Clawdiy runtime boundary on the current host is the correct first stage.
2. Telegram is user ingress only; authoritative machine handoff is private HTTP JSON.
3. Static Git-managed registry is sufficient for phase 1 discovery.
4. Service bearer auth plus allowlist policy is sufficient for phase 1 trust boundary.
5. Initial Telegram mode is long polling; webhook remains rollout-gated.
6. OpenAI Codex OAuth is rollout-gated rather than MVP-critical.
7. Audit evidence should live in per-agent append-only event artifacts plus existing logs/metrics surfaces.

No broad `speckit.clarify` pass is required. If a scope-changing blocker appears later, use a narrow clarify pass on that specific decision only.

## Phase 1: Design Artifacts

### Data Model

Generate and maintain [data-model.md](./data-model.md) for:
- `AgentIdentity`
- `AgentRegistryEntry`
- `AgentCredentialSet`
- `HandoffEnvelope`
- `HandoffExecution`
- `AuditEvent`
- `StateSnapshot`

### Contracts

Generate and maintain:
- [contracts/agent-handoff-contract.md](./contracts/agent-handoff-contract.md)
- [contracts/registry-contract.md](./contracts/registry-contract.md)
- [contracts/runtime-boundary.md](./contracts/runtime-boundary.md)
- [contracts/sample-handoff-submit.json](./contracts/sample-handoff-submit.json)

### Quickstart

Generate and maintain [quickstart.md](./quickstart.md) for operator flow:
- prepare secrets and registry
- validate compose and config
- deploy same-host Clawdiy stack
- verify private handoff and Telegram ingress
- gate Codex OAuth separately
- rollback safely

### Agent Context Update

Do not auto-write `AGENTS.md` from `update-agent-context.sh` in this feature. This repository marks `AGENTS.md` as generated, so the planning context remains in the Speckit package instead of editing generated agent instructions directly.

## Phase 2: Execution Readiness

### Stage 1: Fleet Skeleton and Runtime Boundary

- Add Clawdiy compose definition and runtime config subtree.
- Add fleet registry and policy files.
- Add separate secret inventory and state roots.
- Add preflight validation for duplicate identities, domain collisions, missing secrets, and auth-policy errors.

### Stage 2: Same-Host Clawdiy Deployment

- Deploy Clawdiy on the existing server in a distinct compose project.
- Reuse shared Traefik and monitoring networks while preserving per-agent ownership and labels.
- Verify that Moltinger and Clawdiy can restart independently.

### Stage 3: Authoritative Inter-Agent Handoff MVP

- Implement private HTTP JSON handoff with correlation IDs, explicit acks, retry limits, and timeout states.
- Persist audit events and handoff terminal evidence.
- Add smoke coverage for accepted, rejected, failed, and timed-out handoffs.

### Stage 4: Human Ingress and Operator Runbooks

- Enable Clawdiy Telegram polling mode and dedicated bot identity.
- Add deploy, repeat-auth, incident, rollback, and recovery runbooks.
- Add observability labels, alerts, and correlation guidance for operator diagnosis.

### Stage 5: Codex OAuth Capability Gate

- Add explicit post-auth verification and fail-closed handling for `openai-codex`.
- Keep Clawdiy healthy without Codex OAuth.
- Mark GPT-5.4/Codex-backed coding capability as available only after the auth gate passes.

### Stage 6: Future-Node Extraction Readiness

- Verify that canonical `agent_id`, registry shape, and handoff envelope do not change when endpoint placement changes.
- Document the private-network migration path for moving Clawdiy off the shared host.

## Verification Strategy

- `docker compose -f docker-compose.clawdiy.yml config --quiet`
- preflight secret and identity validation
- same-host health checks for Moltinger and Clawdiy
- protocol smoke cases: accept, reject, timeout, late completion, duplicate idempotency key
- Telegram ingress smoke in polling mode
- rollback drill restoring Moltinger-only or last-known-good Clawdiy state
- live-only provider/Codex auth validation behind explicit gate

## Complexity Tracking

> No constitution violations currently require justification.

| Complexity Area | Why Needed | Simpler Alternative Rejected Because |
|-----------------|------------|-------------------------------------|
| Separate Clawdiy compose stack | Preserves runtime/state isolation and future-node extraction path | Reusing Moltinger runtime would collapse trust/state boundaries |
| Fleet registry + policy files | Gives auditable addressing and authorization | Implicit same-host discovery is too fragile for permanent-agent growth |
| Service-to-service auth | Prevents shared human auth or implicit host trust | No-auth or shared-cookie approaches violate explicit trust boundary requirements |
