# Consilium Report

## Question
How should Moltis be hardened so configuration, OAuth state, provider catalog, and channel sessions cannot be silently broken again by deploy drift, secret drift, or stale runtime state?

## Execution Mode
Mode B (parallel expert review plus live UI/runtime verification)

## Evidence
- Live UI at `https://moltis.ainetic.tech` shows a built-in branch banner: `Running on: 031-moltis-reliability-diagnostics`. The rendered DOM includes the comment `Git branch banner (shown when running on a non-main branch)` and `window.__MOLTIS__.git_branch="031-moltis-reliability-diagnostics"`. This proves the runtime is intentionally exposing branch provenance and is currently running a non-`main` branch.
- Canonical provider/model baseline is tracked in [config/moltis.toml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/config/moltis.toml): `openai-codex` as primary provider and `openai-codex::gpt-5.4` as the production baseline.
- Writable OAuth/auth state is intentionally split out of git and preserved in the runtime config directory by [scripts/prepare-moltis-runtime-config.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/prepare-moltis-runtime-config.sh) and documented in [LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/knowledge/LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md).
- The March 21 OAuth RCA proved the primary failure mode was runtime drift, not token loss: the token store survived, but the live container was detached from the correct runtime config and provider catalog. See [2026-03-21-moltis-openai-oauth-runtime-drift.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-21-moltis-openai-oauth-runtime-drift.md).
- The March 21 Telegram RCA proved a second durable-state fault: even after OAuth/provider repair, the active Telegram session kept stale model/context state until explicit session reconcile/reset. See [2026-03-21-moltis-telegram-session-context-drift.md](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docs/rca/2026-03-21-moltis-telegram-session-context-drift.md).
- Current deploy/runtime guards are materially better than before, but some surfaces are still mutable by env drift or validated only at transport level. Relevant files: [scripts/deploy.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/deploy.sh), [scripts/render-moltis-env.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/render-moltis-env.sh), [docker-compose.prod.yml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/docker-compose.prod.yml), [scripts/test-moltis-api.sh](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/test-moltis-api.sh), [scripts/telegram-web-user-probe.mjs](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/scripts/telegram-web-user-probe.mjs).

## Expert Opinions

### Architect
- Root issue is not one broken file but split-brain across git-tracked config, rendered `.env`, writable runtime auth state, and persisted channel sessions.
- Silent drift remains possible unless runtime provenance and durable state ownership become explicit contracts.

### DevOps / GitOps
- A green `/health` is not enough. Runtime proof must include exact mount sources, exact runtime config path, exact provider catalog, and live canary on the canonical model.
- Production should not depend on a mutable checkout root. Immutable release roots plus attestation are the correct next hardening move.

### Security
- OAuth/auth files must stay outside git, but the path to them must be pinned and fail-closed.
- Rendering `.env` with empty auth values is too permissive; required auth secrets need hard failure at render/preflight time.

### QA / UAT
- Transport-level green is insufficient. `/status` and Telegram probes still allow semantic false-green unless they validate expected model, target chat, and failure classes such as verification gates or wrong-target replies.
- Recovery is incomplete until authoritative Telegram `/status` proves the repaired runtime state end-to-end.

### Moltis Domain Specialist
- Session-level model/context can outlive provider repairs.
- Durable Moltis state lives in more than one place: runtime config, `~/.moltis`, and per-channel sessions each need explicit ownership and recovery rules.

## Root Cause Analysis
- Primary root cause: Moltis durable state is split across four layers with incomplete ownership enforcement: tracked config, rendered server `.env`, writable runtime config/auth state, and channel/session state.
- Contributing factors:
  - production can still drift by path/source even when the container is healthy;
  - some auth/runtime inputs are mutable through env rendering rather than a pinned production contract;
  - operator diagnostics still prove transport more strongly than semantics;
  - recovery paths historically repaired provider state without reconciling active sessions.
- Confidence: High.

## Solution Options
1. Keep current guardrails and rely on runbooks. Lowest cost, highest repeat risk.
2. Strengthen smoke/UAT only. Good near-term value, but does not remove config mutability.
3. Make secret/env/runtime-dir contracts fail-closed. Strong P0 protection against accidental auth loss.
4. Add automated session reconciliation after provider/catalog recovery. Closes Telegram/UI stale-state failures.
5. Move production to immutable release roots plus runtime attestation and drift detection. Best long-term fix for silent runtime drift.
6. Treat recovery as complete only after authoritative Telegram and canonical model canary succeed. Strong operational guardrail.

## Recommended Plan
1. Make auth/config ownership fail-closed:
   - required auth secrets must not render as empty;
   - production runtime config dir must be pinned to the canonical path or an explicit allowlist.
2. Upgrade proof of health:
   - deploy verification should prove canonical provider/model, not only transport;
   - recovery should require restart survival plus authoritative Telegram `/status`.
3. Close stale-state gaps:
   - add explicit session reconcile/reset after provider/catalog changes;
   - document and audit `~/.moltis` as durable runtime state, not incidental cache.
4. Remove mutable-root drift:
   - design immutable release roots and runtime attestation;
   - add periodic drift detection outside the deploy path.

## Rollback Plan
- Keep all new hardening in tracked scripts/docs only; do not mutate live auth state speculatively.
- Before future state-migration work, back up both runtime config and `~/.moltis`.
- If a new guardrail blocks valid deploys, revert the guardrail commit and fall back to the current tracked runbook while preserving live state.

## Verification Checklist
- [x] Live UI branch banner explained from rendered DOM and runtime metadata
- [x] OAuth drift RCA reviewed
- [x] Telegram stale-session RCA reviewed
- [x] Config/runtime/auth ownership gaps identified
- [x] Backlog hardening items defined for follow-up
