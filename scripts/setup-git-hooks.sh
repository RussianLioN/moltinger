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
SESSION_FILE="$PROJECT_ROOT/SESSION_STATE.md"
LOG_FILE="$PROJECT_ROOT/.tmp/sessions/precommit.log"

# Create log directory if needed
mkdir -p "$(dirname "$LOG_FILE")"

# Get commit info
BRANCH=$(git branch --show-current)
TIMESTAMP=$(date +%H:%M:%S)
DATE=$(date +%Y-%m-%d)

# Get commit message from COMMIT_EDITMSG
COMMIT_MSG=$(head -1 "$PROJECT_ROOT/.git/COMMIT_EDITMSG" 2>/dev/null || echo "commit")
COMMIT_SHORT=$(echo "$COMMIT_MSG" | head -c 60)

# Skip if SESSION_STATE.md is in this commit (avoid loop)
if git diff --cached --name-only | grep -q "SESSION_STATE.md"; then
    echo "📝 SESSION_STATE.md in commit, skipping pre-commit update"
    exit 0
fi

# Log the commit (for /session-summary to process later)
echo "- [$DATE $TIMESTAMP] [$BRANCH] $COMMIT_SHORT" >> "$LOG_FILE"

echo "📝 Pre-commit logged: $COMMIT_SHORT"
exit 0
EOF

chmod +x "$HOOKS_DIR/pre-commit"

# Configure git to use .githooks
git config core.hooksPath "$HOOKS_DIR"

echo "✅ Git hooks configured:"
echo "   - pre-commit: Session state logging"
echo ""
echo "📁 Hooks location: $HOOKS_DIR"
echo "⚙️  Git core.hooksPath: $(git config core.hooksPath)"
