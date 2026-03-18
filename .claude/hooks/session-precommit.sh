#!/bin/bash
# PreCommit Hook: Incremental Session State Update
# Updates SESSION_SUMMARY.md with commit info before each commit
# GitOps-compliant: Only adds metadata, doesn't block commits

set -e

PROJECT_ROOT="/Users/rl/coding/moltinger/moltinger-main"
SESSION_FILE="$PROJECT_ROOT/SESSION_SUMMARY.md"

# Change to project root for git commands
cd "$PROJECT_ROOT"

# Skip if SESSION_SUMMARY.md doesn't exist
if [ ! -f "$SESSION_FILE" ]; then
    exit 0
fi

# Get commit message from file (if using -F)
COMMIT_MSG=""
if [ -f "$1" ]; then
    COMMIT_MSG=$(head -1 "$1" 2>/dev/null || echo "")
fi

# Get current state
CURRENT_BRANCH=$(git branch --show-current)
TIMESTAMP=$(date +%H:%M:%S)
DATE=$(date +%Y-%m-%d)

# Check if SESSION_SUMMARY.md is being committed
if git diff --cached --name-only | grep -q "SESSION_SUMMARY.md"; then
    # SESSION_SUMMARY.md is part of this commit, skip update to avoid loop
    exit 0
fi

# Create incremental update (append to Recent Changes section)
UPDATE_LINE="- \`$TIMESTAMP\` [$CURRENT_BRANCH] $(echo "$COMMIT_MSG" | head -c 50 || echo "commit")..."

# Check if today's section exists
if grep -q "### $DATE" "$SESSION_FILE"; then
    # Append to today's section
    # Note: This is a simple append - for complex updates use /session-summary
    :
else
    # Create today's section (optional - can be done by /session-summary)
    :
fi

# Log for debugging (doesn't modify file to avoid pre-commit loop)
echo "📝 PreCommit: $UPDATE_LINE" >> "$PROJECT_ROOT/.tmp/sessions/precommit.log"

exit 0
