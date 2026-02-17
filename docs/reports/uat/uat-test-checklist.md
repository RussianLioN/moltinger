# Moltis UAT Test Execution Checklist

**Test Cycle**: UAT-2026-02-17
**Tester**: ________________
**Date**: ________________

---

## Quick Status Legend

- [ ] Not tested
- [P] Passed
- [F] Failed (log defect)
- [B] Blocked (note reason)
- [S] Skipped (note reason)

---

## 1. Smoke Tests (P0 - Must Pass)

### 1.1 Web UI Access

| ID | Test | Status | Notes |
|----|------|--------|-------|
| SM-01 | Navigate to https://moltis.ainetic.tech | [ ] | |
| SM-02 | Authentication prompt appears | [ ] | |
| SM-03 | Login with valid password | [ ] | |
| SM-04 | Chat interface loads (no black screen) | [ ] | |
| SM-05 | Send message: "Hello" | [ ] | |
| SM-06 | Response received within 30s | [ ] | |
| SM-07 | No JavaScript console errors | [ ] | |

### 1.2 Telegram Bot

| ID | Test | Status | Notes |
|----|------|--------|-------|
| SM-08 | Bot responds to /start | [ ] | |
| SM-09 | Send message, receive response | [ ] | |
| SM-10 | /model command works | [ ] | |

### 1.3 Model Selection

| ID | Test | Status | Notes |
|----|------|--------|-------|
| SM-11 | Exactly 3 models shown (glm-5, glm-4.7, glm-4.5-air) | [ ] | |
| SM-12 | Model selector works | [ ] | |
| SM-13 | Selected model persists to next message | [ ] | |

**Smoke Test Result**: PASS / FAIL
**If FAIL**: STOP - Do not proceed until smoke tests pass

---

## 2. Critical User Journeys (P0/P1)

### CUJ-01: First-Time User

| Step | Expected | Actual | Pass/Fail |
|------|----------|--------|-----------|
| 1. Open URL | Auth prompt | | [ ] |
| 2. Enter password | Access granted | | [ ] |
| 3. See chat UI | Interface loads | | [ ] |
| 4. Check models | 3 models shown | | [ ] |
| 5. Send "Introduce yourself" | Russian response | | [ ] |
| 6. Check response time | < 30 seconds | | [ ] |

### CUJ-02: Developer Workflow

| Step | Expected | Actual | Pass/Fail |
|------|----------|--------|-----------|
| 1. Request Python function | Code generated | | [ ] |
| 2. Check code formatting | Syntax highlighted | | [ ] |
| 3. Request modification | Context maintained | | [ ] |
| 4. Request file save | Operation confirmed | | [ ] |

### CUJ-03: Research Workflow

| Step | Expected | Actual | Pass/Fail |
|------|----------|--------|-----------|
| 1. Request web search | Search triggered | | [ ] |
| 2. Check for sources | URLs included | | [ ] |
| 3. Request summary | Bullets generated | | [ ] |
| 4. Request outline | Structure created | | [ ] |

### CUJ-04: Telegram Full Flow

| Step | Expected | Actual | Pass/Fail |
|------|----------|--------|-----------|
| 1. /start command | Welcome message | | [ ] |
| 2. /model | Current model shown | | [ ] |
| 3. /model glm-4.7 | Model switched | | [ ] |
| 4. Send test message | Response from new model | | [ ] |

---

## 3. Edge Cases

| ID | Test | Status | Notes |
|----|------|--------|-------|
| EC-01 | Network disconnect/reconnect | [ ] | |
| EC-02 | Message > 10,000 chars | [ ] | |
| EC-03 | XSS test: <script>alert(1)</script> | [ ] | |
| EC-04 | Concurrent sessions (2 browsers) | [ ] | |
| EC-05 | Empty message (Enter only) | [ ] | |
| EC-06 | Whitespace-only message | [ ] | |
| EC-07 | Emoji-only message | [ ] | |

---

## 4. Error Scenarios

| ID | Test | Status | Notes |
|----|------|--------|-------|
| ERR-01 | Wrong password (3x) | [ ] | |
| ERR-02 | Non-whitelisted Telegram user | [ ] | |
| ERR-03 | Model timeout simulation | [ ] | |
| ERR-04 | Invalid file path request | [ ] | |

---

## 5. Cross-Channel Testing

| ID | Test | Status | Notes |
|----|------|--------|-------|
| MCP-01 | Session memory persistence (Web) | [ ] | |
| MCP-02 | Cross-channel memory (Web -> Telegram) | [ ] | |
| MCP-03 | Telegram model persistence | [ ] | Known issue |
| MCP-04 | Same user, different channels | [ ] | |

---

## 6. Response Quality

### 6.1 Accuracy Tests

| Prompt | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| 2+2 | 4 | | [ ] |
| Capital of France | Paris | | [ ] |
| Current year | 2026 | | [ ] |
| Days in Feb 2024 | 29 | | [ ] |

### 6.2 Response Time (record actual seconds)

| Query Type | Target | Actual | Pass/Fail |
|------------|--------|--------|-----------|
| Simple Q&A | < 5s | _____s | [ ] |
| Code generation | < 20s | _____s | [ ] |
| Web search | < 25s | _____s | [ ] |

### 6.3 Code Quality

| Prompt | Compiles? | Correct? | Pass/Fail |
|--------|-----------|----------|-----------|
| Reverse string (Python) | [ ] | [ ] | [ ] |
| Email regex | [ ] | [ ] | [ ] |
| SQL top 5 customers | [ ] | [ ] | [ ] |

---

## 7. Accessibility

| ID | Test | Status | Notes |
|----|------|--------|-------|
| A11Y-01 | Tab navigation complete | [ ] | |
| A11Y-02 | Focus indicators visible | [ ] | |
| A11Y-03 | Screen reader (basic nav) | [ ] | |
| A11Y-04 | 200% zoom functional | [ ] | |
| I18N-01 | Russian text renders | [ ] | |
| I18N-02 | Cyrillic input works | [ ] | |
| I18N-03 | Date/time in Moscow TZ | [ ] | |
| I18N-04 | Emoji rendering | [ ] | Known issue |

---

## 8. Known Issues Verification

| Issue | Status | Still Present? | Notes |
|-------|--------|----------------|-------|
| Emoji rendering broken | Open | [ ] Yes / [ ] No | |
| 5 models visible (should be 3) | Open | [ ] Yes / [ ] No | |
| Telegram model persistence | Open | [ ] Yes / [ ] No | |

---

## Summary

### Test Results

| Category | Total | Passed | Failed | Blocked | Pass Rate |
|----------|-------|--------|--------|---------|-----------|
| Smoke | 13 | | | | |
| CUJ | 22 | | | | |
| Edge Cases | 7 | | | | |
| Errors | 4 | | | | |
| Cross-Channel | 4 | | | | |
| Quality | 10 | | | | |
| Accessibility | 8 | | | | |
| **TOTAL** | **68** | | | | |

### Defects Found

| ID | Description | Severity | Status |
|----|-------------|----------|--------|
| D1 | | | |
| D2 | | | |
| D3 | | | |
| D4 | | | |
| D5 | | | |

### Go/No-Go Decision

- [ ] **GO**: All P0 pass, 90% P1 pass, defects documented
- [ ] **NO-GO**: Critical failures block release

**Signature**: ________________ **Date**: ________________

---

## Defect Report Template

```
Defect ID: D#
Title:
Severity: P0/P1/P2/P3
Channel: Web/Telegram/Both

Steps to Reproduce:
1.
2.
3.

Expected Result:

Actual Result:

Screenshots/Logs:

Environment:
- Browser:
- OS:
- Time:
```
