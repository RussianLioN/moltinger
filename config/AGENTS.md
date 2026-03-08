# Config Instructions

This directory is production-adjacent. Treat every change here as high risk.

## Read First

Before changing anything in `config/`, read:

- `MEMORY.md`
- `SESSION_SUMMARY.md`
- `docs/LESSONS-LEARNED.md`

If the change touches networking, domains, Traefik, providers, deploy behavior, or certificates, re-read the relevant sections in `MEMORY.md` first.

## Scope

This directory contains runtime configuration for Moltis and supporting services:

- `moltis.toml`
- `prometheus/`
- `alertmanager/`
- `cron/`
- `systemd/`
- `provider_keys.json`
- `certs/`

## Critical Rules

1. Do not change network assumptions casually.
   `traefik-net` is the critical routing network, not `traefik_proxy`.
2. Do not change domain assumptions casually.
   `moltis.ainetic.tech` is the production Moltis domain.
3. Do not delete or rewrite `provider_keys.json`, certificate files, or key files without explicit user request.
4. Do not introduce configuration drift.
   If config changes here imply workflow or deploy changes, update the corresponding files in:
   - `.github/workflows/`
   - `scripts/`
   - `docker-compose*.yml`
   - `docs/`
5. Prefer full-file correctness over partial patch hacks.
   Avoid solutions that rely on fragile `sed`-style mutation patterns in deployment flows.

## Validation

After changing config, run the narrowest relevant validation possible.

Examples:
- `docker compose config --quiet`
- targeted grep or diff checks
- relevant shell tests from `tests/`
- workflow consistency checks if deploy/test behavior changed

If a change affects runtime behavior, explicitly state:
- what changed
- what was validated
- what was not validated
- rollback considerations

## Escalation

Stop and ask before:
- changing providers or auth behavior
- changing production domains
- changing routing labels or network bindings
- changing cert/key material
- deleting any file in this directory
