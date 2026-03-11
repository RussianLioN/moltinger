#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STANDALONE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$STANDALONE_ROOT/tests/lib/core.sh"

BOOTSTRAP_SCRIPT="$STANDALONE_ROOT/install/bootstrap.sh"
VERIFY_SCRIPT="$STANDALONE_ROOT/install/verify.sh"

run_speckit_bridge_tests() {
    start_timer

    local temp_root host_target spec_dir before_spec before_plan before_tasks
    temp_root="$(mktemp -d /tmp/worktree-skill-speckit.XXXXXX)"
    trap 'rm -rf "$temp_root"' EXIT
    host_target="$temp_root/host"
    spec_dir="$host_target/specs/011-demo"

    mkdir -p "$spec_dir"
    printf '# spec\n' > "$spec_dir/spec.md"
    printf '# plan\n' > "$spec_dir/plan.md"
    printf '# tasks\n' > "$spec_dir/tasks.md"
    before_spec="$(cat "$spec_dir/spec.md")"
    before_plan="$(cat "$spec_dir/plan.md")"
    before_tasks="$(cat "$spec_dir/tasks.md")"

    "$BOOTSTRAP_SCRIPT" --target "$host_target" --adapter claude-code --with-speckit >/dev/null
    "$VERIFY_SCRIPT" --target "$host_target" --adapter claude-code --with-speckit >/dev/null

    test_start "speckit_bridge_bootstrap_preserves_existing_spec_artifacts"
    assert_eq "$before_spec" "$(cat "$spec_dir/spec.md")" "Speckit bridge install should not rewrite spec.md"
    assert_eq "$before_plan" "$(cat "$spec_dir/plan.md")" "Speckit bridge install should not rewrite plan.md"
    assert_eq "$before_tasks" "$(cat "$spec_dir/tasks.md")" "Speckit bridge install should not rewrite tasks.md"
    test_pass

    test_start "speckit_bridge_installs_compatibility_docs"
    assert_dir_exists "$host_target/bridge/speckit" "Speckit bridge directory should exist"
    assert_file_exists "$host_target/bridge/speckit/README.md" "Speckit bridge README should exist"
    assert_file_contains "$host_target/bridge/speckit/README.md" "/speckit.spec" "Speckit bridge README should document non-interference with Speckit commands"
    test_pass

    generate_report
    trap - EXIT
    rm -rf "$temp_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_speckit_bridge_tests
fi
