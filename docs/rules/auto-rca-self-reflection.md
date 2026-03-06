# Rule: Auto-RCA and Self-Reflection for LLM Mistakes

## Purpose

Guarantee that RCA starts automatically when the agent (LLM) makes mistakes, and that self-reflection is explicitly documented before continuing execution.

## Mandatory Triggers

Auto-RCA is mandatory on any of these events:

1. Any command/tool error (`exit code != 0`)
2. User indicates misunderstanding or wrong action (for example: "ты не понял", "это не то", "ошибка")
3. Agent detects context drift (wrong branch/worktree, unexpected repo state)
4. Invalid assumption discovered after execution

## Auto-RCA Protocol (must run immediately)

1. **STOP**
   - Pause implementation and do not continue normal execution.
2. **ACKNOWLEDGE**
   - Explicitly state which trigger fired.
3. **5 Whys (short)**
   - Provide five consecutive "почему" levels.
4. **Root Cause + Corrective Action**
   - Name root cause.
   - Name immediate fix and preventive fix.
5. **Artifact**
   - Create/update RCA report in `docs/rca/YYYY-MM-DD-<topic>.md`.
6. **Lessons Index**
   - Run:
     - `./scripts/build-lessons-index.sh`
     - `./scripts/query-lessons.sh --all`
7. **Instruction Update**
   - Update one of:
     - `AGENTS.md`
     - `CLAUDE.md`
     - `docs/rules/*.md`
8. **Resume**
   - Continue task only after steps above are completed.

## Economy L1/L2 Mode

To avoid token overuse, use two levels:

1. **L1 (default, economical)**
   - Immediate self-reflection block (`AUTO-RCA TRIGGERED`)
   - No heavy documentation/index rebuild
2. **L2 (escalation)**
   - Full RCA report in `docs/rca/`
   - Lessons index update

L2 should be triggered on:
- severity `P0`/`P1`
- repeated error signature
- explicit user request for full RCA

Wrapper reference:
`scripts/auto-rca-wrapper.sh`

## Required Response Format During Auto-RCA

Use this block when trigger occurs:

```text
AUTO-RCA TRIGGERED
Trigger: <what fired>
Symptom: <what failed>
Q1 Why: ...
Q2 Why: ...
Q3 Why: ...
Q4 Why: ...
Q5 Why: ...
Root cause: ...
Immediate fix: ...
Preventive fix: ...
RCA artifact: docs/rca/YYYY-MM-DD-<topic>.md
```

## Definition of Done

Auto-RCA for a mistake is complete only when:

- RCA artifact exists in `docs/rca/`
- Lessons index updated
- Instruction/rule update committed
- Task execution resumed after RCA
