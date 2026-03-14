# Implementation Plan: Moltis Release-Tag Production Policy

**Branch**: `017-moltis-release-tag-policy` | **Date**: 2026-03-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/017-moltis-release-tag-policy/spec.md`

## Summary

Current repo state is inconsistent: docs now say production should prefer explicit upstream release tags, but `.github/workflows/deploy.yml` still hardcodes `latest` as the fallback version and `make version-check` still parses compose files ad hoc. The implementation will introduce one small helper for normalized Moltis version resolution, switch deploy workflow UX to tracked-compose-default plus explicit exceptions, and add tests so the policy cannot silently drift back.

The feature intentionally does not implement arbitrary-version rollback. It keeps the current backup-safe rollback contract intact and focuses only on rollout version resolution and operator UX.

## Technical Context

**Language/Version**: Bash shell, GitHub Actions YAML, Markdown  
**Primary Dependencies**: `bash`, `sed`, `grep`, GitHub Actions workflow inputs/outputs, existing shell test harness  
**Storage**: Repository-tracked compose files, scripts, workflow YAML, test files, spec artifacts  
**Testing**: `bash -n`, component shell tests, static config validation via `./tests/run.sh`  
**Target Platform**: Linux/macOS repo workflows plus GitHub Actions runners  
**Project Type**: Single repository runtime/workflow policy hardening  
**Performance Goals**: Version resolution remains instant and deterministic before rollout begins  
**Constraints**: Do not break intentional `latest` exceptions, do not promise arbitrary-tag rollback, keep backup-safe rollback semantics unchanged, keep compose files as the rollout SSOT  
**Scale/Scope**: One helper script, one workflow, one Make target, static/component coverage, one spec package

## Constitution Check

| Principle | Status | Evidence |
|-----------|--------|----------|
| Context-First Development | ✅ PASS | Official Moltis docs/issues were checked before docs policy changed, and local workflow/test state was inspected before implementation planning |
| Single Source of Truth | ✅ PASS | The plan introduces one normalized Moltis version helper shared by workflow, Makefile, and tests |
| DRY / Reuse | ✅ PASS | Reuses compose files as tracked source of truth rather than introducing another config file |
| Quality Gates | ✅ PASS | Includes static + component validation before landing workflow behavior changes |
| Progressive Specification | ✅ PASS | Spec, plan, and tasks are created before runtime edits |

## Project Structure

### Documentation (this feature)

```text
specs/017-moltis-release-tag-policy/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
└── moltis-version.sh              # New normalized version helper

.github/workflows/
└── deploy.yml                     # Production deploy UX and version-resolution policy

tests/
├── component/
│   └── test_moltis_version_helper.sh
├── static/
│   └── test_config_validation.sh
└── run.sh

Makefile                           # version-check should reuse helper
scripts/manifest.json              # register new helper
```

**Structure Decision**: Keep all runtime behavior in existing high-traffic files and add only one narrow helper script as the new SSOT for version resolution.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |

## Implementation Phases

### Phase 1: Source Of Truth

- Add `scripts/moltis-version.sh`
- Normalize Moltis image extraction from both compose files
- Expose commands needed by workflow and Makefile

### Phase 2: Workflow UX

- Update `.github/workflows/deploy.yml` to derive default version from helper instead of hardcoded `latest`
- Add explicit production acknowledgement for intentional `latest`
- Surface resolved version source in workflow output/summary

### Phase 3: Guardrails

- Update `Makefile` to reuse helper
- Add component coverage for the helper
- Extend static workflow validation so hardcoded production `latest` does not regress

## Validation Strategy

Run at minimum:

- `bash -n scripts/moltis-version.sh tests/component/test_moltis_version_helper.sh tests/static/test_config_validation.sh tests/run.sh`
- `./tests/run.sh --lane component --filter component_moltis_version_helper --json`
- `./tests/run.sh --lane static --filter static_config_validation --json`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/deploy.yml"); puts "deploy.yml ok"'`
