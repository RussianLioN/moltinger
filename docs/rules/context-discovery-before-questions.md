# Context Discovery Before Questions (RCA-008)

**Status:** Active
**Effective date:** 2026-03-07
**Scope:** All AI sessions and maintainers

## Problem This Rule Prevents

Asking the user for already documented values (secrets, paths, env vars, deployment settings) creates process noise and loses trust.

## Mandatory Protocol

Before asking any question about variables, secrets, or known infrastructure values, run this lookup order:

1. `MEMORY.md`
2. `SESSION_SUMMARY.md`
3. `docs/SECRETS-MANAGEMENT.md`
4. `.github/workflows/deploy.yml` (`Generate .env from Secrets`)

If the value is found in these sources, do not ask the user for it again.

## Source of Truth for This Project

- Primary source: GitHub Secrets (repository settings)
- Runtime mirror on server: `/opt/moltinger/.env`
- Sync mechanism: CI/CD deploy workflow generates `/tmp/moltis.env` and uploads it to `/opt/moltinger/.env`

## Known Critical Variables

- `TELEGRAM_BOT_TOKEN`
- `MOLTINGER_SERVICE_TOKEN`
- `GLM_API_KEY`
- `TAVILY_API_KEY`
- `MOLTIS_PASSWORD`
- `OLLAMA_API_KEY` (optional)

Notes:

- For Moltis Telegram ingress, the tracked allowlist in `config/moltis.toml` is authoritative.
- `/opt/moltinger/.env` may still contain `TELEGRAM_ALLOWED_USERS`, but that value is a derived mirror for auxiliary scripts, not the primary auth source.

## When Asking the User Is Allowed

Only ask the user if:

1. The value is missing in all listed sources.
2. Sources conflict and there is no safe way to infer current truth.
3. The user requested a new value/rotation and no target value was provided.

## Expected Behavior

- First: report what was found and where.
- Second: identify the exact gap.
- Third: ask one precise question only if needed.
