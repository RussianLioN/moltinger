# Tasks: Moltis Release-Tag Production Policy

**Input**: Design documents from `/specs/017-moltis-release-tag-policy/`
**Prerequisites**: plan.md, spec.md

**Tests**: Mandatory. This feature changes production workflow UX and requires both component coverage and static guardrails.

## Phase 0: Planning

- [x] T001 Create `specs/017-moltis-release-tag-policy/spec.md`
- [x] T002 Create `specs/017-moltis-release-tag-policy/plan.md`
- [x] T003 Create `specs/017-moltis-release-tag-policy/tasks.md`

## Phase 1: Source Of Truth

- [x] T004 Add normalized Moltis version helper in `scripts/moltis-version.sh`
- [x] T005 Register the helper in `scripts/manifest.json`
- [x] T006 Update `Makefile` `version-check` target to use `scripts/moltis-version.sh`

## Phase 2: Workflow UX

- [x] T007 Update `.github/workflows/deploy.yml` so default version resolution comes from `scripts/moltis-version.sh` instead of hardcoded `latest`
- [x] T008 Add explicit production acknowledgement for intentional `latest` in `.github/workflows/deploy.yml`
- [x] T009 Surface resolved version source/policy in deployment summary in `.github/workflows/deploy.yml`

## Phase 3: Guardrails

- [x] T010 Add helper component coverage in `tests/component/test_moltis_version_helper.sh`
- [x] T011 Register the new component suite in `tests/run.sh`
- [x] T012 Extend `tests/static/test_config_validation.sh` to block regression to hardcoded production `latest`

## Phase 4: Validation And Reconciliation

- [x] T013 Run targeted validation for helper, workflow YAML, component, and static lanes
- [x] T014 Reconcile checkbox state in `specs/017-moltis-release-tag-policy/tasks.md`
