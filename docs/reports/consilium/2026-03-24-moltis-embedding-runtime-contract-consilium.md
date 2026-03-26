# Consilium Report

## Question
What is the minimum safe way to restore Moltis embeddings and Ollama provider availability without papering over the real cause, and what contract should prevent this incident from recurring?

## Execution Mode
Mode B (evidence-first expert matrix inside the main session; sub-agent mode was unavailable because the environment had already reached the active agent-thread limit)

## Evidence
- Tracked [config/moltis.toml](/Users/rl/coding/moltinger/moltinger-main-031-moltis-reliability-diagnostics/config/moltis.toml) already pins `[memory] provider = "ollama"`, `base_url = "http://ollama:11434"`, and `model = "nomic-embed-text"`.
- Tracked config also references cloud-backed Ollama models such as `ollama::gemini-3-flash-preview:cloud`.
- Live writable runtime `moltis.toml` on the server diverged from tracked config and still carried the older auto-detect memory defaults.
- Live logs showed `memory_search` falling through to:
  - `https://api.z.ai/api/coding/paas/v4/embeddings` with `400 Bad Request`
  - `https://api.groq.com/openai/v1/embeddings` with `401 Unauthorized`
- Server `.env` already contained `OLLAMA_API_KEY`, but the running `moltis` container environment did not expose it.
- Ollama sidecar reachability was healthy and exposed `nomic-embed-text`, so the failure was not basic Ollama network availability.

## Expert Opinions

### Architect
- The root problem is contract fragmentation across tracked config, writable runtime config, rendered `.env`, and container env.
- Any fix that changes only provider settings without restoring those invariants will be another short-lived workaround.

### SRE
- Deploy/runtime attestation must prove both mount provenance and config content parity.
- Post-deploy validation must include a live check that `memory_search` no longer hits Z.ai/Groq embeddings and that the `moltis` container actually exposes `OLLAMA_API_KEY`.

### DevOps
- `docker-compose.prod.yml` must forward `OLLAMA_API_KEY` into `moltis`, not only into the Ollama sidecar.
- The rollout should remain GitOps-driven so the fix is reproducible and auditable.

### Security
- Secrets should stay out of git, but “secret rendered to `.env`” is not sufficient evidence.
- The safe boundary is: rendered secret -> compose env -> exact consuming container.

### QA
- Repository proof is necessary but not enough; the authoritative target is the remote Moltis runtime.
- The incident is only closed after a live canary confirms both embeddings and provider/model availability.

### Moltis Domain Specialist
- The tracked memory config is already correct, so the symptom strongly indicates runtime drift rather than a bad baseline.
- Cloud-backed Ollama model discovery depends on the runtime process seeing `OLLAMA_API_KEY`.

### Delivery / GitOps
- This is a classic “green transport, broken semantics” incident.
- The right fix is fail-closed attestation plus redeploy from the tracked branch, not ad-hoc hand edits on the server.

## Root Cause Analysis
- Primary root cause: the live Moltis runtime was not forced to keep writable runtime `moltis.toml` aligned with tracked `config/moltis.toml`, and the live `moltis` container did not receive `OLLAMA_API_KEY` even though the rendered server `.env` already had it.
- Contributing factors:
  - existing runtime attestation checked mount source/writability, but not file parity
  - compose forwarded the Ollama key to the sidecar but not the Moltis process that performs provider discovery
  - user-visible symptoms looked like provider breakage, which can misdirect debugging away from runtime drift
- Confidence: High

## Solution Options
1. Reconfigure memory providers only in runtime state. Pros: fast. Cons: drift-prone, non-GitOps. Risk: high. Effort: low.
2. Add only an operator runbook note. Pros: cheap. Cons: does not prevent recurrence. Risk: high. Effort: low.
3. Forward `OLLAMA_API_KEY` into `moltis` only. Pros: restores cloud model discovery. Cons: leaves stale runtime `moltis.toml` unresolved. Risk: medium. Effort: low.
4. Enforce runtime `moltis.toml` parity only. Pros: fixes embeddings drift. Cons: cloud-backed Ollama models can still stay invisible. Risk: medium. Effort: low.
5. Combine config-parity attestation, `OLLAMA_API_KEY` forwarding, tests, RCA/rule docs, and GitOps redeploy. Pros: closes both failure paths and prevents silent recurrence. Cons: broader change set. Risk: low. Effort: medium.

## Recommended Plan
1. Keep tracked `config/moltis.toml` as the source of truth and fail deploy/runtime attestation if writable runtime `moltis.toml` diverges.
2. Forward `OLLAMA_API_KEY` into the `moltis` container and keep static coverage for that compose contract.
3. Capture the incident in RCA, rules, and runbook guidance so future triage starts with parity and env-delivery checks.
4. Redeploy from this branch through the tracked GitOps path.
5. Validate live with:
   - runtime config parity
   - `docker exec moltis env | grep ^OLLAMA_API_KEY=`
   - successful `memory_search`
   - visible Ollama provider/model surface

## Rollback Plan
- Revert the repo-side hardening commit if it blocks a valid deploy unexpectedly.
- Preserve runtime config and Moltis runtime home before any deeper state migration.
- Do not hand-edit provider state on the server unless GitOps rollout fails and the emergency path is explicitly justified.

## Verification Checklist
- [x] Tracked config confirmed to pin the correct memory backend
- [x] Live runtime drift confirmed in writable `moltis.toml`
- [x] Missing `OLLAMA_API_KEY` delivery into `moltis` confirmed
- [x] Safe repo-side fix identified
- [ ] GitOps redeploy completed
- [ ] Live `memory_search` validated
- [ ] Live Ollama provider/model availability validated
