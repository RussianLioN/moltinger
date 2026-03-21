# Implementation Plan: Safely Unblock `command-worktree finish`

**Branch**: `025-worktree-finish-unblock` | **Date**: 2026-03-15 | **Spec**: `/specs/025-worktree-finish-unblock/spec.md`
**Input**: Feature specification from `/specs/025-worktree-finish-unblock/spec.md`

## Summary

Harden the ordinary worktree finish/readiness contract by making helper issue resolution conservative, adding an executable helper `finish` mode, preserving local Beads ownership behavior, and aligning `command-worktree` documentation to plain `bd` plus deferred topology publication only through the dedicated publish path.

## Technical Context

**Language/Version**: Bash shell scripts and markdown command docs  
**Primary Dependencies**: `git`, repo-local `bd`, `jq`, existing shell test helpers  
**Storage**: Repo-local files and Beads JSONL metadata under `.beads/` (read-only for this follow-up)  
**Testing**: `tests/unit/test_worktree_ready.sh`, `tests/static/test_beads_worktree_ownership.sh`, `make codex-check`  
**Target Platform**: macOS/Linux shell environments used by Codex/Claude sessions  
**Project Type**: single repository with shell runtime helpers and command documentation  
**Performance Goals**: No meaningful runtime regression; helper decisions remain deterministic and O(number of issue ids)  
**Constraints**: Touch only `scripts/worktree-ready.sh`, `.claude/commands/worktree.md`, `tests/unit/test_worktree_ready.sh`, `tests/static/test_beads_worktree_ownership.sh`, and `specs/025-worktree-finish-unblock/*`  
**Scale/Scope**: Narrow follow-up to unblock ordinary `command-worktree finish` safely without touching `.beads/*`, topology docs, deploy/runtime files, or unrelated scripts/docs

## Constitution Check

- **Context-First Development**: Pass. Existing helper/doc/test contracts were inspected before planning changes.
- **Library-First Development**: Pass. No new component over the custom-code threshold; existing repo helpers remain the single source of truth.
- **Code Reuse & DRY**: Pass. The fix extends existing helper/report functions and existing shell test suites instead of adding parallel flows.
- **Atomic Task Execution**: Pass. Work is split into spec, implementation, validation, and PR/CI tasks.
- **Quality Gates**: Planned. Required gates are the two targeted tests, `make codex-check` because `.claude/commands/worktree.md` changes, then PR CI green status.
- **Progressive Specification**: Pass with scoped exception. The user restricted Speckit artifacts to `spec.md`, `plan.md`, and `tasks.md`, so this plan intentionally records research/design decisions inline instead of creating `research.md`, `data-model.md`, `contracts/`, or `quickstart.md`.

## Project Structure

### Documentation (this feature)

```text
specs/025-worktree-finish-unblock/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
└── worktree-ready.sh

.claude/commands/
└── worktree.md

tests/unit/
└── test_worktree_ready.sh

tests/static/
└── test_beads_worktree_ownership.sh
```

**Structure Decision**: Keep the change set inside the existing shell helper, command contract, and two existing test suites. No new runtime files or auxiliary Speckit artifacts are introduced.

## Design Notes

1. **Issue resolution confidence**
   - Replace longest-prefix winning behavior with an exact-confidence rule.
   - If more than one normalized issue id matches a branch prefix, resolve to empty and surface `Issue: n/a`.
   - Preserve confident inference when exactly one issue id matches.

2. **Finish helper contract**
   - Add an ordinary `finish` mode to `scripts/worktree-ready.sh`.
   - Keep the helper non-destructive: it should prepare finish context and exact next steps, not auto-run close or topology publication.
   - Make `Issue: n/a` authoritative for skip-close behavior and keep stale topology informational only.

3. **Local Beads ownership**
   - Keep `beads_state=local` as a ready state.
   - Add regression coverage proving ordinary doctor does not suggest `beads-worktree-localize.sh` for local ownership.

4. **Stale topology**
   - Keep helper behavior non-blocking for `status=stale`.
   - Add explicit regression coverage that ordinary doctor and ordinary finish remain actionable and only defer publication to the dedicated publish path.
   - Align `command-worktree` finish/doctor prose with the same deferred-publication contract.

5. **Plain `bd` documentation**
   - Remove `bd-local.sh` from the ordinary `command-worktree` contract and use plain `bd` with existing `--no-db` fallbacks.
   - Keep finish behavior conservative: `Issue: n/a` means skip `bd close`.

## Verification Plan

1. Update/expand the targeted unit tests in `tests/unit/test_worktree_ready.sh`, including ordinary `finish` coverage.
2. Update/expand the static contract guards in `tests/static/test_beads_worktree_ownership.sh`.
3. Run:
   - `bash tests/unit/test_worktree_ready.sh`
   - `bash tests/static/test_beads_worktree_ownership.sh`
   - `make codex-check`
4. Open a PR, inspect GitHub Actions logs, and fix failures until all checks are green.
