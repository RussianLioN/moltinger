#!/bin/bash
# Session State → GitHub Issues Mirror
# GitOps-compliant: Issues are READ-ONLY mirror, git is source of truth
# Run manually or via /session-summary skill

set -e

PROJECT_ROOT="/Users/rl/coding/moltinger"
SESSION_FILE="$PROJECT_ROOT/SESSION_STATE.md"
REPO="RussianLioN/moltinger"

# Check if gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "⚠️  gh CLI not authenticated. Skipping Issues mirror."
    exit 0
fi

# Check if SESSION_STATE.md exists
if [ ! -f "$SESSION_FILE" ]; then
    echo "⚠️  SESSION_STATE.md not found. Skipping Issues mirror."
    exit 0
fi

# Get current date for issue title
TODAY=$(date +%Y-%m-%d)
SESSION_TITLE="Session Log: $TODAY"

# Check if issue already exists for today
EXISTING_ISSUE=$(gh issue list --repo "$REPO" \
    --label "llm-session" \
    --state open \
    --search "$TODAY" \
    --json number,title \
    --jq '.[0].number // empty')

# Prepare issue body with header
ISSUE_BODY=$(cat <<EOF
> 🔄 **Auto-mirror from SESSION_STATE.md** | $(date +%H:%M:%S)
>
> **GitOps Note**: This is a read-only mirror. Git = Single Source of Truth.
> Edit SESSION_STATE.md to update, then run \`/session-summary\`.

---

$(cat "$SESSION_FILE")
EOF
)

if [ -n "$EXISTING_ISSUE" ]; then
    # Update existing issue
    gh issue edit "$EXISTING_ISSUE" --repo "$REPO" --body "$ISSUE_BODY"
    echo "✅ Updated Issue #$EXISTING_ISSUE"
else
    # Create new issue
    NEW_ISSUE=$(gh issue create --repo "$REPO" \
        --title "$SESSION_TITLE" \
        --body "$ISSUE_BODY" \
        --label "llm-session,auto-generated")
    echo "✅ Created Issue: $NEW_ISSUE"
fi
