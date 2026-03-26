# Post-Close Task Classification And Worktree Escalation

Last reviewed: 2026-03-26

## Purpose

This rule answers one specific question:

When a branch/worktree has already completed its planned tasks and the user brings a new task, should the work continue in the current lane or move into a new one?

Use this rule before starting implementation, not after changes already spilled into the wrong lane.

## Default

Use this default unless a more specific rule overrides it:

`same root cause + same slice + same owning lane + no scope expansion => continue`

Anything else should be treated as a new lane.

Definition:

`same owning lane` means the same active branch/PR/worktree still owns the acceptance boundary and is not yet logically closed.

## Outcomes

The classifier must produce exactly one of these outcomes:

1. `continue-current-lane`
2. `reuse-existing-worktree`
3. `new-branch-new-worktree-from-main`
4. `consilium-required`

## Decision Order

Apply the questions in this order.

### 1. Is this still the same slice?

Treat it as the same slice only if all of these stay true:

- the new request is a direct follow-up to the same incident, feature, or bug family;
- the same acceptance boundary still applies;
- no new subsystem or delivery boundary is introduced;
- the expected change stays narrow.

If any of these are false, stop and choose `new-branch-new-worktree-from-main`.

### 2. Has the task moved into a shared or governance-sensitive surface?

Treat these as shared or governance-sensitive by default:

- `AGENTS.md` and generated instruction sources
- `docs/rules/`
- `skills/`
- auth, secrets, deploy, CI, runtime, topology, Beads ownership, or shared config
- anything already merged into `main` that now needs follow-up

If yes, choose `new-branch-new-worktree-from-main`.

Exception:

If the current slice is still active, not yet merged, and already owns these files, a narrow review-fix or bounded follow-up may remain in the current lane. Do not open a new lane for routine review fixes inside the same active PR just because the touched files live in a shared surface.

### 3. Is the current lane already logically closed?

Treat the current lane as logically closed if any of these are true:

- all planned tasks in the slice are done;
- the branch exists mainly as historical closure or incident record;
- the relevant PRs are already merged;
- the user is now asking for generalized policy, architecture, or follow-up capability work.

If yes, choose `new-branch-new-worktree-from-main`.

### 4. Do we only need to return to the existing authoritative worktree, not create a new lane?

Choose `reuse-existing-worktree` only if all of these are true:

- the root cause and slice are still the same;
- the same active branch still owns the work;
- the branch already has an authoritative worktree that should be reused instead of duplicated;
- a new branch would not improve review or rollback boundaries;
- the main reason is clean local state, returning to the right lane, parallel verification, or context reset;
- the expected changes remain bounded and non-substantial.

If not, do not use this outcome.

### 5. Is the case ambiguous or high-risk?

Choose `consilium-required` if:

- the criteria point in different directions;
- the work touches shared contracts and incident response at the same time;
- the expected blast radius is unclear;
- the operator is about to override the default for cost or convenience reasons.

## Operational Meaning Of Each Outcome

### `continue-current-lane`

Use only for a tight repair pass.

Allowed profile:

- one narrow hypothesis;
- one compact patch series;
- same subsystem;
- quick revalidation.

Stop and reclassify immediately if the change starts to spread.

### `reuse-existing-worktree`

Use when the branch intent is still correct and the right answer is to return to the branch's existing authoritative worktree.

Typical reasons:

- current session is not in the branch's authoritative worktree;
- the authoritative worktree is cleaner than the current local state;
- you need a bounded verification pass without changing branch ownership.

This is a lane-reuse outcome, not permission to create another substantial checkout on the same branch.

### `new-branch-new-worktree-from-main`

This is the default for:

- post-merge follow-up work;
- new governance and process capabilities;
- rules/skills/agent-routing changes;
- cross-cutting fixes;
- new incidents relative to `main`;
- anything that deserves its own PR, rollback boundary, or review story.

### `consilium-required`

Use the `consilium` skill/workflow when cost pressure tempts the operator to stay in the current lane even though the scope is drifting.

The goal is not bureaucracy. The goal is to prevent hidden scope creep.

## Classifier Output Contract

When this rule is used manually or via a skill, return:

1. `Verdict`
2. `Why`
3. `Matched criteria`
4. `Recommended lane`
5. `Prepared prompt`
6. `Need consilium`

`Prepared prompt` must be:

- `n/a` for `continue-current-lane`
- a short lane-reuse handoff for `reuse-existing-worktree`
- the full prompt template below for `new-branch-new-worktree-from-main`
- `defer until consilium verdict` for `consilium-required`

## Prepared Prompt Template

Use this template when the outcome is `new-branch-new-worktree-from-main`:

```text
Работай только в этом worktree на ветке <branch>.

Задача: <one-sentence objective>.

Перед изменениями прочитай:
- AGENTS.md
- MEMORY.md
- SESSION_SUMMARY.md
- ближайшие локальные AGENTS.md
- <extra docs/rules specific to the task>

Контекст:
- исходный lane: <old branch/worktree>
- почему новый lane нужен: <root cause / shared-contract / scope reason>
- что не нужно тащить из старого lane: <out-of-scope items>

Что нужно сделать:
1. <step 1>
2. <step 2>
3. <step 3>

Проверки:
- <check 1>
- <check 2>
- <check 3>

Если по ходу появляются спорные решения, используй `consilium` skill/workflow и исполни его консолидированное решение.
```

## Lane-Reuse Handoff Template

Use this template when the outcome is `reuse-existing-worktree`:

```text
Продолжай в существующем authoritative worktree:
- branch: <branch>
- worktree: <path>
- why reuse: <same-slice bounded continuation reason>
- next action: вернуться в этот worktree и выполнить узкий follow-up без расширения scope
```

## Examples

### Example 1: Tight follow-up in the same bug family

- Situation: a typo-level fix or missing edge-case test immediately after the original patch.
- Verdict: `continue-current-lane`
- Why: same root cause, same slice, no new subsystem, no new review boundary needed.

### Example 2: Same branch, but clean local state needed

- Situation: the same branch still owns the incident, but you need a clean verification worktree.
- Verdict: `reuse-existing-worktree`
- Why: the intent did not change; the right move is to return to the branch's existing authoritative worktree.

### Example 3: Post-merge regression in shared runtime behavior

- Situation: the original branch is already merged, and a new runtime defect appears relative to `main`.
- Verdict: `new-branch-new-worktree-from-main`
- Why: this is now a new follow-up slice with its own rollback/review boundary.

### Example 4: New policy for future AI coding sessions

- Situation: the old incident branch is done, and now the user wants a reusable classifier rule plus a new skill.
- Verdict: `new-branch-new-worktree-from-main`
- Why: this touches shared rules, generated instructions, and `skills/`.

### Example 5: Auth or deploy follow-up after a completed slice

- Situation: a new request touches auth, deploy, CI, runtime, or secrets after the feature is already closed.
- Verdict: `new-branch-new-worktree-from-main`
- Why: shared-contract changes do not belong in a logically closed feature lane.

### Example 6: Unclear scope with conflicting signals

- Situation: the new request sounds related, but it may also require architecture, workflow, and runtime changes.
- Verdict: `consilium-required`
- Why: the operator should not guess through a governance-sensitive boundary.

### Example 7: Review fix inside the same active PR

- Situation: an active unmerged PR that already owns `docs/rules/` or `skills/` needs one narrow wording fix from review.
- Verdict: `continue-current-lane`
- Why: the slice is still active, the owning lane has not changed, and this is not a new governance story.

## Why This Rule Exists

This rule follows the same pattern recommended by current AI coding guidance:

- keep durable project rules in version-controlled docs rather than bloating one central file;
- isolate parallel implementation work with git worktrees;
- reset or isolate context when the task changes enough that stale context becomes a risk;
- keep skill prompts thin and let docs carry the durable policy.

Primary sources:

- Anthropic Claude Code memory and project rules: https://code.claude.com/docs/en/memory
- Anthropic Claude Code worktree workflows: https://code.claude.com/docs/en/common-workflows
- Anthropic Claude Code best practices for context management: https://code.claude.com/docs/en/best-practices
- Git official `git worktree` documentation: https://git-scm.com/docs/git-worktree.html
- OpenAI Codex skills guidance: https://developers.openai.com/codex/skills
