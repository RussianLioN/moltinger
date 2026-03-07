# Research: Browser Compatibility Fix

**Date**: 2026-03-05
**Feature**: 001-browser-compatibility-fix

## R1: Moltis Authentication Mechanism

**Decision**: Moltis uses form-based password + WebAuthn authentication with session cookies.

**Rationale**: Per [Moltis Authentication Docs](https://docs.moltis.org/authentication.html):
- Authentication is password (Argon2id hashed) or passkey (WebAuthn)
- Session cookie: `moltis_session`, HttpOnly, **SameSite=Strict**, 30-day expiry
- All requests pass through `auth_gate` middleware → `check_auth()`
- Public paths bypass auth: `/health`, `/assets/*`, `/api/auth/*`
- WebSocket dual auth: HTTP upgrade uses session cookie, then connect message for non-browser clients

**Key finding**: `SameSite=Strict` is the most restrictive cookie policy. While Chromium treats direct URL-bar navigation as same-site, Yandex Browser may handle this differently. This is the primary suspect for the auth loop.

**Alternatives considered**: HTTP Basic Auth (not used), token-only auth (not used)

## R2: Traefik WebSocket Proxying

**Decision**: Traefik supports WebSocket out of the box. No special middleware needed for basic WS proxying.

**Rationale**: Per [Traefik WebSocket Docs](https://doc.traefik.io/traefik/v3.4/user-guides/websocket/):
- Standard HTTP router labels are sufficient
- TLS termination works with `tls=true` on the router
- Header manipulation available via Headers middleware if origin validation needed
- For HTTP/2 WebSocket, `experimental.http2.websocket` may be needed

**Current Traefik labels** (from `docker-compose.prod.yml`):
```yaml
- "traefik.http.routers.moltis.rule=Host(`moltis.ainetic.tech`)"
- "traefik.http.routers.moltis.entrypoints=websecure"
- "traefik.http.routers.moltis.tls.certresolver=letsencrypt"
- "traefik.http.services.moltis.loadbalancer.server.port=13131"
```

**Gap**: No `X-Forwarded-Proto` or WebSocket-specific headers configured. Moltis checks `MOLTIS_BEHIND_PROXY` but the proxy headers may not be complete.

## R3: Arc Browser Issues

**Decision**: Arc blank page likely caused by WebSocket connection failure or ad-blocker interference, not a fundamental browser incompatibility.

**Rationale**: Per [Arc Release Notes](https://resources.arc.net/hc/en-us/articles/20498293324823-Arc-for-macOS-2024-2026-Release-Notes):
- Recent Arc versions fixed blank page bugs
- Arc is Chromium 139-based — should support all standard web APIs
- Arc has built-in "Boost" features and sidebar that could interfere
- Ad blockers can cause blank pages by blocking critical resources

**Alternatives considered**: WebSocket not supported (rejected — Arc uses Chromium engine)

## R4: Yandex Browser Cookie Handling

**Decision**: Yandex Browser likely rejects or mishandles `SameSite=Strict` cookies in certain navigation scenarios, causing authentication loops.

**Rationale**:
- Yandex Browser is Chromium-based but adds privacy-focused modifications
- `SameSite=Strict` prevents cookie from being sent on cross-site navigations
- Yandex may classify direct URL entry or bookmark navigation differently than Chrome
- The "password request" symptom suggests the session cookie isn't being sent back, triggering re-authentication

**Sources**: [SameSite Cookies Best Practices 2025](https://www.heatware.net/tech-tips/what-are-samesite-cookies/), [Cookie Behavior Reference](https://www.dchost.com/blog/en/cookies-that-behave-samesitelax-strict-secure-and-httponly-done-right-on-nginx-apache-and-in-your-app/)

## R5: Moltis TLS Configuration Conflict

**Decision**: No conflict — env var `MOLTIS_NO_TLS=true` overrides `moltis.toml` TLS settings.

**Rationale**:
- `config/moltis.toml` has `[tls] enabled = true, auto_generate = true`
- `docker-compose.prod.yml` sets `MOLTIS_NO_TLS: "true"` and `MOLTIS_BEHIND_PROXY: "true"`
- Env vars take precedence — Moltis runs HTTP internally, Traefik handles TLS
- This is the correct architecture for a reverse proxy setup

## Summary of Hypotheses (Ordered by Likelihood)

| # | Hypothesis | Browser | Confidence | Fix Location |
|---|-----------|---------|------------|--------------|
| 1 | `SameSite=Strict` cookie rejected by Yandex | Yandex | High | Moltis config or proxy header |
| 2 | Missing proxy headers (`X-Forwarded-*`) break local/remote detection | Both | Medium | docker-compose.prod.yml |
| 3 | WebSocket upgrade fails due to missing headers | Arc | Medium | Traefik middleware |
| 4 | Arc ad-blocker/Boost blocks Moltis assets or WS | Arc | Medium | User-side / CSP headers |
| 5 | Moltis UI JavaScript uses Chrome-specific API | Arc | Low | Upstream Moltis issue |

## Diagnosis Strategy

Before implementing fixes, we MUST diagnose:
1. Open each browser with DevTools (F12 → Console + Network)
2. Check server logs: `docker logs moltis | tail -50`
3. Compare HTTP response headers between browsers
4. Verify WebSocket connection status in each browser
5. Check if "password request" is Moltis login page or browser-native HTTP Basic Auth dialog
