#!/bin/bash
# Configuration Validation Unit Tests
# Tests configuration file validation (TOML, YAML, env vars, secrets)
#
# Test Cases:
#   - TOML syntax validation
#   - Required fields check
#   - YAML syntax validation
#   - Environment variable substitution
#   - Hardcoded secrets detection
#
# Part of: 001-docker-deploy-improvements
# Contract: specs/001-docker-deploy-improvements/contracts/scripts.md

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

# Configuration files to test
TOML_CONFIG="$PROJECT_ROOT/config/moltis.toml"
YAML_COMPOSE="$PROJECT_ROOT/docker-compose.yml"
YAML_COMPOSE_PROD="$PROJECT_ROOT/docker-compose.prod.yml"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate TOML syntax using Python
validate_toml_syntax() {
    local toml_file="$1"

    if ! command_exists python3; then
        echo "SKIP: python3 not found"
        return 2
    fi

    # Use Python tomllib (Python 3.11+) or tomli
    python3 << EOF
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write("ERROR: No TOML library available. Install: pip install tomli\\n")
        sys.exit(2)

try:
    with open("$toml_file", "rb") as f:
        tomllib.load(f)
    print("OK")
except Exception as e:
    sys.stderr.write(f"ERROR: {e}\\n")
    sys.exit(1)
EOF
}

# Validate YAML syntax using Python
validate_yaml_syntax() {
    local yaml_file="$1"

    if ! command_exists python3; then
        echo "SKIP: python3 not found"
        return 2
    fi

    python3 << EOF
import sys
import yaml

try:
    with open("$yaml_file", "r") as f:
        yaml.safe_load(f)
    print("OK")
except yaml.YAMLError as e:
    sys.stderr.write(f"ERROR: {e}\\n")
    sys.exit(1)
except Exception as e:
    sys.stderr.write(f"ERROR: {e}\\n")
    sys.exit(1)
EOF
}

# Check for hardcoded secrets in file
check_hardcoded_secrets() {
    local file="$1"
    local found=0

    # Patterns that suggest hardcoded secrets
    local patterns=(
        "api_key\s*=\s*['\"][^'\$][^'\"]*['\"]"          # api_key = "actual_key"
        "password\s*=\s*['\"][^'\$][^'\"]*['\"]"         # password = "actual_password"
        "token\s*=\s*['\"][^'\$][^'\"]*['\"]"            # token = "actual_token"
        "secret\s*=\s*['\"][^'\$][^'\"]*['\"]"           # secret = "actual_secret"
        "API_KEY\s*=\s*['\"][^'\$][^'\"]*['\"]"         # API_KEY = "actual_key"
        "api_key:\s*[^'\$\n][^'\n]*"                    # YAML: api_key: actual_key
    )

    while IFS= read -r line; do
        for pattern in "${patterns[@]}"; do
            if echo "$line" | grep -qE "$pattern"; then
                # Skip if it's a comment or empty value
                if [[ ! "$line" =~ ^[[:space:]]*# ]] && \
                   [[ ! "$line" =~ =\s*['\"]?['\"]?[[:space:]]*$ ]] && \
                   [[ ! "$line" =~ =\s*['\"]?\[\] ]] && \
                   [[ ! "$line" =~ :\s*[|\[] ]]; then
                    echo "Potential hardcoded secret: $line"
                    found=1
                fi
            fi
        done
    done < "$file"

    return $found
}

# Check for required TOML sections
check_toml_required_sections() {
    local toml_file="$1"
    local missing=0

    # Required sections
    local sections=(
        "server"
        "providers"
        "failover"
    )

    for section in "${sections[@]}"; do
        if ! grep -q "^\[$section\]" "$toml_file"; then
            echo "Missing required section: [$section]"
            missing=1
        fi
    done

    return $missing
}

# Check for environment variable substitution
check_env_substitution() {
    local file="$1"
    local file_type="$2"  # "toml" or "yaml"

    if [[ "$file_type" == "toml" ]]; then
        # TOML style: ${ENV_VAR}
        if grep -q '\${[A-Z_][A-Z0-9_]*}' "$file"; then
            return 0
        fi
    else
        # YAML style: ${ENV_VAR}
        if grep -q '\${[A-Z_][A-Z0-9_]*}' "$file"; then
            return 0
        fi
    fi

    return 1
}

# ==============================================================================
# TEST CASES
# ==============================================================================

# Test 1: TOML syntax is valid
test_toml_syntax_valid() {
    test_start "TOML config should have valid syntax"

    if [[ ! -f "$TOML_CONFIG" ]]; then
        test_skip "Config file not found: $TOML_CONFIG"
        return
    fi

    local result
    result=$(validate_toml_syntax "$TOML_CONFIG")

    if [[ "$result" == "OK" ]]; then
        test_pass
    elif [[ "$result" == "SKIP"* ]]; then
        test_skip "python3 not available"
    else
        test_fail "Invalid TOML syntax: $result"
    fi
}

# Test 2: TOML has required fields
test_toml_required_fields() {
    test_start "TOML config should have required sections"

    if [[ ! -f "$TOML_CONFIG" ]]; then
        test_skip "Config file not found: $TOML_CONFIG"
        return
    fi

    local missing
    missing=$(check_toml_required_sections "$TOML_CONFIG")

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "Missing required sections: $missing"
    fi
}

# Test 3: docker-compose.yml has valid YAML syntax
test_yaml_syntax_valid() {
    test_start "docker-compose.yml should have valid YAML syntax"

    if [[ ! -f "$YAML_COMPOSE" ]]; then
        test_skip "docker-compose.yml not found: $YAML_COMPOSE"
        return
    fi

    local result
    result=$(validate_yaml_syntax "$YAML_COMPOSE")

    if [[ "$result" == "OK" ]]; then
        test_pass
    elif [[ "$result" == "SKIP"* ]]; then
        test_skip "python3 not available"
    else
        test_fail "Invalid YAML syntax: $result"
    fi
}

# Test 4: docker-compose.prod.yml has valid YAML syntax
test_yaml_prod_valid() {
    test_start "docker-compose.prod.yml should have valid YAML syntax"

    if [[ ! -f "$YAML_COMPOSE_PROD" ]]; then
        test_skip "docker-compose.prod.yml not found: $YAML_COMPOSE_PROD"
        return
    fi

    local result
    result=$(validate_yaml_syntax "$YAML_COMPOSE_PROD")

    if [[ "$result" == "OK" ]]; then
        test_pass
    elif [[ "$result" == "SKIP"* ]]; then
        test_skip "python3 not available"
    else
        test_fail "Invalid YAML syntax: $result"
    fi
}

# Test 5: Environment variable substitution is used
test_env_substitution() {
    test_start "Config files should use environment variable substitution"

    local found_toml=0
    local found_yaml=0

    if [[ -f "$TOML_CONFIG" ]]; then
        if check_env_substitution "$TOML_CONFIG" "toml"; then
            found_toml=1
            log_debug "Found env var substitution in $TOML_CONFIG"
        fi
    fi

    if [[ -f "$YAML_COMPOSE_PROD" ]]; then
        if check_env_substitution "$YAML_COMPOSE_PROD" "yaml"; then
            found_yaml=1
            log_debug "Found env var substitution in $YAML_COMPOSE_PROD"
        fi
    fi

    if [[ $found_toml -eq 1 ]] || [[ $found_yaml -eq 1 ]]; then
        test_pass
    else
        test_fail "No environment variable substitution found in config files"
    fi
}

# Test 6: No hardcoded secrets in configs
test_no_hardcoded_secrets() {
    test_start "Config files should not contain hardcoded secrets"

    local found_secrets=""

    if [[ -f "$TOML_CONFIG" ]]; then
        local secrets
        secrets=$(check_hardcoded_secrets "$TOML_CONFIG")
        if [[ -n "$secrets" ]]; then
            found_secrets="$found_secrets\n$TOML_CONFIG:\n$secrets"
        fi
    fi

    if [[ -f "$YAML_COMPOSE_PROD" ]]; then
        local secrets
        secrets=$(check_hardcoded_secrets "$YAML_COMPOSE_PROD")
        if [[ -n "$secrets" ]]; then
            found_secrets="$found_secrets\n$YAML_COMPOSE_PROD:\n$secrets"
        fi
    fi

    if [[ -z "$found_secrets" ]]; then
        test_pass
    else
        test_fail "Found potential hardcoded secrets:$found_secrets"
    fi
}

# Test 7: Specific TOML provider configurations exist
test_toml_provider_configs() {
    test_start "TOML should contain provider configurations"

    if [[ ! -f "$TOML_CONFIG" ]]; then
        test_skip "Config file not found: $TOML_CONFIG"
        return
    fi

    local missing=0

    # Check for at least one enabled provider
    if ! grep -qE '^\[providers\.(openai|anthropic|gemini|ollama)]' "$TOML_CONFIG"; then
        log_warn "No provider configuration found"
        missing=1
    fi

    # Check for failover section
    if ! grep -q '^\[failover]' "$TOML_CONFIG"; then
        log_warn "Missing [failover] section"
        missing=1
    fi

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "Missing required provider configurations"
    fi
}

# Test 8: YAML compose files have required services
test_yaml_required_services() {
    test_start "docker-compose files should define required services"

    local missing=0

    # Check main compose file
    if [[ -f "$YAML_COMPOSE" ]]; then
        if ! grep -q '^\s*moltis:' "$YAML_COMPOSE"; then
            log_warn "moltis service not defined in docker-compose.yml"
            missing=1
        fi
    fi

    # Check production compose file
    if [[ -f "$YAML_COMPOSE_PROD" ]]; then
        if ! grep -q '^\s*moltis:' "$YAML_COMPOSE_PROD"; then
            log_warn "moltis service not defined in docker-compose.prod.yml"
            missing=1
        fi
    fi

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "Missing required service definitions"
    fi
}

# Test 9: TOML server configuration is present
test_toml_server_config() {
    test_start "TOML should contain server configuration"

    if [[ ! -f "$TOML_CONFIG" ]]; then
        test_skip "Config file not found: $TOML_CONFIG"
        return
    fi

    local missing=0

    # Check for server section
    if ! grep -q '^\[server\]' "$TOML_CONFIG"; then
        log_warn "Missing [server] section"
        missing=1
    fi

    # Check for bind address
    if ! grep -q 'bind\s*=' "$TOML_CONFIG"; then
        log_warn "Missing server.bind configuration"
        missing=1
    fi

    # Check for port
    if ! grep -q 'port\s*=' "$TOML_CONFIG"; then
        log_warn "Missing server.port configuration"
        missing=1
    fi

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "Missing required server configuration"
    fi
}

# Test 10: Env var patterns follow proper format
test_env_var_format() {
    test_start "Environment variables should use proper format \${VAR_NAME}"

    if [[ ! -f "$TOML_CONFIG" ]]; then
        test_skip "Config file not found: $TOML_CONFIG"
        return
    fi

    # Check for proper ${VAR} format (not $VAR alone)
    local improper=0

    # Look for bare $VAR without braces (potential error)
    if grep -qE '\$[A-Z_][A-Z0-9_]*[^{a-zA-Z0-9_]' "$TOML_CONFIG"; then
        # Exclude proper ${VAR} patterns
        local bad_patterns
        bad_patterns=$(grep -E '\$[A-Z_][A-Z0-9_]*[^{a-zA-Z0-9_]' "$TOML_CONFIG" | grep -v '\${' || true)
        if [[ -n "$bad_patterns" ]]; then
            log_warn "Found improper env var format (use \${VAR}): $bad_patterns"
            improper=1
        fi
    fi

    if [[ $improper -eq 0 ]]; then
        test_pass
    else
        test_fail "Environment variables should use \${VAR_NAME} format"
    fi
}

# ==============================================================================
# TEST RUNNER
# ==============================================================================

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Configuration Validation Unit Tests"
        echo "========================================="
        echo ""
    fi

    # Run all tests
    test_toml_syntax_valid
    test_toml_required_fields
    test_yaml_syntax_valid
    test_yaml_prod_valid
    test_env_substitution
    test_no_hardcoded_secrets
    test_toml_provider_configs
    test_yaml_required_services
    test_toml_server_config
    test_env_var_format

    # Generate report
    generate_report
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
