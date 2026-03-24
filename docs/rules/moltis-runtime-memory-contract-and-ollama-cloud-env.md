# Moltis runtime memory contract and Ollama Cloud env must stay end-to-end aligned (RCA-022)

**Status:** Active  
**Effective date:** 2026-03-24  
**Scope:** `config/moltis.toml`, `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml`, `docker-compose.prod.yml`, deploy/runtime attestation, remote Moltis operator diagnostics

## Problem This Rule Prevents

Tracked Moltis config can already contain the correct memory and provider baseline while the live runtime still behaves as if embeddings and Ollama Cloud are broken.

The specific failure pattern is:

- tracked `config/moltis.toml` pins memory to `ollama/nomic-embed-text`
- writable runtime `moltis.toml` drifts back to an older auto-detect contract
- `OLLAMA_API_KEY` exists in rendered server `.env`, but the `moltis` container does not receive it
- operators see `memory_search` hit Z.ai or Groq embeddings and assume provider auth is broken

## Mandatory Protocol

Before declaring an embeddings or Ollama provider incident, verify these checks in order:

1. Runtime config parity:
   - tracked `config/moltis.toml`
   - writable runtime `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml`
   - they must match
2. Runtime env delivery:
   - `docker exec moltis sh -lc 'env | grep ^OLLAMA_API_KEY='`
   - if absent, cloud-backed Ollama models are not expected to appear
3. Ollama reachability:
   - `docker exec moltis sh -lc 'curl -sf http://ollama:11434/api/tags'`
4. Only after those checks:
   - inspect provider-specific auth or third-party API behavior

## Hard Guardrail

Production deploy and runtime attestation must fail closed if:

- writable runtime `${MOLTIS_RUNTIME_CONFIG_DIR}/moltis.toml` diverges from tracked `config/moltis.toml`
- `docker-compose.prod.yml` stops forwarding `OLLAMA_API_KEY` into the `moltis` container while tracked config still references cloud-backed Ollama models

## Expected Behavior

- Tracked config expresses the intended memory/provider contract.
- Runtime config is a writable mirror of that tracked contract, not an independently drifting source of truth.
- Server `.env` rendering alone is not accepted as proof; the consuming container must expose the key.
- Operator diagnostics start with parity/env checks before provider blame.
