#!/bin/bash
# WorktreeCreate Hook - Automatic file synchronization
# Called when Claude Code creates a new worktree for agent isolation
#
# Arguments:
#   $1 - Source worktree path (original project)
#   $2 - New worktree path (isolated environment)
#
# Reads configuration from: .worktree-sync.json

set -e

SOURCE_WORKTREE="$1"
NEW_WORKTREE="$2"

echo "🔧 WorktreeCreate Hook: Setting up isolated worktree..."
echo "   Source: $SOURCE_WORKTREE"
echo "   Target: $NEW_WORKTREE"

# Check if sync config exists
SYNC_CONFIG="$SOURCE_WORKTREE/.worktree-sync.json"
if [ ! -f "$SYNC_CONFIG" ]; then
    echo "   ⚠️  No .worktree-sync.json found, skipping sync"
    exit 0
fi

# Parse and sync files
cd "$SOURCE_WORKTREE"

# Sync individual files
FILES=$(cat "$SYNC_CONFIG" | grep -A 100 '"files"' | grep -B 100 ']' | grep '"' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || true)
for FILE in $FILES; do
    if [ -f "$FILE" ]; then
        TARGET_DIR=$(dirname "$NEW_WORKTREE/$FILE")
        mkdir -p "$TARGET_DIR"
        cp "$FILE" "$NEW_WORKTREE/$FILE"
        echo "   ✅ Synced file: $FILE"
    else
        echo "   ⚠️  File not found: $FILE"
    fi
done

# Sync directories
DIRS=$(cat "$SYNC_CONFIG" | grep -A 100 '"directories"' | grep -B 100 ']' | grep '"' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || true)
for DIR in $DIRS; do
    if [ -d "$DIR" ]; then
        mkdir -p "$NEW_WORKTREE/$DIR"
        # Use rsync if available, otherwise cp
        if command -v rsync &> /dev/null; then
            rsync -a --exclude='.git' "$DIR/" "$NEW_WORKTREE/$DIR/"
        else
            cp -r "$DIR/"* "$NEW_WORKTREE/$DIR/" 2>/dev/null || true
        fi
        echo "   ✅ Synced directory: $DIR"
    else
        echo "   ⚠️  Directory not found: $DIR"
    fi
done

# Sync patterns (glob patterns)
PATTERNS=$(cat "$SYNC_CONFIG" | grep -A 100 '"patterns"' | grep -B 100 ']' | grep '"' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || true)
for PATTERN in $PATTERNS; do
    # Expand glob pattern
    for MATCH in $PATTERN; do
        if [ -f "$MATCH" ]; then
            TARGET_DIR=$(dirname "$NEW_WORKTREE/$MATCH")
            mkdir -p "$TARGET_DIR"
            cp "$MATCH" "$NEW_WORKTREE/$MATCH"
            echo "   ✅ Synced pattern match: $MATCH"
        fi
    done
done

echo "✅ WorktreeCreate Hook: Setup complete"
exit 0
