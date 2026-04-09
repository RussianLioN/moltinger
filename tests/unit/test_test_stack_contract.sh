#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

COMPOSE_TEST_FILE="$PROJECT_ROOT/compose.test.yml"
DOCKERFILE_RUNNER="$PROJECT_ROOT/tests/Dockerfile.runner"
TEST_WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"
PACKAGE_JSON="$PROJECT_ROOT/package.json"
PACKAGE_LOCK="$PROJECT_ROOT/package-lock.json"

extract_dockerfile_playwright_version() {
    awk -F= '/^ARG PLAYWRIGHT_VERSION=/{print $2}' "$DOCKERFILE_RUNNER"
}

run_unit_test_stack_contract_tests() {
    start_timer

    test_start "unit_test_stack_contract_masks_workspace_node_modules"

    if [[ ! -f "$COMPOSE_TEST_FILE" ]]; then
        test_skip "Missing compose fixture stack: $COMPOSE_TEST_FILE"
    elif ! grep -Fq '/workspace/node_modules' "$COMPOSE_TEST_FILE"; then
        test_fail "compose.test.yml must mask /workspace/node_modules to keep the hermetic runner isolated from host packages"
    else
        test_pass
    fi

    test_start "unit_test_stack_contract_uses_locked_npm_install_in_ci"

    if [[ ! -f "$TEST_WORKFLOW" || ! -f "$PACKAGE_LOCK" ]]; then
        test_skip "Workflow or package-lock.json missing"
    elif ! grep -Fq 'cache-dependency-path: package-lock.json' "$TEST_WORKFLOW" || \
         ! grep -Fq 'run: npm ci --no-fund --no-audit' "$TEST_WORKFLOW"; then
        test_fail "CI workflow must use package-lock.json with npm ci"
    else
        test_pass
    fi

    test_start "unit_test_stack_contract_pins_playwright_versions_consistently"

    if [[ ! -f "$PACKAGE_JSON" || ! -f "$DOCKERFILE_RUNNER" || ! -f "$PACKAGE_LOCK" ]]; then
        test_skip "Package or Dockerfile contract files missing"
    else
        local package_playwright package_test dockerfile_playwright lock_playwright
        package_playwright="$(jq -r '.devDependencies.playwright // empty' "$PACKAGE_JSON")"
        package_test="$(jq -r '.devDependencies["@playwright/test"] // empty' "$PACKAGE_JSON")"
        dockerfile_playwright="$(extract_dockerfile_playwright_version)"
        lock_playwright="$(jq -r '.packages["node_modules/playwright"].version // empty' "$PACKAGE_LOCK")"

        if [[ -z "$package_playwright" || -z "$package_test" || -z "$dockerfile_playwright" || -z "$lock_playwright" ]]; then
            test_fail "Playwright versions must be explicitly pinned in package.json, package-lock.json, and tests/Dockerfile.runner"
        elif [[ "$package_playwright" != "$package_test" || "$package_playwright" != "$dockerfile_playwright" || "$package_playwright" != "$lock_playwright" ]]; then
            test_fail "Playwright versions drifted across package.json, package-lock.json, or tests/Dockerfile.runner"
        else
            test_pass
        fi
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_unit_test_stack_contract_tests
fi
