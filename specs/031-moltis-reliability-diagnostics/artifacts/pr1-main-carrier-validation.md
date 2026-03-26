# PR1 Main Carrier Validation

**Date**: 2026-03-26
**Branch**: `031-moltis-reliability-diagnostics`

## Goal

Prove that the runtime-only `PR1` carrier can be materialized from this branch onto a clean `origin/main` tree without dragging the whole feature branch.

## Commands Run

```bash
python3 -m py_compile specs/031-moltis-reliability-diagnostics/artifacts/apply_pr1_main_carrier.py

tmp_root="$(mktemp -d /tmp/pr1-main-validate.XXXXXX)"
mkdir -p "$tmp_root/main"
git archive origin/main | tar -x -C "$tmp_root/main"

python3 specs/031-moltis-reliability-diagnostics/artifacts/apply_pr1_main_carrier.py \
  --target-tree "$tmp_root/main" \
  --emit-patch "$tmp_root/pr1-main-carrier.patch" \
  > "$tmp_root/changed.txt"

mkdir -p "$tmp_root/apply"
git archive origin/main | tar -x -C "$tmp_root/apply"
patch --dry-run -p1 -d "$tmp_root/apply" < "$tmp_root/pr1-main-carrier.patch"

cd "$tmp_root/main"
bash tests/unit/test_deploy_workflow_guards.sh
bash tests/component/test_moltis_runtime_attestation.sh
bash tests/component/test_moltis_search_memory_diagnostics.sh
bash tests/static/test_config_validation.sh
```

## Observed Result

- `apply_pr1_main_carrier.py` passed `py_compile`
- applicator succeeded against a clean exported `origin/main` tree
- emitted patch passed `patch --dry-run` against a second fresh exported `origin/main` tree
- transformed `origin/main` tree passed the blocking hermetic lanes:
  - `tests/unit/test_deploy_workflow_guards.sh` -> `23/23 PASS`
  - `tests/component/test_moltis_runtime_attestation.sh` -> `4/4 PASS`
  - `tests/component/test_moltis_search_memory_diagnostics.sh` -> `2/2 PASS`
  - `tests/static/test_config_validation.sh` -> `98/98 PASS`
- emitted patch size at validation time: `1796` lines

## Changed Surface In The Validated Carrier

- `config/moltis.toml`
- `docker-compose.prod.yml`
- `scripts/deploy.sh`
- `scripts/run-tracked-moltis-deploy.sh`
- `scripts/moltis-runtime-attestation.sh`
- `scripts/moltis-search-memory-diagnostics.sh`
- `tests/component/test_moltis_runtime_attestation.sh`
- `tests/component/test_moltis_search_memory_diagnostics.sh`
- `tests/static/test_config_validation.sh`
- `tests/unit/test_deploy_workflow_guards.sh`

## Notes

- An initial 2026-03-26 replay exposed an applicator anchor bug: one short `replace_once(...)` target matched the first dry-run test twice, which duplicated the attestation stub in `output_file` and skipped the `output_json` ABI test block. The applicator was corrected to anchor each replacement to the unique surrounding function context before this validation was rerun.
- The applicator intentionally fails fast on anchor drift; it is not meant to be tolerant of arbitrary mainline edits.
- This validation proves the carrier is mechanically transferable to `main`; it does **not** replace the required hermetic repo checks and canonical production deploy from `main`.
