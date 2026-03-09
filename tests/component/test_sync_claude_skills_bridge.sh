#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-claude-skills-to-codex.sh"

run_component_sync_claude_skills_bridge_tests() {
    start_timer

    local temp_root codex_home command_skill agent_skill
    temp_root="$(mktemp -d)"
    trap 'rm -rf "$temp_root"' EXIT
    codex_home="$temp_root/codex-home"
    mkdir -p "$codex_home"

    CODEX_HOME="$codex_home" "$SYNC_SCRIPT" --install >/dev/null

    command_skill="$codex_home/skills/claude-bridge/commands/command-beads-init/SKILL.md"
    agent_skill="$codex_home/skills/claude-bridge/agents/agent-meta-workers-session-summarizer/SKILL.md"

    test_start "component_sync_claude_skills_bridge_installs_generated_command_and_agent_skills"
    assert_file_exists "$command_skill" "Generated command bridge skill should exist"
    assert_file_exists "$agent_skill" "Generated agent bridge skill should exist"
    test_pass

    test_start "component_sync_claude_skills_bridge_bundles_source_content"
    assert_file_contains "$command_skill" "## Bundled Source Artifact" "Command bridge should embed bundled source section"
    assert_file_contains "$command_skill" 'Origin path: `.claude/commands/beads-init.md`' "Command bridge should record origin path"
    assert_file_contains "$command_skill" "# Beads Initialization" "Command bridge should embed original command content"
    assert_file_contains "$agent_skill" "Maintains SESSION_SUMMARY.md with current session progress and context." "Agent bridge should embed original agent content"
    test_pass

    test_start "component_sync_claude_skills_bridge_avoids_repo_relative_read_instruction"
    if grep -Fq 'Read the source artifact at `.claude/' "$command_skill"; then
        test_fail "Generated bridge should not require reading a repo-relative .claude path from global CODEX_HOME"
    else
        test_pass
    fi

    generate_report
    trap - EXIT
    rm -rf "$temp_root"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_sync_claude_skills_bridge_tests
fi
