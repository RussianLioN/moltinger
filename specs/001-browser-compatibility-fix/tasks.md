# Tasks: Browser Compatibility Fix

**Input**: Design documents from `/specs/001-browser-compatibility-fix/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not requested. Manual browser verification used instead.

**Organization**: Tasks are grouped by user story. This is a diagnosis-first infrastructure fix — Phase 2 (Diagnosis) MUST complete before any fixes are applied.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 0: Planning (Executor Assignment)

**Purpose**: Prepare for implementation by analyzing requirements and assigning executors.

- [ ] P001 Analyze all tasks and identify required agent types and capabilities
- [ ] P002 Create missing agents using meta-agent-v3 (launch N calls in single message, 1 per agent), then ask user restart
- [ ] P003 Assign executors to all tasks: MAIN (trivial only), existing agents (100% match), or specific agent names
- [ ] P004 Resolve research tasks: simple (solve with tools now), complex (create prompts in research/)

**Rules**:
- **MAIN executor**: ONLY for trivial tasks (1-2 line fixes, simple imports, single npm install)
- **Existing agents**: ONLY if 100% capability match after thorough examination
- **Agent creation**: Launch all meta-agent-v3 calls in single message for parallel execution
- **After P002**: Must restart claude-code before proceeding to P003

**Artifacts**:
- Updated tasks.md with [EXECUTOR: name], [SEQUENTIAL]/[PARALLEL-GROUP-X] annotations
- .claude/agents/{domain}/{type}/{name}.md (if new agents created)
- research/*.md (if complex research identified)

---

## Phase 1: Setup (Gather Baseline Data)

**Purpose**: Collect current state information from production server and browsers before making any changes.

- [x] T001 Check Moltis container status and recent logs via SSH read-only: `ssh root@ainetic.tech "docker ps | grep moltis && docker logs moltis --tail 100 2>&1 | grep -iE 'auth|error|cookie|websocket|upgrade'"`
- [x] T002 [P] Check Traefik routing logs for Moltis via SSH read-only: `ssh root@ainetic.tech "docker logs traefik 2>&1 | grep -i moltis | tail -20"`
- [x] T003 [P] Inspect current HTTP response headers from production: `curl -sI https://moltis.ainetic.tech/ 2>&1` and `curl -sI https://moltis.ainetic.tech/api/auth/login 2>&1` — save output to `.tmp/current/baseline-headers.txt`
- [x] T004 [P] Check current Traefik labels on Moltis container via SSH read-only: `ssh root@ainetic.tech "docker inspect moltis --format '{{json .Config.Labels}}'" | jq .`

---

## Phase 2: Foundational — Diagnosis (Blocking Prerequisites)

**Purpose**: Identify root cause for each browser. NO fixes until this phase is complete.

**⚠️ CRITICAL**: No fix tasks can begin until diagnosis confirms which hypotheses are correct.

- [x] T005 Open moltis.ainetic.tech in Chrome (baseline): capture DevTools Console errors, Network headers (especially `Set-Cookie`, `WWW-Authenticate`), WebSocket status, and Cookie storage — document findings in `.tmp/current/diagnosis-chrome.md`
- [ ] T006 Open moltis.ainetic.tech in Yandex Browser: capture same data as T005, specifically determine if "password request" is Moltis login page or browser-native HTTP Basic Auth dialog — document in `.tmp/current/diagnosis-yandex.md`
- [ ] T007 Open moltis.ainetic.tech in Arc Browser: capture same data as T005, specifically check if page loads at all (blank vs error vs partial), check WebSocket tab, test with extensions/Boost disabled — document in `.tmp/current/diagnosis-arc.md`
- [ ] T008 Compare diagnosis results across all 3 browsers: create comparison table of headers, cookies, WebSocket status, console errors — write root cause summary to `.tmp/current/diagnosis-summary.md` with confirmed/rejected hypotheses (H1-H5 from research.md)

**Checkpoint**: Root cause identified. Proceed to appropriate fix phase based on confirmed hypotheses.

---

## Phase 3: User Story 1 — Access Moltis from Any Major Browser (Priority: P1) 🎯 MVP

**Goal**: All target browsers (Chrome, Yandex, Arc) can load the Moltis UI and authenticate without loops or blank pages.

**Independent Test**: Open moltis.ainetic.tech in each browser, verify login works with single authentication, and UI is interactive.

### Implementation for User Story 1

- [x] T009 [US1] Based on diagnosis-summary.md, determine which fixes (A/B/C/D from plan.md) to apply — update `.tmp/current/fix-plan.md` with selected fixes and rationale
- [x] T010 [US1] If H2 confirmed (missing proxy headers): add `X-Forwarded-Proto` and `X-Forwarded-Host` Traefik middleware labels to `docker-compose.prod.yml` (lines ~87-100, moltis labels section)
- [ ] T011 [US1] If H1 confirmed (SameSite=Strict cookie): add Traefik response header middleware to override `SameSite=Lax` in `docker-compose.prod.yml`, OR check if `config/moltis.toml` has a cookie config option
- [ ] T012 [US1] If H3 confirmed (WebSocket upgrade): add WebSocket-specific headers middleware to `docker-compose.prod.yml`
- [ ] T013 [US1] If H4/H5 confirmed (CORS/CSP): add CORS headers middleware to `docker-compose.prod.yml`
- [x] T014 [US1] Validate docker-compose.prod.yml syntax: run `docker compose -f docker-compose.prod.yml config --quiet` locally
- [ ] T015 [US1] Deploy fix via GitOps: commit changes, push to branch, create PR or merge to main for CI/CD deployment
- [ ] T016 [US1] Verify fix in Chrome (regression test): open moltis.ainetic.tech, login, confirm UI works as before
- [ ] T017 [US1] Verify fix in Yandex Browser: open moltis.ainetic.tech, login once, confirm no auth loop, UI is interactive
- [ ] T018 [US1] Verify fix in Arc Browser: open moltis.ainetic.tech, confirm page loads (no blank), login works, UI is interactive

**Checkpoint**: All 3 browsers load Moltis UI and authenticate correctly. MVP delivered.

---

## Phase 4: User Story 2 — Persistent Session Across Browser Restarts (Priority: P2)

**Goal**: Session cookie persists after closing and reopening browser tab in all browsers.

**Independent Test**: Login in Yandex/Arc, close tab, reopen within 30 minutes — session should still be active.

### Implementation for User Story 2

- [ ] T019 [US2] Verify session persistence in Chrome: login, close tab, reopen — confirm still authenticated
- [ ] T020 [US2] Verify session persistence in Yandex: login, close tab, reopen within 30 min — confirm no re-auth needed
- [ ] T021 [US2] Verify session persistence in Arc: login, close tab, reopen within 30 min — confirm no re-auth needed
- [ ] T022 [US2] If session doesn't persist in any browser: inspect cookie expiry and flags in DevTools → Application → Cookies, apply additional fix to `docker-compose.prod.yml` or `config/moltis.toml`

**Checkpoint**: Sessions persist across tab close/reopen in all browsers.

---

## Phase 5: User Story 3 — Real-time Features Work in All Browsers (Priority: P2)

**Goal**: WebSocket connections establish and real-time message streaming works in all browsers.

**Independent Test**: Send a chat message in Arc/Yandex, verify response streams progressively.

### Implementation for User Story 3

- [ ] T023 [US3] Verify WebSocket connection in Chrome: open DevTools Network → WS filter, confirm connection established and messages flow
- [ ] T024 [US3] Verify WebSocket connection in Yandex: same check as T023, confirm real-time streaming works
- [ ] T025 [US3] Verify WebSocket connection in Arc: same check as T023, confirm real-time streaming works
- [ ] T026 [US3] If WebSocket fails in any browser: check Traefik logs for upgrade errors, apply Fix C (WebSocket headers) if not already applied, redeploy and re-verify

**Checkpoint**: Real-time features work in all 3 browsers.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cleanup, and closing tasks.

- [ ] T027 [P] Document browser compatibility findings and fix in `docs/LESSONS-LEARNED.md` — add new section "Browser Compatibility (2026-03-05)"
- [ ] T028 [P] If root cause was in Moltis source: open upstream issue at https://github.com/moltis-org/moltis/issues with reproduction steps and workaround description
- [ ] T029 Close Beads task moltinger-vt0 with reason: `bd close moltinger-vt0 --reason "Fixed browser compatibility: [summary of fix]"`
- [ ] T030 Run quickstart.md validation: verify diagnosis and fix steps in `specs/001-browser-compatibility-fix/quickstart.md` match actual steps taken, update if needed
- [ ] T031 Sync and push: `bd sync && git push`

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 0: Planning → no deps, start immediately
Phase 1: Setup → no deps, can start in parallel with Phase 0
Phase 2: Diagnosis → depends on Phase 1 (need baseline data)
    ⚠️ BLOCKS all fix phases — must complete first
Phase 3: US1 Fix → depends on Phase 2 (need confirmed root cause)
Phase 4: US2 Verify → depends on Phase 3 (need fix deployed)
Phase 5: US3 Verify → depends on Phase 3 (need fix deployed)
    US2 and US3 can run in PARALLEL after US1 fix is deployed
Phase 6: Polish → depends on all user stories complete
```

### User Story Dependencies

- **US1 (P1)**: Depends on Diagnosis (Phase 2) — core fix, MVP
- **US2 (P2)**: Depends on US1 fix deployed — session verification
- **US3 (P2)**: Depends on US1 fix deployed — WebSocket verification
- **US2 and US3 are independent of each other** — can verify in parallel

### Within Phase 3 (US1)

```
T009 (decide fixes) → T010/T011/T012/T013 (apply fixes, conditional) → T014 (validate) → T015 (deploy) → T016/T017/T018 (verify, parallel)
```

### Parallel Opportunities

- **Phase 1**: T001, T002, T003, T004 — all read-only, fully parallel
- **Phase 2**: T005, T006, T007 — can run in parallel (different browsers), T008 depends on all three
- **Phase 3**: T010-T013 — conditional but independent fixes, can apply in parallel
- **Phase 3**: T016, T017, T018 — browser verification, fully parallel
- **Phase 4+5**: US2 and US3 verification can run in parallel after US1 deployment
- **Phase 6**: T027, T028 — documentation tasks, fully parallel

---

## Parallel Example: Phase 1 (Setup)

```bash
# Launch all baseline data collection in parallel:
Task: "Check Moltis logs via SSH"
Task: "Check Traefik logs via SSH"
Task: "Inspect HTTP headers via curl"
Task: "Check Traefik labels via SSH"
```

## Parallel Example: Phase 3 (Verification)

```bash
# After fix deployed, verify all browsers in parallel:
Task: "Verify fix in Chrome (regression)"
Task: "Verify fix in Yandex (auth loop resolved)"
Task: "Verify fix in Arc (blank page resolved)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 0: Planning (assign executors)
2. Complete Phase 1: Setup (gather baseline)
3. Complete Phase 2: Diagnosis (identify root cause) — **CRITICAL GATE**
4. Complete Phase 3: US1 Fix (apply and verify)
5. **STOP and VALIDATE**: All 3 browsers load and authenticate ✅
6. Deploy if MVP sufficient

### Incremental Delivery

1. Setup + Diagnosis → Root cause confirmed
2. Apply US1 Fix → Test all browsers → **MVP deployed!**
3. Verify US2 (session persistence) → Confirm or apply additional fix
4. Verify US3 (WebSocket/real-time) → Confirm or apply additional fix
5. Polish (docs, upstream issue, Beads close) → Done!

### Key Constraint

**All fix tasks (T010-T013) are CONDITIONAL** — they only execute if the corresponding hypothesis is confirmed during diagnosis. The fix-plan.md (T009) determines which to apply.

---

## Notes

- All SSH commands are **READ-ONLY** — GitOps compliant
- Fix deployment is via git commit + push (CI/CD or manual pull on server)
- Browser testing is manual (user must open each browser)
- Playwright MCP can automate some checks but cannot test Yandex/Arc specifically
- Conditional tasks (T010-T013) may be skipped based on diagnosis results
- Total: 31 tasks (4 planning + 4 setup + 4 diagnosis + 10 US1 + 4 US2 + 4 US3 + 5 polish)
