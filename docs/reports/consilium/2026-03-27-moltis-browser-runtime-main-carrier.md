---
title: "Consilium: Moltis browser runtime must land to main as a narrow carrier"
date: 2026-03-27
status: accepted
tags: [consilium, moltis, browser, sandbox, docker, release, main-carrier]
---

# Consilium: Moltis browser runtime must land to main as a narrow carrier

## Question

What is the safest way to close the live Moltis Telegram/browser timeout incident now that:

- shared production still runs the `main` browser baseline
- the audited browser contract already exists in `031`
- production deploys are allowed only from `main`

## Evidence

### Official baseline

Official Moltis docs establish the browser/sandbox baseline:

- browser automation uses a sandboxed browser container and, when Moltis itself runs in Docker, requires working host Docker access plus `container_host`
- sandboxed execution inside Docker uses host-visible absolute paths; container-only paths are not enough when sibling containers are started through the host Docker daemon

Sources:

- https://docs.moltis.org/browser-automation.html
- https://docs.moltis.org/sandbox.html

### Live production facts

- live `moltis.toml` in production currently contains:
  - `sandbox_image = "browserless/chrome"`
  - `container_host = "host.docker.internal"`
  - no `profile_dir`
  - no `persist_profile`
- live `docker-compose`/container mounts do not provide the tracked host-visible browser profile bind from `031`
- live Moltis logs still show `browser manager initialized ... sandbox_image=browserless/chrome`
- live Telegram/browser path times out and browser readiness still fails

### Isolated host repro

- `docker pull browserless/chrome` now succeeds
- an isolated `browserless/chrome` container on the same host becomes healthy when it receives a writable bound profile directory
- the current production failure therefore no longer points first at image-pull permissions; it points at the missing host-visible profile-dir contract in `main`

### Repo diff facts

Relative to `origin/main`, branch `031` now carries the browser contract that production is missing:

- tracked `sandbox_image = "browserless/chrome"`
- tracked `profile_dir = "/tmp/moltis-browser-profile/shared"`
- tracked `persist_profile = false`
- compose bind mount for `/tmp/moltis-browser-profile`
- deploy-time shared profile-dir preparation
- runtime attestation for browser-profile mount source, writability, and tracked browser settings
- a dedicated browser canary script plus blocking validation

## Expert Verdicts

### Moltis/OpenClaw docs view

Current production is only partially official-compliant:

- it satisfies Docker/socket and `container_host`
- it does **not** satisfy the host-visible-path discipline needed for sibling-container sandbox execution

So the official baseline was not ignored completely, but it was not carried through to the full host-path/runtime contract.

### Docker/browserless view

The current incident is no longer best explained by image pull failure.

The stronger explanation is:

- production is still on the partial stock browser baseline from `main`
- the missing host-visible shared profile mount means the sibling browser container gets an auto-created root-owned host path
- Chrome then fails to create singleton state under `/data/browser-profile`, and the user only sees the later timeout/activity-log symptom

### Release safety view

Because production deploys must come from `main`, the safe next step is not more feature-branch repair and not a whole-branch merge.

It is a **narrow runtime-only browser carrier** to `main`.

## Consolidated Decision

Accepted path:

1. Freeze the current browser diagnosis in tracked artifacts.
2. Prepare a minimal browser-runtime carrier to `main`.
3. Keep that carrier limited to production-critical browser files plus blocking validation.
4. Land it to `main`.
5. Use the canonical deploy path from `main`.
6. Re-run an exercised browser canary on the same Telegram/`t.me/...` class of path.

## Must-Have Carrier Scope

- `config/moltis.toml`
- `docker-compose.prod.yml`
- `scripts/deploy.sh`
- `scripts/moltis-runtime-attestation.sh`
- `scripts/moltis-browser-canary.sh`
- `tests/component/test_moltis_runtime_attestation.sh`
- `tests/static/test_config_validation.sh`
- `tests/unit/test_deploy_workflow_guards.sh`

## Docs-Only / Deferred Scope

These are valuable but must not expand the production-critical carrier:

- mutable RCA wording refinements
- extra lessons/runbook prose
- broader phase closeout documentation

## Recommendation

Do not keep diagnosing the live Telegram/browser incident as if production already had the `031` browser fixes.

Treat the missing `main` landing as a first-order cause:

- prepare the narrow browser carrier around the host-visible profile-dir contract
- validate it against clean `origin/main`
- then deploy canonically from `main`
