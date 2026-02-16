# Session Summary Command

Updates SESSION_SUMMARY.md with current session progress.

## Usage

```bash
/session-summary
```

## Workflow

1. **Analyze current session**:
   - Git commits since last update
   - Tasks completed/updated
   - Files modified
   - Beads issues status

2. **Update SESSION_SUMMARY.md**:
   - Current Status section
   - Session History section
   - Next Steps section
   - Last updated timestamp

3. **Commit changes**:
   - Auto-commit SESSION_SUMMARY.md updates

4. **Report**:
   - Summary of changes made
   - Link to updated file

## Required Sections in SESSION_SUMMARY.md

- Project Overview
- Current Status (progress, commits)
- Key Files
- Beads Issues
- Next Steps
- Key Decisions
- Session History
- Quick Links

## Automation

This command should be run:
- At the end of each significant session
- Before major context switches
- When completing phases
- Before creating PRs

## Example Output

```
📊 Session Summary Updated

Commits analyzed: 3
Tasks completed: 5
Files modified: 8

Updated sections:
- Current Status
- Session History
- Next Steps

📄 File: SESSION_SUMMARY.md
🔗 Read at start of next session
```
