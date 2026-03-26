---
title: "Moltis memory embeddings and Ollama cloud models drifted because runtime config parity and runtime env delivery were not enforced together"
date: 2026-03-24
severity: P1
category: configuration
tags: [moltis, memory, embeddings, ollama, runtime-drift, gitops, deploy, rca, lessons]
root_cause: "Tracked config already pinned the correct memory contract, but deploy/runtime verification did not prove writable runtime moltis.toml parity and compose did not deliver OLLAMA_API_KEY into the moltis container that needed cloud-backed Ollama model discovery."
---

# RCA: Moltis memory embeddings and Ollama cloud models drifted because runtime config parity and runtime env delivery were not enforced together

## Summary

Two blocking Moltis symptoms looked like provider breakage, but both came from runtime contract drift:

1. `memory_search` failed with `openai ... /embeddings -> 400` against the Z.ai Coding endpoint and `groq ... /embeddings -> 401`.
2. Cloud-backed Ollama models such as `ollama::gemini-3-flash-preview:cloud` were missing from the live provider catalog.

Tracked git config was already correct:

- `config/moltis.toml` pinned `[memory] provider = "ollama"` with `model = "nomic-embed-text"`
- tracked memory `watch_dirs` already included repo-visible paths
- tracked provider config already referenced `OLLAMA_API_KEY` for cloud-backed Ollama models

The live runtime was wrong in two different layers:

- writable runtime `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml` was stale and no longer matched tracked `config/moltis.toml`
- server `.env` contained `OLLAMA_API_KEY`, but the running `moltis` container did not receive it

As a result, live Moltis kept using an older auto-detect memory path for embeddings and could not discover the Ollama Cloud model catalog needed for `gemini-3-flash-preview:cloud`.

## Error

Moltis looked as if embeddings providers and Ollama provider auth were broken, even though the repository already defined the correct memory backend and the server already had the Ollama Cloud secret.

## 5 Whys

| Level | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 1 | Why did `memory_search` hit Z.ai and Groq embeddings instead of Ollama? | Because the live writable runtime `moltis.toml` still carried an older auto-detect memory contract instead of the tracked pinned `[memory] provider = "ollama"` contract. | Diff between `/opt/moltinger-active/config/moltis.toml` and `/opt/moltinger-state/config-runtime/moltis.toml`; live logs showed `openai ... /embeddings -> 400` and `groq ... /embeddings -> 401`. |
| 2 | Why was the live writable runtime config stale? | Because deploy/runtime guards proved mount source and writability, but did not yet prove file parity between tracked `config/moltis.toml` and writable runtime `moltis.toml`. | `scripts/deploy.sh` and `scripts/moltis-runtime-attestation.sh` lacked a config-parity check before this fix. |
| 3 | Why were Ollama cloud models missing even though the secret existed on the server? | Because `OLLAMA_API_KEY` was rendered into `/opt/moltinger/.env` and forwarded to the Ollama sidecar, but not to the `moltis` container that performs provider discovery. | Server `.env` contained `OLLAMA_API_KEY`; `docker exec moltis env` did not. `docker-compose.prod.yml` forwarded the key only to `ollama` before this fix. |
| 4 | Why did the incident look like provider/API breakage instead of runtime drift? | Because the tracked config already expressed the intended provider surface, but the live runtime silently diverged in a writable config copy and in container env delivery. | `config/moltis.toml` already pinned `provider = "ollama"` and `model = "nomic-embed-text"`; runtime still behaved as if memory were on auto-detect and Ollama Cloud were unauthenticated. |
| 5 | Why could this survive into user-visible degradation? | Because the production contract was split across tracked config, rendered env, writable runtime config, and container env, but verification did not yet enforce those layers together as one end-to-end invariant. | Deploy/runtime attestation was transport/mount-aware, but not config-parity-aware or container-env-delivery-aware for this path. |

## Root Cause

The repository had the right Moltis memory and Ollama intent in git, but did not fully enforce that intent at the live runtime boundary.

Two specific enforcement gaps caused the incident:

1. writable runtime `moltis.toml` could drift away from tracked `config/moltis.toml` without failing deploy/runtime attestation
2. `OLLAMA_API_KEY` could exist in the rendered server `.env` and sidecar env, yet never reach the `moltis` container that actually needs it for cloud model discovery

## Evidence

- `config/moltis.toml` contains:
  - `[memory] provider = "ollama"`
  - `base_url = "http://ollama:11434"`
  - `model = "nomic-embed-text"`
  - repo-visible `watch_dirs`
- Live writable runtime config on the server still showed the default commented memory block and old `http://localhost:11434/v1` pattern.
- Live logs contained:
  - `openai: HTTP status client error (400 Bad Request) for url (https://api.z.ai/api/coding/paas/v4/embeddings)`
  - `groq: HTTP status client error (401 Unauthorized) for url (https://api.groq.com/openai/v1/embeddings)`
- `curl http://localhost:11434/api/tags` and `docker exec moltis curl http://ollama:11434/api/tags` both showed Ollama reachable with `nomic-embed-text`.
- `/opt/moltinger/.env` on the server already contained `OLLAMA_API_KEY=...`.
- `docker exec moltis sh -lc 'env | grep ^OLLAMA_API_KEY='` returned nothing before the fix.

## Fix

1. Forwarded `OLLAMA_API_KEY` into the production `moltis` container in `docker-compose.prod.yml`.
2. Extended `scripts/deploy.sh` so deploy verification fails closed if writable runtime `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml` diverges from tracked `config/moltis.toml`.
3. Extended `scripts/moltis-runtime-attestation.sh` with the same parity check and explicit machine-readable failure code `RUNTIME_CONFIG_FILE_MISMATCH`.
4. Added repository coverage for both contracts:
   - component test for runtime config parity failure
   - static validation for `OLLAMA_API_KEY` forwarding and parity enforcement
5. Updated the remote Moltis runbook to make runtime config parity and `OLLAMA_API_KEY` delivery first-line diagnostics for this incident class.

## Verification

- `bash tests/component/test_moltis_runtime_attestation.sh` -> `4/4 PASS`
- `bash tests/static/test_config_validation.sh` -> `112/112 PASS`
- `bash tests/unit/test_deploy_workflow_guards.sh` -> `34/34 PASS`

## Preventive Actions

1. Treat tracked `config/moltis.toml` and writable runtime `moltis.toml` as one contract that must stay byte-for-byte aligned after render/copy.
2. Treat “secret exists in `.env`” as insufficient proof; verify the exact consuming container receives it.
3. When `memory_search` shows embeddings traffic against chat-provider endpoints, check runtime-config parity before reconfiguring providers.
4. When cloud-backed Ollama models disappear, check `docker exec moltis env | grep ^OLLAMA_API_KEY=` before blaming OAuth or provider bugs.
5. Keep operator runbooks, RCA, and tests aligned so future sessions start from the right first checks.

## Lessons

1. Runtime mount provenance is necessary but not sufficient; writable config copies must also be checked for content parity.
2. Container-env delivery is part of the runtime contract. A rendered secret that never reaches the consuming process is operationally equivalent to a missing secret.
3. Embeddings failures can be a downstream sign of runtime drift, not proof that the embeddings provider itself is misconfigured.
