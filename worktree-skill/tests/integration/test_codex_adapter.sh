#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STANDALONE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$STANDALONE_ROOT/tests/lib/core.sh"

BOOTSTRAP_SCRIPT="$STANDALONE_ROOT/install/bootstrap.sh"
REGISTER_SCRIPT="$STANDALONE_ROOT/install/register.sh"

run_codex_adapter_tests() {
    start_timer

    local temp_root host_target codex_home bridge_root
    temp_root="$(mktemp -d /tmp/worktree-skill-codex.XXXXXX)"
    trap 'rm -rf "$temp_root"' EXIT
    host_target="$temp_root/host"
    codex_home="$temp_root/codex-home"
    mkdir -p "$host_target" "$codex_home"

    "$BOOTSTRAP_SCRIPT" --target "$host_target" --adapter codex-cli >/dev/null
    CODEX_HOME="$codex_home" "$REGISTER_SCRIPT" --target "$host_target" --adapter codex-cli >/dev/null

    bridge_root="$codex_home/skills/worktree-skill-codex"

    test_start "codex_adapter_register_installs_expected_bridge_files"
    assert_dir_exists "$bridge_root" "Codex bridge directory should exist"
    assert_file_exists "$bridge_root/worktree.md" "Codex bridge should install worktree command"
    assert_file_exists "$bridge_root/session-summary.md" "Codex bridge should install session-summary command"
    assert_file_exists "$bridge_root/git-topology.md" "Codex bridge should install git-topology command"
    test_pass

    test_start "codex_adapter_bridge_preserves_portable_worktree_content"
    assert_file_contains "$bridge_root/worktree.md" "# Worktree Command" "Codex bridge worktree file should preserve portable command content"
    assert_file_contains "$bridge_root/git-topology.md" "# Git Topology Command" "Codex bridge topology file should preserve portable topology command content"
    test_pass

    generate_report
    trap - EXIT
    rm -rf "$temp_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_codex_adapter_tests
fi
