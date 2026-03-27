# PR3 Main Browser Carrier

## Purpose

Materialize the smallest possible `main` carrier that repairs the live Moltis browser runtime without dragging along docs/process-only deltas from `031`.

## Why This Carrier Exists

Current production still runs the partial `origin/main` browser baseline:

- `sandbox_image = "browserless/chrome"`
- `container_host = "host.docker.internal"`
- no tracked `profile_dir`
- no tracked `persist_profile`
- no host-visible `/tmp/moltis-browser-profile` bind mount in compose

That baseline is official-ish at a coarse level, but the authoritative 2026-03-27 evidence shows it is still insufficient for the real Telegram/browser path on this deployment:

- live `moltis` times out on the `browser` path for `t.me/...`
- live `moltis` still never received the tracked host-visible browser profile contract from `031`
- `docker pull browserless/chrome` now succeeds from inside `moltis`
- isolated `browserless/chrome` becomes healthy on the same host once it receives a writable bound profile directory

So the immediate production-safe next step is not a broad branch merge and not another docs-only pass. It is a narrow `main` carrier that lands only the browser/runtime/UAT surface required to repair and validate the browser path through the canonical deploy workflow.

## Included Surface

Runtime/browser contract:

- `config/moltis.toml`
- `docker-compose.prod.yml`
- `scripts/deploy.sh`
- `scripts/moltis-runtime-attestation.sh`
- `scripts/moltis-browser-canary.sh`

Blocking validation for the same incident:

- `tests/component/test_moltis_runtime_attestation.sh`
- `tests/static/test_config_validation.sh`
- `tests/unit/test_deploy_workflow_guards.sh`

## Why These Files

`config/moltis.toml`

- keeps `sandbox_image = "browserless/chrome"`
- adds the host-visible `profile_dir`
- keeps `persist_profile = false`
- retains the tracked `container_host`

`docker-compose.prod.yml`

- mounts `/tmp/moltis-browser-profile` into the Moltis container at the same absolute host-visible path used by the tracked browser contract

`scripts/deploy.sh`

- prepares the shared host-visible browser profile directory
- pre-pulls the tracked browser image before Moltis comes up
- carries the browser runtime contract into deploy verification instead of treating Docker/socket recovery alone as enough

`scripts/moltis-runtime-attestation.sh`

- fails closed when the live runtime drifts on browser profile mount source, writability, or tracked browser settings

`scripts/moltis-browser-canary.sh`

- proves a real `browser` run and rejects a transport-green rollout that still cannot execute the browser tool

`tests/*`

- block future drift on the tracked browser contract and on the runtime/browser attestation semantics

## Explicitly Excluded

Do not include in `PR3`:

- RCA / consilium / lessons / runbook / rule text
- Speckit finalization
- Telegram-only probe refinements not required for the browser rollout itself
- unrelated Tavily/search/memory or process-only cleanups

## Merge Criteria

`PR3` is merge-ready only if:

1. The carrier applies cleanly to a fresh `origin/main` export.
2. The blocking repo checks pass on the carrier surface.
3. The carrier remains runtime/UAT-scoped and does not drag in mutable docs/process layers.
4. Canonical deploy from `main` is the first production rollout path.

## Post-Merge Proof

After `PR3` lands in `main`, incident closure still requires:

1. Canonical production deploy from `main`.
2. Live verification that the running container now reflects the tracked browser contract.
3. A real `browser` canary on the same `t.me/...` class of path that previously timed out.
4. Authoritative Telegram validation without timeout and without leaked internal activity.
