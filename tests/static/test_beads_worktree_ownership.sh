#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ENVRC_FILE="$PROJECT_ROOT/.envrc"
BD_SHIM="$PROJECT_ROOT/bin/bd"
RESOLVE_SCRIPT="$PROJECT_ROOT/scripts/beads-resolve-db.sh"
LOCALIZE_SCRIPT="$PROJECT_ROOT/scripts/beads-worktree-localize.sh"
AUDIT_SCRIPT="$PROJECT_ROOT/scripts/beads-worktree-audit.sh"
NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/beads-normalize-issues-jsonl.sh"
CODEX_LAUNCHER="$PROJECT_ROOT/scripts/codex-profile-launch.sh"
WORKTREE_READY_SCRIPT="$PROJECT_ROOT/scripts/worktree-ready.sh"
WORKTREE_PHASE_A_SCRIPT="$PROJECT_ROOT/scripts/worktree-phase-a.sh"
HOOK_BOOTSTRAP="$PROJECT_ROOT/.githooks/_repo-local-path.sh"
HOOK_PRE_COMMIT="$PROJECT_ROOT/.githooks/pre-commit"
HOOK_POST_CHECKOUT="$PROJECT_ROOT/.githooks/post-checkout"
HOOK_POST_MERGE="$PROJECT_ROOT/.githooks/post-merge"
HOOK_PRE_PUSH="$PROJECT_ROOT/.githooks/pre-push"
QUICKSTART_RU="$PROJECT_ROOT/.claude/docs/beads-quickstart.md"
QUICKSTART_EN="$PROJECT_ROOT/.claude/docs/beads-quickstart.en.md"
BEADS_SKILL="$PROJECT_ROOT/.claude/skills/beads/SKILL.md"
BEADS_COMMAND_QUICKREF="$PROJECT_ROOT/.claude/skills/beads/resources/COMMANDS_QUICKREF.md"
BEADS_WORKFLOWS="$PROJECT_ROOT/.claude/skills/beads/resources/WORKFLOWS.md"
SESSION_SUMMARIZER_DOC="$PROJECT_ROOT/.claude/agents/meta/workers/session-summarizer.md"
BEADS_INIT_COMMAND="$PROJECT_ROOT/.claude/commands/beads-init.md"
SPECKIT_TOBEADS_COMMAND="$PROJECT_ROOT/.claude/commands/speckit.tobeads.md"
DEPS_HEALTH_SKILL="$PROJECT_ROOT/.claude/skills/deps-health-inline/SKILL.md"
CLEANUP_HEALTH_SKILL="$PROJECT_ROOT/.claude/skills/cleanup-health-inline/SKILL.md"
REUSE_HEALTH_SKILL="$PROJECT_ROOT/.claude/skills/reuse-health-inline/SKILL.md"
SECURITY_HEALTH_SKILL="$PROJECT_ROOT/.claude/skills/security-health-inline/SKILL.md"
HEALTH_BUGS_SKILL="$PROJECT_ROOT/.claude/skills/health-bugs/SKILL.md"
WORKTREE_COMMAND="$PROJECT_ROOT/.claude/commands/worktree.md"
SHARED_CORE_INSTRUCTIONS="$PROJECT_ROOT/.ai/instructions/shared-core.md"
ROOT_AGENTS="$PROJECT_ROOT/AGENTS.md"
CLAUDE_DOC="$PROJECT_ROOT/CLAUDE.md"
BEADS_STATE_AGENTS="$PROJECT_ROOT/.beads/AGENTS.md"
BEADS_STATE_CONFIG="$PROJECT_ROOT/.beads/config.yaml"
WORKTREE_HOTFIX_PLAYBOOK="$PROJECT_ROOT/docs/WORKTREE-HOTFIX-PLAYBOOK.md"

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

    test_start "static_resolver_blocks_legacy_redirect_root_fallback_and_root_mutation"
    if [[ -x "$RESOLVE_SCRIPT" ]] && \
       rg -q 'block_legacy_redirect' "$RESOLVE_SCRIPT" && \
       rg -q 'block_root_fallback' "$RESOLVE_SCRIPT" && \
       rg -q 'block_root_mutation' "$RESOLVE_SCRIPT" && \
       rg -q 'pass_through_root_readonly' "$RESOLVE_SCRIPT" && \
       rg -q 'beads-worktree-localize\.sh' "$RESOLVE_SCRIPT"; then
        test_pass
    else
        test_fail "The resolver must fail closed on legacy redirect, root fallback, and default canonical-root mutation states"
    fi

    test_start "static_localize_helper_exists_for_compatibility_migration"
    if [[ -x "$LOCALIZE_SCRIPT" ]] && \
       rg -q 'migratable_legacy' "$LOCALIZE_SCRIPT" && \
       rg -q 'partial_foundation' "$LOCALIZE_SCRIPT" && \
       rg -q 'post_migration_runtime_only' "$LOCALIZE_SCRIPT" && \
       rg -q 'bootstrap_required' "$LOCALIZE_SCRIPT" && \
       rg -q '"\$\{system_bd\}" bootstrap' "$LOCALIZE_SCRIPT" && \
       rg -q '"\$\{system_bd\}" --db "\$\{report_db_path\}" import "\$\{beads_dir\}/issues\.jsonl"' "$LOCALIZE_SCRIPT" && \
       rg -q -- '--bootstrap-source' "$LOCALIZE_SCRIPT"; then
        test_pass
    else
        test_fail "The repo must provide a managed compatibility localization helper"
    fi

    test_start "static_audit_helper_exists_for_canonical_root_enforcement"
    if [[ -x "$AUDIT_SCRIPT" ]] && \
       rg -q 'worktree list --porcelain' "$AUDIT_SCRIPT" && \
       rg -q 'migratable_legacy' "$AUDIT_SCRIPT" && \
       rg -q 'partial_foundation' "$AUDIT_SCRIPT" && \
       rg -q 'post_migration_runtime_only' "$AUDIT_SCRIPT" && \
       rg -q 'Non-canonical worktree' "$AUDIT_SCRIPT"; then
        test_pass
    else
        test_fail "The repo must provide a canonical-root sibling ownership audit helper"
    fi

    test_start "static_root_instructions_define_post_migration_runtime_repair_protocol"
    if rg -q -F 'Do not treat a missing tracked `.beads/issues.jsonl` as proof that the Beads backlog is unavailable' "$SHARED_CORE_INSTRUCTIONS" "$ROOT_AGENTS" && \
       rg -q -F 'Treat `config + local runtime + no tracked .beads/issues.jsonl` as the expected post-migration local-runtime state' "$SHARED_CORE_INSTRUCTIONS" "$ROOT_AGENTS" && \
       rg -q -F 'local Beads repair problem' "$SHARED_CORE_INSTRUCTIONS" "$ROOT_AGENTS" && \
       rg -q -F 'bd status' "$SHARED_CORE_INSTRUCTIONS" "$ROOT_AGENTS"; then
        test_pass
    else
        test_fail "Root instructions must define the post-migration local-runtime state and repair protocol explicitly"
    fi

    test_start "static_root_instructions_do_not_reference_absent_migration_scripts"
    if [[ ! -f "$PROJECT_ROOT/scripts/beads-dolt-pilot.sh" && ! -f "$PROJECT_ROOT/scripts/beads-dolt-rollout.sh" ]]; then
        if ! rg -q 'beads-dolt-pilot\.sh|beads-dolt-rollout\.sh|pilot-mode\.json|cutover-mode\.json' "$SHARED_CORE_INSTRUCTIONS" "$ROOT_AGENTS" "$PROJECT_ROOT/docs/CODEX-OPERATING-MODEL.md"; then
            test_pass
        else
            test_fail "Ordinary source branches must not reference absent Beads migration scripts or mode markers"
        fi
    else
        test_pass
    fi

    test_start "static_active_instruction_surfaces_retire_bd_sync_guidance"
    if ! rg -q 'bd sync' "$CLAUDE_DOC" "$BEADS_STATE_AGENTS" "$BEADS_STATE_CONFIG" && \
       ! rg -q 'bd sync' "$QUICKSTART_RU" "$QUICKSTART_EN" "$BEADS_COMMAND_QUICKREF" "$BEADS_WORKFLOWS" && \
       ! rg -q 'bd sync' "$SESSION_SUMMARIZER_DOC" "$BEADS_INIT_COMMAND" "$SPECKIT_TOBEADS_COMMAND" "$WORKTREE_HOTFIX_PLAYBOOK" && \
       ! rg -q 'bd sync' "$DEPS_HEALTH_SKILL" "$CLEANUP_HEALTH_SKILL" "$REUSE_HEALTH_SKILL" "$SECURITY_HEALTH_SKILL" "$HEALTH_BUGS_SKILL" && \
       ! rg -q 'add_next_step "bd sync"' "$WORKTREE_READY_SCRIPT" && \
       rg -q 'bd status' "$CLAUDE_DOC" "$BEADS_STATE_AGENTS" "$QUICKSTART_RU" "$QUICKSTART_EN" "$BEADS_COMMAND_QUICKREF" "$BEADS_WORKFLOWS"; then
        test_pass
    else
        test_fail "Active instruction surfaces must not reintroduce retired bd sync guidance"
    fi

    test_start "static_codex_launcher_bootstraps_repo_local_plain_bd"
    if rg -q 'export PATH="\$\{REPO_ROOT\}/bin:\$\{PATH\}"' "$CODEX_LAUNCHER"; then
        test_pass
    else
        test_fail "Codex launcher must prepend the repo-local bin directory"
    fi

    test_start "static_git_hooks_bootstrap_repo_local_plain_bd"
    if [[ -f "$HOOK_BOOTSTRAP" ]] && \
       rg -q 'export PATH="\$\{PROJECT_ROOT\}/bin:\$\{PATH\}"' "$HOOK_BOOTSTRAP" && \
       rg -q '_repo-local-path\.sh' "$HOOK_PRE_COMMIT" "$HOOK_POST_CHECKOUT" "$HOOK_POST_MERGE" "$HOOK_PRE_PUSH" && \
       rg -q 'beads-worktree-localize\.sh' "$HOOK_POST_CHECKOUT" "$HOOK_POST_MERGE" && \
       rg -q -- '--bootstrap-source' "$HOOK_POST_CHECKOUT" "$HOOK_POST_MERGE" && \
       rg -q 'requested_bootstrap_source="origin/main"' "$HOOK_POST_CHECKOUT" "$HOOK_POST_MERGE" && \
       rg -q 'unset state action bootstrap_source' "$HOOK_POST_CHECKOUT" "$HOOK_POST_MERGE"; then
        test_pass
    else
        test_fail "Tracked git hooks must preserve the requested bootstrap source across env-eval and auto-heal safe Beads ownership residue"
    fi

    test_start "static_hooks_enforce_sibling_beads_ownership_audit"
    if rg -q 'beads-worktree-audit\.sh' "$HOOK_PRE_COMMIT" && \
       rg -q 'beads-worktree-audit\.sh' "$HOOK_PRE_PUSH"; then
        test_pass
    else
        test_fail "Pre-commit and pre-push must run the sibling Beads ownership audit"
    fi

    test_start "static_pre_commit_normalizes_branch_local_beads_issues"
    if [[ -x "$NORMALIZE_SCRIPT" ]] && \
       rg -q 'find_dependencies_slice' "$NORMALIZE_SCRIPT" && \
       rg -q 'python3 - ' "$NORMALIZE_SCRIPT" && \
       rg -q 'beads-normalize-issues-jsonl\.sh' "$HOOK_PRE_COMMIT" && \
       rg -q 'git diff --cached --quiet -- \.beads/issues\.jsonl' "$HOOK_PRE_COMMIT" && \
       rg -q 'partially staged \.beads/issues\.jsonl' "$HOOK_PRE_COMMIT" && \
       rg -q 'git add -- \.beads/issues\.jsonl' "$HOOK_PRE_COMMIT"; then
        test_pass
    else
        test_fail "Pre-commit must normalize tracked .beads/issues.jsonl before commit"
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
       ! rg -q 'bd-local' "$QUICKSTART_RU" "$QUICKSTART_EN" "$BEADS_SKILL" "$BEADS_COMMAND_QUICKREF" "$BEADS_WORKFLOWS" && \
       ! rg -q 'bd sync' "$BEADS_SKILL"; then
        test_pass
    else
        test_fail "High-traffic Beads docs must use the plain bd contract without wrapper-choice drift"
    fi

    test_start "static_worktree_finish_contract_uses_plain_bd_and_skips_ambiguous_close"
    if [[ -f "$WORKTREE_COMMAND" ]] && \
       rg -q 'plain `bd`' "$WORKTREE_COMMAND" && \
       rg -q 'Issue: n/a' "$WORKTREE_COMMAND" && \
       ! rg -q 'bd-local\.sh' "$WORKTREE_COMMAND" && \
       ! rg -q 'bd sync' "$WORKTREE_COMMAND"; then
        test_pass
    else
        test_fail "Ordinary worktree/finish contract must use plain bd and skip close when issue resolution is ambiguous"
    fi

    test_start "static_worktree_finish_contract_defers_topology_publication"
    if [[ -f "$WORKTREE_COMMAND" ]] && \
       rg -q 'dedicated non-main topology-publish worktree/branch' "$WORKTREE_COMMAND" && \
       rg -q 'do not auto-run `refresh --write-doc` during ordinary `start`, `attach`, `finish`, or `cleanup`' "$WORKTREE_COMMAND" && \
       rg -q 'Stale topology is informational only for ordinary doctor/finish; do not auto-publish from the invoking branch.' "$WORKTREE_COMMAND"; then
        test_pass
    else
        test_fail "Ordinary finish contract must defer topology publication to the dedicated publish path instead of promising auto publication"
    fi

    test_start "static_worktree_helper_integration_includes_finish_mode"
    if [[ -f "$WORKTREE_COMMAND" ]] && \
       rg -q 'scripts/worktree-ready\.sh finish --branch <branch-or-path>' "$WORKTREE_COMMAND" && \
       rg -q 'Canonical finish vocabulary:' "$WORKTREE_COMMAND" && \
       rg -q 'Close: <exact bd close command or skip>' "$WORKTREE_COMMAND"; then
        test_pass
    else
        test_fail "Worktree helper integration must advertise the finish helper contract explicitly"
    fi

    test_start "static_worktree_command_separates_phase_a_executor_from_create_helper"
    if [[ -f "$WORKTREE_COMMAND" ]] && \
       rg -q 'post-Phase-A readiness/handoff helper' "$WORKTREE_COMMAND" && \
       rg -q 'does not create git branches or worktrees by itself' "$WORKTREE_COMMAND" && \
       rg -q 'scripts/worktree-phase-a\.sh create-from-base' "$WORKTREE_COMMAND"; then
        test_pass
    else
        test_fail "Worktree command docs must separate the Phase A executor from the create helper explicitly"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_static_beads_worktree_ownership_tests
fi
