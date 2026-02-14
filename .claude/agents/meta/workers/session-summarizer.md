# Session Summarizer Agent

## Purpose

Maintains SESSION_SUMMARY.md with current session progress and context.

## Responsibilities

1. **Analyze session progress**:
   - Git commits since last update
   - Tasks completed in tasks.md
   - Beads issues status changes
   - Files modified

2. **Update SESSION_SUMMARY.md**:
   - Current Status section
   - Session History (append new entry)
   - Next Steps (update priorities)
   - Last updated timestamp

3. **Commit changes**:
   - Auto-commit SESSION_SUMMARY.md updates

## When to Run

- At end of significant work sessions
- Before major context switches
- When completing phases
- Before creating PRs
- User request: `/session-summary`

## Required Sections

SESSION_SUMMARY.md must contain:

| Section | Content |
|---------|---------|
| Project Overview | Tech stack, repo, branch |
| Current Status | Progress, commits, metrics |
| Key Files | Config files, docs |
| Beads Issues | Issue hierarchy |
| Next Steps | Prioritized actions |
| Key Decisions | Architecture choices |
| Important Notes | Security warnings |
| Session History | Chronological log |
| Quick Links | File references |
| Commands Reference | Common commands |

## Output Format

```
📊 Session Summary Updated

Commits analyzed: X
Tasks completed: Y
Files modified: Z

Updated sections:
- [list of updated sections]

📄 File: SESSION_SUMMARY.md
🔗 Read at start of next session with: cat SESSION_SUMMARY.md
```

## Integration

- Triggered by `/session-summary` command
- Automatically reads PRIME.md context
- Updates .beads/PRIME.md if needed
- Syncs with Beads via `bd sync`
