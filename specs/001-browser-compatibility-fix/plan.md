# Implementation Plan: Browser Compatibility Fix

**Branch**: `001-browser-compatibility-fix` | **Date**: 2026-03-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/001-browser-compatibility-fix/spec.md`

## Summary

Moltis UI works in Chrome but fails in Yandex Browser (auth loop) and Arc (blank page). Research reveals that Moltis uses `SameSite=Strict` session cookies and WebSocket dual-auth. The fix requires diagnosis-first approach: inspect browser DevTools and server logs to confirm root cause, then apply targeted configuration changes to Traefik proxy headers and/or Moltis config.

## Technical Context

**Language/Version**: Bash scripts, YAML (Docker Compose), TOML (Moltis config)
**Primary Dependencies**: Traefik v3 (reverse proxy), Moltis (third-party Docker image)
**Storage**: N/A (configuration changes only)
**Testing**: Manual browser testing + Playwright MCP for automated verification
**Target Platform**: Linux server (Ubuntu 22.04) with Docker
**Project Type**: Infrastructure/configuration fix
**Performance Goals**: WebSocket connection within 5 seconds, single auth step
**Constraints**: Cannot modify Moltis source code (third-party image). All changes via proxy config or Moltis TOML config. GitOps-compliant (no manual server edits).
**Scale/Scope**: Single production instance, 1 user, 5 target browsers

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Context-First | PASS | Config files read, Moltis docs researched, Traefik docs reviewed |
| II. Single Source of Truth | N/A | No types/schemas in this fix |
| III. Library-First | N/A | No custom code >20 lines |
| IV. Code Reuse & DRY | N/A | Config changes only |
| V. Strict Type Safety | N/A | No TypeScript in this fix |
| VI. Atomic Task Execution | PASS | Each task independently testable |
| VII. Quality Gates | PASS | Docker compose validation, browser testing |
| VIII. Progressive Specification | PASS | Following speckit workflow |
| IX. Error Handling | N/A | No custom code |
| X. Observability | ADVISORY | Consider adding monitoring for browser compatibility post-fix |
| XI. Accessibility | N/A | UI is third-party |

## Project Structure

### Documentation (this feature)

```text
specs/001-browser-compatibility-fix/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0: Research findings
├── data-model.md        # Phase 1: Entity documentation
├── quickstart.md        # Phase 1: Diagnosis & fix guide
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (files to modify)

```text
# Configuration files (modification candidates)
docker-compose.prod.yml          # Traefik labels, proxy headers middleware
config/moltis.toml               # Moltis auth/TLS settings (if needed)

# Diagnostic scripts (may create)
scripts/browser-compat-test.sh   # Automated header comparison script
```

**Structure Decision**: This is an infrastructure fix. No new source directories needed. Changes are limited to existing Docker Compose and Moltis configuration files.

## Technical Approach

### Phase 1: Diagnosis (MUST complete before any fixes)

#### 1.1 Server-Side Log Analysis
- SSH to production, check `docker logs moltis` for auth errors
- Check `docker logs traefik` for routing/upgrade issues
- Inspect current response headers via `curl`

#### 1.2 Browser-Side Analysis
- Open moltis.ainetic.tech in Chrome (baseline), Yandex, Arc
- Compare: response headers, cookies, WebSocket status, console errors
- Determine if Yandex "password request" is Moltis login page or HTTP Basic Auth dialog
- Determine if Arc blank page is pre-auth or post-auth

#### 1.3 Root Cause Confirmation
Based on diagnosis, confirm or reject these hypotheses:

| # | Hypothesis | Diagnosis Method |
|---|-----------|-----------------|
| H1 | `SameSite=Strict` cookie rejected by Yandex | Check cookie in Yandex DevTools → Application → Cookies |
| H2 | Missing `X-Forwarded-*` headers break local/remote detection | Check request headers in Moltis logs |
| H3 | WebSocket upgrade fails in Arc | Check WS tab in Arc DevTools |
| H4 | Arc ad-blocker blocks Moltis assets | Test with extensions disabled |
| H5 | Moltis sends `WWW-Authenticate` header triggering browser-native dialog | Check response headers for 401 + WWW-Authenticate |

### Phase 2: Fix Implementation

Based on diagnosis results, apply one or more of these fixes:

#### Fix A: Traefik Proxy Headers (for H2)
Add `X-Forwarded-*` headers middleware to ensure Moltis correctly identifies the request as coming through a proxy:

```yaml
# docker-compose.prod.yml — add middleware labels
- "traefik.http.middlewares.moltis-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
- "traefik.http.middlewares.moltis-headers.headers.customrequestheaders.X-Forwarded-Host=${MOLTIS_DOMAIN:-moltis.ainetic.tech}"
- "traefik.http.routers.moltis.middlewares=moltis-headers"
```

#### Fix B: Cookie SameSite Override (for H1)
If Moltis doesn't have a config option for SameSite, use Traefik response header middleware to rewrite the cookie:

```yaml
# Rewrite Set-Cookie header to use SameSite=Lax
- "traefik.http.middlewares.moltis-cookies.headers.customresponseheaders.Set-Cookie=moltis_session=...; SameSite=Lax; Secure; HttpOnly"
```

Note: This is a proxy-level workaround. Proper fix requires Moltis config option or upstream issue.

#### Fix C: WebSocket Headers (for H3)
Ensure WebSocket upgrade headers pass through correctly:

```yaml
- "traefik.http.middlewares.moltis-ws.headers.customrequestheaders.Connection=Upgrade"
- "traefik.http.middlewares.moltis-ws.headers.customrequestheaders.Upgrade=websocket"
```

#### Fix D: CSP/CORS Headers (for H4/H5)
Add permissive CORS and CSP headers if needed:

```yaml
- "traefik.http.middlewares.moltis-cors.headers.accesscontrolalloworiginlist=https://moltis.ainetic.tech"
- "traefik.http.middlewares.moltis-cors.headers.accesscontrolallowmethods=GET,POST,OPTIONS"
```

### Phase 3: Verification

1. Deploy via GitOps (commit → push → CI/CD)
2. Test each browser:
   - Chrome: regression test (still works)
   - Yandex: login → verify no loop → check session persistence
   - Arc: page loads → WebSocket connects → send message
3. Check server logs for errors
4. Verify with `curl` that headers are correct

### Phase 4: Documentation & Cleanup

1. Update `docs/LESSONS-LEARNED.md` with browser compatibility findings
2. Close Beads task `moltinger-vt0`
3. Consider: add automated browser compatibility test to CI/CD

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Fix breaks Chrome (regression) | High | Test Chrome first after each change |
| SameSite=Lax reduces security | Medium | Lax is standard for most apps; Strict is overly restrictive for this use case |
| Proxy header override conflicts with Traefik defaults | Low | Test with `docker compose config` before deploy |
| Root cause is in Moltis source (can't fix) | Medium | Apply proxy workaround + open upstream issue |

## Complexity Tracking

No constitution violations. All changes are within allowed scope (config files, GitOps-compliant).
