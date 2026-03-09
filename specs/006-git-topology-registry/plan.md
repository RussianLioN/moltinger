# Implementation Plan: Auto-Maintained Git Topology Registry

**Branch**: `006-git-topology-registry` | **Date**: 2026-03-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-git-topology-registry/spec.md`

## Summary

Turn `docs/GIT-TOPOLOGY-REGISTRY.md` from a hand-seeded note into a deterministic, sanitized coordination artifact generated from live git topology plus a reviewed intent sidecar. Keep the implementation script-first, wire it into `/worktree` and `/session-summary`, and use hooks only as validation/backstop mechanisms.

## Technical Context

**Language/Version**: Bash 3.2+ and repository-standard Markdown/YAML  
**Primary Dependencies**: `git`, standard shell utilities, existing repo hooks/command workflows  
**Storage**: committed docs, committed sidecar intent file, repo-shared state under `git-common-dir`  
**Testing**: Existing shell test runners plus shell-based unit/integration/e2e coverage  
**Target Platform**: macOS/Linux developer machines and Codex/Claude worktrees
**Project Type**: Repository workflow automation + documentation governance  
**Performance Goals**: `check`/`status` in under 2 seconds, `refresh` in under 5 seconds on a typical developer machine  
**Constraints**: deterministic output, sanitized committed state, no destructive topology mutation, low diff churn  
**Scale/Scope**: single repository, multiple parallel worktrees, local and remote branch coordination

## Post-UAT Hardening Note

- Canonical worktree identity for numbered feature branches must be observer-independent. Running `doctor` from a child task branch may add new topology rows, but it must not rename or orphan the authoritative feature worktree for the parent `NNN-*` branch.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (live hooks, commands, instructions, and current topology artifact reviewed)
- Single Source of Truth: PASS (one owner script for generated registry, one reviewed sidecar for non-derivable intent)
- Library-First Development: PASS (no external library needed for v1; shell + git primitives are sufficient)
- Code Reuse & DRY: PASS (reuse existing session guard, worktree workflow, and hook installation patterns where safe)
- Strict Type Safety: N/A (Bash/Markdown/YAML scope)
- Atomic Task Execution: PASS (implementation can be split into generator, integration, recovery, and validation slices)
- Quality Gates: PASS (shell validation + integration scenarios required before merge)
- Progressive Specification: PASS (spec -> plan -> tasks flow is being followed)

No constitution violations require exception handling.

## Project Structure

### Documentation (this feature)

```text
specs/006-git-topology-registry/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
.githooks/
.claude/commands/
docs/
tests/
```

**Structure Decision**: Keep the implementation in the existing repo workflow layers: one script in `scripts/`, tracked hook files in `.githooks/`, workflow wiring in `.claude/commands/`, shared artifacts in `docs/`, and shell-based validation in `tests/`.

## Phase 0: Research Decisions (to `research.md`)

1. Adopt a script-first hybrid rather than an agent-first maintainer.
2. Separate generated topology facts from reviewed intent metadata.
3. Sanitize the committed registry and remove volatile fields that would churn on every commit.
4. Use full reconcile against live git state as the correctness path; hooks are hints/backstops only.

## Phase 1: Design Artifacts

- Define normalized topology entities and registry health state.
- Define command contract for `refresh`, `check`, `status`, and `doctor`.
- Define the generated registry format and sidecar annotation semantics.
- Define integration points for `/worktree`, `/session-summary`, and hook validation.

## Phase 2: Execution Readiness

- Generate atomic tasks grouped by user story.
- Keep implementation centered on one owner script.
- Ensure final validation covers parser, renderer, annotation preservation, and topology mutation workflows.

## V1 Scope Freeze

### In Scope

- One owner script at `scripts/git-topology-registry.sh` for discovery, render, check, status, and doctor flows.
- One committed intent sidecar at `docs/GIT-TOPOLOGY-INTENT.yaml`.
- One generated committed registry at `docs/GIT-TOPOLOGY-REGISTRY.md`.
- Managed workflow integration through `/worktree`, `/session-summary`, and tracked git hooks.
- Shell-based unit, integration, and workflow validation.

### Out of Scope

- Long-running topology maintainer agents.
- Hooks that silently rewrite tracked markdown.
- Auto-delete or auto-merge behavior for branches/worktrees.
- CI-only topology freshness enforcement for local worktrees.
- Committing absolute local paths or volatile per-commit worktree HEAD data.

## Executor Lanes

| Lane | Scope | Primary owner |
|---|---|---|
| `shell-core` | `scripts/git-topology-registry.sh`, `scripts/setup-git-hooks.sh`, `scripts/manifest.json` | main implementer |
| `workflow-hooks` | `.githooks/*`, `.claude/commands/*` | main implementer, can delegate after Phase 2 |
| `docs-registry` | `docs/GIT-TOPOLOGY-REGISTRY.md`, `docs/GIT-TOPOLOGY-INTENT.yaml`, shared docs/instructions | main implementer |
| `test-fixtures` | `tests/lib/`, `tests/unit/`, `tests/integration/`, `tests/e2e/` | main implementer, can parallelize after script skeleton lands |

## Test Fixture Strategy

- Build topology tests around temporary throwaway repositories created under `mktemp -d`.
- Use a local bare repo as `origin` so remote-tracking and unmerged-branch scenarios stay deterministic and offline.
- Create topology mutations through both raw `git` commands and tracked hook installation to cover managed and unmanaged flows.
- Centralize helpers in `tests/lib/git_topology_fixture.sh` so unit, integration, and e2e suites share the same fixture API.
