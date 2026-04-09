#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

MEMPALACE_COMMON_SCRIPT="$PROJECT_ROOT/scripts/mempalace-common.sh"
MEMPALACE_BOOTSTRAP_SCRIPT="$PROJECT_ROOT/scripts/mempalace-bootstrap.sh"
MEMPALACE_DOC="$PROJECT_ROOT/docs/MEMPALACE-PROJECT-MEMORY.md"
SHARED_CORE_INSTRUCTIONS="$PROJECT_ROOT/.ai/instructions/shared-core.md"
ROOT_AGENTS="$PROJECT_ROOT/AGENTS.md"
CLAUDE_SETTINGS="$PROJECT_ROOT/.claude/settings.json"
MCP_CONFIG_FILE="$PROJECT_ROOT/.mcp.json"

setup_unit_mempalace_project_memory() {
    require_commands_or_skip bash jq mktemp cat mkdir rm grep sort || return 2
    return 0
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-string should not contain substring}"
    if [[ "$haystack" == *"$needle"* ]]; then
        test_fail "$message (needle: '$needle')"
        return 0
    fi
    return 0
}

run_unit_mempalace_project_memory_tests() {
    start_timer

    local setup_code=0
    set +e
    setup_unit_mempalace_project_memory
    setup_code=$?
    set -e
    if [[ $setup_code -ne 0 ]]; then
        generate_report
        return
    fi

    test_start "unit_mempalace_corpus_manifest_filters_only_allowed_paths"

    local fixture_root output
    fixture_root="$(secure_temp_dir mempalace-corpus)"
    mkdir -p "$fixture_root/docs" "$fixture_root/knowledge" "$fixture_root/specs/demo" "$fixture_root/config"
    printf '# Memory\n' > "$fixture_root/MEMORY.md"
    printf '# Session\n' > "$fixture_root/SESSION_SUMMARY.md"
    printf '# Doc\n' > "$fixture_root/docs/guide.md"
    printf '# Topology\n' > "$fixture_root/docs/GIT-TOPOLOGY-REGISTRY.md"
    printf 'skip me\n' > "$fixture_root/docs/guide.txt"
    printf '# Knowledge\n' > "$fixture_root/knowledge/note.md"
    printf '# Spec\n' > "$fixture_root/specs/demo/spec.md"
    printf '# Plan\n' > "$fixture_root/specs/demo/plan.md"
    printf '# Tasks\n' > "$fixture_root/specs/demo/tasks.md"
    printf '# Extra\n' > "$fixture_root/specs/demo/extra.md"
    printf 'SECRET=1\n' > "$fixture_root/.env"
    printf 'sensitive\n' > "$fixture_root/config/provider_keys.json"

    output="$(
        MEMPALACE_PROJECT_ROOT_OVERRIDE="$fixture_root" \
        MEMPALACE_CORPUS_MANIFEST_OVERRIDE="$PROJECT_ROOT/scripts/mempalace-corpus.txt" \
        bash -c 'source "$1"; collect_curated_corpus_paths' _ "$MEMPALACE_COMMON_SCRIPT"
    )"

    assert_contains "$output" 'MEMORY.md' "Curated corpus must include MEMORY.md"
    assert_contains "$output" 'SESSION_SUMMARY.md' "Curated corpus must include SESSION_SUMMARY.md"
    assert_contains "$output" 'docs/guide.md' "Curated corpus must include markdown docs"
    assert_contains "$output" 'knowledge/note.md' "Curated corpus must include knowledge notes"
    assert_contains "$output" 'specs/demo/spec.md' "Curated corpus must include spec artifacts"
    assert_contains "$output" 'specs/demo/plan.md' "Curated corpus must include plan artifacts"
    assert_contains "$output" 'specs/demo/tasks.md' "Curated corpus must include task artifacts"
    assert_not_contains "$output" 'docs/GIT-TOPOLOGY-REGISTRY.md' "Curated corpus must exclude topology registry"
    assert_not_contains "$output" '.env' "Curated corpus must exclude secrets"
    assert_not_contains "$output" 'config/provider_keys.json' "Curated corpus must exclude provider keys"
    assert_not_contains "$output" 'docs/guide.txt' "Curated corpus must include markdown docs only"
    assert_not_contains "$output" 'specs/demo/extra.md' "Curated corpus must exclude non-canonical spec artifacts"
    rm -rf "$fixture_root"
    test_pass

    test_start "unit_mempalace_wrapper_pins_version_and_state_root"
    if grep -Fq 'MEMPALACE_VERSION="${MEMPALACE_VERSION_OVERRIDE:-3.0.0}"' "$MEMPALACE_COMMON_SCRIPT" && \
       grep -Fq '.local/share}/moltinger/mempalace' "$MEMPALACE_COMMON_SCRIPT" && \
       grep -Fq 'pip install --disable-pip-version-check --upgrade "mempalace==${MEMPALACE_VERSION}"' "$MEMPALACE_BOOTSTRAP_SCRIPT" && \
       grep -Fq 'init "$MEMPALACE_CORPUS_DIR" --yes' "$PROJECT_ROOT/scripts/mempalace-refresh.sh"; then
        test_pass
    else
        test_fail "MemPalace wrapper must pin version 3.0.0, use the repo-managed state root, and follow init -> mine"
    fi

    test_start "unit_mempalace_memory_protocol_is_documented_and_not_hooked_by_default"
    if grep -Fq 'Treat MemPalace as search/index only' "$SHARED_CORE_INSTRUCTIONS" && \
       grep -Fq 'Treat MemPalace as search/index only' "$ROOT_AGENTS" && \
       grep -Fq 'Experimental Hooks (Opt-In, Unsupported)' "$MEMPALACE_DOC" && \
       ! grep -qi 'mempalace' "$CLAUDE_SETTINGS"; then
        test_pass
    else
        test_fail "MemPalace memory protocol must be documented while repo default hooks stay disabled"
    fi

    test_start "unit_mempalace_mcp_entry_uses_repo_wrapper"
    if [[ -x "$PROJECT_ROOT/scripts/mempalace-mcp-server.sh" ]] && \
       jq -e '.mcpServers.mempalace.command == "./scripts/mempalace-mcp-server.sh"' "$MCP_CONFIG_FILE" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "MemPalace MCP entry must use the repo-managed wrapper script"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_unit_mempalace_project_memory_tests
fi
