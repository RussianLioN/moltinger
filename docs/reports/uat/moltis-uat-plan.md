# Moltis AI Assistant - UAT Plan

**Product**: Moltis AI Assistant
**Version**: v1.5.0+
**Date**: 2026-02-17
**UAT Engineer**: AI UAT Team
**Status**: Draft

---

## 1. Executive Summary

This User Acceptance Testing (UAT) plan covers comprehensive testing scenarios for Moltis AI Assistant deployed at https://moltis.ainetic.tech with Telegram bot integration.

### 1.1 Product Overview

| Component | Description | URL/Channel |
|-----------|-------------|-------------|
| Web UI | Browser-based chat interface | https://moltis.ainetic.tech |
| Telegram Bot | Mobile/messaging integration | Configured bot via @BotFather |
| LLM Provider | GLM-5 via Z.ai Coding Plan | OpenAI-compatible API |
| Web Search | Tavily MCP server | 1,000 requests/month |
| Voice TTS | Piper (local, Russian) | ru_RU-irina-medium |
| Voice STT | Whisper (local, Russian) | large-v3 model |

### 1.2 Known Issues (Pre-UAT)

| Issue | Priority | Status | Impact |
|-------|----------|--------|--------|
| Emoji rendering broken | P3 | Open | Visual only |
| 5 models visible instead of 3 | P2 | Open | User confusion |
| Telegram: old model in persistence | P2 | Open | Wrong model used |

---

## 2. UAT Test Scenarios

### 2.1 Critical User Journeys (CUJ)

#### CUJ-01: First-Time Web User Onboarding

```
ID: CUJ-01
Priority: P0 - Blocker
Channel: Web UI
Persona: General User

Preconditions:
- Browser: Chrome/Firefox/Safari latest
- Network: Stable internet connection

Steps:
1. Navigate to https://moltis.ainetic.tech
2. Observe authentication prompt
3. Enter valid password
4. Observe chat interface
5. Verify model selector shows exactly 3 models:
   - glm-5
   - glm-4.7
   - glm-4.5-air
6. Send message: "Hello, introduce yourself"
7. Verify response received within 30 seconds
8. Verify response is in Russian (matching user profile)

Expected Results:
[A] Authentication required and works
[B] Chat interface loads without errors
[C] Exactly 3 models available (not 5)
[D] AI responds coherently in Russian
[E] Response time < 30 seconds

Acceptance Criteria:
- All [A-E] must PASS
- No JavaScript console errors
- No black screen on load
```

#### CUJ-02: Developer Code Assistance

```
ID: CUJ-02
Priority: P0 - Blocker
Channel: Web UI
Persona: Developer

Preconditions:
- Authenticated session
- Model: glm-5 selected

Steps:
1. Send request: "Write a Python function to merge two sorted arrays"
2. Verify code block in response
3. Verify syntax highlighting works
4. Send follow-up: "Add error handling"
5. Verify context maintained (previous code referenced)
6. Send: "Save this to /tmp/merge.py"
7. Verify file operation response

Expected Results:
[A] Code generated with proper formatting
[B] Syntax highlighting renders correctly
[C] Multi-turn context maintained
[D] File operations execute (if sandbox enabled)

Acceptance Criteria:
- All [A-D] must PASS
- Code is syntactically correct
- No hallucinated imports
```

#### CUJ-03: Content Creator Research Workflow

```
ID: CUJ-03
Priority: P1 - Critical
Channel: Web UI
Persona: Content Creator

Preconditions:
- Authenticated session
- Tavily MCP enabled

Steps:
1. Send request: "Search for latest AI trends in 2026"
2. Verify web search triggered (Tavily MCP)
3. Verify sources cited in response
4. Send: "Summarize findings in bullet points"
5. Verify formatted summary
6. Send: "Write a blog post outline based on this"
7. Verify structured outline generated

Expected Results:
[A] Web search executes via Tavily
[B] Results include source URLs
[C] Context carries between messages
[D] Content formatted appropriately

Acceptance Criteria:
- All [A-D] must PASS
- At least 3 sources cited
- Coherent summary generated
```

#### CUJ-04: Telegram Bot Basic Interaction

```
ID: CUJ-04
Priority: P0 - Blocker
Channel: Telegram
Persona: General User

Preconditions:
- User ID in allowed_users list
- Telegram bot token valid
- Bot started (/start command sent)

Steps:
1. Open Telegram bot chat
2. Send: "/start"
3. Verify welcome message received
4. Send: "/model"
5. Verify current model displayed
6. Send: "/model glm-4.7"
7. Verify model switched
8. Send: "Test message"
9. Verify response from new model

Expected Results:
[A] Bot responds to /start
[B] /model command shows current model
[C] Model switching works
[D] Subsequent messages use new model

Acceptance Criteria:
- All [A-D] must PASS
- Response time < 60 seconds
- No error messages
```

---

### 2.2 Edge Cases

#### EC-01: Network Interruption Recovery

```
ID: EC-01
Priority: P1
Channel: Web UI

Steps:
1. Start a conversation
2. Disconnect network mid-response
3. Wait 10 seconds
4. Reconnect network
5. Send new message

Expected Results:
[A] Graceful error message on disconnect
[B] Session recovers on reconnect
[C] Chat history preserved
[D] New message processed normally

Acceptance Criteria:
- No data loss
- No page reload required
```

#### EC-02: Long Message Handling

```
ID: EC-02
Priority: P2
Channel: Both

Steps:
1. Send message > 10,000 characters
2. Verify handling (truncate/split/error)
3. Send message with special characters: <script>alert(1)</script>
4. Verify XSS protection

Expected Results:
[A] Long message handled gracefully
[B] No system crash
[C] XSS injection prevented
[D] Appropriate error/success message

Acceptance Criteria:
- Security validated
- System stable
```

#### EC-03: Concurrent Sessions

```
ID: EC-03
Priority: P2
Channel: Web UI

Steps:
1. Open session in Chrome (Tab 1)
2. Open same account in Firefox (Tab 2)
3. Send different messages from each tab
4. Verify both responses
5. Verify session state consistency

Expected Results:
[A] Both sessions active
[B] Responses routed correctly
[C] No session collision
[D] Memory persists across sessions

Acceptance Criteria:
- No data corruption
- Both sessions functional
```

#### EC-04: Empty/Whitespace Messages

```
ID: EC-04
Priority: P3
Channel: Both

Steps:
1. Send empty message (just Enter)
2. Send whitespace-only message
3. Send message with only emojis: 🤖🎉

Expected Results:
[A] Empty message rejected with feedback
[B] Whitespace handled appropriately
[C] Emojis processed (if rendering fixed)

Acceptance Criteria:
- No API errors
- Clear user feedback
```

---

### 2.3 Error Scenarios

#### ERR-01: Invalid Authentication

```
ID: ERR-01
Priority: P0
Channel: Web UI

Steps:
1. Navigate to URL
2. Enter incorrect password 3 times
3. Wait for lockout period (if implemented)
4. Enter correct password

Expected Results:
[A] Clear error message on wrong password
[B] Rate limiting active (if implemented)
[C] Successful login after correct password
[D] No password exposure in logs/UI

Acceptance Criteria:
- Brute force protection
- No security bypass
```

#### ERR-02: LLM Provider Failure

```
ID: ERR-02
Priority: P0
Channel: Both

Steps:
1. Simulate GLM API timeout/failure
2. Send message
3. Verify fallback behavior

Expected Results:
[A] Error message shown to user
[B] Failover model used (if configured)
[C] No infinite loading
[D] User can retry

Acceptance Criteria:
- Graceful degradation
- User informed of issue
```

#### ERR-03: Telegram User Not Whitelisted

```
ID: ERR-03
Priority: P1
Channel: Telegram

Steps:
1. Send message from non-whitelisted Telegram ID
2. Verify rejection behavior

Expected Results:
[A] No response to unauthorized user
[B] Or clear "Access denied" message
[C] Admin notified (if configured)
[D] No security exposure

Acceptance Criteria:
- Access control enforced
- No information leakage
```

#### ERR-04: MCP Server Unavailable

```
ID: ERR-04
Priority: P2
Channel: Web UI

Steps:
1. Disable Tavily MCP server
2. Request web search
3. Verify error handling

Expected Results:
[A] Clear error about search unavailable
[B] Chat continues without search
[C] Graceful fallback
[D] User can continue conversation

Acceptance Criteria:
- Non-blocking error
- Clear communication
```

---

## 3. Multi-Channel Testing

### 3.1 Web UI vs Telegram Parity

| Feature | Web UI | Telegram | Parity Status |
|---------|--------|----------|---------------|
| Text chat | Yes | Yes | Full |
| Model selection | Dropdown | /model command | Functional |
| Web search | Yes | Yes (via MCP) | Full |
| File operations | Yes | Limited | Partial |
| Voice input | Yes (STT) | No | No |
| Voice output | Yes (TTS) | No | No |
| Image analysis | Yes | Yes | Full |
| Memory persistence | Yes | Yes | Full |
| Session history | Full | Limited | Partial |

### 3.2 Context Persistence Tests

```
ID: MCP-01
Priority: P1
Name: Cross-Session Memory

Steps:
1. Web UI: Tell AI your favorite color is blue
2. End session (close browser)
3. Reopen Web UI (new session)
4. Ask: "What's my favorite color?"
5. Verify AI remembers "blue"

Expected: Memory persists across sessions

---

ID: MCP-02
Priority: P1
Name: Cross-Channel Memory

Steps:
1. Web UI: Tell AI your project is "Project Alpha"
2. Switch to Telegram
3. Ask: "What project am I working on?"
4. Verify AI mentions "Project Alpha"

Expected: Memory shared across channels (if same user ID)

---

ID: MCP-03
Priority: P2
Name: Telegram Model Persistence

Steps:
1. Telegram: /model glm-4.7
2. Wait 5 minutes
3. Send new message
4. Verify glm-4.7 still active

Expected: Model selection persists
Note: Known issue - verify if fixed
```

### 3.3 Cross-Channel Consistency Matrix

| Test Case | Web Action | Telegram Check | Expected |
|-----------|------------|----------------|----------|
| User identity | Login | Send message | Same user context |
| Preferences | Set timezone | Query time | Consistent |
| Memory | Store fact | Retrieve fact | Same data |
| Active model | Select glm-5 | /model | Shows glm-5 |

---

## 4. AI Response Quality

### 4.1 Accuracy Validation

```
ID: QA-01
Priority: P0
Category: Factual Accuracy

Test Prompts:
1. "What is 2+2?" Expected: "4"
2. "Capital of France?" Expected: "Paris"
3. "Current year?" Expected: "2026"
4. "Days in February 2024?" Expected: "29" (leap year)

Acceptance Criteria:
- All factual answers correct
- No hallucinations on basic facts
```

```
ID: QA-02
Priority: P1
Category: Code Accuracy

Test Prompts:
1. "Write a function to reverse a string in Python"
2. "Create a SQL query to find top 5 customers by revenue"
3. "Write a regex to match email addresses"

Validation:
- Code executes without syntax errors
- Logic is correct
- Best practices followed
```

### 4.2 Response Time Benchmarks

| Query Type | Target | Acceptable | Unacceptable |
|------------|--------|------------|--------------|
| Simple Q&A | < 3s | < 5s | > 10s |
| Code generation | < 10s | < 20s | > 30s |
| Web search | < 15s | < 25s | > 45s |
| Long analysis | < 30s | < 60s | > 120s |

```
ID: QA-03
Priority: P1
Name: Response Time Benchmark

Steps:
1. Send 10 simple queries
2. Record response times
3. Calculate average, min, max
4. Compare against benchmarks

Acceptance Criteria:
- 90th percentile within "Acceptable"
- No response > 120 seconds
```

### 4.3 Error Handling Quality

```
ID: QA-04
Priority: P1
Category: Error Messages

Test Cases:
1. Request to summarize empty input
2. Request for real-time data (stock prices)
3. Request for private information
4. Malformed query

Expected Results:
- Clear, helpful error messages
- Guidance on how to correct
- No raw API errors exposed
- Polite tone maintained
```

---

## 5. Accessibility Testing

### 5.1 Web UI Accessibility (WCAG 2.1)

| Criterion | Level | Status | Notes |
|-----------|-------|--------|-------|
| Keyboard navigation | AA | To Test | Tab order, focus visible |
| Screen reader support | A | To Test | ARIA labels, semantic HTML |
| Color contrast | AA | To Test | 4.5:1 for text |
| Text scaling | AA | To Test | 200% zoom functional |
| Focus indicators | AA | To Test | Visible focus states |

```
ID: A11Y-01
Priority: P1
Name: Keyboard Navigation

Steps:
1. Navigate entire UI using only keyboard
2. Verify Tab order logical
3. Verify Enter/Space activate buttons
4. Verify Escape closes modals
5. Verify no keyboard traps

Acceptance Criteria:
- Full keyboard accessibility
- Logical tab order
- Visible focus indicators
```

```
ID: A11Y-02
Priority: P2
Name: Screen Reader Compatibility

Steps:
1. Enable VoiceOver (Mac) or NVDA (Windows)
2. Navigate chat interface
3. Verify messages announced properly
4. Verify input field labeled
5. Verify buttons have accessible names

Acceptance Criteria:
- All elements announced
- Meaningful sequence
- No redundant announcements
```

### 5.2 Telegram Accessibility Limitations

| Feature | Telegram Limitation | Mitigation |
|---------|---------------------|------------|
| Alt text for images | No native support | Caption text |
| Keyboard navigation | Platform-dependent | N/A |
| Screen reader | Platform-dependent | N/A |
| Text formatting | Limited markdown | Use sparingly |

### 5.3 Internationalization (Russian)

```
ID: I18N-01
Priority: P1
Name: Russian Language Support

Test Cases:
1. UI elements in Russian (if localized)
2. AI responses in Russian
3. Date/time formatting (Europe/Moscow)
4. Number formatting (Russian locale)
5. Input in Cyrillic characters

Expected Results:
- Russian text renders correctly
- No encoding issues
- Proper date format: DD.MM.YYYY
- Time in Moscow timezone

Known Issue: Emoji rendering broken
- Verify status during testing
- Document visual impact
```

---

## 6. User Feedback Collection

### 6.1 Current Feedback Mechanisms

| Channel | Method | Status |
|---------|--------|--------|
| Web UI | None | Not implemented |
| Telegram | None | Not implemented |
| Logs | Internal only | Active |

### 6.2 Recommended Feedback Features

```
Feature Request: Feedback Buttons

Implementation:
- Add thumbs up/down on each response
- Optional text feedback field
- Store in database for analysis
- Dashboard for admin review

Priority: P2
Effort: Medium
```

```
Feature Request: Rating System

Implementation:
- Post-conversation rating (1-5 stars)
- Categorized feedback (accuracy, speed, helpfulness)
- Trend analysis over time
- User satisfaction metrics

Priority: P3
Effort: Medium
```

### 6.3 Analytics Integration Recommendations

| Metric | Description | Collection Method |
|--------|-------------|-------------------|
| DAU/MAU | Daily/Monthly active users | Server logs |
| Session duration | Time per chat session | Timestamps |
| Message volume | Messages per user per day | Server logs |
| Error rate | Failed requests / total | Error logs |
| Response time | Average, P50, P95, P99 | Performance monitoring |
| Model usage | Which models used most | Feature flags |
| Feature adoption | Which features used | Event tracking |

---

## 7. UAT Process

### 7.1 Test Case Documentation Template

```markdown
## Test Case: [ID]

**Title**: [Descriptive name]
**Priority**: P0/P1/P2/P3
**Channel**: Web UI / Telegram / Both
**Persona**: Developer / Content Creator / General User

**Preconditions**:
- [ ] Condition 1
- [ ] Condition 2

**Test Data**:
- Input: [specific test data]
- Expected Output: [expected result]

**Steps**:
1. Step 1
2. Step 2
3. Step 3

**Expected Results**:
[A] Result A
[B] Result B
[C] Result C

**Actual Results**:
[A] PASS / FAIL - [notes]
[B] PASS / FAIL - [notes]
[C] PASS / FAIL - [notes]

**Status**: PASS / FAIL / BLOCKED / SKIP
**Defect ID**: [If applicable]
**Tester**: [Name]
**Date**: [YYYY-MM-DD]
```

### 7.2 Acceptance Criteria Summary

| Category | P0 Blockers | P1 Critical | P2 Major | P3 Minor |
|----------|-------------|-------------|----------|----------|
| Authentication | 100% pass | | | |
| Core Chat | 100% pass | | | |
| Telegram | 100% pass | | | |
| Web Search | | 90% pass | | |
| Voice | | | 80% pass | |
| Accessibility | | | 80% pass | |
| i18n | | 90% pass | | |

### 7.3 Sign-off Procedure

```
Phase 1: Internal Testing
- All P0 tests PASS
- 90%+ P1 tests PASS
- Document all defects

Phase 2: Bug Fixing
- Resolve all P0 defects
- Resolve 80%+ P1 defects
- Re-test affected areas

Phase 3: UAT Sign-off
- Regression testing complete
- Test report finalized
- Stakeholder approval
- Deployment authorization

Sign-off Checklist:
[ ] All P0 tests PASS
[ ] 90% P1 tests PASS (document exceptions)
[ ] 80% P2 tests PASS (document exceptions)
[ ] All known defects logged
[ ] Test report completed
[ ] Product Owner approval
[ ] Deployment readiness confirmed
```

### 7.4 Test Execution Schedule

| Day | Phase | Activities |
|-----|-------|------------|
| 1 | Smoke | P0 critical paths only |
| 2-3 | Functional | All test scenarios |
| 4 | Edge Cases | EC-01 through EC-04 |
| 5 | Cross-Channel | MCP-01 through MCP-03 |
| 6 | Quality | QA-01 through QA-04 |
| 7 | Accessibility | A11Y-01, A11Y-02, I18N-01 |
| 8 | Regression | Re-test failed cases |
| 9 | Sign-off | Final report, approval |

---

## 8. Defect Severity Guidelines

| Severity | Definition | Response Time | Blocks Release |
|----------|------------|---------------|----------------|
| P0 - Blocker | Core functionality broken | Immediate fix | YES |
| P1 - Critical | Major feature impaired | 24 hours | YES (if >10%) |
| P2 - Major | Feature degraded | 48 hours | NO |
| P3 - Minor | Cosmetic/UX issue | Next sprint | NO |
| P4 - Enhancement | Improvement suggestion | Backlog | NO |

---

## 9. Test Data

### 9.1 Sample Test Prompts

```
# Simple Q&A
"What is machine learning?"
"Explain REST APIs in simple terms"

# Code Generation
"Write a TypeScript interface for a User with id, name, email"
"Create a Python function to validate email addresses"

# Web Search
"What are the latest developments in quantum computing?"
"Find documentation for Docker Compose v3"

# Creative
"Write a haiku about programming"
"Create a product name for an AI assistant"

# Russian Language
"Расскажи о себе"
"Напиши функцию на Python для сортировки списка"

# Edge Cases
"Repeat the word 'test' 100 times"
"What's the weather? (no search available)"
```

### 9.2 Test User Accounts

| Persona | Purpose | Channel |
|---------|---------|---------|
| dev_test | Developer workflows | Web UI |
| content_test | Content creation | Web UI |
| telegram_test | Telegram integration | Telegram |
| edge_test | Edge case testing | Both |

---

## 10. Deliverables

1. **Test Execution Report** - Results of all test cases
2. **Defect Log** - All defects found with severity
3. **Metrics Report** - Response times, pass rates
4. **UAT Sign-off Document** - Formal approval
5. **Recommendations** - Improvements for future releases

---

## Appendix A: Quick Reference

### Model Configuration (moltis.toml)

```toml
[providers.openai]
enabled = true
api_key = "${GLM_API_KEY}"
model = "glm-5"
base_url = "https://api.z.ai/api/coding/paas/v4"
models = ["glm-5", "glm-4.7", "glm-4.5-air"]

[chat]
allowed_models = ["zai::glm-5", "zai::glm-4.7", "zai::glm-4.5-air"]
```

### Telegram Commands

| Command | Description |
|---------|-------------|
| /start | Initialize bot |
| /model | Show current model |
| /model [name] | Switch model |
| /help | Show help |

### Health Check Endpoints

| Endpoint | Purpose |
|----------|---------|
| /health | Container health |
| /metrics | Prometheus metrics |

---

## Appendix B: Contacts

| Role | Responsibility |
|------|----------------|
| Product Owner | Business requirements |
| Dev Lead | Technical implementation |
| QA Lead | Test coordination |
| DevOps | Infrastructure |

---

**Document Version**: 1.0
**Last Updated**: 2026-02-17
**Next Review**: After UAT completion
