# Secure Telegram Bot Integration Patterns

**Date**: 2026-02-19
**Researcher**: Research Specialist
**Status**: Complete
**Related**: Session Summary - Moltinger AI Agent Factory

---

## Executive Summary

This document analyzes secure patterns for integrating LLM systems (Claude Code, Moltis) with Telegram bots. The research identifies that **Telegram's official Bot API is already secure by design** when following established best practices for secret management. For Moltinger's use case (monitoring @tsingular for knowledge extraction), the existing configuration in `config/moltis.toml` follows correct security patterns.

**Key Finding**: The most secure and elegant solution is to use **Telegram Bot API with environment variable substitution**, following GitOps principles for secret management (already implemented in Moltinger).

---

## Pattern Analysis

### 1. Telegram Bot API (Recommended - Currently Implemented)

**Description**: Official Telegram Bot API server-to-server communication.

**How it works**:
1. Bot token is stored in environment variable (`TELEGRAM_BOT_TOKEN`)
2. Token is never exposed to client-side or LLM context
3. Moltis server-side code makes HTTPS requests to Telegram API
4. Token is injected via `${TELEGRAM_BOT_TOKEN}` substitution in `config/moltis.toml`

**Pros**:
- Official, maintained by Telegram
- Server-side only - token never exposed to browser/LLM
- HTTPS encryption enforced by Telegram
- No additional infrastructure needed
- Works with webhooks (production) or long polling (development)
- No rate limiting issues for legitimate bots
- Already implemented in Moltinger

**Cons**:
- Bot must be added as admin for private channels
- Cannot access channels where bot isn't a member
- Some API limitations (e.g., no user account features)

**Security**:
- Token is secret, but not sensitive in the same way as user credentials
- Bot permissions are scoped (can only access channels it's invited to)
- Token revocation is instant via @BotFather
- No user data exposure (bot is separate entity)

**Elegance Rating**: **10/10** - Industry standard, minimal complexity

**Current Moltinger Implementation**:
```toml
# config/moltis.toml
[channels.telegram.moltis-bot]
token = "${TELEGRAM_BOT_TOKEN}"              # GitOps-compliant
allowed_users = "${TELEGRAM_ALLOWED_USERS:-}"  # Comma-separated user IDs from env
```

**GitHub Secrets**:
```bash
TELEGRAM_BOT_TOKEN = 123456789:ABCdefGHI...  # Stored in GitHub Secrets
TELEGRAM_ALLOWED_USERS = 123456789,987654321
```

**Deployment** (from `.github/workflows/deploy.yml`):
```yaml
env:
  TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
  TELEGRAM_ALLOWED_USERS: ${{ secrets.TELEGRAM_ALLOWED_USERS }}
```

---

### 2. Telegram Userbot (MTProto) - Not Recommended

**Description**: User account automation using MTProto protocol (Telethon, Pyrogram).

**How it works**:
1. Uses real user account credentials (phone + verification code)
2. Requires session files with authentication keys
3. Can access any channel visible to user account
4. Bypasses bot API limitations

**Pros**:
- Access to private channels without admin rights
- Full user account features
- No bot limitations

**Cons**:
- Security risk: exposes user account credentials
- Violates Telegram ToS for automated actions
- Requires 2FA handling (manual intervention on restart)
- Session files must be stored securely
- Account can be banned for automation
- Token/session rotation is complex

**Security**:
- User credentials are HIGHLY sensitive
- Session files contain private keys
- If compromised, attacker gains full account access
- Cannot be revoked without changing phone number

**Elegance Rating**: **2/10** - High complexity, high risk, violates ToS

**Recommended Libraries** (for reference only - NOT recommended):
```python
# Python: Telethon
from telethon import TelegramClient

# WARNING: Stores session file with private keys
client = TelegramClient('session_name', api_id, api_hash)
```

**Recommendation**: **DO NOT USE** for Moltinger. Use Bot API with proper admin access instead.

---

### 3. Proxy/Gateway Services (Overkill for Moltinger)

**Description**: Intermediate server that proxies requests to Telegram API.

**How it works**:
1. LLM/Moltis requests go to proxy server
2. Proxy adds bot token server-side
3. Proxy forwards to Telegram API
4. Response returns via proxy

**Pros**:
- Token never exists on LLM/app server
- Centralized token management
- Can add rate limiting, logging, caching
- Multiple apps can share same proxy

**Cons**:
- Additional infrastructure component
- Single point of failure
- Latency increase
- Maintenance overhead
- Unnecessary for single-server deployment

**Security**:
- Token now stored on proxy server instead
- Still needs secret management
- Adds attack surface

**Elegance Rating**: **5/10** - Useful for microservices, overkill for Moltinger

**Recommended Tools**:
- **Nginx reverse proxy** with environment variable injection
- **Cloudflare Workers** (serverless)
- **AWS Lambda** (serverless)
- **Custom Node.js/Python proxy** (simple implementation)

**Example: Nginx Proxy**
```nginx
# nginx.conf
location /bot/ {
    set $telegram_bot_token $TELEGRAM_BOT_TOKEN;
    proxy_pass https://api.telegram.org/bot${telegram_bot_token}/;
}
```

**Recommendation**: Not needed for Moltinger's current architecture.

---

### 4. Webhook vs Long Polling (Delivery Methods)

**Description**: How the bot receives messages from Telegram.

#### Webhook (Recommended for Production)

**How it works**:
1. Telegram sends HTTPS POST to your endpoint
2. Your server processes message immediately
3. Requires public HTTPS endpoint with valid certificate

**Pros**:
- Real-time message delivery
- Lower server resource usage (no polling loops)
- Scales better for high message volume
- More efficient for production

**Cons**:
- Requires public HTTPS endpoint
- Certificate validation required
- Self-signed certificates need special handling
- Needs port 443 or 8443

**Security**:
- **Webhook secret token** prevents spoofed requests
- Telegram verifies SSL certificate
- IP whitelisting possible (Telegram's IP ranges)

**Configuration**:
```toml
# config/moltis.toml (Moltis handles this internally)
[channels.telegram.moltis-bot]
webhook_url = "https://moltis.ainetic.tech/telegram/webhook"
webhook_secret = "${TELEGRAM_WEBHOOK_SECRET}"  # Optional but recommended
```

**Elegance Rating**: **9/10** for production - Best practice for deployed services

---

#### Long Polling (Development/Testing)

**How it works**:
1. Your server repeatedly asks Telegram for updates
2. Telegram returns messages (or empty timeout)
3. Process repeats in loop

**Pros**:
- Works from local development (no public endpoint needed)
- Simpler setup for testing
- No certificate requirements

**Cons**:
- Higher server resource usage (continuous polling)
- Delay between message and bot seeing it (up to timeout)
- Not suitable for production

**Security**:
- Same security as Bot API (HTTPS)
- No additional risks

**Elegance Rating**: **7/10** for development - Simple but not production-ready

---

### 5. Open Source Patterns (Reference)

**Pattern A: Direct Bot API (Most Common)**
```python
# node-telegram-bot-api (Node.js)
const TelegramBot = require('node-telegram-bot-api');
const token = process.env.TELEGRAM_BOT_TOKEN;  // Environment variable
const bot = new TelegramBot(token, {polling: true});
```

**Pattern B: Webhook with Secret**
```python
# python-telegram-bot (Python)
from telegram import Update
from telegram.ext import Updater

updater = Updater(
    token=os.getenv('TELEGRAM_BOT_TOKEN'),
    webhook_url='https://example.com/webhook',
    webhook_secret=os.getenv('TELEGRAM_WEBHOOK_SECRET')  # Anti-spoofing
)
```

**Pattern C: MCP Server Pattern (Relevant for Moltinger)**
```typescript
// Model Context Protocol server for Telegram
// Keeps token server-side, exposes only tools to LLM
const telegramMcpServer = {
  name: 'telegram',
  tools: ['send_message', 'get_updates', 'get_channel_posts'],
  token: process.env.TELEGRAM_BOT_TOKEN,  // Never exposed in tool outputs
  allowedChannels: ['tsingular', 'moltinger_updates']
};
```

---

## Recommended Architecture for Moltinger

### Current Implementation (Recommended - No Changes Needed)

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Repository                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ GitHub Secrets                                          │ │
│  │ • TELEGRAM_BOT_TOKEN                                    │ │
│  │ • TELEGRAM_ALLOWED_USERS                                │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼ (CI/CD injects into .env)
┌─────────────────────────────────────────────────────────────┐
│               Production Server (Docker)                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Moltis Container                                       │ │
│  │ ┌──────────────────────────────────────────────────┐  │ │
│  │ │ config/moltis.toml                                │  │ │
│  │ │ token = "${TELEGRAM_BOT_TOKEN}"  ← Substituted    │  │ │
│  │ └──────────────────────────────────────────────────┘  │ │
│  │                        │                               │ │
│  │                        ▼                               │ │
│  │ ┌──────────────────────────────────────────────────┐  │ │
│  │ │ Telegram Channel (moltis-bot)                    │  │ │
│  │ │ • Sends messages to @tsingular                   │  │ │
│  │ │ • Receives updates via webhook/polling           │  │ │
│  │ └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS (Bot token in Authorization header)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                 Telegram Bot API                            │
│  api.telegram.org/bot<token>/sendMessage                     │
└─────────────────────────────────────────────────────────────┘
```

### Security Properties

| Property | Implementation | Status |
|----------|---------------|--------|
| Token Storage | GitHub Secrets (encrypted) | ✅ |
| Token Delivery | CI/CD only, never manual | ✅ |
| Token Visibility | Server-side only, never to LLM/client | ✅ |
| Transport Security | HTTPS enforced by Telegram | ✅ |
| Access Control | `allowed_users` whitelist | ✅ |
| Revocation | Instant via @BotFather | ✅ |
| Audit Trail | GitHub Actions logs + Moltis logs | ✅ |

---

## Security Best Practices Checklist

### Token Management
- [x] Store in GitHub Secrets (not in code)
- [x] Use environment variable substitution (`${TELEGRAM_BOT_TOKEN}`)
- [x] Never commit to git (add `.env` to `.gitignore`)
- [x] Rotate via @BotFather if compromised
- [x] Use separate bot per environment (dev/staging/prod)

### Access Control
- [x] Use `allowed_users` whitelist in Moltis config
- [ ] Consider adding `allowed_channels` whitelist (future enhancement)
- [ ] Add rate limiting per user (future enhancement)

### Webhook Security (if using webhooks)
- [ ] Set webhook secret token (`TELEGRAM_WEBHOOK_SECRET`)
- [ ] Validate webhook signature on each request
- [ ] Use HTTPS with valid certificate (Traefik handles this)

### Monitoring
- [ ] Log Telegram API errors
- [ ] Alert on rate limit hits
- [ ] Monitor for unusual message patterns

### Documentation
- [x] Document in `.env.example`
- [x] Document in `SECRETS-MANAGEMENT.md`
- [x] Include in deployment documentation

---

## Comparison Summary

| Pattern | Elegance | Security | Complexity | Moltinger Fit |
|---------|----------|----------|------------|---------------|
| Bot API (current) | 10/10 | High | Low | ✅ **Perfect** |
| Userbot (MTProto) | 2/10 | Very Low | High | ❌ Not recommended |
| Proxy Gateway | 5/10 | Medium | High | ❌ Overkill |
| Webhook delivery | 9/10 | High | Medium | ✅ Production-ready |
| Long Polling | 7/10 | High | Low | ✅ Dev/testing |

---

## Recommended Next Steps

### Immediate (P0)
- [x] Continue using existing Bot API implementation
- [ ] Add webhook secret for additional security
- [ ] Document webhook endpoint in deployment docs

### Short-term (P1)
- [ ] Add `allowed_channels` whitelist to Moltis config
- [ ] Implement rate limiting per user/channel
- [ ] Add Telegram-specific error logging

### Long-term (P2)
- [ ] Consider multi-bot setup (different bots for different purposes)
- [ ] Implement Telegram analytics (message volume, response times)
- [ ] Add Telegram health check to smoke tests

---

## Implementation Example: Webhook Secret (Optional Enhancement)

```toml
# config/moltis.toml
[channels.telegram.moltis-bot]
token = "${TELEGRAM_BOT_TOKEN}"
allowed_users = "${TELEGRAM_ALLOWED_USERS}"
webhook_url = "https://moltis.ainetic.tech/telegram/webhook"
webhook_secret = "${TELEGRAM_WEBHOOK_SECRET}"  # Anti-spoofing
```

```bash
# GitHub Secrets
gh secret set TELEGRAM_WEBHOOK_SECRET --repo RussianLioN/moltinger
# Generate with: openssl rand -hex 32
```

```yaml
# .github/workflows/deploy.yml
env:
  TELEGRAM_WEBHOOK_SECRET: ${{ secrets.TELEGRAM_WEBHOOK_SECRET }}
```

---

## Conclusion

The current Moltinger implementation of Telegram Bot API integration follows security best practices:

1. **Token stored in GitHub Secrets** (encrypted, never in code)
2. **Environment variable substitution** in config
3. **Server-side only** - token never exposed to LLM or client
4. **GitOps compliant** - delivered via CI/CD, never manual

**Recommendation**: Continue with current implementation. Consider adding webhook secret for anti-spoofing protection. No architectural changes needed.

---

## References

- [Telegram Bot API - Official Documentation](https://core.telegram.org/bots/api)
- [Telegram Bot API - Security Best Practices](https://core.telegram.org/bots/features#security)
- [Moltinger Secrets Management Policy](/docs/SECRETS-MANAGEMENT.md)
- [Moltinger Session Summary](/SESSION_SUMMARY.md)
- [Moltinger Telegram Learner Skill](/skills/telegram-learner/SKILL.md)

---

*Document created: 2026-02-19*
*Research completed: ✅ All patterns analyzed*
*Recommendation: Continue with current Bot API implementation*
