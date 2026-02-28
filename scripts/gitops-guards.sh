#!/bin/bash
# GitOps Guards Library
# Version: 1.0
# Purpose: Prevent manual modifications and enforce GitOps compliance
# Usage: Source this file in other scripts

# ========================================================================
# CONFIGURATION
# ========================================================================
GITOPS_GIT_REPO="https://github.com/RussianLioN/moltinger"
GITOPS_CI_VAR="GITHUB_ACTIONS"
GITOPS_CONFIRM_SKIP="${GITOPS_CONFIRM_SKIP:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================================================
# GITOPS GUARD FUNCTIONS
# ========================================================================

# Check if running in CI/CD environment
gitops_is_ci() {
    [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${CIRCLECI:-}" ]]
}

# Warn about manual execution and require confirmation
gitops_confirm_manual() {
    local script_name="$1"
    local action="$2"

    if gitops_is_ci; then
        return 0  # Auto-approve in CI
    fi

    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║            ⚠️  GitOps Compliance Warning                    ║${NC}"
    echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC} You are running: ${BLUE}$script_name${NC}"
    echo -e "${YELLOW}║${NC} Action: ${BLUE}$action${NC}"
    echo -e "${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} ${RED}This should normally be done via CI/CD pipeline.${NC}"
    echo -e "${YELLOW}║${NC} Manual execution may cause configuration drift."
    echo -e "${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} Repository: $GITOPS_GIT_REPO"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$GITOPS_CONFIRM_SKIP" == "true" ]]; then
        echo -e "${YELLOW}[GitOps] Skipping confirmation (GITOPS_CONFIRM_SKIP=true)${NC}"
        return 0
    fi

    read -p "Are you sure you want to proceed? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}[GitOps] Operation cancelled.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[GitOps] Proceeding with manual execution...${NC}"
    return 0
}

# Log action for audit trail
gitops_log_action() {
    local action="$1"
    local details="${2:-}"
    local log_file="/var/log/gitops-actions.log"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user="${USER:-unknown}"
    local source="manual"

    if gitops_is_ci; then
        source="ci/${GITHUB_RUN_ID:-unknown}"
    fi

    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

    # Append to log
    echo "[$timestamp] [$source] [$user] $action | $details" >> "$log_file" 2>/dev/null || true
}

# Verify file hasn't been manually modified (compare with git)
gitops_verify_file() {
    local file_path="$1"
    local git_hash="$2"
    local current_hash

    if [[ ! -f "$file_path" ]]; then
        return 0  # File doesn't exist, can't verify
    fi

    current_hash=$(sha256sum "$file_path" | cut -d' ' -f1)

    if [[ "$current_hash" != "$git_hash" ]]; then
        echo -e "${RED}[GitOps] WARNING: $file_path has been modified locally!${NC}"
        echo "  Expected: $git_hash"
        echo "  Current:  $current_hash"
        return 1
    fi

    echo -e "${GREEN}[GitOps] $file_path verified ✓${NC}"
    return 0
}

# Check for drift before deployment
gitops_check_drift() {
    local deploy_path="${1:-/opt/moltinger}"
    local drift_found=false

    echo -e "${BLUE}[GitOps] Checking for configuration drift...${NC}"

    # Check docker-compose.yml
    if [[ -f "$deploy_path/docker-compose.yml" ]]; then
        if ! grep -q "traefik.enable=true" "$deploy_path/docker-compose.yml"; then
            echo -e "${RED}[GitOps] DRIFT: docker-compose.yml missing Traefik labels${NC}"
            drift_found=true
        fi
    fi

    # Check for manual modifications marker
    if [[ -f "$deploy_path/.manual-modifications" ]]; then
        echo -e "${RED}[GitOps] DRIFT: .manual-modifications marker found${NC}"
        echo "  Content: $(cat "$deploy_path/.manual-modifications")"
        drift_found=true
    fi

    if [[ "$drift_found" == true ]]; then
        return 1
    fi

    echo -e "${GREEN}[GitOps] No drift detected ✓${NC}"
    return 0
}

# Create marker file to indicate manual modifications
gitops_mark_manual() {
    local file_path="$1"
    local marker_dir="/opt/moltinger"
    local marker_file="$marker_dir/.manual-modifications"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mkdir -p "$marker_dir" 2>/dev/null || true

    echo "[$timestamp] $file_path modified manually by ${USER:-unknown}" >> "$marker_file"
    echo -e "${YELLOW}[GitOps] Manual modification logged to $marker_file${NC}"
}

# Require specific environment variable
gitops_require_env() {
    local var_name="$1"
    local var_value="${!var_name:-}"

    if [[ -z "$var_value" ]]; then
        echo -e "${RED}[GitOps] ERROR: Required environment variable $var_name is not set${NC}"
        return 1
    fi

    return 0
}

# ========================================================================
# CONVENIENCE FUNCTIONS
# ========================================================================

# Full GitOps guard for deployment scripts
gitops_guard_deploy() {
    local script_name="$1"

    # Log the action
    gitops_log_action "deploy" "script=$script_name"

    # Check for drift
    if ! gitops_check_drift; then
        echo -e "${RED}[GitOps] Drift detected! Consider redeploying from CI/CD.${NC}"
    fi

    # Confirm if manual
    if ! gitops_confirm_manual "$script_name" "deployment"; then
        exit 1
    fi
}

# Full GitOps guard for configuration changes
gitops_guard_config() {
    local script_name="$1"
    local config_file="$2"

    # Log the action
    gitops_log_action "config_change" "script=$script_name file=$config_file"

    # Confirm if manual
    if ! gitops_confirm_manual "$script_name" "configuration change to $config_file"; then
        exit 1
    fi

    # Mark as manual modification
    gitops_mark_manual "$config_file"
}

# ========================================================================
# INITIALIZATION
# ========================================================================

# Source this file provides all guard functions
# Usage in other scripts:
#   source /opt/moltinger/scripts/gitops-guards.sh
#   gitops_guard_deploy "$0"
