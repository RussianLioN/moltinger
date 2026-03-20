#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib/test_helpers.sh"

MIGRATION_DOC="${PROJECT_ROOT}/docs/beads-dolt-native-migration.md"
RULE_DOC="${PROJECT_ROOT}/docs/rules/beads-dolt-native-contract.md"
CUTOVER_DOC="${PROJECT_ROOT}/docs/migration/beads-dolt-native-cutover.md"
TASKS_DOC="${PROJECT_ROOT}/specs/029-beads-dolt-native-migration/tasks.md"

run_static_beads_dolt_docs_alignment_tests() {
    start_timer

    test_start "static_migration_doc_exists_and_stays_inventory_first"
    if [[ -f "$MIGRATION_DOC" ]] && \
       rg -q 'Phase B' "$MIGRATION_DOC" && \
       rg -q 'inventory/readiness' "$MIGRATION_DOC" && \
       rg -q 'Do not start pilot or rollout from this step' "$MIGRATION_DOC"; then
        test_pass
    else
        test_fail "Migration doc must exist and preserve the inventory-first boundary"
    fi

    test_start "static_rule_doc_defines_single_target_contract"
    if [[ -f "$RULE_DOC" ]] && \
       rg -q 'one active Beads operating model' "$RULE_DOC" && \
       rg -q 'Dolt-native direction' "$RULE_DOC" && \
       rg -q 'Long-lived mixed mode' "$RULE_DOC"; then
        test_pass
    else
        test_fail "Rule doc must define the single target contract and forbidden mixed mode"
    fi

    test_start "static_cutover_baseline_records_blocking_gate"
    if [[ -f "$CUTOVER_DOC" ]] && \
       rg -q 'Initial Inventory Baseline' "$CUTOVER_DOC" && \
       rg -q 'Pilot Gate' "$CUTOVER_DOC" && \
       rg -q 'blocked' "$CUTOVER_DOC"; then
        test_pass
    else
        test_fail "Cutover baseline must capture the initial inventory verdict and pilot gate"
    fi

    test_start "static_tasks_track_inventory_iteration_completion"
    if [[ -f "$TASKS_DOC" ]] && \
       rg -q '\[x\] T004' "$TASKS_DOC" && \
       rg -q '\[x\] T012' "$TASKS_DOC" && \
       rg -q '\[x\] T014' "$TASKS_DOC"; then
        test_pass
    else
        test_fail "Tasks doc must record the completed inventory/readiness iteration"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_static_beads_dolt_docs_alignment_tests
fi
