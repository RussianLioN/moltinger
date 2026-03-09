# Session Summary Command

Updates `SESSION_SUMMARY.md` with current session progress and reconciles the generated git-topology registry at session boundaries.

## Codex Note

- In Claude-style clients, examples below use `/session-summary`.
- In Codex CLI, invoke this workflow via the bridged skill `command-session-summary`.
- Do not assume `/session-summary` is registered as a native Codex slash command.

## Usage

```bash
/session-summary
```

## Workflow

1. **Reconcile topology state first**:
   - If `scripts/git-topology-registry.sh` exists, run:
     - `scripts/git-topology-registry.sh doctor --prune --write-doc`
   - If reconciliation changes `docs/GIT-TOPOLOGY-REGISTRY.md`, include that file in the session update.

2. **Analyze current session**:
   - Git commits since last update (`git log --oneline -10`)
   - Tasks completed/updated
   - Files modified
   - Beads issues status
   - GitHub Secrets status (`gh secret list`)
   - Registry status (`scripts/git-topology-registry.sh status`, when available)

3. **Update `SESSION_SUMMARY.md`**:
   - Current Status section (git commits)
   - Secrets Status table (update ✅/❌ flags)
   - Session History section (add new entry)
   - Next Steps section
   - Last updated timestamp
   - Quick Links section should include `docs/GIT-TOPOLOGY-REGISTRY.md` when present

4. **Commit changes**:
   - Auto-commit `SESSION_SUMMARY.md` updates
   - Include `docs/GIT-TOPOLOGY-REGISTRY.md` if it was regenerated during reconciliation

5. **Report**:
   - Summary of changes made
   - Link to updated file

## Required Sections in SESSION_SUMMARY.md

- Project Overview
- Current Status (progress, commits)
- **GitHub Secrets Status** (with ✅/❌ flags)
- Key Files
- Beads Issues
- Next Steps
- Key Decisions
- Session History
- Quick Links

## Secrets Tracking

When updating, check:
```bash
gh secret list
```

Update the Secrets Status table:
- ✅ EXISTS - secret is configured
- ❌ NEEDED - secret required but not set
- ❌ Optional - nice to have

## Automation

This command should be run:
- At the end of each significant session
- Before major context switches
- When completing phases
- Before creating PRs

When topology changed outside `/worktree`, this command is the preferred session-boundary reconciliation point.

## Example Output

```
📊 Session Summary Updated

Commits analyzed: 3
Tasks completed: 5
Files modified: 8
Secrets checked: 8 (2 needed)

Updated sections:
- Current Status
- Secrets Status
- Session History
- Next Steps

📄 File: SESSION_SUMMARY.md
🔗 Read at start of next session
```
