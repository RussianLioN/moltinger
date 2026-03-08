#!/bin/bash
# Setup Git Hooks for Session Management
# Run once after cloning repo or when hooks are updated

set -e

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')"
HOOKS_DIR="$PROJECT_ROOT/.githooks"

echo "🔧 Setting up git hooks..."

# Create .githooks directory
mkdir -p "$HOOKS_DIR"

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit: Session state incremental update
# GitOps-compliant: Non-blocking, adds metadata only

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
GUARD_SCRIPT="$PROJECT_ROOT/scripts/git-session-guard.sh"
SESSION_FILE="$PROJECT_ROOT/SESSION_SUMMARY.md"
LOG_FILE="$PROJECT_ROOT/.tmp/sessions/precommit.log"

# Enforce branch/worktree session consistency before commit.
if [[ -x "$GUARD_SCRIPT" ]]; then
    if ! "$GUARD_SCRIPT" --check --hook pre-commit; then
        exit 1
    fi
fi

# Create log directory if needed
mkdir -p "$(dirname "$LOG_FILE")"

# Get commit info
BRANCH=$(git branch --show-current)
TIMESTAMP=$(date +%H:%M:%S)
DATE=$(date +%Y-%m-%d)

# Get commit message from COMMIT_EDITMSG
COMMIT_MSG=$(head -1 "$PROJECT_ROOT/.git/COMMIT_EDITMSG" 2>/dev/null || echo "commit")
COMMIT_SHORT=$(echo "$COMMIT_MSG" | head -c 60)

# Skip if SESSION_SUMMARY.md is in this commit (avoid loop)
if git diff --cached --name-only | grep -q "SESSION_SUMMARY.md"; then
    echo "📝 SESSION_SUMMARY.md in commit, skipping pre-commit update"
    exit 0
fi

# Log the commit (for /session-summary to process later)
echo "- [$DATE $TIMESTAMP] [$BRANCH] $COMMIT_SHORT" >> "$LOG_FILE"

echo "📝 Pre-commit logged: $COMMIT_SHORT"
exit 0
EOF

chmod +x "$HOOKS_DIR/pre-commit"

# Create pre-push hook
cat > "$HOOKS_DIR/pre-push" << 'EOF'
#!/bin/bash
# Pre-push: Block push when branch/worktree session guard detects drift.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
GUARD_SCRIPT="$PROJECT_ROOT/scripts/git-session-guard.sh"

if [[ -x "$GUARD_SCRIPT" ]]; then
  "$GUARD_SCRIPT" --check --hook pre-push
fi

exit 0
EOF

chmod +x "$HOOKS_DIR/pre-push"

# Configure git to use .githooks
git config core.hooksPath "$HOOKS_DIR"

echo "✅ Git hooks configured:"
echo "   - pre-commit: Session logging + session guard"
echo "   - pre-push: Session guard"
echo ""
echo "📁 Hooks location: $HOOKS_DIR"
echo "⚙️  Git core.hooksPath: $(git config core.hooksPath)"
