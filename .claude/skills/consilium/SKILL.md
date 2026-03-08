---
description: Multi-expert consilium analysis with graceful degradation across environments (parallel if possible, reliable single-agent otherwise).
argument-hint: "[question]"
---

# Consilium Skill

Run a structured multi-expert analysis and always return a full `Consilium Report`, even when parallel sub-agents are unavailable.

## Execution Modes

1. **Mode A: Parallel Sub-Agents**
   - Use when `Task`/sub-agent tooling is available.
   - Launch expert roles in parallel and aggregate results.

2. **Mode B: Tool-Parallel Evidence + Expert Matrix**
   - Use when sub-agents are unavailable but parallel tool calls are available.
   - Collect evidence in parallel (git, configs, logs), then evaluate via expert roles.

3. **Mode C: Autonomous Expert Matrix**
   - Use when neither Mode A nor Mode B is available.
   - Run an explicit multi-role reasoning pass in one agent.
   - Do not label output as "fallback"; present a normal Consilium report with declared execution mode.

## Required Behavior

1. Parse the question and restate the target decision.
2. Gather concrete evidence first:
   - If repository is available: inspect git history, recent diffs, relevant config/code paths.
   - If runtime/server context is available: inspect service state and logs.
   - If context is missing: state assumptions explicitly.
3. Evaluate findings through expert lenses (minimum 7 roles):
   - Architect, SRE, DevOps, Security, QA, Domain Specialist, Delivery/GitOps.
4. Identify root cause candidates and rank by likelihood.
5. Propose at least 5 elegant solutions with trade-offs.
6. Recommend one primary plan with rollback strategy.

## Quality Rules

1. Prioritize evidence over speculation.
2. If uncertain, mark uncertainty and show what would validate it.
3. Keep recommendations executable (owner, action, expected signal).
4. For incident/debug tasks, include short verification checklist.

## Output Format

```markdown
# Consilium Report

## Question
[Restated question]

## Execution Mode
Mode A / Mode B / Mode C

## Evidence
- [Fact 1 with source/path/command]
- [Fact 2]
- [Fact 3]

## Expert Opinions
### Architect
- Opinion: ...
- Key points: ...

### SRE
- Opinion: ...
- Key points: ...

### DevOps
- Opinion: ...
- Key points: ...

### Security
- Opinion: ...
- Key points: ...

### QA
- Opinion: ...
- Key points: ...

### [Additional roles...]
- Opinion: ...
- Key points: ...

## Root Cause Analysis
- Primary root cause: ...
- Contributing factors: ...
- Confidence: High / Medium / Low

## Solution Options (>=5)
1. [Option] — Pros / Cons / Risk / Effort
2. [Option] — Pros / Cons / Risk / Effort
3. [Option] — Pros / Cons / Risk / Effort
4. [Option] — Pros / Cons / Risk / Effort
5. [Option] — Pros / Cons / Risk / Effort

## Recommended Plan
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Rollback Plan
- [How to revert safely]

## Verification Checklist
- [ ] [Check 1]
- [ ] [Check 2]
- [ ] [Check 3]
```
