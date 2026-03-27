# Implementation Plan: Moltis Reliability Diagnostics and Runtime Guardrails

**Branch**: `031-moltis-reliability-diagnostics` | **Date**: 2026-03-21 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/031-moltis-reliability-diagnostics/spec.md`

## Summary

Production Moltis currently exhibits several symptoms that look unrelated from the outside but collapse into one core pattern: the live runtime is not honoring the tracked repository contract. The running container is healthy on `/health`, yet it does not see the repository as `/server`, does not load repo-managed skills, does not use the prepared writable runtime config directory, and therefore fails across model selection, browser execution, vector memory usefulness, and some tool availability. After the OAuth/runtime contract repair, the highest unresolved live blockers were Tavily SSE instability and `memory_search` embedding-provider failures. The next incident pass showed the deeper root cause: tracked `config/moltis.toml` already pins memory to `ollama/nomic-embed-text`, but the writable runtime `moltis.toml` had drifted back to an older auto-detect memory contract, while `OLLAMA_API_KEY` existed in server `.env` but was not forwarded into the running `moltis` container. A new live-authoritative Telegram pass on 2026-03-26 then exposed another user-facing regression: the bot can emit internal telemetry replies like `📋 Activity log`, `💻 Running`, and `🧠 Searching memory...`, while the current authoritative UAT still passes because its reply-quality gate only recognizes plain ASCII `Activity log ...` forms and ignores recent invalid pre-send incoming activity. The follow-up evidence on 2026-03-27 proved that browser recovery also has a second layer: restoring Docker socket access and `container_host` is not enough when the sibling browser container still receives a non-writable host-visible `profile_dir` bind mount and the real Telegram `t.me/...` path was not re-exercised after the partial fix. Production policy adds one more hard constraint: shared production deploys are allowed only from `main`. This slice therefore extends the safe repository-managed fixes with a fail-closed Telegram channel-output guardrail, browser/sandbox contract lessons, and authoritative UAT hardening, while keeping any live repair or rollout on the canonical `main` path.

## Technical Context

**Language/Version**: Bash, TOML, Speckit Markdown, Docker Compose, Moltis 0.10.18 tracked image contract  
**Primary Dependencies**: `config/moltis.toml`, `docker-compose.prod.yml`, `scripts/deploy.sh`, `scripts/run-tracked-moltis-deploy.sh`, `scripts/test-moltis-api.sh`, `tests/lib/http.sh`, `tests/lib/rpc.sh`, `tests/lib/ws_rpc_cli.mjs`  
**Storage**: Runtime config under `${MOLTIS_RUNTIME_CONFIG_DIR}`, persistent Moltis state under `/home/moltis/.moltis`, repo-managed config/docs/scripts in the checkout mounted as `/server`  
**Testing**: Targeted shell tests, static config validation, script syntax checks, authoritative remote Telegram probing, remote runtime inspection  
**Target Platform**: Shared remote Moltis deployment in Docker, plus repository validation in this worktree  
**Project Type**: Diagnostics and guardrail hardening for an existing production runtime  
**Performance Goals**: Fail fast on invalid runtime contract; keep smoke diagnostics lightweight and operator-friendly  
**Constraints**: No speculative destructive server changes, official-docs-first setup guidance, remote target remains authoritative, preserve GitOps discipline, and respect the deploy-only-from-`main` production policy
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
- Runtime logs show repeated `memory_search` failures where the fallback chain hits `https://api.z.ai/api/coding/paas/v4/embeddings` with `400 Bad Request`, then Groq embeddings with `401 Unauthorized`.
- Live runtime diff shows tracked `config/moltis.toml` already pins `[memory] provider = "ollama"` with `model = "nomic-embed-text"` and repo-visible `watch_dirs`, while `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml` still carries the older default commented memory block and `http://localhost:11434/v1`.
- Server `.env` already contains `OLLAMA_API_KEY`, but the running `moltis` container environment does not, so cloud-backed Ollama models such as `gemini-3-flash-preview:cloud` never enter the live provider catalog.
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
4. Memory embeddings are left on auto-detect, so the runtime can infer a chat-provider chain that is unsuitable for embeddings, including the Z.ai Coding endpoint under `[providers.openai]`.
5. The tracked compose contract forwarded `OLLAMA_API_KEY` to the Ollama sidecar but not to the `moltis` container itself, so cloud-backed Ollama chat models could be configured in git but remain invisible at runtime.
6. The tracked Moltis identity/prompt contract does not explicitly forbid internal activity/tool-progress traces in user-facing messaging channels, so the repo has no fail-closed prompt guard against `Activity log`, `Running`, or `Searching memory` style replies.

### Missing Integration

1. Repo-managed skills and scripts are not visible to the running container because the checkout is not mounted as `/server`.
2. Repo knowledge cannot flow into vector memory because the runtime neither sees the repository nor watches repository docs/knowledge paths.
3. The tracked codex-update runtime contract depends on container-visible `/server/...` paths; those integrations are unreachable while `/server` is absent.
4. Search and memory health have no dedicated repository-managed proof today, so transport-green deploy/UAT signals can miss Tavily SSE churn and embedding-provider drift.
5. Deploy/runtime attestation proved mount source and writability, but did not yet prove that the writable runtime `moltis.toml` still matched tracked `config/moltis.toml`.

### Bugs

1. `scripts/test-moltis-api.sh` still uses the retired `/login` form flow and `/api/v1/chat`, so it misdiagnoses current runtimes.
2. Session/model state appears to survive provider-surface drift without auto-healing; this is a runtime bug candidate, but fixing it is deferred until the tracked runtime contract is restored.
3. Browser tool startup currently fails at Docker access; if permission and connectivity are both required, the runtime may be missing a clearer preflight error path. That remains a runtime bug candidate, not a repository-managed fix in this slice.
4. The authoritative Telegram UAT reply-quality gate is emoji-blind for internal telemetry replies, so it can return green on `📋 Activity log`, `💻 Running`, and `🧠 Searching memory...`.
5. The authoritative Telegram UAT does not fail when the quiet window immediately before the probe already contains a recent invalid incoming Telegram reply, so chat contamination can slip through as a false pass.

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
3. Add a read-only `moltis-search-memory-diagnostics.sh` entrypoint that summarizes tracked Tavily/memory contract plus optional runtime-log failure taxonomy without mutating live state.

### Phase 4 - Highest-Priority Live Follow-Up

The following actions are intentionally **not** auto-applied in this slice and must remain operator-driven after the repository guardrails land:

- stabilize Tavily SSE search or replace it with a less fragile search path
- arrest `memory_search` embedding failures by pinning a deterministic memory contract or explicitly forcing keyword-only fallback until a supported embedding backend is validated
- add live search/memory proof once the runtime contract is healthy

### Phase 4a - Embedding And Ollama Contract Repair

The current incident narrows the highest-priority live work to one concrete contract:

- deploy/runtime verification must fail if writable runtime `moltis.toml` drifts away from tracked `config/moltis.toml`
- the `moltis` container must receive `OLLAMA_API_KEY` so cloud-backed Ollama chat models can be discovered
- operator runbooks and RCA/lessons must point first to runtime-config parity and env delivery before blaming provider auth or third-party embeddings endpoints

### Phase 4b - Mainline Landing Strategy (Solution 3)

Because production deploys are blocked from feature branches, incident closure must be split deliberately instead of merging this entire branch into `main`.

`PR1` to `main` should carry only the production-critical embedding/Ollama delta plus blocking proof:

- source the runtime-only carrier from the already proven technical deltas in this branch, not by merging the whole branch
  - `95a0feb`: pin memory embeddings to Ollama and repo-visible `watch_dirs`
  - `81ebeaa`: force-recreate Moltis on deploy so env/config changes actually take effect
  - `a1829bf` + `87a39fc`: live runtime attestation plus component proof
  - `e7f3066`: forward `OLLAMA_API_KEY` into `moltis` and fail closed on runtime `moltis.toml` drift
- `config/moltis.toml`
  - keep only the `[memory]` pin to `provider = "ollama"`, the verified Ollama embeddings endpoint/model, and repo-visible `watch_dirs`
- `docker-compose.prod.yml`
  - forward `OLLAMA_API_KEY` into the `moltis` container
- `scripts/deploy.sh`
  - force-recreate the Moltis runtime during deploy so new env/config take effect immediately
  - fail deploy when writable runtime `moltis.toml` diverges from tracked `config/moltis.toml`
- `scripts/moltis-runtime-attestation.sh`
  - include runtime-config parity proof in post-deploy attestation so the same drift cannot pass as healthy
- workflow/control-plane plumbing only as needed to execute the attestation during canonical deploy from `main`
  - `.github/workflows/deploy.yml`
  - `.github/workflows/uat-gate.yml`
  - `scripts/run-tracked-moltis-deploy.sh`
- blocking tests for that runtime-only carrier
  - `tests/static/test_config_validation.sh`
  - `tests/unit/test_deploy_workflow_guards.sh`
  - `tests/component/test_moltis_runtime_attestation.sh`
  - `tests/component/test_moltis_search_memory_diagnostics.sh`

As of 2026-03-26, `PR1` has been merged to `main`, the canonical production deploy from `main` succeeded, and the authoritative remote runtime has proven the fix via successful live `memory_search` plus Ollama provider/model availability checks.

`PR2` should stay deferred until after successful live verification from `main` and carry the mutable post-incident knowledge layer through a fresh docs-only carrier based on the verified `main` state, not by opening this mixed-scope branch directly:

- RCA / consilium / rules / runbook updates
- lessons index tooling and lessons content
- Speckit artifact finalization that depends on live outcome wording
- any browser/Tavily or other reliability hardening not strictly required to clear the current embedding/Ollama blocker
- do not blindly drag unrelated browser/Tavily/runtime-hardening commits from this branch into `PR1`; if they are still desired, land them later as separate reviewed work after the current blocker is closed
- do not open `PR2` directly from `031-moltis-reliability-diagnostics`; materialize a narrow docs/process carrier from `main` so the deferred learning layer stays reviewable and rollback-safe

### Phase 5 - Remaining Live-Only Remediation

The following actions remain deferred and must stay operator-driven after the highest-priority Tavily/memory blockers are addressed:

- merge the runtime-only `PR1` into `main`, then redeploy production from `main` so the tracked runtime contract is actually applied
- clear or migrate stale session/model state that still references removed models
- repair browser Docker access or runtime permissions on the target host
- explicitly wire repository docs/knowledge into memory watch/index scope and then backfill embeddings

### Phase 5a - Telegram Activity Leakage Closure

The next reliability pass closes the new Telegram user-facing regression in the narrowest repo-controlled way available:

1. Add an explicit fail-closed rule to the tracked Moltis identity prompt:
   - user-facing messaging channels such as Telegram must never emit internal activity/tool-progress traces like `Activity log`, `Running`, `Searching memory`, `thinking`, raw tool names, or raw shell commands
   - at most one short human-facing progress preface is allowed before the final answer
2. Harden `scripts/telegram-web-user-probe.mjs` so emoji-prefixed telemetry replies are classified as failures, not green replies.
3. Harden authoritative Telegram UAT so a recent invalid pre-send incoming Telegram reply also invalidates the run.
4. Record the incident in RCA/rules/lessons with the live evidence from the 2026-03-26 authoritative Telegram runs.

This does not claim to patch an upstream Telegram adapter implementation that is not present in this repository. It instead establishes the strongest repo-owned barriers available now:

- fail-closed prompt/channel contract
- fail-closed authoritative UAT
- explicit RCA for any remaining upstream/runtime behavior

### Phase 5b - Browser Sandbox Contract Audit And New-Instance Lessons

The next hardening pass must not stop at the first restored browser invariant. It must audit the full browser sandbox contract against official Moltis docs plus tracked repo-specific runtime constraints:

1. Re-check official Moltis browser/sandbox/cloud guidance for Docker-backed sibling browser containers, including sandbox mode, `container_host`, and host Docker socket requirements.
2. Re-check repo-specific browser contract elements that official docs do not fail-close automatically:
   - tracked `sandbox_image`
   - `profile_dir`
   - `persist_profile`
   - host-visible browser profile mount source
   - writable shared profile directory
   - end-to-end `browser` canary against the same Telegram/`t.me/...` user path that previously timed out
3. Record explicitly that the initial deployment failure was not “sandbox mode was disabled” but “the first fix stopped after socket connectivity and did not yet prove writable browser profile storage plus exercised browser launch.”
4. Preserve that lesson in tracked RCA/rules/runbook artifacts so new agent instances and future deploys start from a complete browser contract checklist instead of rediscovering the same gap.

## Structure Decision

Keep this slice intentionally narrow:

- Speckit artifacts under `specs/031-moltis-reliability-diagnostics/`
- deploy/runtime verification hardening in existing deploy scripts
- operator smoke diagnostic refresh in the existing Moltis API test script
- read-only search/memory diagnostics as a separate operator entrypoint
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
- Add a read-only Tavily/memory diagnostic entrypoint for tracked config plus optional runtime logs.
- Validate the updated diagnostics with syntax and targeted contract checks.

### Phase 4: Highest-Priority Live Backlog

- Rank Tavily SSE failures and `memory_search` embedding failures above browser and stale-context cleanup.
- Keep their remediation explicit and operator-driven until a deterministic provider contract is chosen.

### Phase 4a: Embedding/Ollama Primary Cause Closure

- Forward `OLLAMA_API_KEY` into the `moltis` container.
- Extend deploy/runtime attestation to reject stale writable runtime `moltis.toml`.
- Capture the incident in RCA, rules, and lessons so future sessions start from the right first checks.

### Phase 4b: Mainline PR Split And Canonical Rollout

- Prepare the exact `PR1` carrier for `main` and validate it with hermetic blocking lanes only.
- Merge `PR1` into `main` and use the standard production deploy workflow from `main`.
- Prove the live fix remotely with authoritative `memory_search` and Ollama provider/model checks.
- Only then land `PR2` with the mutable documentation/process layer.

### Phase 5: Handoff

- Update `tasks.md` with completed safe fixes.
- Leave a precise operational follow-up list for the `main`-based live repair and the deferred `PR2`.

### Phase 6: Architectural Hardening Backlog

- Record the consilium-backed backlog for fail-closed auth/config durability so follow-up work is driven by tracked artifacts rather than chat history.

### Phase 7: Browser Contract Follow-Up Backlog

- Add a dedicated backlog track for browser/sandbox contract audit, including official-doc cross-check, community caveats, deploy/UAT invariants, and new-instance lessons.
- Keep the resulting tasks explicit until the live Telegram/browser timeout path is re-proven without leaked activity logs.
- Prioritize secret/env hardening, runtime-dir pinning, semantic proof of health, session reconciliation, durable-state audit, and immutable release-root design.

### Phase 7: Telegram Activity-Log And UAT Hardening

- Extend the current slice with a dedicated Telegram user-facing reliability pass.
- Treat `Activity log`/tool-progress leakage as a first-class reliability defect, not just as operator noise.
- Prove the fix with targeted component tests plus authoritative Telegram revalidation.
