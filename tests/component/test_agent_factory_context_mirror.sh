#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MIRROR_DOC="$PROJECT_ROOT/docs/ASC-AI-FABRIQUE-MIRROR.md"
QUICKSTART_DOC="$PROJECT_ROOT/specs/020-agent-factory-prototype/quickstart.md"

require_path_refs_exist() {
    local source_file="$1"
    local refs
    mapfile -t refs < <(rg -o 'docs/[A-Za-z0-9А-Яа-яЁё_./ ()-]+\.(md|bpmn)|specs/[A-Za-z0-9А-Яа-яЁё_./ ()-]+\.(md)' "$source_file" | sort -u)
    local ref
    for ref in "${refs[@]}"; do
        assert_file_exists "$PROJECT_ROOT/$ref" "Referenced path should exist: $ref"
    done
}

run_component_agent_factory_context_mirror_tests() {
    start_timer
    require_commands_or_skip rg || {
        test_start "component_agent_factory_context_mirror_prereqs"
        test_skip "rg is required"
        generate_report
        return
    }

    test_start "component_agent_factory_context_mirror_has_required_navigation"
    if [[ -f "$MIRROR_DOC" && -f "$QUICKSTART_DOC" ]]
    then
        assert_contains "$(cat "$MIRROR_DOC")" "Upstream Repository" "Mirror doc should keep upstream provenance"
        assert_contains "$(cat "$MIRROR_DOC")" "Verified Upstream Commit" "Mirror doc should pin the verified upstream commit"
        assert_contains "$(cat "$MIRROR_DOC")" "docs/asc-roadmap/INDEX.md" "Mirror doc should point to roadmap entrypoint"
        assert_contains "$(cat "$MIRROR_DOC")" "docs/concept/INDEX.md" "Mirror doc should point to concept entrypoint"
        assert_contains "$(cat "$MIRROR_DOC")" "specs/020-agent-factory-prototype/spec.md" "Mirror doc should point to the active spec package"
        assert_contains "$(cat "$MIRROR_DOC")" "config/fleet/agents-registry.json" "Mirror doc should point to platform contracts"
        assert_contains "$(cat "$QUICKSTART_DOC")" "docs/ASC-AI-FABRIQUE-MIRROR.md" "Quickstart should point back to the mirror index"
        assert_contains "$(cat "$QUICKSTART_DOC")" "docs/plans/agent-factory-lifecycle.md" "Quickstart should point to local lifecycle planning"
        test_pass
    else
        test_fail "Mirror and quickstart docs should exist"
    fi

    test_start "component_agent_factory_context_mirror_uses_repo_paths_only"
    if ! rg -n '/Users/|file://|vscode://' "$MIRROR_DOC" "$QUICKSTART_DOC" >/dev/null
    then
        test_pass
    else
        test_fail "Mirror navigation should rely on repo paths only"
    fi

    test_start "component_agent_factory_context_mirror_referenced_paths_exist"
    if require_path_refs_exist "$MIRROR_DOC" && require_path_refs_exist "$QUICKSTART_DOC"
    then
        test_pass
    else
        test_fail "All referenced mirror and quickstart paths should exist"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_context_mirror_tests
fi
