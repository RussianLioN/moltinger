#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

PLAYGROUND_SCRIPT="$PROJECT_ROOT/scripts/agent-factory-playground.py"
FIXTURE_FILE="$PROJECT_ROOT/tests/fixtures/agent-factory/swarm-evidence.json"

run_component_agent_factory_playground_tests() {
    start_timer
    require_commands_or_skip python3 jq tar || {
        test_start "component_agent_factory_playground_prereqs"
        test_skip "python3, jq, and tar are required"
        generate_report
        return
    }

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    test_start "component_agent_factory_playground_packages_fixture_bundle"
    if python3 "$PLAYGROUND_SCRIPT" package --swarm-run "$FIXTURE_FILE" --output-dir "$tmpdir/playground" --output "$tmpdir/playground.json" >/dev/null
    then
        assert_eq "packaged" "$(jq -r '.status' "$tmpdir/playground.json")" "Playground packaging status should be packaged"
        assert_eq "synthetic" "$(jq -r '.playground_package.data_profile' "$tmpdir/playground.json")" "Playground must remain synthetic-data only"
        assert_eq "ready_for_demo" "$(jq -r '.playground_package.review_status' "$tmpdir/playground.json")" "Fixture playground should remain ready_for_demo"
        assert_file_exists "$(jq -r '.files.dockerfile_ref' "$tmpdir/playground.json")" "Dockerfile should exist"
        assert_file_exists "$(jq -r '.files.server_ref' "$tmpdir/playground.json")" "Playground server source should exist"
        assert_file_exists "$(jq -r '.files.dataset_ref' "$tmpdir/playground.json")" "Synthetic dataset should exist"
        assert_file_exists "$(jq -r '.files.manifest_ref' "$tmpdir/playground.json")" "Playground manifest should exist"
        assert_file_exists "$(jq -r '.files.archive_ref' "$tmpdir/playground.json")" "Playground archive should exist"
        test_pass
    else
        test_fail "Playground packager should build a runnable bundle from the swarm fixture"
    fi

    test_start "component_agent_factory_playground_archive_is_readable"
    if tar -tzf "$(jq -r '.files.archive_ref' "$tmpdir/playground.json")" >/dev/null 2>&1
    then
        assert_contains "$(tar -tzf "$(jq -r '.files.archive_ref' "$tmpdir/playground.json")")" "playground-bundle/Dockerfile" "Archive should contain the Dockerfile"
        assert_contains "$(tar -tzf "$(jq -r '.files.archive_ref' "$tmpdir/playground.json")")" "playground-bundle/playground-package.json" "Archive should contain the package manifest"
        test_pass
    else
        test_fail "Playground archive should be readable"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_agent_factory_playground_tests
fi
