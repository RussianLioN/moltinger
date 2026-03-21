# Implementation Plan: Moltis Reliability Diagnostics and Runtime Guardrails

**Branch**: `031-moltis-reliability-diagnostics` | **Date**: 2026-03-21 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/031-moltis-reliability-diagnostics/spec.md`

## Summary

Production Moltis currently exhibits several symptoms that look unrelated from the outside but collapse into one core pattern: the live runtime is not honoring the tracked repository contract. The running container is healthy on `/health`, yet it does not see the repository as `/server`, does not load repo-managed skills, does not use the prepared writable runtime config directory, and therefore fails across model selection, browser execution, vector memory usefulness, and some tool availability. This slice documents the evidence, separates configuration faults from operational drift, and lands only the safest repository-managed fixes: deploy-time runtime contract checks and a current API/RPC smoke diagnostic.

## Technical Context

**Language/Version**: Bash, TOML, Speckit Markdown, Docker Compose, Moltis 0.10.18 tracked image contract  
**Primary Dependencies**: `config/moltis.toml`, `docker-compose.prod.yml`, `scripts/deploy.sh`, `scripts/run-tracked-moltis-deploy.sh`, `scripts/test-moltis-api.sh`, `tests/lib/http.sh`, `tests/lib/rpc.sh`, `tests/lib/ws_rpc_cli.mjs`  
**Storage**: Runtime config under `${MOLTIS_RUNTIME_CONFIG_DIR}`, persistent Moltis state under `/home/moltis/.moltis`, repo-managed config/docs/scripts in the checkout mounted as `/server`  
**Testing**: Targeted shell tests, static config validation, script syntax checks, authoritative remote Telegram probing, remote runtime inspection  
**Target Platform**: Shared remote Moltis deployment in Docker, plus repository validation in this worktree  
**Project Type**: Diagnostics and guardrail hardening for an existing production runtime  
**Performance Goals**: Fail fast on invalid runtime contract; keep smoke diagnostics lightweight and operator-friendly  
**Constraints**: No speculative destructive server changes, official-docs-first setup guidance, remote target remains authoritative, preserve GitOps discipline  
**Scale/Scope**: Single Moltis deployment, one repository-managed runtime contract, one safe-fix slice

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS. Root instructions, memory/session files, local `AGENTS.md`, tracked config, runtime scripts, live container state, Telegram authoritative probe, and official Moltis docs were reviewed before proposing fixes.
- Single Source of Truth: PASS. The tracked repository remains the intended source for config, compose, scripts, and skills, while the investigation explicitly calls out where the live runtime drifted away from that source.
- Library-First Development: PASS. Safe fixes reuse existing deploy and test helpers instead of inventing parallel runtime control planes.
- Code Reuse & DRY: PASS. The smoke script will reuse the shared auth/RPC helpers already used by integration tests.
- Strict Type Safety: PASS for the Speckit artifact layer and JSON/RPC contract reuse; no new loose data shape is introduced.
- Atomic Task Execution: PASS. The slice is decomposed into evidence capture, guardrail hardening, diagnostic script refresh, and validation.
- Quality Gates: PASS. Planned fixes will be validated with targeted shell/static tests.
- Progressive Specification: PASS. Diagnostics are captured in the spec package before expanding implementation.

No constitution exception is required.

## Evidence Snapshot

### Tracked Intent

- `docker-compose.prod.yml` expects the Moltis container to use `working_dir: /server`, mount the repository checkout as `./:/server:ro`, and mount `${MOLTIS_RUNTIME_CONFIG_DIR}` into `/home/moltis/.config/moltis`.
- `config/moltis.toml` expects repo-visible skills at `/server/skills`, repo-visible scripts under `/server/scripts`, and writable runtime state under `/home/moltis/.moltis`.
- `scripts/prepare-moltis-runtime-config.sh` is already designed to copy static config into a writable runtime directory while preserving runtime-managed auth files.
- Static tests already assert some of this contract, but only at the tracked-file layer.

### Live Production Facts

- The running Moltis container does **not** mount `/server` at all and runs from `/home/moltis`.
- The running Moltis container mounts `/opt/moltinger/config` read-only into `/home/moltis/.config/moltis` instead of the prepared runtime config directory.
- Runtime logs show `skills: 2 enabled, 0 repos`; repo skills from `/server/skills` are absent.
- Runtime logs show `memory system initialized` with `chunks: 0` and watch scope limited to `~/.moltis`, so project docs are not entering useful vector memory.
- Runtime logs show browser image pull failures due Docker socket permission errors; official docs also require Docker-aware browser container connectivity for sibling browser containers.
- Tavily MCP search intermittently fails its SSE handshake and auto-restart sequence.
- Telegram authoritative testing returns `model 'openai-codex::gpt-5.3-codex-spark' not found`, matching stale provider/model state rather than the tracked provider surface.
- Runtime logs show `provider_keys.json.tmp... read-only file system`, proving the live config mount is incompatible with runtime-managed auth/key persistence.

## Root Cause Classification

### Operational Drift

1. The running Moltis container no longer matches tracked compose intent: `/server` is missing, the working directory is wrong, and the runtime config mount points at a stale read-only path.
2. The active `moltis.toml` inside the container differs materially from tracked `config/moltis.toml`, including provider surface and skill autoload behavior.
3. Persisted session/model state still references removed `openai-codex::*` models, which leaks stale runtime assumptions into Telegram chat behavior.
4. `~/.moltis/MEMORY.md` and adjacent runtime context contain stale content unrelated to the current repository contract.

### Misconfiguration

1. `config/moltis.toml` leaves memory watch scope effectively pointed away from repository knowledge, so even a healthy runtime will not build useful project vector memory by default.
2. Browser automation is enabled, but the configuration does not explicitly set the Docker-in-Docker browser connectivity contract documented by Moltis for Docker deployments.
3. Built-in web search is disabled while production depends entirely on a remote Tavily MCP path that is already showing transport instability.

### Missing Integration

1. Repo-managed skills and scripts are not visible to the running container because the checkout is not mounted as `/server`.
2. Repo knowledge cannot flow into vector memory because the runtime neither sees the repository nor watches repository docs/knowledge paths.
3. The tracked codex-update runtime contract depends on container-visible `/server/...` paths; those integrations are unreachable while `/server` is absent.

### Bugs

1. `scripts/test-moltis-api.sh` still uses the retired `/login` form flow and `/api/v1/chat`, so it misdiagnoses current runtimes.
2. Session/model state appears to survive provider-surface drift without auto-healing; this is a runtime bug candidate, but fixing it is deferred until the tracked runtime contract is restored.
3. Browser tool startup currently fails at Docker access; if permission and connectivity are both required, the runtime may be missing a clearer preflight error path. That remains a runtime bug candidate, not a repository-managed fix in this slice.

## Minimal Safe Fix Plan

### Phase 1 - Lock The Diagnosis Into Artifacts

1. Create the Speckit package and record the exact tracked-vs-live evidence, root-cause categories, and safe remediation order.
2. Keep deferred operational actions explicit so repository fixes are not mistaken for live repair completion.

### Phase 2 - Fail Fast On Broken Runtime Contract

1. Extend deploy verification so Moltis is considered healthy only if:
   - the working directory is `/server`
   - the checkout is mounted into `/server`
   - `/server/skills` is visible inside the container
   - `/home/moltis/.config/moltis` is mounted from the configured runtime config directory
   - the runtime config directory is writable for runtime-managed files
2. Cover the new guardrail with targeted repository tests so future drift cannot silently re-enter through script edits.

### Phase 3 - Refresh Operator Diagnostics

1. Update `scripts/test-moltis-api.sh` to use the current `/api/auth/*` contract and the current WebSocket RPC chat/status path.
2. Reuse existing shared test helpers instead of duplicating auth or RPC logic.

### Phase 4 - Defer Live-Only Remediation

The following actions are intentionally **not** auto-applied in this slice and must remain operator-driven after the repository guardrails land:

- redeploy production so the tracked runtime contract is actually applied
- clear or migrate stale session/model state that still references removed models
- repair browser Docker access or runtime permissions on the target host
- stabilize or replace the Tavily MCP transport path
- explicitly wire repository docs/knowledge into memory watch/index scope and then backfill embeddings

## Structure Decision

Keep this slice intentionally narrow:

- Speckit artifacts under `specs/031-moltis-reliability-diagnostics/`
- deploy/runtime verification hardening in existing deploy scripts
- operator smoke diagnostic refresh in the existing Moltis API test script
- no speculative production state mutation inside repository code

This keeps the work safe, auditable, and aligned with GitOps.

## Phase Breakdown

### Phase 0: Evidence Capture

- Capture tracked config intent and live runtime evidence.
- Cross-check key assumptions against official Moltis docs.

### Phase 1: Artifact Creation

- Write `spec.md`, `plan.md`, and `tasks.md`.
- Encode root-cause categories and remediation order.

### Phase 2: Guardrail Hardening

- Add Moltis runtime contract verification to deploy checks.
- Add targeted repository validation for the new guardrails.

### Phase 3: Diagnostic Tool Refresh

- Refresh `scripts/test-moltis-api.sh` to current auth/RPC behavior.
- Validate the updated script with syntax and targeted contract checks.

### Phase 4: Handoff

- Update `tasks.md` with completed safe fixes.
- Leave a precise operational follow-up list for the actual live repair.

### Phase 5: Architectural Hardening Backlog

- Record the consilium-backed backlog for fail-closed auth/config durability so follow-up work is driven by tracked artifacts rather than chat history.
- Prioritize secret/env hardening, runtime-dir pinning, semantic proof of health, session reconciliation, durable-state audit, and immutable release-root design.
