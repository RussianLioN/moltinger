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

## Target Procedures

### 1. Telegram token rotation

1. Rotate the bot token in BotFather.
2. Update GitHub Secret `CLAWDIY_TELEGRAM_BOT_TOKEN`.
3. Redeploy Clawdiy-only runtime.
4. Verify:
   ```bash
   ./scripts/clawdiy-auth-check.sh --provider telegram
   ./scripts/clawdiy-smoke.sh --stage telegram-polling
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
2. Run:
   ```bash
   ./scripts/clawdiy-auth-check.sh --provider openai-codex
   ```
3. Promote Codex-backed capability only if post-auth verification passes.

## Failure Handling

- If Telegram repeat-auth fails, Clawdiy stays deployable but Telegram ingress remains degraded
- If provider OAuth fails, keep Clawdiy running and leave Codex/GPT-5.4 capability disabled
- If service auth fails, stop cross-agent handoff and escalate through `fleet-handoff-incident.md`
