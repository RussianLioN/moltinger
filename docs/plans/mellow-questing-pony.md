# Plan: Fix Telegram Bot Verification Code Issue

## Context

### Problem
The Moltis Telegram bot `@moltinger_bot` forces **all users** to enter a verification code:
> "To use this bot, please enter the verification code. Ask the bot owner for the code — it is visible in the web UI under **Channels → Senders**. The code expires in 5 minutes."

This happens repeatedly on every message, including for the bot owner and intended authorized users.

### Root Cause
**Wrong parameter name in `config/moltis.toml`.**

| Current (broken) | Correct (Moltis docs) |
|---|---|
| `allowed_users = [262872984]` | `dm_policy = "allowlist"` |
| _(no dm_policy)_ | `allowlist = [...]` |

The parameter `allowed_users` is **not a recognized Moltis config key**. It is silently ignored, so Moltis falls back to requiring verification codes from all users by default.

**History**: The commit `f30fe19 fix(telegram): use array format for allowed_users instead of env string` changed the format from env string to array, but kept the wrong parameter name. The underlying issue was not resolved.

### Evidence
- `config/moltis.toml:378-380` — current broken config
- Moltis docs (`channels.html`) — correct format with `dm_policy` + `allowlist`
- Screenshot — verification code shown to what appears to be the owner's own messages

---

## Approach

### Phase 0: Consilium (Pre-implementation expert review)
Run `/consilium` to get expert perspectives on:
- Correct Moltis Telegram config format
- Security implications of `dm_policy` choices (`"open"` vs `"allowlist"`)
- Whether `allowlist` accepts integer IDs or string usernames/usernames

### Phase 1: Spec (speckit.specify)
Create `specs/003-telegram-dm-policy-fix/spec.md` describing:
- User story: "As a bot user, I want to chat with the bot without needing a verification code"
- Acceptance criteria: Users in allowlist chat directly; unknown users get verification

### Phase 2: Implementation Plan (speckit.plan)
Single file change: `config/moltis.toml`

**Fix** — `dm_policy = "allowlist"` with confirmed owner ID + additional users:
```toml
[channels.telegram.moltis-bot]
token = "${TELEGRAM_BOT_TOKEN}"
dm_policy = "allowlist"
allowlist = [262872984, <additional_user_ids...>]  # owner ID confirmed correct; add others during impl
```

> **Note on ID format**: Moltis docs show string usernames, but Telegram identifies users by integer IDs. Try integers first; fall back to strings if Moltis rejects on startup.

### Phase 3: Tasks (speckit.tasks)
Tasks are small — this is a single config file change:
- [ ] T1: Update `config/moltis.toml` telegram config (replace `allowed_users` with `dm_policy` + `allowlist`)
- [ ] T2: Verify config with `docker compose config` (no syntax errors)
- [ ] T3: Create Beads issue and commit via `/push patch`
- [ ] T4: Verify bot behavior post-deploy (no verification code for allowlisted users)

### Phase 4: Deploy (GitOps)
```bash
git add config/moltis.toml
/push patch   # commit + push → triggers CI/CD → deploys to ainetic.tech
```

---

## Critical Files

| File | Change |
|---|---|
| `config/moltis.toml:378-380` | Replace `allowed_users` with `dm_policy` + `allowlist` |

---

## Confirmed Decisions (from user)

- **Access policy**: `dm_policy = "allowlist"` — restricted to specific users ✓
- **Owner ID**: `262872984` is correct ✓
- **Additional users**: Several user IDs should be added — user will provide them during implementation

## Open Questions (resolved before implementation)

- **ID format**: Docs show string usernames `["alice", "bob"]` but integers are likely needed for Telegram. Implementation step should verify — try `[262872984]` first; if bot fails to start, try `["262872984"]`.
- **Additional IDs**: User to provide exact Telegram user IDs of other allowed users (via `@userinfobot`).

---

## Verification

After deploy:
1. Send a message to `@moltinger_bot` from an allowlisted account → expect **no verification code**, direct response
2. Send from an unknown account → expect verification code (if `dm_policy = "allowlist"`)
3. Check Moltis web UI: `https://moltis.ainetic.tech` → Channels → Senders

---

## Consilium Focus Areas

When running `/consilium`, experts should address:
- **Claude Code Expert / Moltis Specialist**: Confirm correct TOML parameter names (`allowlist` vs `allowed_users`, `dm_policy` values)
- **Security Expert**: Recommend appropriate `dm_policy` for a personal assistant bot
- **DevOps Engineer**: Confirm config change flows correctly through Docker env vars to moltis.toml
