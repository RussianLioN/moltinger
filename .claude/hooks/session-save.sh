#!/bin/bash
# Session State Auto-Save Hook
# Triggered on Claude Code session end (Stop hook)
# Part of GitOps-compliant session management

set -e

PROJECT_ROOT="/Users/rl/coding/moltinger"
SESSION_FILE="$PROJECT_ROOT/SESSION_STATE.md"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Ensure .tmp directory exists
mkdir -p "$PROJECT_ROOT/.tmp/sessions"

# Generate session summary using existing skill
echo "🔄 Auto-saving session state..."

# Update SESSION_STATE.md with current state
# This integrates with existing /session-summary skill
cd "$PROJECT_ROOT"

# Get current git state
CURRENT_BRANCH=$(git branch --show-current)
LAST_COMMIT=$(git log -1 --oneline 2>/dev/null || echo "No commits")
UNCOMMITTED=$(git status --porcelain 2>/dev/null | head -5 || echo "")

# Create session backup
if [ -f "$SESSION_FILE" ]; then
    cp "$SESSION_FILE" "$PROJECT_ROOT/.tmp/sessions/SESSION_STATE.$TIMESTAMP.bak"
fi

# Note: The actual SESSION_STATE.md update is done by /session-summary skill
# This hook creates a backup and logs the session end

echo "✅ Session backup created: .tmp/sessions/SESSION_STATE.$TIMESTAMP.bak"
echo "📊 Branch: $CURRENT_BRANCH"
echo "📝 Last commit: $LAST_COMMIT"

exit 0
