#!/bin/bash
#
# Pre-flight Validation Script for Docker Deployment
# Validates all required secrets and configuration before deployment
#
# Usage:
#   ./scripts/preflight-check.sh [OPTIONS]
#
# Options:
#   --json       Output in JSON format
#   --strict     Fail on warnings (not just errors)
#   --ci         CI/CD mode (skip Docker/runtime checks)
#   -h, --help   Show help message
#
# Exit Codes:
#   0 - All checks passed
#   1 - General error
#   4 - Pre-flight validation failed
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"

# Required secrets (from data-model.md)
REQUIRED_SECRETS=(
    "moltis_password"
    "telegram_bot_token"
    "tavily_api_key"
    "glm_api_key"
)

# Optional secrets (warnings only)
OPTIONAL_SECRETS=(
    "smtp_password"
    "ollama_api_key"  # Optional - only needed for Ollama Cloud models
)

# Output format
OUTPUT_JSON=false
STRICT_MODE=false
CI_MODE="${CI:-false}"  # Auto-detect from CI env var, or use --ci flag

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Results storage
declare -a CHECKS
declare -a ERRORS
declare -a WARNINGS
declare -a MISSING_SECRETS

# Helper functions
log_info() {
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
    WARNINGS+=("$1")
}

log_error() {
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
    ERRORS+=("$1")
}

add_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    local severity="${4:-error}"

    CHECKS+=("{\"name\":\"$name\",\"status\":\"$status\",\"message\":\"$message\",\"severity\":\"$severity\"}")

    if [[ "$status" == "fail" ]]; then
        if [[ "$severity" == "error" ]]; then
            log_error "$message"
        else
            log_warn "$message"
        fi
    else
        log_info "$message"
    fi
}

# Validation functions
check_secrets_exist() {
    local all_found=true
    local count=0

    for secret in "${REQUIRED_SECRETS[@]}"; do
        local secret_file="$SECRETS_DIR/${secret}.txt"
        if [[ ! -f "$secret_file" ]]; then
            MISSING_SECRETS+=("$secret")
            all_found=false
        else
            ((count++)) || true
        fi
    done

    if [[ "$all_found" == "true" ]]; then
        add_check "secrets_exist" "pass" "All ${#REQUIRED_SECRETS[@]} required secrets found" "error"
    else
        add_check "secrets_exist" "fail" "Missing secrets: ${MISSING_SECRETS[*]}" "error"
    fi

    # Check optional secrets
    for secret in "${OPTIONAL_SECRETS[@]}"; do
        local secret_file="$SECRETS_DIR/${secret}.txt"
        if [[ ! -f "$secret_file" ]]; then
            log_warn "Optional secret '$secret' not found"
        fi
    done
}

check_docker_available() {
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        add_check "docker_available" "pass" "Docker daemon is running" "error"
    else
        add_check "docker_available" "fail" "Docker daemon is not available" "error"
    fi
}

check_compose_valid() {
    # In CI mode, check docker-compose.prod.yml; locally check both
    local compose_files=()

    if [[ "$CI_MODE" == "true" ]]; then
        compose_files+=("$PROJECT_ROOT/docker-compose.prod.yml")
    else
        compose_files+=("$PROJECT_ROOT/docker-compose.yml")
        compose_files+=("$PROJECT_ROOT/docker-compose.prod.yml")
    fi

    local all_valid=true
    local checked_files=()

    for compose_file in "${compose_files[@]}"; do
        if [[ ! -f "$compose_file" ]]; then
            if [[ "$CI_MODE" != "true" || "$compose_file" == *"prod"* ]]; then
                # In CI, only prod is required; locally both are checked
                all_valid=false
                add_check "compose_valid" "fail" "$(basename $compose_file) not found" "error"
            fi
            continue
        fi

        checked_files+=("$(basename $compose_file)")

        # In CI mode, just check syntax without Docker
        if [[ "$CI_MODE" == "true" ]]; then
            # Basic YAML validation (requires yq or python)
            if command -v yq &> /dev/null && yq eval '.' "$compose_file" &> /dev/null; then
                : # Valid
            elif python3 -c "import yaml; yaml.safe_load(open('$compose_file'))" 2>/dev/null; then
                : # Valid
            else
                all_valid=false
                add_check "compose_valid" "fail" "$(basename $compose_file) has syntax errors" "error"
                continue
            fi
        else
            # Full Docker validation
            if ! docker compose -f "$compose_file" config --quiet 2>/dev/null; then
                all_valid=false
                add_check "compose_valid" "fail" "$(basename $compose_file) has syntax errors" "error"
                continue
            fi
        fi
    done

    if [[ "$all_valid" == "true" && ${#checked_files[@]} -gt 0 ]]; then
        add_check "compose_valid" "pass" "Compose files valid: ${checked_files[*]}" "error"
    fi
}

check_network_exists() {
    # Check if moltis_network exists or can be created
    if docker network ls | grep -q "moltis_network" 2>/dev/null; then
        add_check "network_exists" "pass" "moltis_network exists" "error"
    else
        # Network will be created by docker compose up, so this is a soft check
        add_check "network_exists" "pass" "moltis_network will be created on deploy" "warning"
    fi
}

check_s3_credentials() {
    # Check if rclone is configured for S3 backups
    if command -v rclone &> /dev/null && rclone config show backup-s3 &> /dev/null 2>&1; then
        add_check "s3_credentials" "pass" "S3 credentials configured" "warning"
    else
        add_check "s3_credentials" "warning" "S3 credentials not configured, backup will be local only" "warning"
    fi
}

check_disk_space() {
    local backup_dir="/var/backups/moltis"
    local required_mb=1024  # 1GB minimum

    # Check if backup directory exists or can be created
    if [[ -d "$backup_dir" ]]; then
        local available_kb
        available_kb=$(df -k "$backup_dir" | awk 'NR==2 {print $4}')
        local available_mb=$((available_kb / 1024))

        if [[ $available_mb -ge $required_mb ]]; then
            add_check "disk_space" "pass" "Sufficient disk space: ${available_mb}MB available" "warning"
        else
            add_check "disk_space" "fail" "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required" "warning"
        fi
    else
        add_check "disk_space" "pass" "Backup directory will be created on first backup" "warning"
    fi
}

# ========================================================================
# LLM FAILOVER CHECKS (Fallback LLM Feature)
# ========================================================================

check_ollama_config() {
    local moltis_config="$PROJECT_ROOT/config/moltis.toml"
    local ollama_enabled=false
    local ollama_base_url=""
    local ollama_model=""
    local failover_enabled=false

    # Check if moltis.toml exists
    if [[ ! -f "$moltis_config" ]]; then
        add_check "ollama_config" "fail" "moltis.toml not found" "error"
        return
    fi

    # Parse Ollama configuration from moltis.toml
    # Using grep and sed for TOML parsing (basic but works for our use case)
    if grep -q '^\[providers\.ollama\]' "$moltis_config"; then
        ollama_enabled=$(grep -A5 '^\[providers\.ollama\]' "$moltis_config" | grep 'enabled' | sed 's/.*=.*\(true\|false\).*/\1/' | head -1)
        ollama_base_url=$(grep -A5 '^\[providers\.ollama\]' "$moltis_config" | grep 'base_url' | sed 's/.*=.*"\([^"]*\)".*/\1/' | head -1)
        ollama_model=$(grep -A5 '^\[providers\.ollama\]' "$moltis_config" | grep 'model' | sed 's/.*=.*"\([^"]*\)".*/\1/' | head -1)
    fi

    # Check failover configuration
    if grep -q '^\[failover\]' "$moltis_config"; then
        failover_enabled=$(grep -A5 '^\[failover\]' "$moltis_config" | grep 'enabled' | sed 's/.*=.*\(true\|false\).*/\1/' | head -1)
    fi

    # Validate configuration
    if [[ "$ollama_enabled" == "true" ]]; then
        # Check base URL
        if [[ -n "$ollama_base_url" ]]; then
            add_check "ollama_base_url" "pass" "Ollama base URL configured: $ollama_base_url" "warning"
        else
            add_check "ollama_base_url" "fail" "Ollama enabled but base_url not set" "error"
        fi

        # Check model
        if [[ -n "$ollama_model" ]]; then
            add_check "ollama_model" "pass" "Ollama model configured: $ollama_model" "warning"
        else
            add_check "ollama_model" "fail" "Ollama enabled but model not set" "error"
        fi

        # Check if OLLAMA_API_KEY is needed (cloud models)
        if [[ "$ollama_model" == *":cloud"* ]]; then
            local ollama_key_file="$SECRETS_DIR/ollama_api_key.txt"
            if [[ -f "$ollama_key_file" ]] && [[ -s "$ollama_key_file" ]]; then
                # Check if it's not the placeholder
                if grep -q "PLACEHOLDER" "$ollama_key_file" 2>/dev/null; then
                    add_check "ollama_api_key" "fail" "Ollama API key is placeholder - replace with actual key" "warning"
                else
                    add_check "ollama_api_key" "pass" "Ollama API key configured for cloud model" "warning"
                fi
            else
                add_check "ollama_api_key" "fail" "Ollama cloud model requires ollama_api_key secret" "warning"
            fi
        fi

        # Check failover is enabled
        if [[ "$failover_enabled" == "true" ]]; then
            add_check "failover_config" "pass" "Failover is enabled in moltis.toml" "warning"
        else
            add_check "failover_config" "warning" "Ollama configured but failover not enabled" "warning"
        fi
    else
        add_check "ollama_config" "pass" "Ollama provider not enabled (optional)" "warning"
    fi
}

check_ollama_secret() {
    local ollama_key_file="$SECRETS_DIR/ollama_api_key.txt"

    if [[ -f "$ollama_key_file" ]]; then
        # Check file is not empty
        if [[ -s "$ollama_key_file" ]]; then
            # Check file permissions
            local perms
            perms=$(stat -f "%Lp" "$ollama_key_file" 2>/dev/null || stat -c "%a" "$ollama_key_file" 2>/dev/null || echo "unknown")

            if [[ "$perms" == "600" ]]; then
                add_check "ollama_secret_perms" "pass" "Ollama API key file has correct permissions (600)" "warning"
            else
                add_check "ollama_secret_perms" "warning" "Ollama API key file should have 600 permissions (got: $perms)" "warning"
            fi

            # Check it's not placeholder
            if grep -q "PLACEHOLDER" "$ollama_key_file" 2>/dev/null; then
                add_check "ollama_secret_valid" "warning" "Ollama API key contains placeholder - replace before deployment" "warning"
            else
                add_check "ollama_secret_valid" "pass" "Ollama API key file exists and is not empty" "warning"
            fi
        else
            add_check "ollama_secret_valid" "warning" "Ollama API key file is empty" "warning"
        fi
    else
        # This is optional - only needed for cloud models
        add_check "ollama_secret_valid" "pass" "Ollama API key not configured (optional for local models)" "warning"
    fi
}

# Output functions
output_json() {
    local status="pass"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        status="fail"
    elif [[ ${#WARNINGS[@]} -gt 0 && "$STRICT_MODE" == "true" ]]; then
        status="fail"
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        status="warning"
    fi

    # Build checks array
    local checks_json
    checks_json=$(printf '%s\n' "${CHECKS[@]}" | jq -s '.')

    # Build output
    jq -n \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson checks "$checks_json" \
        --argjson missing_secrets "$(printf '%s\n' "${MISSING_SECRETS[@]}" | jq -R . | jq -s .)" \
        --argjson errors "$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s .)" \
        --argjson warnings "$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)" \
        '{
            status: $status,
            timestamp: $timestamp,
            checks: $checks,
            missing_secrets: $missing_secrets,
            errors: $errors,
            warnings: $warnings
        }'
}

output_text() {
    echo ""
    echo "========================================="
    echo "  Pre-flight Validation Results"
    echo "========================================="
    echo ""

    if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
        echo -e "${GREEN}✓ All checks passed${NC}"
    elif [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠ All critical checks passed, ${#WARNINGS[@]} warnings${NC}"
    else
        echo -e "${RED}✗ ${#ERRORS[@]} checks failed${NC}"
    fi

    echo ""
    echo "Checks performed: ${#CHECKS[@]}"
    echo "Errors: ${#ERRORS[@]}"
    echo "Warnings: ${#WARNINGS[@]}"

    if [[ ${#MISSING_SECRETS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Missing secrets:${NC}"
        for secret in "${MISSING_SECRETS[@]}"; do
            echo "  - $secret"
        done
    fi

    echo ""
}

# Help function
show_help() {
    cat << EOF
Pre-flight Validation Script for Docker Deployment

Usage:
    $0 [OPTIONS]

Options:
    --json       Output in JSON format for AI parsing
    --strict     Fail on warnings (not just errors)
    --ci         CI/CD mode (skip Docker/runtime checks, use docker-compose.prod.yml)
    -h, --help   Show this help message

Exit Codes:
    0 - All checks passed
    1 - General error
    4 - Pre-flight validation failed

Examples:
    $0                    # Human-readable output (local)
    $0 --json             # JSON output for CI/CD
    $0 --ci --json        # CI mode (GitHub Actions)
    $0 --json --strict    # Strict mode for production

Contract: specs/001-docker-deploy-improvements/contracts/scripts.md
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # In CI mode, only check configuration files (secrets are in GitHub Secrets)
    if [[ "$CI_MODE" == "true" ]]; then
        if [[ "$OUTPUT_JSON" == "false" ]]; then
            echo "Running in CI mode - skipping Docker/runtime checks"
        fi
        check_compose_valid
        check_ollama_config
    else
        # Full checks for local/production runtime
        check_secrets_exist
        check_docker_available
        check_compose_valid
        check_network_exists
        check_s3_credentials
        check_disk_space

        # LLM Failover checks
        check_ollama_config
        check_ollama_secret
    fi

    # Output results
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json
    else
        output_text
    fi

    # Determine exit code
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        exit 4
    elif [[ ${#WARNINGS[@]} -gt 0 && "$STRICT_MODE" == "true" ]]; then
        exit 4
    else
        exit 0
    fi
}

main
