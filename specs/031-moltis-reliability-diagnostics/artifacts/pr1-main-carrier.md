# PR1 Main Carrier: Embedding And Ollama Runtime Fix

**Purpose**: prepare the exact runtime-only carrier that must move from `031-moltis-reliability-diagnostics` into `main` before the canonical production deploy.

## Decision

Consilium consensus for this incident:

- `PR1` must be a `selected-hunks carrier`, not a full merge of branch `031`.
- `PR1` must include runtime attestation and force-recreate behavior, not just `config + compose`.
- `PR2` must stay deferred until after successful live verification from `main`.

## Executable Artifacts

- `apply_pr1_main_carrier.py`
  - deterministic applicator that mutates a `main` checkout tree in place and fails fast if `origin/main` anchors drift
- `pr1-main-carrier.patch`
  - generated unified diff emitted by the applicator against a clean `origin/main` snapshot
- `pr1-main-carrier-validation.md`
  - proof that the applicator ran successfully on a clean exported `origin/main` tree and that the emitted patch also passes `patch --dry-run`

## Source Deltas

The carrier should be sourced from these already-proven branch deltas, but not cherry-picked wholesale:

- `95a0feb`
  - pin memory embeddings to Ollama
- `81ebeaa`
  - force-recreate Moltis on deploy
- `a1829bf`
  - live runtime attestation and deploy control-plane integration
- `87a39fc`
  - component proof for runtime attestation
- `e7f3066`
  - forward `OLLAMA_API_KEY` into `moltis`
  - fail closed on runtime `moltis.toml` drift

## Must-Have Files And Hunks

### 1. `config/moltis.toml`

Carry only the `[memory]` contract:

- `provider = "ollama"`
- `base_url = "http://ollama:11434"`
- `model = "nomic-embed-text"`
- `watch_dirs = ["~/.moltis/memory", "/server/knowledge"]`

Do not drag unrelated browser, Tavily-prompt, or Telegram-account hunks into `PR1`.

### 2. `docker-compose.prod.yml`

Carry only the `moltis` service env hunk:

- `OLLAMA_API_KEY: ${OLLAMA_API_KEY:-}`

Do not drag browser profile, `host-gateway`, or other branch-only Docker runtime changes into `PR1`.

### 3. `scripts/deploy.sh`

Carry these runtime-only behaviors:

- `deploy_args+=(--force-recreate)` for Moltis rollout
- fail-closed verification that writable runtime `moltis.toml` matches tracked `config/moltis.toml`

If deploy verification also checks `/server`, runtime config mount source, and runtime config writability, that is acceptable because it reduces false-green risk for the same incident class.

Do not drag browser sandbox image prep, knowledge sync, or other unrelated runtime hardening into `PR1`.

### 4. `scripts/moltis-runtime-attestation.sh`

Carry the shared runtime attestation script as a new tracked contract.

Required proofs:

- live `/server` mount resolves to the active deploy root
- runtime config mount source is correct and writable
- tracked `config/moltis.toml` equals runtime `moltis.toml`
- live auth surface still includes valid `openai-codex`

### 5. `scripts/run-tracked-moltis-deploy.sh`

Carry only the changes required to make canonical deploy from `main` fail closed:

- require `scripts/moltis-runtime-attestation.sh`
- record deploy markers needed for attestation
- run live attestation after deploy and before final `success`
- stay backward-compatible with the current workflow/wrapper contract from `origin/main`

Prefer keeping `/opt/moltinger-active` as the default active root so workflow changes are optional for `PR1`.

### 6. Minimal Test Carrier

Carry only the tests needed to prove this incident-specific contract:

- `tests/static/test_config_validation.sh`
  - pinned Ollama memory contract
  - `OLLAMA_API_KEY` forwarded to `moltis`
  - tracked deploy invokes runtime attestation
  - runtime config parity is enforced
- `tests/unit/test_deploy_workflow_guards.sh`
  - Moltis deploy force-recreates the runtime
  - tracked deploy dry-run includes `attest-live-runtime`
- `tests/component/test_moltis_runtime_attestation.sh`
  - success on tracked/runtime parity
  - failure on `RUNTIME_CONFIG_FILE_MISMATCH`
- `scripts/moltis-search-memory-diagnostics.sh`
- `tests/component/test_moltis_search_memory_diagnostics.sh`
  - tracked config summary expects pinned `ollama` memory contract

## Explicit Excludes For PR1

Leave these for `PR2` or later follow-up PRs:

- RCA / consilium / rules / runbook updates
- lessons tooling and lessons content
- Speckit wording that depends on live outcome
- browser-specific hardening
- Tavily-specific hardening
- broader UAT/provider smoke matrices
- env-render durability work unrelated to this embedding incident
- workflow cosmetics that are not required for backward-compatible canonical deploy from `main`

## Pre-Merge Hermetic Proof

`PR1` is not ready for `main` without these checks:

```bash
bash tests/static/test_config_validation.sh
bash tests/unit/test_deploy_workflow_guards.sh
bash tests/component/test_moltis_runtime_attestation.sh
bash tests/component/test_moltis_search_memory_diagnostics.sh
```

## Carrier Usage

Generate or refresh the carrier against a clean `main` tree:

```bash
tmp_root="$(mktemp -d /tmp/pr1-main-carrier.XXXXXX)"
mkdir -p "$tmp_root/main"
git archive origin/main | tar -x -C "$tmp_root/main"
python3 specs/031-moltis-reliability-diagnostics/artifacts/apply_pr1_main_carrier.py \
  --target-tree "$tmp_root/main" \
  --emit-patch "$tmp_root/pr1-main-carrier.patch"
patch --dry-run -p1 -d "$tmp_root/main" < "$tmp_root/pr1-main-carrier.patch"
```

The committed `pr1-main-carrier.patch` is the already validated output of that flow, not a hand-written diff.

## Post-Deploy Live Proof From `main`

After `PR1` lands in `main`, canonical deploy must prove all of the following against the authoritative remote runtime:

- tracked deploy succeeds and runtime attestation succeeds
- `docker exec moltis env` shows `OLLAMA_API_KEY`
- `docker exec moltis moltis auth status` still shows valid `openai-codex`
- `memory_search` no longer hits:
  - `https://api.z.ai/api/coding/paas/v4/embeddings -> 400`
  - `https://api.groq.com/openai/v1/embeddings -> 401`
- provider/model surface includes `ollama::gemini-3-flash-preview:cloud`
- a repo-memory prompt returns a fact from tracked project knowledge instead of generic fallback

## Operational Note

This artifact completes `T055` at the planning/carrier-preparation layer only.

Actual incident closure still requires:

1. merge the carrier into `main`
2. run the canonical production deploy from `main`
3. complete live verification
4. only then land `PR2`
