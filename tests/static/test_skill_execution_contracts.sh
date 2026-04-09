#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

SHARED_CORE_INSTRUCTIONS="$PROJECT_ROOT/.ai/instructions/shared-core.md"
ROOT_AGENTS="$PROJECT_ROOT/AGENTS.md"
WORKTREE_COMMAND="$PROJECT_ROOT/.claude/commands/worktree.md"
WORKTREE_HOTFIX_PLAYBOOK="$PROJECT_ROOT/docs/WORKTREE-HOTFIX-PLAYBOOK.md"
REPORT_RULE="$PROJECT_ROOT/docs/rules/operator-facing-task-report-contract.md"
ABNORMAL_BEHAVIOR_RULE="$PROJECT_ROOT/docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md"

run_static_skill_execution_contract_tests() {
    start_timer

    test_start "static_report_contract_exists_and_requires_simple_operator_shape"
    if [[ -f "$REPORT_RULE" ]] && \
       rg -q -F '1. `Что сделано`' "$REPORT_RULE" && \
       rg -q -F '2. `Что это дает`' "$REPORT_RULE" && \
       rg -q -F '3. `Что дальше`' "$REPORT_RULE" && \
       rg -q -F 'Do not dump a changelog when the user asked for "простыми словами".' "$REPORT_RULE"; then
        test_pass
    else
        test_fail "Operator-facing report rule must enforce the short three-section summary contract"
    fi

    test_start "static_abnormal_helper_rule_requires_root_fix_not_workaround"
    if [[ -f "$ABNORMAL_BEHAVIOR_RULE" ]] && \
       rg -q -F '1. Stop normal task continuation at the abnormal boundary.' "$ABNORMAL_BEHAVIOR_RULE" && \
       rg -q -F '2. Run the lessons pre-check and then RCA.' "$ABNORMAL_BEHAVIOR_RULE" && \
       rg -q -F 'Do not use a manual workaround as a substitute for fixing the broken skill/helper path.' "$ABNORMAL_BEHAVIOR_RULE" && \
       rg -q -F 'If temporary mitigation is used, it must still produce:' "$ABNORMAL_BEHAVIOR_RULE"; then
        test_pass
    else
        test_fail "Abnormal helper behavior rule must require RCA and root-fix instead of workaround continuation"
    fi

    test_start "static_shared_core_carries_operator_report_and_root_fix_contracts"
    if rg -q -F '## Operator-Facing Task Reports' "$SHARED_CORE_INSTRUCTIONS" && \
       rg -q -F 'Rule: `docs/rules/operator-facing-task-report-contract.md`' "$SHARED_CORE_INSTRUCTIONS" && \
       rg -q -F '## Abnormal Skill Or Helper Behavior' "$SHARED_CORE_INSTRUCTIONS" && \
       rg -q -F 'Rule: `docs/rules/abnormal-skill-helper-behavior-needs-root-cause-fix.md`' "$SHARED_CORE_INSTRUCTIONS" && \
       rg -q -F 'treat the behavior as a first-class defect, not as a cue to improvise a workaround completion path' "$SHARED_CORE_INSTRUCTIONS"; then
        test_pass
    else
        test_fail "Shared source instructions must carry both the simple-report and abnormal-helper root-fix contracts"
    fi

    test_start "static_generated_root_agents_inherits_new_contracts"
    if rg -q -F '## Operator-Facing Task Reports' "$ROOT_AGENTS" && \
       rg -q -F '## Abnormal Skill Or Helper Behavior' "$ROOT_AGENTS" && \
       rg -q -F 'Что сделано' "$ROOT_AGENTS" && \
       rg -q -F 'fix the source contract in the owning layer before treating the broader task as resolved' "$ROOT_AGENTS"; then
        test_pass
    else
        test_fail "Generated AGENTS.md must inherit the simple-report and root-fix behavior contracts"
    fi

    test_start "static_worktree_guidance_forbids_manual_completion_when_helper_breaks"
    if rg -q -F 'do not continue the original task through manual git, PR, cleanup, or publish steps just to get past the broken helper' "$WORKTREE_HOTFIX_PLAYBOOK" && \
       rg -q -F 'Manual cleanup or hygiene actions are acceptable only as temporary mitigation under explicit user direction' "$WORKTREE_HOTFIX_PLAYBOOK" && \
       rg -q -F 'Do not finish the downstream task through manual git/PR/publish workarounds just because the intended helper path felt unreliable.' "$WORKTREE_COMMAND" && \
       rg -q -F 'If temporary mitigation is explicitly requested, label it as mitigation only, then create the root-fix follow-up and repair the source contract in the owning layer.' "$WORKTREE_COMMAND"; then
        test_pass
    else
        test_fail "Worktree playbook and command source must reject workaround-based completion when helper behavior is abnormal"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_static_skill_execution_contract_tests "$@"
fi
