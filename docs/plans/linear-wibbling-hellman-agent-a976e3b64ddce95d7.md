# E2E User Scenario Test Plan: demo.ainetic.tech

**Status**: PLAN MODE - READ-ONLY TEST
**Date**: 2026-03-19
**Objective**: Full end-to-end Playwright MCP test of the ASC AI Fabrique demo workflow
**Scope**: Access gate → discovery questions → brief → confirm → artifacts
**Tool**: Playwright MCP (browser navigation, snapshots, form filling)

---

## CONTEXT

This is a READ-ONLY E2E test validating the complete user workflow on https://demo.ainetic.tech:
1. **Access Gate**: Token authentication
2. **Discovery Phase**: 6-7 turn conversation to gather requirements
3. **Brief Review**: Confirmation of collected data
4. **Artifacts**: Download generated documents

The test focuses on verifying:
- UI responsiveness and proper flow progression
- File upload handling (critical hang point previously identified)
- Chat interaction and agent responses
- No repeated/duplicate questions
- Proper state transitions

**Key Previous Issue**: Turn 6 (file upload + input examples) was hanging for 60+ seconds. This test will validate the fix.

---

## EXECUTION PLAN

### Phase 1: Setup & Gate (Step 1)
- **Action**: Navigate to demo site → authenticate with token
- **Acceptance**: Workspace visible (not gate), no console errors
- **Expected Time**: <5s

### Phase 2: Discovery Turns 1-6 (Steps 2-7)
- **Sequence**:
  - Turn 1: Problem statement (CS summary automation)
  - Turn 2: Target users (client manager + committee)
  - Turn 3: Current workflow (CSV → Word → PDF, manual work)
  - Turn 4: Expected output (PDF brief with recommendation)
  - Turn 5: Use case timing (before committee meeting)
  - Turn 6: **FILE UPLOAD** - CSV with client data + text input
- **Critical Check**: Turn 6 response time (should be <45s, not hanging)
- **Acceptance**: Each turn progresses to next question, agent doesn't repeat

### Phase 3: Discovery Completion (Steps 8-9)
- **Action**: Final threshold question + success metrics (if needed)
- **Acceptance**: Discovery marked complete or brief appears
- **Expected Time**: <60s total for remaining turns

### Phase 4: Brief Review (Steps 10-11)
- **Action**: Wait for brief panel → click Confirm button
- **Acceptance**: Artifacts generated, no errors
- **Expected Time**: <30s for brief review, <60s for artifact generation

### Phase 5: Download Verification (Step 12)
- **Action**: Verify download links present and clickable
- **Acceptance**: Links respond without 404/errors
- **Expected Time**: <10s

---

## REPORTING CHECKLIST

After each step, record:
- ✓ Page snapshot (visual confirmation)
- ✓ Key UI elements visible
- ✓ Response time
- ✓ Any console errors/warnings
- ✓ State transition confirmed

**Final Summary Report Must Include**:
- Total steps completed (target: 12/12)
- Failed steps (if any)
- Hang detection (timeout vs success)
- File upload handling result (CRITICAL)
- Full workflow completion percentage
- Console error count
- Recommendation: PASS / FAIL / PARTIAL with blockers

---

## CONSTRAINTS & RULES

✓ **READ-ONLY**: No file edits, no config changes, no production modifications
✓ **Playwright Only**: Use browser_navigate, browser_snapshot, browser_fill_form, browser_type, browser_click, browser_file_upload, browser_wait_for
✓ **Timeouts**: 45s for normal turns, 60s for file upload + response
✓ **No Manual Intervention**: Fully automated E2E
✓ **Token**: Use provided `demo-access-token`

---

## SUCCESS CRITERIA

| Criterion | Status |
|-----------|--------|
| Gate authentication succeeds | TBD |
| All 7 discovery turns complete without repeats | TBD |
| File upload (Turn 6) responds <45s | TBD |
| Brief appears after discovery | TBD |
| Confirm button triggers artifact generation | TBD |
| No console errors during workflow | TBD |
| Full cycle completes (gate→discovery→brief→artifacts) | TBD |

---

## NEXT STEPS

1. **Execution Phase**: Proceed with Steps 1-12 in sequence
2. **Monitoring**: Track response times and watch for hangs
3. **Reporting**: Record snapshots and results after each step
4. **Analysis**: Determine if previous file upload hang is fixed
