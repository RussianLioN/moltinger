---
description: Consilium panel with strict 19-role coverage and Codex-native execution modes (CLI multi-agent, App worktree threads, or single-session matrix).
argument-hint: "[question]"
---

# Consilium Skill (Codex-Native)

Run a deterministic expert panel for architecture and operations decisions.
Goal: keep 19 roles, isolate context when platform allows, and always return a complete report.

## Required Expert Roster (19)

1. Architect (Lead)
2. Docker Expert
3. Bash Master
4. DevOps Engineer
5. CI/CD Architect
6. GitOps Guardian
7. IaC Expert
8. Backup Specialist
9. SRE Engineer
10. Claude/Codex Tooling Expert
11. Prompt Engineer
12. TDD Expert
13. UAT Engineer
14. Traefik Expert
15. TOML Specialist
16. GLM Expert
17. Prometheus Expert
18. Security Expert
19. MCP Specialist

Do not reduce the roster unless user explicitly scopes fewer experts.

## Execution Modes

### Mode A (Preferred): CLI Experimental Multi-Agent

Use when Codex CLI supports `/experimental` and `/agent` and `features.multi_agent=true`.

- Spawn one isolated agent thread per expert role.
- Keep each thread on a dedicated worktree branch if code changes are needed.
- Ensure every expert receives the same question plus evidence pack.
- Wait for all expert threads or timeout, then mark missing experts explicitly.

### Mode B: Codex App Parallel Threads + Worktrees

Use when running in Codex App where CLI multi-agent visibility is unavailable.

- Create one thread per expert (or a scoped subset agreed by user).
- Bind each thread to a dedicated worktree.
- Aggregate outputs in lead thread (Architect).
- Report any experts that were skipped or timed out.

### Mode C: Single-Session Expert Matrix

Use only when Mode A and Mode B are impossible.

- Run 19 explicit role sections in one response.
- Label as `Execution Mode: Mode C`.
- Do not claim isolated execution in this mode.

## Mandatory Flow

1. Restate the question and decision target.
2. Gather evidence before opinions (code/config/log/commands).
3. Execute one of the modes above.
4. Produce one opinion block per required expert.
5. Build consensus: agreements, disagreements, conflict resolution.
6. Rank root-cause candidates by likelihood (when troubleshooting).
7. Provide at least 5 solution options with trade-offs.
8. Recommend one primary plan plus rollback and verification checks.

## Quality Gates

- If fewer than 19 experts replied, include `Missing Experts`.
- Opinions must be evidence-linked, not generic.
- Keep recommendations executable with owner/action/signal.
- Confidence must match evidence quality.

## Output Format

```markdown
# Consilium Report

## Question
[Restated question]

## Execution Mode
Mode A / Mode B / Mode C

## Evidence
- [Fact plus source/path/command]

## Expert Opinions
### 1) Architect (Lead)
- Key points:
- Opinion:
- Confidence:

### 2) Docker Expert
...

### 19) MCP Specialist
...

## Missing Experts (if any)
- [Expert] - [reason]

## Consensus
- Agreements:
- Disagreements:
- Resolution:

## Root Cause Candidates (if applicable)
1. [Cause] - Likelihood
2. [Cause] - Likelihood
3. [Cause] - Likelihood

## Solution Options (>=5)
1. [Option] - Pros / Cons / Risk / Effort
2. [Option] - Pros / Cons / Risk / Effort
3. [Option] - Pros / Cons / Risk / Effort
4. [Option] - Pros / Cons / Risk / Effort
5. [Option] - Pros / Cons / Risk / Effort

## Recommended Plan
1. [Step]
2. [Step]
3. [Step]

## Rollback
- [How to revert safely]

## Verification Checklist
- [ ] [Check]
- [ ] [Check]
- [ ] [Check]
```
