# Data Model: Browser Compatibility Fix

**Date**: 2026-03-05

## Entities

This is an infrastructure/configuration fix. No new data entities are created. The relevant entities are part of the existing Moltis system.

### Session (existing, managed by Moltis)

| Attribute | Type | Notes |
|-----------|------|-------|
| cookie_name | string | `moltis_session` |
| same_site | enum | Currently `Strict` — suspected root cause |
| secure | boolean | `true` (HTTPS via Traefik) |
| http_only | boolean | `true` |
| expiry | duration | 30 days |
| domain | string | Not set (defaults to request host) |

### Reverse Proxy Config (existing, managed by us)

| Attribute | Source File | Current Value |
|-----------|------------|---------------|
| router rule | docker-compose.prod.yml | `Host(moltis.ainetic.tech)` |
| entrypoint | docker-compose.prod.yml | `websecure` |
| TLS resolver | docker-compose.prod.yml | `letsencrypt` |
| backend port | docker-compose.prod.yml | `13131` |
| network | docker-compose.prod.yml | `traefik-net` |
| MOLTIS_NO_TLS | docker-compose.prod.yml | `true` |
| MOLTIS_BEHIND_PROXY | docker-compose.prod.yml | `true` |

### Configuration Files (modification candidates)

| File | Purpose | Likely Change |
|------|---------|---------------|
| `docker-compose.prod.yml` | Traefik labels, env vars | Add proxy headers middleware |
| `config/moltis.toml` | Moltis app config | Potentially no change (env vars override) |

## State Transitions

```
Browser Request → Traefik (TLS termination)
                    → Moltis auth_gate (check_auth)
                        → Has valid session cookie?
                            → YES → Serve page
                            → NO → Redirect to login
                                → User enters password
                                → Set moltis_session cookie (SameSite=Strict)
                                → Redirect to app
                                    → Cookie sent? (SameSite check)
                                        → YES → Serve page ✅
                                        → NO → Back to login ❌ (LOOP)
```
