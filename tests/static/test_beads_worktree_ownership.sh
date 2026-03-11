#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ENVRC_FILE="$PROJECT_ROOT/.envrc"
BD_SHIM="$PROJECT_ROOT/bin/bd"
RESOLVE_SCRIPT="$PROJECT_ROOT/scripts/beads-resolve-db.sh"
LOCALIZE_SCRIPT="$PROJECT_ROOT/scripts/beads-worktree-localize.sh"
CODEX_LAUNCHER="$PROJECT_ROOT/scripts/codex-profile-launch.sh"
WORKTREE_READY_SCRIPT="$PROJECT_ROOT/scripts/worktree-ready.sh"
WORKTREE_PHASE_A_SCRIPT="$PROJECT_ROOT/scripts/worktree-phase-a.sh"
QUICKSTART_RU="$PROJECT_ROOT/.claude/docs/beads-quickstart.md"
QUICKSTART_EN="$PROJECT_ROOT/.claude/docs/beads-quickstart.en.md"
BEADS_SKILL="$PROJECT_ROOT/.claude/skills/beads/SKILL.md"
BEADS_COMMAND_QUICKREF="$PROJECT_ROOT/.claude/skills/beads/resources/COMMANDS_QUICKREF.md"
BEADS_WORKFLOWS="$PROJECT_ROOT/.claude/skills/beads/resources/WORKFLOWS.md"

run_static_beads_worktree_ownership_tests() {
    start_timer

    test_start "static_envrc_bootstraps_repo_local_plain_bd"
    if rg -q 'git rev-parse --show-toplevel' "$ENVRC_FILE" && \
       rg -q 'export PATH="\$\{repo_root\}/bin:\$\{PATH\}"' "$ENVRC_FILE"; then
        test_pass
    else
        test_fail ".envrc must prepend the repo-local bin directory for plain bd"
    fi

    test_start "static_bd_shim_uses_explicit_local_db_dispatch"
    if [[ -x "$BD_SHIM" ]] && \
       rg -q 'source "\$\{REPO_ROOT\}/scripts/beads-resolve-db\.sh"' "$BD_SHIM" && \
       rg -q 'exec "\$\{SYSTEM_BD\}" --db "\$\{BEADS_RESOLVE_DB_PATH\}" "\$@"' "$BD_SHIM"; then
        test_pass
    else
        test_fail "bin/bd must source the resolver and dispatch via explicit --db"
    fi

    test_start "static_resolver_blocks_legacy_redirect_and_root_fallback"
    if [[ -x "$RESOLVE_SCRIPT" ]] && \
       rg -q 'block_legacy_redirect' "$RESOLVE_SCRIPT" && \
       rg -q 'block_root_fallback' "$RESOLVE_SCRIPT" && \
       rg -q 'beads-worktree-localize\.sh' "$RESOLVE_SCRIPT"; then
        test_pass
    else
        test_fail "The resolver must fail closed on legacy redirect and root fallback states"
    fi

    test_start "static_localize_helper_exists_for_compatibility_migration"
    if [[ -x "$LOCALIZE_SCRIPT" ]] && \
       rg -q 'migratable_legacy' "$LOCALIZE_SCRIPT" && \
       rg -q 'partial_foundation' "$LOCALIZE_SCRIPT"; then
        test_pass
    else
        test_fail "The repo must provide a managed compatibility localization helper"
    fi

    test_start "static_codex_launcher_bootstraps_repo_local_plain_bd"
    if rg -q 'export PATH="\$\{REPO_ROOT\}/bin:\$\{PATH\}"' "$CODEX_LAUNCHER"; then
        test_pass
    else
        test_fail "Codex launcher must prepend the repo-local bin directory"
    fi

    test_start "static_worktree_helpers_bootstrap_plain_bd_and_avoid_raw_create_fallback"
    if rg -q 'build_plain_bd_bootstrap_command_for_path' "$WORKTREE_READY_SCRIPT" && \
       rg -q 'git -C "\$\{canonical_root\}" worktree add "\$\{target_path\}" "\$\{branch\}"' "$WORKTREE_PHASE_A_SCRIPT" && \
       ! rg -q '"\$\{bd_command\}" worktree create' "$WORKTREE_PHASE_A_SCRIPT" && \
       ! rg -q 'add_next_step "bd worktree create' "$WORKTREE_READY_SCRIPT"; then
        test_pass
    else
        test_fail "Managed worktree helpers must bootstrap plain bd while keeping Phase A off raw bd worktree create"
    fi

    test_start "static_high_traffic_docs_do_not_reintroduce_wrapper_choice"
    if rg -q 'plain `bd`' "$QUICKSTART_RU" && \
       rg -q 'plain `bd`' "$QUICKSTART_EN" && \
       rg -q 'plain `bd`' "$BEADS_SKILL" && \
       ! rg -q 'bd-local' "$QUICKSTART_RU" "$QUICKSTART_EN" "$BEADS_SKILL" "$BEADS_COMMAND_QUICKREF" "$BEADS_WORKFLOWS"; then
        test_pass
    else
        test_fail "High-traffic Beads docs must use the plain bd contract without wrapper-choice drift"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_static_beads_worktree_ownership_tests
fi
