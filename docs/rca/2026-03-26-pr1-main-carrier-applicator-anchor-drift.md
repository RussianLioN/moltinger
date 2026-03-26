---
title: "PR1 main carrier replay drifted because the applicator used a non-unique test anchor"
date: 2026-03-26
severity: P3
category: process
tags: [carrier, main-pr, applicator, tests, rca, lessons]
root_cause: "The PR1 carrier applicator updated tests with repeated replace_once() calls keyed to the same short line, so the first dry-run block was patched twice and the ABI dry-run block was left stale."
---

# RCA: PR1 main carrier replay drifted because the applicator used a non-unique test anchor

## Summary

While validating the runtime-only `PR1` carrier against a clean `origin/main` export, the transformed tree failed the blocking unit lane:

- `tests/unit/test_deploy_workflow_guards.sh` -> `22/23 PASS`
- failing case: `Tracked deploy dry-run JSON should expose the workflow ABI contract fields`

The runtime carrier itself was not wrong. The applicator that materializes the carrier onto `origin/main` patched one dry-run test block twice and skipped the second one. As a result, the transformed tree required `scripts/moltis-runtime-attestation.sh` in the shared tracked-deploy script, but the ABI dry-run test fixture still did not create that file.

## Error

Carrier validation failed on a clean `origin/main` replay even though the intended runtime-only delta was otherwise correct.

## 5 Whys

| Level | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 1 | Why did the transformed `origin/main` tree fail the ABI dry-run test? | Because `run-tracked-moltis-deploy.sh --dry-run` now requires `scripts/moltis-runtime-attestation.sh`, but the ABI test fixture did not create it. | Replay output returned `Missing required file: .../scripts/moltis-runtime-attestation.sh`. |
| 2 | Why did the ABI test fixture not create the attestation stub? | Because the carrier applicator did not patch that specific fixture block in `tests/unit/test_deploy_workflow_guards.sh`. | Fresh replay showed the first dry-run test contained two attestation stub lines while the ABI test still had none. |
| 3 | Why did the applicator patch the wrong block? | Because it used two `replace_once(...)` calls against the same short anchor line `: > "$project_root/scripts/deploy.sh"`. | The second replacement matched the first function again, since the first function still contained the same line after the first insertion. |
| 4 | Why was a non-unique anchor used in the applicator? | Because the carrier generator was optimized for minimal selected-hunk transfer and assumed the repeated line was safe enough as a unique matcher. | `apply_pr1_main_carrier.py` used repeated short replacements instead of anchoring on function-local context like `output_file` vs `output_json`. |
| 5 | Why did this reach validation instead of being caught earlier? | Because the original carrier validation proved `py_compile`, applicator execution, and `patch --dry-run`, but did not yet rerun the blocking lanes on a freshly transformed `origin/main` tree after the later applicator edits. | The stale temp replay exposed the failure only when the transformed tree was exercised with `tests/unit/test_deploy_workflow_guards.sh`. |

## Root Cause

The PR1 carrier applicator relied on a non-unique line anchor inside a test file with repeated fixture setup blocks. That made the selected-hunk transfer mechanically valid as a patch, but semantically wrong for one of the dry-run tests.

## Fix

1. Replaced the short repeated anchor with function-specific multi-line anchors keyed to the surrounding `output_file` and `output_json` contexts.
2. Replayed the applicator onto a fresh exported `origin/main` tree.
3. Reran the blocking hermetic lanes on the transformed tree:
   - `bash tests/unit/test_deploy_workflow_guards.sh`
   - `bash tests/component/test_moltis_runtime_attestation.sh`
   - `bash tests/component/test_moltis_search_memory_diagnostics.sh`
   - `bash tests/static/test_config_validation.sh`
4. Regenerated `specs/031-moltis-reliability-diagnostics/artifacts/pr1-main-carrier.patch`.
5. Updated `pr1-main-carrier-validation.md` with the corrected replay evidence.

## Verification

- Fresh transformed `origin/main` tree:
  - `tests/unit/test_deploy_workflow_guards.sh` -> `23/23 PASS`
  - `tests/component/test_moltis_runtime_attestation.sh` -> `4/4 PASS`
  - `tests/component/test_moltis_search_memory_diagnostics.sh` -> `2/2 PASS`
  - `tests/static/test_config_validation.sh` -> `98/98 PASS`
- Regenerated patch passed `patch --dry-run` against a second clean `origin/main` export.

## Preventive Actions

1. Do not use repeated one-line anchors for carrier applicators when the target file contains duplicated fixture setup blocks.
2. Require transformed-tree test execution, not only patch materialization, for any future selected-hunk `main` carrier.
3. Keep carrier validation notes current with the latest replay, not only the first successful `patch --dry-run`.

## Lessons

1. A carrier can be mechanically patchable and still semantically wrong; replay tests on the transformed target are the real proof.
2. For selected-hunk applicators, anchor specificity is part of the contract, not an implementation detail.
