#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

ENVRC_FILE="$PROJECT_ROOT/.envrc"
PHASE_A_SCRIPT="$PROJECT_ROOT/scripts/worktree-phase-a.sh"
LOCALIZE_SCRIPT="$PROJECT_ROOT/scripts/beads-worktree-localize.sh"
BATCH_SCRIPT="$PROJECT_ROOT/scripts/beads-recovery-batch.sh"
OWNERSHIP_MAP="$PROJECT_ROOT/docs/beads-recovery-ownership.json"

run_static_beads_worktree_ownership_tests() {
    start_timer

    test_start "static_envrc_exports_worktree_local_beads_db"
    if rg -q 'export BEADS_DB="\$\(git rev-parse --show-toplevel\)/\.beads/beads\.db"' "$ENVRC_FILE"; then
        test_pass
    else
        test_fail ".envrc must export a worktree-local BEADS_DB"
    fi

    test_start "static_phase_a_uses_git_worktree_add"
    if rg -q 'git -C "\$\{canonical_root\}" worktree add "\$\{target_path\}" "\$\{branch\}"' "$PHASE_A_SCRIPT" && \
       ! rg -q 'bd worktree create' "$PHASE_A_SCRIPT"; then
        test_pass
    else
        test_fail "Phase A must use git worktree add and avoid bd worktree create"
    fi

    test_start "static_phase_a_localizes_beads_state"
    if [[ -x "$LOCALIZE_SCRIPT" ]] && \
       rg -q 'beads-worktree-localize\.sh' "$PHASE_A_SCRIPT"; then
        test_pass
    else
        test_fail "Managed worktree creation must call the Beads localization helper"
    fi

    test_start "static_batch_recovery_contract_exists"
    if [[ -x "$BATCH_SCRIPT" ]] && [[ -f "$OWNERSHIP_MAP" ]] && \
       rg -q 'beads-worktree-localize\.sh' "$BATCH_SCRIPT" && \
       rg -q 'beads-recover-issue\.sh' "$BATCH_SCRIPT"; then
        test_pass
    else
        test_fail "Batch recovery automation must use the localized worktree and single-issue recovery helpers"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_static_beads_worktree_ownership_tests
fi
