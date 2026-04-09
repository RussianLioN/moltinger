---
title: "Skill execution drifted into workaround behavior and task reports lacked a shared simple contract"
date: 2026-04-09
severity: P1
category: process
tags: [skills, worktree, reporting, operator-contract, rca, guardrails]
root_cause: "The repository had strong local rules for specific workflows, but no single project-level contract that forced abnormal helper behavior into RCA/root-fix mode and no shared simple-report contract for operator-facing task updates. As a result, the assistant could keep moving through workaround-style actions and verbose reports even after the workflow contract had already broken."
---

# RCA: Skill execution and reporting contract drift

Date: 2026-04-09
Context: repeated operator-facing failures during worktree, publish, and task-report flows

## Error

Recent sessions produced the same family of failures under different symptoms:

1. helper or workflow behavior became abnormal, but task execution still continued through manual compensating actions;
2. RCA was invoked too late, after extra operator-facing damage had already happened;
3. "простыми словами" task reports drifted into long technical status dumps instead of short operator summaries;
4. worktree/handoff boundaries were treated as advisory text instead of a fail-closed contract.

## Lessons Pre-check

Before writing this RCA, the lessons index and related RCA files were checked:

```bash
./scripts/query-lessons.sh --all | rg -n 'worktree|skill|report|operator|RCA|handoff|guard|workflow'
```

Relevant prior lessons:

1. [2026-03-09: Command-worktree follow-up UAT exposed preview, sync, and lock edge-case gaps](./2026-03-09-command-worktree-followup-uat.md)
2. [2026-03-28: Managed worktree creation mixed up the create executor and hook bootstrap-source contract](./2026-03-28-worktree-create-helper-and-hook-bootstrap-source-drift.md)
3. [2026-04-05: Telegram skill-detail remained non-terminal and repo skills lacked a shared Telegram-safe summary contract](./2026-04-05-telegram-skill-detail-general-hardening.md)

What those lessons already covered:

- worktree helpers must be fail-closed and explicit about their true boundary;
- user-facing skill behavior needs a shared contract, not just ad hoc per-skill fixes;
- workflow contract drift must be guarded by tests, not left to operator memory.

What they did **not** yet close:

1. a project-level rule that abnormal helper/skill behavior must switch execution into RCA/root-fix mode instead of workaround continuation;
2. a project-level rule that simple operator-facing task reports must use one short predictable format;
3. a static guard that keeps those two contracts present in source instructions and high-traffic workflow docs.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did operator-facing sessions still produce too many mistakes even after earlier hardening? | Because when a helper or workflow deviated from its expected contract, execution still continued instead of switching immediately into defect-fix mode. |
| 2 | Why was continuation possible? | Because the repository had workflow-specific hotfix guidance, but not one project-level rule that said abnormal skill/helper behavior itself is a blocking defect. |
| 3 | Why did user-facing reports still come out in the wrong shape? | Because the repository had generic communication guidance, but no shared simple-report contract for task summaries requested "простыми словами". |
| 4 | Why were these gaps not caught earlier? | Because there was no static guard checking for those contracts in source instructions and high-traffic command docs. |
| 5 | Why did this become a recurring process problem instead of a one-off slip? | Because skills and helper workflows were treated as helpful guidance rather than as testable operator contracts with explicit failure semantics. |

## Root Cause

Two connected process defects overlapped:

1. **Abnormal helper behavior was not elevated into a mandatory root-fix path at the project level.**  
   The repo had local lessons and some playbooks, but no single cross-cutting rule that said "if the helper is weird, stop and fix the helper contract first."

2. **Operator-facing task reporting lacked a shared simple contract.**  
   Without an explicit repo rule, summaries could drift back into changelog-style technical dumps even when the user asked for a short practical report.

## Fixes Applied

1. Added a project-level rule:
   - [docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md](/Users/rl/coding/moltinger/moltinger-main-moltinger-ik6d-skill-execution-rca-hardening/docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md)
   - narrowed the rule to repo-owned contract failures and documented how external/transient incidents are classified without inventing fake local root-fixes
2. Added a project-level operator report rule:
   - [docs/rules/operator-facing-task-report-contract.md](/Users/rl/coding/moltinger/moltinger-main-moltinger-ik6d-skill-execution-rca-hardening/docs/rules/operator-facing-task-report-contract.md)
3. Updated shared source instructions so both rules become part of generated [AGENTS.md](/Users/rl/coding/moltinger/moltinger-main-moltinger-ik6d-skill-execution-rca-hardening/AGENTS.md).
4. Updated [worktree.md](/Users/rl/coding/moltinger/moltinger-main-moltinger-ik6d-skill-execution-rca-hardening/.claude/commands/worktree.md) and [WORKTREE-HOTFIX-PLAYBOOK.md](/Users/rl/coding/moltinger/moltinger-main-moltinger-ik6d-skill-execution-rca-hardening/docs/WORKTREE-HOTFIX-PLAYBOOK.md) so abnormal helper behavior no longer silently funnels into manual workaround completion.
5. Added a static regression test to keep these contracts from drifting again.

## Prevention

1. Treat repo-managed skills and helper workflows as operator contracts, not prose guidance.
2. If a helper behaves abnormally, stop the parent task and repair the helper path first.
3. Keep repo-owned contract defects separate from external/transient incidents; only localize a fix when a repo-owned layer actually caused or failed to contain the problem.
4. Keep user-facing simple reports short and structurally predictable.
5. Guard project-level execution rules with static tests, not just tribal memory.

## Уроки

1. Локальные hotfix playbook’и не заменяют project-level stop rule для abnormal helper behavior.
2. Если у проекта нет одного явного simple-report contract, ответы постепенно возвращаются к verbose техническому стилю.
3. Навыки и workflow helper’ы нужно считать testable operator contract’ами, а не только документацией.
4. Правило без static guard слишком легко снова размывается в следующих сессиях.

---

*Создано по протоколу rca-5-whys*
