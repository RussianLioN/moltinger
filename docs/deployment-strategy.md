# Deployment Strategy

## Purpose

This document is the operator summary for deploying the two-agent platform:

- `Moltinger` remains the primary production runtime.
- `Clawdiy` is the second long-lived agent, deployed same-host first and designed for later remote-node extraction.

## Deployment Units

| Unit | Workflow / entrypoint | Scope |
|------|------------------------|-------|
| Moltinger baseline | `.github/workflows/deploy.yml` | Main application deploy and shared platform baseline |
| Feature diagnostics | `.github/workflows/feature-diagnostics.yml` | Read-only branch diagnostics against the live target without production mutation |
| Moltis version update runbook | `docs/runbooks/moltis-backup-safe-update.md` | Backup-safe image bump with restore-check and rollback evidence |
| Clawdiy same-host rollout | `.github/workflows/deploy-clawdiy.yml` | Clawdiy-only deploy, smoke, auth rendering, restore-readiness checks |
| Rollback drill | `.github/workflows/rollback-drill.yml` | Backup integrity and restore-readiness verification |

## Current Strategy

### 1. Same-host first

Clawdiy starts on the same server in its own compose stack:

- compose: `docker-compose.clawdiy.yml`
- runtime config: `config/clawdiy/openclaw.json`
- control-plane registry/policy: `config/fleet/agents-registry.json`, `config/fleet/policy.json`
- persistent state: `data/clawdiy/state`
- audit evidence: `data/clawdiy/audit`
- the first CI rollout may create `fleet-internal` if it does not exist yet; `traefik-net` and `moltinger_monitoring` must already exist

### 2. Private machine handoff

Authoritative inter-agent transport is:

- private authenticated HTTP JSON
- stable `/internal/v1/agent-handoffs*` contract
- bearer service auth bound to `X-Agent-Id`

Telegram is human ingress only. It is not the authoritative machine transport.

### 3. Telegram ingress stays in polling mode

Phase 1 keeps Telegram in long-polling mode:

- dedicated Clawdiy bot identity
- fail-closed token and allowlist checks
- webhook rollout remains later and does not block same-host launch

### 4. Rollout-gated provider auth

`gpt-5.4` via OpenAI Codex OAuth is a later capability gate:

- baseline Clawdiy deploy does not depend on it
- provider auth stays fail-closed
- Clawdiy can remain healthy while Codex-backed capability is disabled

## Operator Flow

### 1. Same-host launch

```bash
./scripts/preflight-check.sh --ci --target clawdiy --json
./scripts/deploy.sh --json clawdiy deploy
./scripts/clawdiy-smoke.sh --json --stage same-host
```

This is the first live OpenClaw launch step for Clawdiy.
If `fleet-internal` is absent on the first rollout, the GitHub deploy workflow or `deploy.sh` bootstraps it; do not create it manually over ad-hoc SSH.

### 2. Handoff verification

```bash
./scripts/clawdiy-smoke.sh --json --stage handoff
```

### 3. Telegram and baseline auth verification

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider telegram --json
./scripts/clawdiy-smoke.sh --json --stage auth
```

### 4. Codex OAuth rollout gate

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth --json
```

Preferred first operator path:
- open the live UI at `https://clawdiy.ainetic.tech`
- complete hosted browser bootstrap through `Overview -> Gateway Access -> Gateway Token -> Connect -> device pairing`
- do not expect a dedicated first-run wizard; on a fresh browser the normal initial state is `Version n/a` / `Health Offline`
- only after browser bootstrap inspect whether the current build exposes a provider-auth UI entrypoint
- treat SSH/CLI paste-back as fallback only if the UI layer still lacks a provider-auth path or fails to write into the actual runtime store

Related planning package:
- [specs/017-clawdiy-remote-oauth-lifecycle/spec.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/spec.md)
- [docs/runbooks/clawdiy-browser-bootstrap.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-browser-bootstrap.md)

### 5. Recovery verification

```bash
./scripts/deploy.sh --json clawdiy rollback
./scripts/clawdiy-smoke.sh --json --stage rollback-evidence
```

### 6. Future-node readiness

```bash
./scripts/clawdiy-smoke.sh --json --stage extraction-readiness
```

## Required Secrets

| Scope | Secret refs |
|-------|-------------|
| Moltinger | `MOLTIS_PASSWORD`, `MOLTINGER_SERVICE_TOKEN`, `TELEGRAM_BOT_TOKEN` |
| Clawdiy baseline | `CLAWDIY_GATEWAY_TOKEN`, `CLAWDIY_SERVICE_TOKEN`, `CLAWDIY_TELEGRAM_BOT_TOKEN`, `CLAWDIY_TELEGRAM_ALLOWED_USERS` |
| Clawdiy rollout gate | `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` |

Canonical source of truth is GitHub Secrets. The server runtime copy is generated into `/opt/moltinger/.env` and `/opt/moltinger/clawdiy/.env` by CI.
During the gateway-auth migration, `CLAWDIY_PASSWORD` remains an accepted compatibility fallback for rendering `OPENCLAW_GATEWAY_TOKEN`, but it is no longer the preferred secret.

## Rollout Gates

| Gate | Must be true before continuing |
|------|--------------------------------|
| Same-host deploy | Clawdiy health is green and Moltinger remains healthy |
| Handoff | sample accept/reject/timeout evidence exists |
| Telegram polling | token and allowlist checks pass or capability stays degraded |
| Codex OAuth | required scopes include `api.responses.write` and allowed models include `gpt-5.4` |
| Recovery | rollback evidence and restore-readiness checks pass |
| Extraction readiness | identity, registry, and handoff paths stay stable across topology profiles |

## Non-Negotiable Rules

- Do not replay production deploy steps manually after a branch/ref guard blocks the workflow.
- Do use `feature-diagnostics.yml` for read-only evidence from feature branches, then promote to `main`.
- Do not reuse Moltinger secrets for Clawdiy.
- Do not expose machine handoffs through the public subdomain.
- Do not treat Telegram success as proof that machine handoff works.
- Do not enable Codex-backed capability before the OAuth gate passes.
- Do not move Clawdiy to another node until `extraction-readiness` passes.
