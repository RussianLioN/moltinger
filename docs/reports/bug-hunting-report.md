# Bug Hunting Report

**Generated**: 2026-02-28
**Project**: moltinger
**Files Analyzed**: 45
**Total Issues Found**: 14
**Status**: Issues identified

---

## Executive Summary

This bug hunting scan analyzed the Moltinger project - a Claude Code orchestrator kit with Docker deployment configurations, GitHub Actions workflows, and shell scripts. The scan identified 14 issues across different severity levels.

### Key Metrics

| Priority | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 2 |
| MEDIUM | 5 |
| LOW | 7 |
| **Total** | **14** |

### Highlights

- No critical security vulnerabilities found
- All shell scripts use proper error handling (`set -e` or `set -euo pipefail`)
- GitOps compliance patterns are well implemented
- Several medium-priority issues related to deprecated scripts and configuration drift risks

---

## Critical Issues (Priority 1)

No critical issues found.

---

## High Priority Issues (Priority 2)

### BUG-001: Deprecated Backup Script Still Present

- **File**: `/Users/rl/coding/moltinger/scripts/backup-moltis.sh`
- **Line**: 1-87
- **Category**: Dead Code / Maintenance
- **Description**: The `backup-moltis.sh` script is marked as deprecated in `manifest.json` with `replaced_by: backup-moltis-enhanced.sh`, but it still exists in the repository and could be accidentally used.
- **Impact**: Confusion about which script to use; potential use of less capable backup tool
- **Fix**: Remove the deprecated script or move to an `archive/` directory:
  ```bash
  # Option 1: Remove entirely
  rm scripts/backup-moltis.sh

  # Option 2: Archive for reference
  mkdir -p scripts/archive
  git mv scripts/backup-moltis.sh scripts/archive/
  ```

### BUG-002: Docker Socket Exposed with Privileged Mode

- **File**: `/Users/rl/coding/moltinger/docker-compose.yml:9,22-23`
- **Line**: 9, 22-23
- **Category**: Security
- **Description**: The Moltis container runs with `privileged: true` AND has the Docker socket mounted. This grants near-host-level access to the container.
- **Impact**: If the Moltis container is compromised, an attacker gains full control over the Docker daemon and potentially the host
- **Fix**: Consider using rootless Docker or specific capabilities instead of privileged mode. At minimum, document this security decision:
  ```yaml
  # SECURITY NOTE: privileged mode + docker socket required for sandbox execution
  # This is intentional for Moltis's container-in-container functionality
  privileged: true
  ```

---

## Medium Priority Issues (Priority 3)

### BUG-003: Missing GitOps Guard in backup-moltis.sh

- **File**: `/Users/rl/coding/moltinger/scripts/backup-moltis.sh`
- **Line**: 1-5
- **Category**: Consistency
- **Description**: The simple backup script doesn't source the `gitops-guards.sh` library unlike other scripts. While deprecated, it should maintain consistency.
- **Impact**: Inconsistent behavior if script is still used
- **Fix**: Either remove the script (see BUG-001) or add GitOps guards:
  ```bash
  # Source GitOps guards library
  if [[ -f "$SCRIPT_DIR/gitops-guards.sh" ]]; then
      source "$SCRIPT_DIR/gitops-guards.sh"
  fi
  ```

### BUG-004: Health Monitor Has No Graceful Degradation

- **File**: `/Users/rl/coding/moltinger/scripts/health-monitor.sh`
- **Line**: 185-186
- **Category**: Reliability
- **Description**: The `check_disk_space` function runs `docker system prune -af --volumes` automatically when disk usage exceeds 90%. This aggressive cleanup could delete volumes that are still needed.
- **Impact**: Potential data loss if volumes are pruned during high disk usage
- **Fix**: Add confirmation or less aggressive cleanup:
  ```bash
  # Instead of automatic prune, log warning and send alert
  log_warn "Consider manual cleanup: docker system prune"
  # Or use non-destructive: docker system prune -f (without --volumes)
  ```

### BUG-005: GitOps Drift Detection Creates Duplicate Issues

- **File**: `/Users/rl/coding/moltinger/.github/workflows/gitops-drift-detection.yml`
- **Line**: 103-140
- **Category**: Maintainability
- **Description**: The drift detection workflow creates a new GitHub issue every time drift is detected without checking if an open issue already exists. Running every 6 hours could create many duplicate issues.
- **Impact**: Issue spam, reduced signal-to-noise ratio
- **Fix**: Check for existing open issues before creating new ones:
  ```bash
  # Check if drift issue already exists
  EXISTING=$(gh issue list --repo ${{ github.repository }} --label drift --state open --limit 1)
  if [[ -n "$EXISTING" ]]; then
    echo "Drift issue already exists: $EXISTING"
    exit 0
  fi
  ```

### BUG-006: UAT Gate Has Hardcoded Server Path

- **File**: `/Users/rl/coding/moltinger/.github/workflows/uat-gate.yml`
- **Line**: 23, 273
- **Category**: Maintainability
- **Description**: The deployment path `/opt/moltinger` is hardcoded in multiple places. While it's defined in `env`, the `sed` command uses a hardcoded path.
- **Impact**: Inconsistency if path changes; harder to test with different paths
- **Fix**: Use the environment variable consistently:
  ```bash
  sed -i.bak "s|image: ghcr.io/moltis-org/moltis:.*|image: ghcr.io/moltis-org/moltis:$VERSION|" ${{ env.DEPLOY_PATH }}/docker-compose.yml
  ```

### BUG-007: TOML Configuration Has Duplicate Section

- **File**: `/Users/rl/coding/moltinger/config/moltis.toml`
- **Line**: 130-131, 516-517
- **Category**: Configuration
- **Description**: There are potentially confusing TOML sections. Line 130-131 defines `[providers.glm-coding]` marked as disabled with comment "invalid provider name", and there's an odd `[memory.qmd.collections]` section at line 516 that appears misplaced.
- **Impact**: Confusion about configuration; potential parsing issues
- **Fix**: Remove or clarify these sections:
  ```toml
  # Remove the invalid provider section entirely
  # Move [memory.qmd.collections] to appropriate location or remove
  ```

---

## Low Priority Issues (Priority 4)

### BUG-008: TODO/FIXME Markers in Documentation

- **File**: Multiple files
- **Category**: Documentation
- **Description**: Several TODO items exist in `docs/LESSONS-LEARNED.md` that should be tracked as issues:
  - Line 294: Add TOML validation step
  - Line 295: Update CLAUDE.md with Pre-Integration Checklist
  - Line 301-311: Multiple SRE/TDD tasks
- **Impact**: Untracked work items may be forgotten
- **Fix**: Convert to GitHub issues or Beads tasks

### BUG-009: Shell Script Variable Expansion Without Quoting

- **File**: `/Users/rl/coding/moltinger/scripts/test-moltis-api.sh`
- **Line**: 26, 40, 75, 91
- **Category**: Code Quality
- **Description**: Variables like `${MOLTIS_PASSWORD}` and `${command}` are used in strings without proper quoting, which could cause issues with special characters.
- **Impact**: Potential issues with passwords containing special characters
- **Fix**: Use proper quoting:
  ```bash
  -d "password=${MOLTIS_PASSWORD}"
  # Should be:
  -d "password=$(printf '%s' "$MOLTIS_PASSWORD" | jq -sRr @uri)"
  ```

### BUG-010: No Input Validation in test-moltis-api.sh

- **File**: `/Users/rl/coding/moltinger/scripts/test-moltis-api.sh`
- **Line**: 63-97
- **Category**: Security
- **Description**: The `main` function accepts arbitrary command input without validation. If this script is exposed to untrusted input, it could be exploited.
- **Impact**: Potential command injection if used with untrusted input
- **Fix**: Validate and sanitize input:
  ```bash
  # Validate command doesn't contain dangerous characters
  if [[ "$command" =~ [\"\'\$\`] ]]; then
      echo "ERROR: Invalid characters in command"
      exit 1
  fi
  ```

### BUG-011: Deprecated GitHub Actions Output Syntax

- **File**: `/Users/rl/coding/moltinger/scripts/scripts-verify.sh`
- **Line**: 253-254
- **Category**: Deprecation
- **Description**: Uses deprecated `::set-output` syntax instead of the new `$GITHUB_OUTPUT` file approach.
- **Impact**: Will break when GitHub removes support for old syntax
- **Fix**: Update to new syntax:
  ```bash
  echo "scripts_valid=true" >> "$GITHUB_OUTPUT"
  echo "total_scripts=$(jq -r '.scripts | length' "$MANIFEST_FILE")" >> "$GITHUB_OUTPUT"
  ```

### BUG-012: Hardcoded Telegram Bot Token Example

- **File**: `/Users/rl/coding/moltinger/.env.example`
- **Line**: 107
- **Category**: Documentation
- **Description**: The example Telegram bot token `123456789:ABCdefGHIjklMNOpqrsTUVwxyz` looks realistic but is invalid. While documented as an example, it could be confused with a real token.
- **Impact**: Minor - could confuse users
- **Fix**: Use clearly placeholder format:
  ```
  TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
  ```

### BUG-013: Inconsistent Error Handling in Workflows

- **File**: `/Users/rl/coding/moltinger/.github/workflows/deploy.yml`
- **Line**: 204-207
- **Category**: Code Quality
- **Description**: The preflight validation checks if `secrets.SSH_PRIVATE_KEY` is empty, but GitHub Actions secrets are always masked and this check may not work as expected in the `run` step.
- **Impact**: Check may not actually validate the secret exists
- **Fix**: Use job-level environment secrets or move validation to a separate step

### BUG-014: Manifest Sync Command Uses Non-GitOps Pattern

- **File**: `/Users/rl/coding/moltinger/scripts/manifest.json`
- **Line**: 103
- **Category**: GitOps Compliance
- **Description**: The `sync_command` in manifest.json suggests `scp` for syncing scripts, which violates GitOps principles (should go through CI/CD).
- **Impact**: Encourages manual server modifications
- **Fix**: Update documentation to reference the deploy workflow instead:
  ```json
  "sync_command": "Trigger via GitHub Actions: gh workflow run deploy.yml"
  ```

---

## Code Cleanup Required

### Debug Code to Remove

No production debug code (console.log, etc.) found. The codebase is clean of debug statements.

### Dead Code to Remove

| File | Lines | Type | Description |
|------|-------|------|-------------|
| scripts/backup-moltis.sh | 1-87 | Deprecated Script | Replaced by backup-moltis-enhanced.sh |
| config/moltis.toml | 130-131 | Disabled Section | Invalid provider name, disabled |

### Duplicate Code Blocks

| Files | Lines | Description | Refactor Suggestion |
|-------|-------|-------------|-------------------|
| deploy.yml, uat-gate.yml | Multiple | SSH setup steps | Extract to composite action |
| deploy.yml, gitops-drift-detection.yml | Multiple | Drift check functions | Extract to shared library |

---

## Metrics Summary

| Metric | Value |
|--------|-------|
| Security Vulnerabilities | 0 (Critical) |
| Deprecated Code | 2 instances |
| Configuration Issues | 3 instances |
| Documentation TODOs | 7 items |
| Shell Scripts Analyzed | 8 |
| GitHub Workflows Analyzed | 5 |
| Docker Compose Files | 2 |
| Technical Debt Score | Low-Medium |

---

## Task List

### High Priority Tasks (Fix Before Next Deployment)

- [ ] **[HIGH-1]** Remove or archive deprecated `backup-moltis.sh` script
- [ ] **[HIGH-2]** Document security decision for privileged mode + Docker socket

### Medium Priority Tasks (Schedule for Sprint)

- [ ] **[MEDIUM-1]** Add duplicate issue check to drift detection workflow
- [ ] **[MEDIUM-2]** Replace aggressive volume pruning with safer cleanup
- [ ] **[MEDIUM-3]** Clean up confusing TOML configuration sections
- [ ] **[MEDIUM-4]** Fix hardcoded paths in UAT gate workflow
- [ ] **[MEDIUM-5]** Add GitOps guards to backup-moltis.sh (or remove it)

### Low Priority Tasks (Backlog)

- [ ] **[LOW-1]** Convert LESSONS-LEARNED.md TODOs to tracked issues
- [ ] **[LOW-2]** Update GitHub Actions output syntax in scripts-verify.sh
- [ ] **[LOW-3]** Add input validation to test-moltis-api.sh
- [ ] **[LOW-4]** Improve example token format in .env.example
- [ ] **[LOW-5]** Extract common SSH setup to composite action
- [ ] **[LOW-6]** Update manifest.json sync_command documentation
- [ ] **[LOW-7]** Fix secret validation in deploy.yml preflight

---

## Recommendations

### Immediate Actions

1. **Remove deprecated backup script** - The `backup-moltis.sh` is marked deprecated but still exists, causing potential confusion.

2. **Document security posture** - The privileged Docker setup is intentional but should be clearly documented for security audits.

### Short-term Improvements (1-2 weeks)

1. **Extract common workflow steps** - SSH setup and drift checking are duplicated across workflows. Create composite actions.

2. **Improve drift detection** - Add duplicate issue prevention to avoid spam.

3. **Fix configuration drift risks** - Remove confusing TOML sections and use environment variables consistently.

### Long-term Refactoring

1. **Implement ShellCheck in CI** - Add automated shell script linting to catch issues early.

2. **Create security documentation** - Document the threat model and security decisions for the Docker deployment.

3. **Standardize error handling** - Create a shared library for common error handling patterns.

---

## Next Steps

1. Review HIGH priority bugs and create issues for them
2. Schedule MEDIUM priority fixes for current sprint
3. Add LOW priority items to backlog
4. Consider adding ShellCheck to CI pipeline for automated shell script validation

---

*Report generated by bug-hunter agent*
*Scan completed successfully*
