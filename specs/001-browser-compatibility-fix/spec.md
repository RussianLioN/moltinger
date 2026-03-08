# Feature Specification: Browser Compatibility Fix

**Feature Branch**: `001-browser-compatibility-fix`
**Created**: 2026-03-05
**Status**: Draft
**Input**: User description: "Fix browser compatibility issues with Moltis UI. Chrome works normally, Yandex browser requests password in a loop, Arc browser doesn't load at all."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Access Moltis from Any Major Browser (Priority: P1)

As a user, I want to access Moltis UI at moltis.ainetic.tech from any modern Chromium-based browser (Chrome, Yandex, Arc, Edge, Brave) and have it load correctly, so I am not limited to a single browser.

**Why this priority**: This is the core problem — the application is currently only usable in Chrome. Users who prefer other browsers cannot work at all (Arc) or get stuck in auth loops (Yandex).

**Independent Test**: Can be fully tested by opening moltis.ainetic.tech in each target browser and verifying the UI loads and responds to user input. Delivers value by expanding browser support from 1 to 5+ browsers.

**Acceptance Scenarios**:

1. **Given** Moltis is running on production, **When** a user opens moltis.ainetic.tech in Yandex Browser, **Then** the login page loads, the user authenticates once, and the main UI appears without additional password prompts.
2. **Given** Moltis is running on production, **When** a user opens moltis.ainetic.tech in Arc Browser, **Then** the page loads completely (no blank screen, no infinite spinner) and the UI is interactive.
3. **Given** Moltis is running on production, **When** a user opens moltis.ainetic.tech in Chrome, **Then** the existing behavior is preserved — login and UI work as before.

---

### User Story 2 - Persistent Session Across Browser Restarts (Priority: P2)

As a user, I want my session to persist after closing and reopening the browser, so I don't need to re-enter my password every time I return.

**Why this priority**: The Yandex "password loop" symptom suggests session persistence may be broken. Fixing this ensures authentication works reliably across browsers, not just loads initially.

**Independent Test**: Open Moltis in Yandex, authenticate, close the tab, reopen — the session should still be active (or at least require only one re-authentication, not a loop).

**Acceptance Scenarios**:

1. **Given** a user has authenticated in Yandex Browser, **When** they close and reopen the tab within 30 minutes, **Then** the session is still active and no re-authentication is required.
2. **Given** a user has authenticated in Arc Browser, **When** they close and reopen the tab within 30 minutes, **Then** the session is still active.

---

### User Story 3 - Real-time Features Work in All Browsers (Priority: P2)

As a user, I want real-time features (chat responses, live updates) to work in all supported browsers, so I get the same experience regardless of browser choice.

**Why this priority**: Moltis relies on WebSocket connections for real-time communication. If WebSocket fails in certain browsers, the UI may load but remain non-functional.

**Independent Test**: Open Moltis in Arc, send a message, and verify the response streams back in real-time (not delayed or requiring page refresh).

**Acceptance Scenarios**:

1. **Given** a user is connected to Moltis in Arc Browser, **When** they send a chat message, **Then** the response appears progressively (streaming), not as a single block after delay.
2. **Given** a user is connected to Moltis in Yandex Browser, **When** the agent is processing, **Then** status updates appear in real-time.

---

### Edge Cases

- What happens when a browser blocks third-party cookies?
- How does the system handle browsers with aggressive ad-blocking extensions?
- What happens if the user's browser does not support WebSocket (very old browsers)?
- How does the system behave when the browser sends a non-standard User-Agent string?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST serve the UI correctly to Chrome, Yandex, Arc, Edge, and Brave browsers.
- **FR-002**: System MUST NOT enter an authentication loop regardless of browser — a single successful authentication grants access.
- **FR-003**: System MUST establish WebSocket connections in all supported browsers for real-time communication.
- **FR-004**: System MUST set session cookies with attributes compatible with all target browsers (correct SameSite, Secure, and Path values).
- **FR-005**: System MUST NOT rely on browser-specific features or APIs that are unavailable in other Chromium-based browsers.
- **FR-006**: System MUST return correct HTTP response headers (CORS, CSP, cache-control) that do not block page loading in any supported browser.

### Key Entities

- **Session**: Authenticated user session with a token/cookie, associated with a browser fingerprint and expiration time.
- **WebSocket Connection**: Persistent connection between the browser and Moltis for real-time message exchange.
- **Reverse Proxy (Traefik)**: TLS-terminating proxy that forwards requests to Moltis — must correctly proxy both HTTP and WebSocket traffic.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 5 target browsers (Chrome, Yandex, Arc, Edge, Brave) successfully load the Moltis UI on first attempt without errors.
- **SC-002**: Authentication completes in a single step (no loops) across all target browsers.
- **SC-003**: WebSocket connections are established within 5 seconds in all target browsers.
- **SC-004**: Session persists for at least 30 minutes across tab close/reopen in all target browsers.
- **SC-005**: Zero browser-specific JavaScript errors in the console after page load in all target browsers.

### Assumptions

- All target browsers are up-to-date (latest stable versions).
- The issue is in the server/proxy configuration, not in the Moltis application source code (which is a third-party Docker image).
- Users access Moltis via HTTPS through the Traefik reverse proxy (moltis.ainetic.tech), not directly on port 13131.
- The current Chrome behavior is the correct baseline — all other browsers should match it.
- **Escalation path**: If diagnosis reveals the root cause is in Moltis source code, apply a proxy-level workaround and open an upstream issue in the Moltis repository for a permanent fix.

## Clarifications

### Session 2026-03-05

- Q: What should we do if the root cause is in Moltis source code, not proxy/config? → A: Apply proxy workaround + open upstream Moltis issue.
