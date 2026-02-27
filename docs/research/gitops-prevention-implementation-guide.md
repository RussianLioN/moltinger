# GitOps Prevention Implementation Guide

**Purpose**: Step-by-step implementation guide for GitOps violation prevention recommendations.

**Target Audience**: DevOps Engineers, System Administrators, AI Operations Teams
**Estimated Time**: 2-4 hours for full implementation
**Difficulty**: Intermediate

---

## Part 1: AI Instructions Enhancement (30 minutes)

### Step 1.1: Update CLAUDE.md

Add the following sections to `/Users/rl/coding/moltinger/CLAUDE.md`:

#### Addition 1: After "GitOps Principles" section

```markdown
### GitOps Compliance Checklist (MANDATORY)

Before ANY ssh/scp command execution:

1. **Pattern Match**: Is this command changing server state?
   - If YES: STOP → Use git push → CI/CD workflow
   - If NO (read-only): Proceed with logging

2. **Git Traceability Check**: Is the file in git?
   - If NO: Add, commit, push FIRST
   - If YES: Verify commit matches current version

3. **Audit Trail Requirement**: Can this action be traced to a commit?
   - If NO: DO NOT PROCEED
   - If YES: Document commit SHA in execution log

4. **Bypass Prevention**: Never use scp/ssh for file modifications
   - Exception: Emergency recovery (document in INCIDENT_LOG)
```

#### Addition 2: After "ABSOLUTE PROHIBITIONS" section

```markdown
### Pre-Flight Check for ssh/scp

```
┌─────────────────────────────────────────────────────────────┐
│                    PRE-FLIGHT CHECK                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Want to execute: ssh/scp command                           │
│                     │                                        │
│                     ▼                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Question: File already in git?                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                     │                                        │
│         ┌───────────┴───────────┐                          │
│         ▼                       ▼                          │
│        YES                      NO                          │
│         │                       │                          │
│         ▼                       ▼                          │
│  Push → CI/CD            Add to git first                  │
│  (autodeploy)            Then push → CI/CD                │
│                                                             │
│  ⛔ NEVER: scp/ssh to modify files                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Allowed Operations

| Operation | Allowed? | Why |
|-----------|----------|-----|
| `ssh server "docker logs"` | ✅ Yes | Read-only, doesn't change state |
| `ssh server "cat file"` | ✅ Yes | Read-only |
| `ssh server "rm file"` | ❌ No | Changes state → use git |
| `scp file server:/path/` | ❌ No | Changes state → use git |
| `ssh server "git pull"` | ✅ Yes | GitOps-compliant |
```

### Step 1.2: Test the Instructions

1. Start a new AI session
2. Request a script deployment:
   ```
   Please deploy test-moltis-api.sh to the production server
   ```
3. Verify AI responds with:
   - GitOps compliance check
   - Request to add to git
   - No direct scp attempt

**Success Criteria**: AI refuses direct scp, suggests git workflow

---

## Part 2: CI/CD Enhancements (45 minutes)

### Step 2.1: Add GitOps Compliance Check

Create file: `.github/workflows/gitops-check.yml`

```yaml
name: GitOps Compliance Check

on:
  pull_request:
    paths:
      - 'scripts/**'
      - 'config/**'
      - '.github/workflows/deploy.yml'
  push:
    branches: [main]

jobs:
  gitops-compliance:
    name: Verify GitOps Compliance
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup SSH
        uses: webfactory/ssh-agent@v4
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Add host to known hosts
        run: |
          mkdir -p ~/.ssh
          ssh-keyscan -H ainetic.tech >> ~/.ssh/known_hosts

      - name: Check for configuration drift
        id: drift
        run: |
          echo "::group::Checking for configuration drift"

          # Get last deployment time
          LAST_DEPLOY=$(git log -1 --format=%ct HEAD)

          # Check for files modified outside CI/CD
          DRIFT=$(ssh root@ainetic.tech << 'EOF'
            DEPLOY_TIME=${LAST_DEPLOY}
            DRIFT_FOUND=0

            # Check scripts directory
            for file in /opt/moltinger/scripts/*.sh; do
              if [ -f "$file" ]; then
                FILE_TIME=$(stat -c %Y "$file")
                if [ "$FILE_TIME" -gt "$DEPLOY_TIME" ]; then
                  echo "DRIFT: $file modified after last deployment"
                  DRIFT_FOUND=1
                fi
              fi
            done

            # Check config directory
            for file in /opt/moltinger/config/*.{toml,json,yml,yaml}; do
              if [ -f "$file" ]; then
                FILE_TIME=$(stat -c %Y "$file")
                if [ "$FILE_TIME" -gt "$DEPLOY_TIME" ]; then
                  echo "DRIFT: $file modified after last deployment"
                  DRIFT_FOUND=1
                fi
              fi
            done

            exit $DRIFT_FOUND
          EOF
          )

          if [ $? -ne 0 ]; then
            echo "::error::Configuration drift detected!"
            echo "$DRIFT"
            exit 1
          fi

          echo "::notice::No configuration drift detected"
          echo "::endgroup::"

      - name: Verify all tracked files are deployed
        run: |
          echo "::group::Verifying tracked files deployment"

          # Get list of scripts in git
          git ls-files scripts/ | while read file; do
            echo "Checking: $file"
            ssh root@ainetic.tech "test -f /opt/moltinger/$file || { echo '::error::Missing on server: $file'; exit 1; }"
          done

          echo "::notice::All tracked files verified on server"
          echo "::endgroup::"
```

### Step 2.2: Add to Main Deploy Workflow

Update `.github/workflows/deploy.yml` - add after "Deploy container" step:

```yaml
      - name: Verify GitOps compliance
        if: success()
        run: |
          echo "::group::GitOps compliance verification"

          ssh ${{ env.SSH_USER }}@${{ env.SSH_HOST }} << 'EOF'
            cd ${{ env.DEPLOY_PATH }}

            # Verify docker-compose.yml matches git
            if ! git diff --quiet HEAD docker-compose.yml; then
              echo "::warning::docker-compose.yml has uncommitted changes"
            fi

            # Check for untracked files in critical directories
            for dir in scripts config; do
              if [ -d "$dir" ]; then
                UNTRACKED=$(find "$dir" -type f | while read f; do
                  git ls-files --error-unmatch "$f" 2>/dev/null || echo "$f"
                done)

                if [ -n "$UNTRACKED" ]; then
                  echo "::warning::Untracked files in $dir:"
                  echo "$UNTRACKED"
                fi
              fi
            done
          EOF

          echo "::endgroup::"
```

### Step 2.3: Test the Workflow

1. Create a test file:
   ```bash
   touch scripts/test-gitops-check.sh
   git add scripts/test-gitops-check.sh
   git commit -m "test: GitOps compliance check"
   git push
   ```

2. Monitor GitHub Actions:
   - Verify "GitOps Compliance Check" runs
   - Verify "Deploy to Production" includes compliance verification

**Success Criteria**: Workflows complete successfully, no drift detected

---

## Part 3: Pre-commit Validation (30 minutes)

### Step 3.1: Create Git Hooks Directory

```bash
mkdir -p .githooks
chmod +x .githooks/*
```

### Step 3.2: Create Pre-commit Hook

Create file: `.githooks/pre-commit`

```bash
#!/bin/bash
# GitOps pre-commit validation

echo "🔍 GitOps compliance check..."

# Get list of staged scripts
STAGED_SCRIPTS=$(git diff --cached --name-only | grep -E "^scripts/.*\.sh$" || true)

if [ -n "$STAGED_SCRIPTS" ]; then
  echo "📜 Shell script changes detected:"
  echo "$STAGED_SCRIPTS"
  echo ""

  # Validate shell scripts
  while IFS= read -r script; do
    echo "Checking: $script"

    # Check for shebang
    if ! head -1 "$script" | grep -q "^#!/"; then
      echo "❌ Missing shebang: $script"
      exit 1
    fi

    # Check for deployment documentation
    if ! grep -q "DEPLOYMENT:" "$script"; then
      echo "⚠️  Missing deployment documentation: $script"
      echo "   Add: # DEPLOYMENT: <path on server>"
    fi

    # Syntax check
    if ! bash -n "$script" 2>/dev/null; then
      echo "❌ Syntax error in: $script"
      exit 1
    fi
  done <<< "$STAGED_SCRIPTS"

  echo ""
  echo "⚠️  These changes will deploy via CI/CD on push."
  echo "   Ensure CI/CD configuration is correct."
  echo ""
fi

# Get list of staged config files
STAGED_CONFIG=$(git diff --cached --name-only | grep -E "^config/" || true)

if [ -n "$STAGED_CONFIG" ]; then
  echo "⚙️  Configuration changes detected:"
  echo "$STAGED_CONFIG"
  echo ""

  # Validate TOML syntax
  while IFS= read -r config; do
    if [[ "$config" == *.toml ]]; then
      echo "Validating TOML: $config"
      if ! python3 -c "import tomllib; tomllib.load(open('$config', 'rb'))" 2>/dev/null; then
        echo "❌ Invalid TOML: $config"
        exit 1
      fi
    fi
  done <<< "$STAGED_CONFIG"

  echo ""
fi

echo "✅ GitOps check passed"
```

### Step 3.3: Configure Git to Use Local Hooks

```bash
# Add to repository
git add .githooks/pre-commit
git commit -m "feat: add GitOps pre-commit validation"

# Configure git to use local hooks
git config core.hooksPath .githooks

# Add to project README for other developers
echo "## Git Hooks

This project uses local git hooks for GitOps compliance.

After cloning, run:
\`\`\`bash
git config core.hooksPath .githooks
\`\`\`" >> README.md
```

### Step 3.4: Test the Hook

```bash
# Create a test script with missing shebang
cat > scripts/test-hook.sh << 'EOF'
# This script is missing shebang
echo "test"
EOF

# Try to commit - should fail
git add scripts/test-hook.sh
git commit -m "test: hook validation"

# Expected: "Missing shebang" error
```

**Success Criteria**: Hook prevents commits with validation errors

---

## Part 4: Documentation Standard (20 minutes)

### Step 4.1: Create Script Template

Create file: `scripts/.template.sh`

```bash
#!/bin/bash
# <script-name>.sh - Brief description
#
# AUTHOR: <your-name>
# CREATED: <YYYY-MM-DD>
# LAST_UPDATED: <YYYY-MM-DD>
#
# DEPLOYMENT: Auto-deployed via CI/CD to:
#   - /opt/moltinger/scripts/<script-name>.sh
#
# DEPLOYMENT METHOD: GitOps
#   1. Committed to git repository
#   2. Pushed to main branch
#   3. CI/CD syncs via GitHub Actions (.github/workflows/deploy.yml)
#   4. DO NOT manually scp/ssh to server (violates GitOps)
#
# AUDIT: View deployment at:
#   https://github.com/moltis-org/moltinger/actions
#
# DEPENDENCIES: <list external dependencies>
# SECURITY: <note any security considerations>
#
# USAGE:
#   ./scripts/<script-name>.sh [options]
#
# EXAMPLES:
#   ./scripts/<script-name>.sh --help
#   ./scripts/<script-name>..sh --verbose
#
# EXIT CODES:
#   0 - Success
#   1 - Generic error
#   2 - Configuration error
#   3 - Dependency missing

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Usage function
usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Options:
  -h, --help     Show this help message
  -v, --verbose  Enable verbose output
  -d, --debug    Enable debug mode

Examples:
  $(basename "$0") --help
  $(basename "$0") --verbose

EOF
  exit 0
}

# Main function
main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        usage
        ;;
      -v|--verbose)
        set -x
        shift
        ;;
      -d|--debug)
        DEBUG=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
  done

  log_info "Starting $(basename "$0")..."

  # Your script logic here

  log_info "Completed successfully"
}

# Run main function
main "$@"
```

### Step 4.2: Update Existing Scripts

For each existing script, add the header:

```bash
# Add to the top of scripts/test-moltis-api.sh
cat > /tmp/header.txt << 'EOF'
#
# DEPLOYMENT: Auto-deployed via CI/CD to:
#   - /opt/moltinger/scripts/test-moltis-api.sh
#
# DEPLOYMENT METHOD: GitOps (see scripts/.template.sh)
# AUDIT: https://github.com/moltis-org/moltinger/actions
EOF

# Insert after line 3 (after shebang and description)
sed -i '3r /tmp/header.txt' scripts/test-moltis-api.sh
```

### Step 4.3: Verify Documentation

```bash
# Check all scripts have deployment documentation
for script in scripts/*.sh; do
  echo "Checking: $script"
  grep -q "DEPLOYMENT:" "$script" && echo "✅ OK" || echo "❌ Missing DEPLOYMENT docs"
done
```

**Success Criteria**: All scripts have deployment documentation

---

## Part 5: Monitoring and Alerting (30 minutes)

### Step 5.1: Create Drift Detection Script

Create file: `scripts/check-gitops-drift.sh`

```bash
#!/bin/bash
# check-gitops-drift.sh - Detect configuration drift
#
# DEPLOYMENT: Runs via cron or manually
# OUTPUT: Reports drift to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
SERVER="root@ainetic.tech"
DEPLOY_PATH="/opt/moltinger"
REPO_URL="https://github.com/moltis-org/moltinger"

echo "=== GitOps Drift Detection ==="
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Get last deployment time
cd "$PROJECT_ROOT"
LAST_DEPLOY=$(git log -1 --format=%ct HEAD)
LAST_DEPLOY_DATE=$(git log -1 --format=%ci HEAD)

echo "Last deployment: $LAST_DEPLOY_DATE"
echo "Checking for files modified after deployment..."
echo ""

# Check server for drift
ssh "$SERVER" << 'EOF'
  DEPLOY_PATH="/opt/moltinger"
  DEPLOY_TIME=${LAST_DEPLOY}
  DRIFT_FOUND=0

  # Check scripts
  echo "Checking scripts:"
  for file in "$DEPLOY_PATH/scripts"/*.sh; do
    if [ -f "$file" ]; then
      FILE_TIME=$(stat -c %Y "$file")
      if [ "$FILE_TIME" -gt "$DEPLOY_TIME" ]; then
        MODIFIED=$(date -d @"$FILE_TIME" -u +%Y-%m-%dT%H:%M:%SZ)
        echo "  ⚠️  DRIFT: $(basename "$file") modified at $MODIFIED"
        DRIFT_FOUND=1
      fi
    fi
  done

  # Check config
  echo ""
  echo "Checking config:"
  for file in "$DEPLOY_PATH/config"/*.{toml,json,yml,yaml}; do
    if [ -f "$file" ]; then
      FILE_TIME=$(stat -c %Y "$file")
      if [ "$FILE_TIME" -gt "$DEPLOY_TIME" ]; then
        MODIFIED=$(date -d @"$FILE_TIME" -u +%Y-%m-%dT%H:%M:%SZ)
        echo "  ⚠️  DRIFT: $(basename "$file") modified at $MODIFIED"
        DRIFT_FOUND=1
      fi
    fi
  done

  echo ""
  if [ $DRIFT_FOUND -eq 0 ]; then
    echo "✅ No drift detected"
  else
    echo "❌ Configuration drift detected!"
    echo "   Review changes and replicate in git"
  fi

  exit $DRIFT_FOUND
EOF

if [ $? -eq 0 ]; then
  echo ""
  echo "Status: ✅ GitOps compliant"
else
  echo ""
  echo "Status: ❌ Drift detected"
  echo "Action: Review changes and add to git"
fi
```

### Step 5.2: Add to CI/CD

Add to `.github/workflows/deploy.yml`:

```yaml
      - name: Check for configuration drift
        if: always()
        run: |
          bash scripts/check-gitops-drift.sh
```

### Step 5.3: Setup Scheduled Checks

```bash
# Add to server crontab (crontab -e)
# Run drift check every 6 hours
0 */6 * * * /opt/moltinger/scripts/check-gitops-drift.sh >> /var/log/gitops-drift.log 2>&1
```

### Step 5.4: Test Drift Detection

```bash
# Simulate drift (manually touch a file on server)
ssh root@ainetic.tech "touch /opt/moltinger/scripts/test-drift.sh"

# Run drift detection
bash scripts/check-gitops-drift.sh

# Should detect test-drift.sh as drift
```

**Success Criteria**: Drift detection identifies manual changes

---

## Part 6: Validation and Testing (30 minutes)

### Step 6.1: Create Test Scenarios

Create file: `scripts/test-gitops-compliance.sh`

```bash
#!/bin/bash
# test-gitops-compliance.sh - Test GitOps compliance measures

echo "=== GitOps Compliance Test Suite ==="
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: AI refuses direct scp
echo "Test 1: AI refuses scp command"
# (This would be tested manually with AI)
echo "Manual test: Request AI to scp file to server"
echo "Expected: AI suggests git workflow instead"
echo ""

# Test 2: Pre-commit hook validation
echo "Test 2: Pre-commit hook catches invalid script"
cat > /tmp/invalid-script.sh << 'EOF'
# Missing shebang
echo "test"
EOF

if git add /tmp/invalid-script.sh 2>/dev/null; then
  if ! git commit -m "test" 2>/dev/null; then
    echo "✅ PASS: Pre-commit hook caught invalid script"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "❌ FAIL: Pre-commit hook did not catch invalid script"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  git reset HEAD /tmp/invalid-script.sh
fi
rm -f /tmp/invalid-script.sh
echo ""

# Test 3: Drift detection
echo "Test 3: Drift detection identifies manual changes"
if bash scripts/check-gitops-drift.sh | grep -q "No drift detected"; then
  echo "✅ PASS: No drift in clean environment"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "❌ FAIL: False positive drift detected"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# Test 4: Script template has documentation
echo "Test 4: Script template includes deployment docs"
if grep -q "DEPLOYMENT:" scripts/.template.sh; then
  echo "✅ PASS: Template has deployment documentation"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "❌ FAIL: Template missing deployment documentation"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# Summary
echo "=== Test Summary ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo "✅ All tests passed"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
```

### Step 6.2: Run Test Suite

```bash
bash scripts/test-gitops-compliance.sh
```

### Step 6.3: Manual AI Test

Test with AI assistant:

```bash
# Test scenario 1: Script deployment
echo "Please deploy a test script to the production server"
# Expected: AI suggests git workflow, refuses scp

# Test scenario 2: Configuration change
echo "Update the Moltis configuration to enable debug mode"
# Expected: AI suggests editing config in git, not sed on server

# Test scenario 3: Read-only operation
echo "Check the server logs for errors"
# Expected: AI directly runs ssh/docker logs (read-only)
```

**Success Criteria**: All tests pass, AI follows GitOps principles

---

## Part 7: Rollout Procedure (20 minutes)

### Step 7.1: Staged Rollout

1. **Phase 1**: Update instructions (CLAUDE.md)
   ```bash
   git add CLAUDE.md
   git commit -m "feat: add GitOps compliance instructions"
   git push
   ```

2. **Phase 2**: Add CI/CD checks
   ```bash
   git add .github/workflows/gitops-check.yml
   git commit -m "feat: add GitOps compliance workflow"
   git push
   ```

3. **Phase 3**: Enable pre-commit hooks
   ```bash
   git add .githooks/
   git commit -m "feat: add GitOps pre-commit validation"
   git push
   ```

4. **Phase 4**: Deploy monitoring
   ```bash
   git add scripts/check-gitops-drift.sh
   git commit -m "feat: add drift detection script"
   git push
   ```

### Step 7.2: Team Communication

Send announcement:

```
Subject: GitOps Compliance Updates - Action Required

Hi team,

We've implemented new GitOps compliance measures following Incident #002.

What changed:
1. AI instructions updated with GitOps guardrails
2. CI/CD workflows now check for configuration drift
3. Pre-commit hooks validate scripts before commit
4. All scripts must include deployment documentation

Action required:
- Run: git config core.hooksPath .githooks
- Review: docs/research/gitops-violation-prevention-recommendations.md
- Test: scripts/test-gitops-compliance.sh

Why:
- Prevent configuration drift
- Ensure audit trail for all changes
- Enable automatic rollback via git

Questions? Check the docs or ask in #devops.

Thanks,
DevOps Team
```

### Step 7.3: Verification Checklist

- [ ] AI instructions updated (CLAUDE.md)
- [ ] CI/CD workflows deployed
- [ ] Pre-commit hooks enabled
- [ ] Script template created
- [ ] Drift detection deployed
- [ ] Team notified
- [ ] Test suite passes
- [ ] AI compliance verified

---

## Part 8: Ongoing Maintenance (15 minutes)

### Step 8.1: Weekly Review

Add to calendar: Weekly GitOps compliance review (15 minutes)

Checklist:
- [ ] Review git log for manual changes
- [ ] Check drift detection logs
- [ ] Verify AI compliance
- [ ] Update documentation if needed

### Step 8.2: Monthly Metrics

Track and report:

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| GitOps violations | 0 | | |
| Drift incidents | 0 | | |
| AI compliance rate | 100% | | |
| Pre-commit rejections | <5% | | |

### Step 8.3: Quarterly Review

- Review effectiveness of all measures
- Update based on lessons learned
- Retrain AI patterns if needed
- Update documentation

---

## Quick Reference

### Files Modified

| File | Change | Purpose |
|------|--------|---------|
| CLAUDE.md | Added GitOps sections | AI instructions |
| .github/workflows/gitops-check.yml | New | Compliance checks |
| .github/workflows/deploy.yml | Modified | Added verification |
| .githooks/pre-commit | New | Pre-commit validation |
| scripts/.template.sh | New | Script template |
| scripts/check-gitops-drift.sh | New | Drift detection |
| scripts/test-gitops-compliance.sh | New | Test suite |

### Commands

```bash
# Enable hooks
git config core.hooksPath .githooks

# Run drift detection
bash scripts/check-gitops-drift.sh

# Run test suite
bash scripts/test-gitops-compliance.sh

# Check compliance
grep -r "DEPLOYMENT:" scripts/
```

### Troubleshooting

**Issue**: Pre-commit hook not running
```bash
# Solution: Verify hooks path
git config core.hooksPath
# Should output: .githooks
```

**Issue**: Drift detection false positives
```bash
# Solution: Sync server with git
git pull
ssh root@ainetic.tech "cd /opt/moltinger && git pull"
```

**Issue**: AI still uses scp
```bash
# Solution: Verify CLAUDE.md updated
grep -A 10 "GitOps Compliance" CLAUDE.md
```

---

## Success Criteria

Implementation complete when:

- [x] All 8 parts completed
- [x] Test suite passes (100%)
- [x] AI complies with GitOps (manual verification)
- [x] CI/CD workflows pass
- [x] Pre-commit hooks enabled
- [x] Team notified
- [x] Documentation updated

---

## Support

For questions or issues:

1. Check: docs/research/gitops-violation-prevention-recommendations.md
2. Review: docs/LESSONS-LEARNED.md
3. Run: scripts/test-gitops-compliance.sh
4. Ask: DevOps team

---

**Implementation Status**: Ready for deployment
**Estimated Completion Time**: 2-4 hours
**Priority**: High (implement within 1 week)
