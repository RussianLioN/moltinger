# Session Summary Command

Updates a host-project session summary and reconciles topology state at session boundaries.

## Invocation Notes

- Claude-style clients may expose this as `/session-summary`.
- Codex-style clients may expose it through a bridge such as `command-session-summary`.
- The host project decides the final invocation surface.

## Workflow

1. If `scripts/git-topology-registry.sh` exists, run `scripts/git-topology-registry.sh doctor --prune --write-doc`.
2. Review current progress:
   - recent commits
   - tasks completed or updated
   - modified files
   - optional issue-tracker status
   - topology status
3. Update the host summary file if the project uses one.
4. If topology docs changed, include them in the summary update.
5. Report what changed and what remains next.

## Boundary Rules

- Do not assume the host project has GitHub secrets tracking.
- Do not assume the host project uses Beads.
- Keep this command focused on session handoff and topology reconciliation.
