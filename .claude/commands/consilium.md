---
description: Launch Consilium panel in Codex with strict expert coverage and isolated execution when available.
argument-hint: "[question]"
---

# Consilium Command

Run an expert panel for a question:

```text
/consilium [question]
```

## Runtime Selection

1. Mode A: Codex CLI Experimental Multi-Agent
   - Preconditions: `/experimental` and `/agent` available, `features.multi_agent=true`.
   - Execute experts in isolated agent threads.
2. Mode B: Codex App Parallel Threads + Worktrees
   - Use separate app threads and dedicated worktrees per expert.
3. Mode C: Single-Session Matrix
   - Only when A and B are unavailable.
   - Produce explicit 19-role matrix in one response.

## Required Experts

Architect, Docker, Bash, DevOps, CI/CD, GitOps, IaC, Backup, SRE, Claude/Codex tooling, Prompt, TDD, UAT, Traefik, TOML, GLM, Prometheus, Security, MCP.

If fewer experts run, add a `Missing Experts` section with reasons.

## Output

1. Execution mode used (A/B/C)
2. Evidence summary
3. Individual expert opinions
4. Consensus and disagreements
5. Root cause candidates (if troubleshooting)
6. At least 5 solution options with trade-offs
7. Final recommendation, rollback, and verification checklist
