#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STANDALONE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$STANDALONE_ROOT/tests/lib/core.sh"

BOOTSTRAP_SCRIPT="$STANDALONE_ROOT/install/bootstrap.sh"
REGISTER_SCRIPT="$STANDALONE_ROOT/install/register.sh"
VERIFY_SCRIPT="$STANDALONE_ROOT/install/verify.sh"

run_opencode_adapter_tests() {
    start_timer

    local temp_root host_target register_output
    temp_root="$(mktemp -d /tmp/worktree-skill-opencode.XXXXXX)"
    trap 'rm -rf "$temp_root"' EXIT
    host_target="$temp_root/host"
    mkdir -p "$host_target"

    "$BOOTSTRAP_SCRIPT" --target "$host_target" --adapter opencode >/dev/null
    "$VERIFY_SCRIPT" --target "$host_target" --adapter opencode >/dev/null
    register_output="$("$REGISTER_SCRIPT" --target "$host_target" --adapter opencode)"

    test_start "opencode_adapter_bootstrap_installs_manual_registration_artifact"
    assert_file_exists "$host_target/register-example.md" "OpenCode bootstrap should materialize the manual registration template"
    assert_file_contains "$host_target/register-example.md" "OpenCode Registration Example" "OpenCode registration template should contain the expected heading"
    test_pass

    test_start "opencode_adapter_register_reports_manual_fallback"
    assert_contains "$register_output" "register-example.md" "OpenCode registration should point the user at the manual registration example"
    test_pass

    generate_report
    trap - EXIT
    rm -rf "$temp_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_opencode_adapter_tests
fi
