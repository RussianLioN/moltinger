# Implementation Plan: Portable Worktree Skill Extraction

**Branch**: `011-worktree-skill-extraction` | **Date**: 2026-03-11 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/011-worktree-skill-extraction/spec.md`

## Summary

Нужно спроектировать и подготовить extraction path для самостоятельного репозитория `worktree-skill`, который сохраняет единый portable core worktree behavior и выносит Claude Code, Codex CLI, OpenCode и Speckit compatibility в отдельные adapter surfaces. Технический подход: сначала инвентаризировать текущие worktree-related assets, затем определить canonical repo layout и extraction boundaries, после чего реализовать repository skeleton, portable core, optional adapters, install/bootstrap flow, примеры, migration docs и validation evidence в новом standalone репозитории без Moltinger runtime coupling.

Ключевое design решение: extracted repo должен поставлять copy-as-is friendly overlay плюс optional bootstrap scripts. Core behavior остается единым для всех IDE: planning, branch/worktree contract, handoff boundary, topology awareness, verification semantics. Различия между Claude Code, Codex CLI и OpenCode ограничиваются discovery, registration и install surface. Speckit не внедряется в core, а оформляется как bridge layer, чтобы skill работал рядом с `spec.md`, `plan.md`, `tasks.md` и уважал artifact-first workflow.

## Technical Context

**Language/Version**: Markdown prompt artifacts + Bash shell helpers  
**Primary Dependencies**: `git`, shell scripts, optional `bd`, optional Claude/Codex/OpenCode registration surfaces  
**Storage**: File-based repo artifacts and git worktree metadata  
**Testing**: Shell smoke tests, contract fixture checks, install/verification scenarios, adapter discovery checks  
**Target Platform**: Local developer workstations using Claude Code, Codex CLI, or OpenCode  
**Project Type**: Single standalone skill repository with docs, scripts, adapters, and examples  
**Performance Goals**: First successful install and verification in 5-10 minutes; no hidden prerequisite required for baseline core flow  
**Constraints**: Zero hard dependency on Moltinger runtime, deploy, secrets, or historical repo topology; safe defaults; predictable file layout; adapter-only IDE differences; Speckit compatibility preserved without forking Speckit itself  
**Scale/Scope**: One portable repo, three IDE adapters, one Speckit bridge layer, one migration path from current in-repo assets

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | PASS | Existing worktree prompts, helper scripts, topology registry, bridge docs, and prior spec packages were reviewed before planning |
| II. Single Source of Truth | PASS | Plan centralizes reusable semantics in portable core rather than duplicating behavior across IDE adapters |
| III. Library-First Development | PASS | No new third-party library is required for the first extraction plan; shell and markdown assets cover the current scope |
| IV. Code Reuse & DRY | PASS | Existing `worktree-ready`, `worktree-phase-a`, and topology registry helpers are reused conceptually instead of re-invented |
| V. Strict Type Safety | N/A | Planned first release is shell and markdown oriented |
| VI. Atomic Task Execution | PASS | Tasks are phased by inventory, boundary definition, skeleton, extraction, adapters, bridge, install, examples, validation, and rollout |
| VII. Quality Gates | PASS | Validation strategy includes install verification, adapter parity checks, Speckit coexistence checks, and acceptance evidence |
| VIII. Progressive Specification | PASS | This feature is progressing through `spec` -> `plan` -> `tasks` before any runtime extraction work |

**Gate Status**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/011-worktree-skill-extraction/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── adapter-surface.md
│   ├── install-verification.md
│   └── portable-repo-layout.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Target Portable Repository Shape

```text
worktree-skill/
├── README.md
├── docs/
│   ├── quickstart.md
│   ├── compatibility-matrix.md
│   ├── migration-from-in-repo.md
│   └── release-policy.md
├── core/
│   ├── .claude/commands/
│   │   ├── worktree.md
│   │   ├── session-summary.md
│   │   └── git-topology.md
│   ├── scripts/
│   │   ├── worktree-ready.sh
│   │   ├── worktree-phase-a.sh
│   │   └── git-topology-registry.sh
│   ├── templates/
│   │   ├── handoff/
│   │   └── topology/
│   └── config/
│       └── worktree-skill.env.example
├── adapters/
│   ├── claude-code/
│   ├── codex-cli/
│   └── opencode/
├── bridge/
│   └── speckit/
├── install/
│   ├── bootstrap.sh
│   ├── register.sh
│   └── verify.sh
├── examples/
│   ├── greenfield/
│   └── existing-project/
└── tests/
    ├── unit/
    ├── integration/
    └── fixtures/
```

### Source Code (current repository surfaces to mine)

```text
.claude/commands/
├── worktree.md
├── session-summary.md
└── git-topology.md

scripts/
├── worktree-ready.sh
├── worktree-phase-a.sh
├── git-topology-registry.sh
└── sync-claude-skills-to-codex.sh

docs/
└── claude-to-codex-migration.md
```

**Structure Decision**: Keep the portable runtime assets together under `core/` so users can copy them as a coherent overlay. Place all IDE-specific discovery or registration behavior under `adapters/`, and keep Speckit coexistence rules in `bridge/speckit/`. Installation should work by either copying `core/` plus selected adapters manually or invoking `install/bootstrap.sh` to materialize the same layout.

## Target Repo Shape

### Portable Core

Portable core owns:

- worktree planning and handoff contracts
- topology/worktree helper scripts
- generic handoff templates
- generic topology templates or docs
- portable verification rules
- no hidden dependency on `bd`, GitHub, Moltinger, or one specific IDE

### Optional Adapters

Adapters own:

- IDE-specific command registration
- bridge or discovery steps
- installation surface differences
- adapter-specific verification probes

Adapters must not re-implement core behavior.

### Speckit Bridge Layer

The bridge layer owns:

- coexistence rules with `spec.md`, `plan.md`, `tasks.md`
- branch-spec alignment guidance
- artifact-first workflow notes
- dedicated worktree handoff semantics for spec-driven feature work

The bridge layer must not fork or replace Speckit commands.

## Canonical Directory Layout

The extracted repo should define three installable surfaces:

1. `core/`  
   Copy-as-is runtime artifacts for all supported hosts.
2. `adapters/<ide>/`  
   Small overlays or bridge assets that activate the same core in one IDE.
3. `bridge/speckit/`  
   Optional compatibility assets that inform spec-driven workflows without becoming a hard dependency.

Supporting directories:

- `install/` for bootstrap, register, and verify scripts
- `examples/` for adoption patterns
- `docs/` for quickstart, matrix, migration, release policy
- `tests/` for portable validation evidence

## Extraction Strategy

### Phase A: Inventory and Boundary Lock

- Audit current worktree-related assets
- Mark each asset as portable, adapter-only, host-only, or template-needed
- Record conflicts and Moltinger-specific residue before any move

### Phase B: Portable Skeleton

- Create the standalone repo skeleton with explicit `core/`, `adapters/`, `bridge/`, `install/`, `examples/`, `docs/`, and `tests/`
- Define repo-local configuration defaults that replace Moltinger-specific hardcoded paths

### Phase C: Core Artifact Extraction

- Move reusable worktree prompts into `core/`
- Move reusable shell helpers into `core/scripts/`
- Generalize topology registry targets and naming
- Split host-only concerns out of the extracted artifacts

### Phase D: Adapter Surface Extraction

- Create a Claude Code adapter that maps to the extracted core without hidden assumptions
- Create a Codex CLI adapter that packages the required bridge behavior without syncing unrelated assets
- Create an OpenCode adapter with explicit support level and verification guidance

### Phase E: Speckit Bridge and Migration

- Add Speckit coexistence docs/templates under `bridge/speckit/`
- Write migration docs showing how current in-repo users move to the extracted repo

### Phase F: Validation and Release Readiness

- Prove greenfield and existing-project install flows
- Verify adapter parity
- Verify Speckit coexistence
- Produce acceptance evidence and release policy for the first standalone release

## Compatibility Matrix

| Surface | Core Behavior | Adapter Surface | First-Release Expectation |
|---------|---------------|-----------------|---------------------------|
| Claude Code | Same planning, branch/worktree contract, handoff boundary, verification semantics | Prompt placement and registration in Claude-specific directories | Fully supported |
| Codex CLI | Same planning, branch/worktree contract, handoff boundary, verification semantics | Bridge skill install and Codex discovery/registration | Fully supported |
| OpenCode | Same planning, branch/worktree contract, handoff boundary, verification semantics | OpenCode-specific install and discovery layer | Supported, with explicit fallback if auto-registration is limited |
| Speckit bridge | No change to core behavior | Optional coexistence docs/templates | Fully documented compatibility contract |

## Risk Log

| Risk | Impact | Mitigation |
|------|--------|------------|
| Core prompts still embed `bd` or Moltinger paths | Hidden dependency breaks portability | Add explicit inventory and portability review before extraction |
| Topology registry remains repo-bound | Extracted core still assumes one host repo layout | Introduce configurable doc/intent paths and verify defaults |
| Codex bridge extraction stays too broad | New repo drags unrelated Claude assets | Build a worktree-skill-scoped bridge installer instead of bulk sync |
| OpenCode support surface is underspecified | Third adapter becomes documentation-only by accident | Record exact support level and fallback rules in compatibility docs |
| Session-summary logic remains mixed with host secrets workflow | Portable docs become polluted with host operations | Split portable handoff summary rules from host-only operational checklist |
| Migration leaves two divergent sources of truth | Users cannot trust which repo is authoritative | Publish explicit migration path and release policy; stop editing the in-repo copy once extraction is adopted |

## Validation Strategy

Validation for first release should include:

1. Repository shape validation  
   Confirm every required directory and artifact exists in the extracted repo.
2. Install flow validation  
   Prove `copy-only`, `copy+bootstrap`, and `copy+register` paths.
3. Adapter validation  
   Verify Claude Code, Codex CLI, and OpenCode surfaces each activate the same core semantics.
4. Speckit coexistence validation  
   Verify the skill works next to `spec.md`, `plan.md`, `tasks.md` without changing Speckit commands.
5. Migration validation  
   Verify a host project can move from in-repo assets to the standalone repo without broken references.
6. Acceptance evidence  
   Produce a checklist or validation log proving the state `portable repo ready`.

## Migration and Rollout Strategy

### Migration

- Freeze the current in-repo worktree assets as the extraction source of truth for one release window.
- Extract reusable artifacts into `worktree-skill`.
- Replace in-repo copies with either:
  - documented vendor/import instructions, or
  - thin compatibility stubs that point to the standalone repo contract.

### Rollout

1. Land repository skeleton and docs first.
2. Extract portable core next.
3. Add Claude Code and Codex CLI adapters.
4. Add OpenCode adapter and Speckit bridge.
5. Publish quickstart, migration guide, and compatibility matrix.
6. Cut first standalone release only after acceptance evidence is collected.

## Definition of Done for First Release

The first release is done when all of the following are true:

- `worktree-skill` has a canonical repo layout with `core`, `adapters`, `bridge`, `install`, `examples`, `docs`, and `tests`
- Portable core contains generalized worktree planning, handoff, and topology helpers
- Claude Code, Codex CLI, and OpenCode adapters are documented and validated
- Speckit bridge layer is documented and validated
- Quickstart covers greenfield and existing-project install flows
- Migration guidance exists from the current in-repo Moltinger assets
- Post-install verification is predictable and documented
- Release policy and semantic versioning are documented
- Acceptance evidence proves the state `portable repo ready`
- No mandatory runtime dependency remains on Moltinger-specific secrets, deploys, issue ids, remote hosts, or historical repo topology

## Repository Naming Options

- `worktree-skill` (working name and recommended default)
- `portable-worktree-skill`
- `worktree-flow-kit`
- `worktree-handoff-skill`
- `spec-aware-worktree-skill`

## Release and Versioning Strategy

- Use semantic versioning for the standalone repo.
- Track compatibility at three layers:
  - Core contract version
  - IDE adapter support matrix
  - Speckit bridge support level
- Recommend release notes sections:
  - Core behavior changes
  - Adapter changes
  - Migration notes
  - Compatibility changes

## Open Questions

- Is `bd` support part of the first release as an adapter, or only a documented follow-up?
- Should topology registry be installed by default or via an opt-in profile?
- Should the repo ship ready-to-copy overlay directories, or a canonical normalized structure rendered by bootstrap scripts?
- What minimum OpenCode discovery contract can be guaranteed in the first release?

## Assumptions

- The first release can prioritize a file-based install model over package-registry publication.
- Some extracted assets will need renaming or templating before they become portable.
- Partial support is acceptable only for adapter surfaces, never for core behavior semantics.

## Complexity Tracking

> No constitution violations require justification at this stage.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
