# Clawdiy Repeat-Auth Runbook

**Status**: Draft operator runbook for feature `001-clawdiy-agent-platform`  
**Scope**: Clawdiy-only auth rotation and repeat-auth procedures

## Purpose

Recover or rotate Clawdiy auth material without changing Moltinger auth state.

## Auth Surfaces

- Human/web auth: `CLAWDIY_PASSWORD`
- Service-to-service auth: `CLAWDIY_SERVICE_TOKEN`
- Telegram ingress: `CLAWDIY_TELEGRAM_BOT_TOKEN`
- Telegram allowlist: `CLAWDIY_TELEGRAM_ALLOWED_USERS`
- Provider auth: rollout-gated profile such as `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE`

## Rules

- Never reuse Moltinger auth material for Clawdiy
- A failed provider auth gate must not block baseline Clawdiy runtime health
- Repeat-auth events must produce operator-visible evidence
- `deploy-clawdiy.yml` is the only workflow that may render `/opt/moltinger/clawdiy/.env`
- `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` must stay compact single-line JSON with `provider=codex-oauth`, `auth_type=oauth`, `granted_scopes`, and `allowed_models`
- Inside `/opt/moltinger/clawdiy/.env`, `TELEGRAM_BOT_TOKEN` is a runtime-only alias for OpenClaw and mirrors `CLAWDIY_TELEGRAM_BOT_TOKEN`; do not treat that alias as Moltinger auth material during audits

## Verification Commands

Use the dedicated env file after every auth rotation:

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider telegram
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth
./scripts/clawdiy-smoke.sh --stage auth --json
```

Interpretation:
- `status=pass`: capability is ready for operator promotion
- `status=warning`: baseline remains healthy, but optional hardening such as Telegram allowlist is incomplete
- `status=fail`: capability stays quarantined; do not promote it until repeat-auth succeeds

## Target Procedures

### 1. Telegram token rotation

1. Rotate the bot token in BotFather.
2. Update GitHub Secret `CLAWDIY_TELEGRAM_BOT_TOKEN`.
3. If operator allowlist changed, update `CLAWDIY_TELEGRAM_ALLOWED_USERS` as a comma-separated list without spaces.
4. Redeploy Clawdiy-only runtime.
5. Verify:
   ```bash
   ./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider telegram
   ./scripts/clawdiy-smoke.sh --stage auth
   ```

### 2. Service token rotation

1. Generate a new bearer token for Clawdiy internal handoff.
2. Update GitHub Secret `CLAWDIY_SERVICE_TOKEN`.
3. Redeploy Clawdiy and re-run handoff smoke:
   ```bash
   ./scripts/clawdiy-smoke.sh --stage handoff
   ```

### 3. GPT-5.4 / Codex OAuth gate

This is a later rollout gate, not a first-deploy requirement.

1. Refresh or replace `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE`.
2. Store it as compact JSON, for example:
   ```json
   {"provider":"codex-oauth","auth_type":"oauth","granted_scopes":["api.responses.write"],"allowed_models":["gpt-5.4"]}
   ```
3. Redeploy Clawdiy-only runtime so `/opt/moltinger/clawdiy/.env` is regenerated.
4. Run:
   ```bash
   ./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth
   ```
5. Promote Codex-backed capability only if post-auth verification passes.
6. If the check reports missing `api.responses.write` or missing `gpt-5.4` authorization, keep the capability quarantined and repeat OAuth instead of forcing enablement.

## Failure Handling

- If Telegram repeat-auth fails, Clawdiy stays deployable but Telegram ingress remains degraded
- If provider OAuth fails, keep Clawdiy running and leave Codex/GPT-5.4 capability disabled
- If service auth fails, stop cross-agent handoff and escalate through `fleet-handoff-incident.md`
- If `clawdiy-auth-check.sh` reports cross-agent secret reuse, treat it as configuration drift and redeploy only after restoring Clawdiy-specific secrets
