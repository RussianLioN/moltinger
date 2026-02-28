#!/bin/bash
# Scripts Integrity Checker
# Version: 1.0
# Purpose: Validate scripts manifest and verify integrity
# Usage: scripts-verify.sh [--fix] [--ci]

set -euo pipefail

# ========================================================================
# CONFIGURATION
# ========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
HASHES_FILE="$SCRIPT_DIR/.scripts-hashes"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================================================
# FUNCTIONS
# ========================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if jq is available
check_jq() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is required for manifest parsing"
        log_info "Install: apt-get install jq || brew install jq"
        exit 1
    fi
}

# Validate manifest.json syntax
validate_manifest_syntax() {
    log_info "Validating manifest.json syntax..."

    if [[ ! -f "$MANIFEST_FILE" ]]; then
        log_error "manifest.json not found"
        return 1
    fi

    if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
        log_error "manifest.json is not valid JSON"
        return 1
    fi

    log_success "manifest.json syntax valid"
    return 0
}

# Check all scripts in manifest exist
validate_scripts_exist() {
    log_info "Checking scripts exist..."
    local errors=0

    while IFS= read -r script; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_error "Missing script: $script"
            ((errors++))
        else
            log_success "Found: $script"
        fi
    done < <(jq -r '.scripts | keys[]' "$MANIFEST_FILE")

    return $errors
}

# Check all .sh files are in manifest
validate_no_orphans() {
    log_info "Checking for orphan scripts..."
    local orphans=0

    for script in "$SCRIPT_DIR"/*.sh; do
        local basename
        basename=$(basename "$script")

        if ! jq -e ".scripts[\"$basename\"]" "$MANIFEST_FILE" >/dev/null 2>&1; then
            log_warn "Orphan script not in manifest: $basename"
            ((orphans++))
        fi
    done

    if [[ $orphans -gt 0 ]]; then
        log_warn "Found $orphans orphan scripts (not in manifest)"
    fi

    return 0
}

# Check script permissions
validate_permissions() {
    log_info "Checking script permissions..."
    local errors=0

    while IFS= read -r script; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            local perms
            perms=$(stat -c "%a" "$script_path" 2>/dev/null || stat -f "%Lp" "$script_path")

            if [[ "$perms" != "755" ]] && [[ "$perms" != "744" ]]; then
                log_warn "Non-standard permissions on $script: $perms"
                if [[ "${1:-}" == "--fix" ]]; then
                    chmod 755 "$script_path"
                    log_info "Fixed permissions for $script"
                fi
            fi
        fi
    done < <(jq -r '.scripts | to_entries[] | select(.value.entrypoint == true) | .key' "$MANIFEST_FILE")

    return 0
}

# Generate/verify hashes
verify_hashes() {
    log_info "Verifying script hashes..."

    # Generate current hashes
    local temp_hashes
    temp_hashes=$(mktemp)

    for script in "$SCRIPT_DIR"/*.sh; do
        if [[ -f "$script" ]]; then
            local basename
            basename=$(basename "$script")
            local hash
            hash=$(sha256sum "$script" | cut -d' ' -f1)
            echo "$basename:$hash" >> "$temp_hashes"
        fi
    done

    if [[ -f "$HASHES_FILE" ]]; then
        # Compare with stored hashes
        local changed=0
        while IFS=: read -r script hash; do
            local stored_hash
            stored_hash=$(grep "^$script:" "$HASHES_FILE" | cut -d: -f2)

            if [[ "$hash" != "$stored_hash" ]]; then
                if [[ -n "$stored_hash" ]]; then
                    log_warn "CHANGED: $script"
                    log_info "  Old: $stored_hash"
                    log_info "  New: $hash"
                    ((changed++))
                else
                    log_info "NEW: $script"
                fi
            fi
        done < "$temp_hashes"

        if [[ $changed -gt 0 ]]; then
            log_warn "$changed scripts have changed since last hash"
        fi
    else
        log_info "No previous hashes found (first run)"
    fi

    # Update hashes file
    mv "$temp_hashes" "$HASHES_FILE"
    log_success "Hashes updated in $HASHES_FILE"

    return 0
}

# Check dependencies
check_dependencies() {
    log_info "Checking script dependencies..."

    local missing=0

    # Check system dependencies
    while IFS= read -r dep; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "Missing dependency: $dep"
            ((missing++))
        else
            log_success "Dependency OK: $dep"
        fi
    done < <(jq -r '.dependencies.packages | keys[]' "$MANIFEST_FILE")

    return $missing
}

# Generate summary
generate_summary() {
    local total_scripts
    total_scripts=$(jq -r '.scripts | length' "$MANIFEST_FILE")

    local entrypoints
    entrypoints=$(jq -r '[.scripts[] | select(.entrypoint == true)] | length' "$MANIFEST_FILE")

    local libraries
    libraries=$(jq -r '[.scripts[] | select(.type == "library")] | length' "$MANIFEST_FILE")

    local deprecated
    deprecated=$(jq -r '[.scripts[] | select(.deprecated == true)] | length' "$MANIFEST_FILE")

    echo ""
    echo "═══════════════════════════════════════════"
    echo "         SCRIPTS INTEGRITY SUMMARY         "
    echo "═══════════════════════════════════════════"
    echo "  Total scripts:    $total_scripts"
    echo "  Entrypoints:      $entrypoints"
    echo "  Libraries:        $libraries"
    echo "  Deprecated:       $deprecated"
    echo "═══════════════════════════════════════════"
    echo ""
}

# ========================================================================
# MAIN
# ========================================================================

main() {
    local fix_mode="${1:-}"
    local ci_mode="${2:-}"

    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║     Scripts Integrity Checker v1.0        ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

    check_jq

    local errors=0

    validate_manifest_syntax || ((errors++))
    validate_scripts_exist || ((errors++))
    validate_no_orphans
    validate_permissions "$fix_mode"
    verify_hashes
    check_dependencies || ((errors++))
    generate_summary

    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors error(s)"
        exit 1
    fi

    log_success "All checks passed!"

    # Output for CI
    if [[ "$ci_mode" == "--ci" ]]; then
        echo "::set-output name=scripts_valid::true"
        echo "::set-output name=total_scripts::$(jq -r '.scripts | length' "$MANIFEST_FILE")"
    fi
}

main "$@"
