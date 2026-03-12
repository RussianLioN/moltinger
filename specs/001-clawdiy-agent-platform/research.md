# Research: Clawdiy Agent Platform

**Feature**: 001-clawdiy-agent-platform  
**Date**: 2026-03-09  
**Status**: Complete  
**Purpose**: Capture the official evidence, fresh community evidence, and explicit inference needed to plan Clawdiy as a second permanent platform agent without repeating discovery work.

## 1. Executive Summary

Clawdiy should be treated as a second permanent platform runtime, not as a temporary extension of Moltinger. The evidence points to four planning constraints:

1. Official Moltis and OpenClaw docs both support multi-agent and Telegram-based operation, but they also assume strong separation of state, auth, and routing.
2. Fresh March 2026 repo traffic shows multiple real-world failures in Telegram delivery, sub-agent completion signaling, workspace inheritance, and OpenAI Codex OAuth scopes.
3. Telegram is appropriate for human ingress and notifications, but recent issue patterns make it a poor choice for authoritative machine-to-machine handoff.
4. The first rollout can reuse the current server, Traefik, CI/CD, and monitoring baseline, but Clawdiy needs its own runtime boundary so later extraction to a separate node only changes endpoint placement, not protocol semantics.

## 2. Local Baseline From This Repository

### Current Production Reality

- Server baseline is `ainetic.tech` with `2` CPU cores and `8 GB` RAM, documented in [MEMORY.md](../../MEMORY.md).
- Current Moltinger ingress is `https://moltis.ainetic.tech`.
- Traefik routing depends on the existing external Docker network `traefik-net`.
- GitHub Secrets are the canonical secret source; CI/CD generates `/opt/moltinger/.env`.
- Production compose already exposes health, Prometheus scraping, logging rotation, and shared monitoring services in [docker-compose.prod.yml](../../docker-compose.prod.yml).

### Local Design Implication

Clawdiy should reuse the existing GitOps and ingress patterns, but must not reuse Moltinger's config directory, state volume, bot token, auth password, or provider auth artifacts.

## 3. Official Evidence

### 3.1 Moltis Official Documentation

| Source | Checked | Key Evidence | Planning Impact |
|---|---|---|---|
| https://docs.moltis.org/docker.html | 2026-03-09 | Docker deployment expects persistent config under `~/.config/moltis`, persistent data under `~/.moltis`, optional Docker socket mount, and reverse-proxy mode with `MOLTIS_NO_TLS=true`. It also documents headless OAuth callback behavior on the redirect port. | Clawdiy needs its own config/state roots, its own OAuth callback handling, and a deployment shape that stays valid behind Traefik. |
| https://docs.moltis.org/authentication.html | 2026-03-09 | Remote access requires auth outside localhost. Docs support bootstrap via browser setup or preconfigured `MOLTIS_PASSWORD`. | Clawdiy needs separate auth bootstrap, reset, and recovery runbooks; it cannot inherit Moltinger's auth state. |
| https://docs.moltis.org/agent-presets.html | 2026-03-09 | Moltis explicitly frames specialized agents through reusable presets and role-focused identities. | Permanent role-specific agents are aligned with the official product model, not a repo-specific hack. |
| https://docs.moltis.org/channels.html | 2026-03-09 | Moltis supports Telegram accounts, account bindings, and channel-specific stream modes. | Clawdiy can have its own Telegram ingress, but channel behavior must stay separate from authoritative inter-agent transport. |
| https://docs.moltis.org/hooks.html | 2026-03-09 | Moltis supports hooks around prompt, session, notifications, and tool lifecycle. | Audit trail, escalation hooks, and operator notifications can be designed as first-class operational behaviors. |
| https://docs.moltis.org/hooks-reference.html | 2026-03-09 | Hook docs describe structured lifecycle events such as notification, stop, and session events. | Planning can require event-based audit and escalation without inventing a platform concept from scratch. |
| https://docs.moltis.org/openclaw-import.html | 2026-03-09 | Moltis can import data from OpenClaw homes or custom paths. | Migration and coexistence between Moltis and OpenClaw are officially recognized concerns. |

### 3.2 OpenClaw Official Documentation

| Source | Checked | Key Evidence | Planning Impact |
|---|---|---|---|
| https://docs.openclaw.ai/concepts/multi-agent | 2026-03-09 | OpenClaw documents agent routing, explicit addressing, and multi-agent session behavior. | Clawdiy should use stable agent ids and explicit addressing instead of chat-local heuristics. |
| https://docs.openclaw.ai/agents/teams-and-groups | 2026-03-09 | Teams/groups docs describe shared-channel multi-agent patterns. | Shared human communication surfaces are possible, but group routing rules must be explicit and testable. |
| https://docs.openclaw.ai/agents/telegram | 2026-03-09 | Telegram docs cover agent/channel setup for OpenClaw. | Separate bot identity per permanent agent is an expected deployment pattern. |
| https://docs.openclaw.ai/models-and-auth | 2026-03-09 | OpenClaw has provider auth flows, including `codex-oauth`, and supports stored auth profiles. | Clawdiy should treat OpenAI Codex auth as its own lifecycle with operator verification, not as a shared host credential. |
| https://docs.openclaw.ai/start/faq | 2026-03-09 | FAQ guidance favors Tailscale/SSH style remote access over exposing internal control surfaces broadly to the public internet. | Future remote-node extraction should prefer private agent-to-agent routing over public cross-agent traffic. |

### 3.3 Telegram Official Documentation

| Source | Checked | Key Evidence | Planning Impact |
|---|---|---|---|
| https://core.telegram.org/bots/api | 2026-03-09 | Bot API defines polling/webhook delivery, `secret_token` for webhook verification, and update-delivery semantics. | Telegram ingress must have explicit verification, replay handling, and offset hygiene. |
| https://core.telegram.org/bots/api#setwebhook | 2026-03-09 | Webhooks support a verification token header and expose pending update counters. | Clawdiy rollout should document webhook verification and backlog monitoring if webhook mode is used. |
| https://core.telegram.org/bots/faq | 2026-03-09 | Bot FAQ discusses privacy mode and bot behavior constraints in chats/groups. | Multi-bot group setups need explicit operator steps; they are not safe defaults. |

### 3.4 OpenAI Official Documentation

| Source | Checked | Key Evidence | Planning Impact |
|---|---|---|---|
| https://openai.com/index/introducing-codex/ | 2026-03-09 | OpenAI positions Codex as a cloud coding agent product with separate auth and runtime posture. | If Clawdiy later uses Codex-backed flows, those auth and runtime assumptions must remain agent-local and operationally reversible. |

## 4. Community Evidence

Community evidence below is intentionally limited to fresh GitHub issues and PRs in the official OpenClaw and Moltis repos. This gives first-hand operational signals without relying on second-hand summaries.

| Source | Checked | Community Signal | Planning Impact |
|---|---|---|---|
| https://github.com/openclaw/openclaw/issues/40842 | 2026-03-09 | Telegram polling can enter an infinite retry loop when media-group processing fails and offsets are not advanced. | Inter-agent transport must not depend on Telegram delivery semantics; Clawdiy needs dead-letter and retry-cap logic. |
| https://github.com/openclaw/openclaw/issues/40605 | 2026-03-09 | Sub-agent completion can be delivered to users while the requester session never receives the internal completion signal. | User-visible delivery and machine-facing acknowledgement must be modeled as separate obligations. |
| https://github.com/openclaw/openclaw/issues/40765 | 2026-03-09 | Channel-triggered runs may not produce the same real-time observability signals as dashboard-triggered runs. | The audit trail must be channel-agnostic and session-correlation aware. |
| https://github.com/openclaw/openclaw/issues/40825 | 2026-03-09 | Spawned sub-agents can inherit the parent's workspace instructions instead of their own configured workspace. | Per-agent workspace and instruction isolation must be a first-class acceptance concern for Clawdiy and future permanent agents. |
| https://github.com/openclaw/openclaw/issues/39994 | 2026-03-09 | `codex-oauth` OAuth can succeed superficially but still lack required scopes such as `api.responses.write`. | OpenAI Codex auth cannot be assumed healthy after login; the plan needs explicit post-auth verification and fail-closed behavior. |
| https://github.com/openclaw/openclaw/issues/40715 | 2026-03-09 | Users are actively asking for simultaneous, independently scheduled agent tasks. | The platform design should assume concurrent permanent-agent work is a real requirement, not a hypothetical future feature. |
| https://github.com/openclaw/openclaw/pull/38381 | 2026-03-09 | The repo is actively documenting Codex CLI multi-agent orchestration and sandbox inheritance. | A future Clawdiy role can participate in fleet-style coding workflows, but sandbox inheritance and role boundaries need explicit policy. |
| https://github.com/openclaw/openclaw/pull/38685 | 2026-03-09 | Multi-agent Telegram group setup has non-obvious gotchas: privacy mode, re-adding bots, sender filters, group policy. | Group-based multi-agent UX needs operator runbooks and should not be treated as self-explanatory. |
| https://github.com/moltis-org/moltis/issues/207 | 2026-03-09 | Moltis users still report Open Codex OAuth authentication failures in Docker-based setups. | Initial Clawdiy rollout should not make OpenAI Codex OAuth the only path to platform viability. |
| https://github.com/moltis-org/moltis/issues/316 | 2026-03-09 | Authentication reset flows can fail or loop back unexpectedly. | Auth reset and recovery must have a documented non-UI fallback path. |
| https://github.com/moltis-org/moltis/issues/319 | 2026-03-09 | Tool outputs may disappear from later model context in Telegram-heavy flows. | Handoff contracts must carry explicit artifacts and correlation data; they cannot rely on model memory continuity. |
| https://github.com/moltis-org/moltis/issues/371 | 2026-03-09 | Telegram voice-related replies can duplicate text output when streaming and delivery fallbacks interact. | Delivery dedupe rules must be explicit for channel notifications. |
| https://github.com/moltis-org/moltis/issues/235 | 2026-03-09 | There is active demand for PTY-backed multi-agent orchestration around Claude/Codex style tools. | If Clawdiy grows into a coding-agent runtime, PTY semantics belong in future implementation planning, not in the same trust boundary as end-user chat. |

## 5. Explicit Inference

The following points are not direct quotes from the sources above. They are the planning synthesis that follows from the evidence.

### 5.1 Platform Topology

- Clawdiy should start as a separate compose project on the current server, with dedicated ingress, volumes, and secrets, but may reuse shared Traefik and monitoring networks.
- The canonical agent model should not encode "same host" assumptions. Future node extraction should only change endpoint placement and infrastructure routing.
- The current host is resource-constrained enough that per-agent resource budgets and health thresholds must be part of planning, not afterthoughts.

### 5.2 Inter-Agent Transport

- Telegram should remain a human-facing ingress and notification channel, not the authoritative transport for platform-to-platform handoff.
- The primary handoff path should be an authenticated platform-native RPC/API transport with explicit acknowledgements and correlation identifiers.
- A manual or operator-mediated fallback path should exist when the primary handoff path is degraded, but that fallback should still produce audit evidence.

### 5.3 Identity and Trust

- Canonical ids such as `moltinger` and `clawdiy` should be the durable source of identity. Domains, bots, and internal endpoints are transport-specific attachments to those identities.
- Human auth, service-to-service auth, Telegram bot auth, and model-provider auth should be tracked as four separate lifecycles.
- No agent should inherit another agent's workspace instructions, model auth profiles, or persistent state by default.

### 5.4 Operational Readiness

- Repeat-auth procedures for Telegram and OpenAI Codex need to be treated as operational runbooks, not as hidden setup trivia.
- Audit trail requirements must include user-visible outcomes, machine-visible acknowledgements, and operator interventions under a shared correlation model.
- Backup and restore should be scoped per agent, so one compromised or misconfigured agent can be recovered without rewriting the rest of the platform.

## 6. Phase 0 Decision Log

### 6.1 Authoritative Inter-Agent Transport

**Decision**: Use a private authenticated HTTP JSON handoff path between agents as the authoritative machine-to-machine transport in phase 1.

**Rationale**:
- Supports correlation IDs, acknowledgements, retries, and timeout control directly.
- Keeps authoritative handoff independent from Telegram delivery behavior.
- Reuses platform-native request/response semantics without adding a broker on the current host.

**Alternatives considered**:
- Telegram as authoritative handoff: rejected due to duplicate, delayed, and user-visible delivery failure modes.
- Shared database queue: rejected for phase 1 because it adds new stateful infrastructure and schema migration burden.
- External broker: rejected for phase 1 because it exceeds current host and rollout complexity budget.

**Library/Platform**: Reuse OpenClaw/Moltis HTTP or gateway-style JSON exchange patterns, Docker private networking, and existing GitOps deployment flow. No new transport library or broker in phase 1.

### 6.2 Phase-1 Registry and Discovery

**Decision**: Use a version-controlled static registry file for permanent agents, deployed read-only with each runtime.

**Rationale**:
- Aligns with GitOps and auditability requirements already enforced in this repo.
- Keeps same-host and future-node routing semantics consistent.
- Avoids premature service-discovery infrastructure.

**Alternatives considered**:
- Dynamic service discovery: rejected as premature for phase 1.
- Database-backed registry: rejected because it adds operational state before agent count justifies it.

**Library/Platform**: Reuse repo-managed JSON configuration and existing deployment synchronization patterns.

### 6.3 Internal Auth and Trust Boundary

**Decision**: Use per-agent service bearer secrets on private network paths, separate from human login credentials.

**Rationale**:
- Prevents implicit trust based only on host locality.
- Keeps service auth separate from user cookies/passwords and Telegram tokens.
- Preserves a clean upgrade path to stronger transport security later.

**Alternatives considered**:
- Implicit same-host trust: rejected as too weak for long-lived fleet operation.
- Shared human session/auth state: rejected as a cross-agent blast-radius problem.
- Day-one mTLS: rejected as too heavy for phase 1 relative to host budget and rollout speed.

**Library/Platform**: Reuse GitHub Secrets, CI-generated env material, private Docker networking, and policy allowlists.

### 6.4 Initial Telegram Mode

**Decision**: Start Clawdiy in long-polling mode for phase 1 and stage webhook mode behind a later rollout gate.

**Rationale**:
- Keeps the first production rollout focused on runtime isolation and authoritative handoff.
- Avoids coupling the same-host MVP to public webhook rollout and secret rotation complexity.
- Still satisfies the requirement for a dedicated Clawdiy Telegram bot.

**Alternatives considered**:
- Webhook from day one: rejected as higher ingress and operator complexity before baseline stability.
- No Telegram in phase 1: rejected because dedicated Telegram ingress is part of the requested feature.

**Library/Platform**: Reuse built-in Telegram channel support and existing repo webhook-monitoring/rollout patterns as later-stage references.

### 6.5 OpenAI Codex OAuth Criticality

**Decision**: Treat OpenAI Codex OAuth as rollout-gated capability rather than platform MVP-critical dependency.

**Rationale**:
- Fresh repo evidence shows unresolved OAuth scope and login instability.
- The user wants a durable second platform agent, not a platform blocked by a single provider auth path.
- This preserves GPT-5.4/Codex readiness as a staged capability rather than a day-one dependency.

**Alternatives considered**:
- MVP requires Codex OAuth: rejected because it makes platform rollout hostage to unstable provider auth.
- Exclude Codex entirely: rejected because GPT-5.4/Codex-backed work remains in target scope.

**Library/Platform**: Reuse existing provider-chain patterns and explicit post-auth verification scripts/runbooks.

### 6.6 Audit Artifact Storage

**Decision**: Store authoritative handoff/audit artifacts in append-only JSONL event files inside each agent's persistent state root, with logs/metrics as observability overlays rather than source of truth.

**Rationale**:
- Keeps evidence local to the agent runtime for backup, restore, and rollback.
- Avoids introducing a central database before phase 1 needs it.
- Supports correlation between handoff events, auth events, and operator actions.

**Alternatives considered**:
- Logs only: rejected because logs are insufficient as authoritative state.
- Central audit database: rejected as premature for current rollout scope.

**Library/Platform**: Reuse file-based state boundaries and existing monitoring/logging stack.

## 7. Recommended Planning Decisions

These are the decisions this research recommends handing into the implementation planning phase.

1. Define Clawdiy as a permanent agent with its own canonical id, subdomain, Telegram bot, config root, state root, secret set, and auth lifecycle.
2. Define a static, version-controlled phase-1 registry for agent discovery and capability declarations.
3. Define a versioned agent-to-agent envelope with sender, recipient, correlation ids, idempotency keys, delivery deadlines, and terminal-state evidence.
4. Treat user-channel delivery and internal agent acknowledgement as separate flows that can both succeed or fail independently.
5. Keep cross-agent trust private-by-default. Public subdomains are for human access; inter-agent routing should be private or explicitly authenticated.
6. Ship staged rollout and rollback from day one: same-host Clawdiy first, protocol handoff second, remote-node extraction later.
7. Make the implementation epic include documentation ownership for protocol docs, deployment docs, secrets docs, and topology registry updates.

## 8. Planning Inputs For The Next Phase

The next `speckit.plan` phase should treat the following as required inputs:

- [spec.md](./spec.md) for the product/operational contract.
- [protocol.md](./protocol.md) for the detailed inter-agent contract draft.
- Current production compose and config patterns in [docker-compose.prod.yml](../../docker-compose.prod.yml) and [config/moltis.toml](../../config/moltis.toml).
- Secret-source rules in [docs/SECRETS-MANAGEMENT.md](../../docs/SECRETS-MANAGEMENT.md).
- Topology constraints in [docs/GIT-TOPOLOGY-REGISTRY.md](../../docs/GIT-TOPOLOGY-REGISTRY.md).

## 9. Follow-On Research Track

After the initial Clawdiy platform rollout, the repository collected a dedicated follow-on OAuth track for real remote-container runtime auth:

- [docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md)

That document refines the `codex-oauth` problem from “rollout-gated capability” into an explicit runtime auth lifecycle problem with three compared operator methods, consolidated consilium scoring, and a follow-on Speckit package for implementation planning.
