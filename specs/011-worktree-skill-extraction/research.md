# Research: Portable Worktree Skill Extraction

## Decision 1: Extract a Portable Core Plus Optional Adapters

- **Decision**: Split the future repository into a project-agnostic portable core and explicit optional adapters for Claude Code, Codex CLI, OpenCode, and Speckit.
- **Rationale**: Current assets mix reusable worktree behavior with IDE-specific registration, host-project hooks, and Moltinger governance. A clean split keeps the reusable behavior stable while letting integration surfaces vary.
- **Alternatives considered**:
  - Single flat repo with all assets required: rejected because it would keep hidden coupling and force every host project to adopt every integration surface.
  - Separate repos per IDE: rejected because it would fork the core behavior and make compatibility drift likely.

## Decision 2: Keep `bd` and Host-Project Operations Out of Core

- **Decision**: Treat `bd` issue transitions, host-specific session hooks, and project operational commands as optional integration points rather than part of the mandatory portable core.
- **Rationale**: The user goal is "download, copy, register, use". Requiring Beads, GitHub workflow conventions, or project-local hooks would violate zero-project-coupling.
- **Alternatives considered**:
  - Keep `bd` mandatory because current flow uses it heavily: rejected because it blocks adoption in projects that only need worktree and handoff discipline.
  - Remove all issue awareness entirely: rejected because an optional adapter can still preserve richer workflows where the host project wants them.

## Decision 3: Preserve One Core Behavior Across IDEs

- **Decision**: Core semantics for branch/worktree planning, handoff boundary, topology awareness, and verification must be shared; only invocation, registration, and discovery can vary by IDE.
- **Rationale**: The extracted repo is meant to be reusable knowledge, not three separate implementations with divergent behavior.
- **Alternatives considered**:
  - Rewriting each adapter independently: rejected because long-term parity would be unmanageable.
  - Restricting first release to one IDE: rejected because the target outcome explicitly requires Claude Code, Codex CLI, and OpenCode compatibility.

## Decision 4: Preserve Speckit as a Neighbor, Not a Dependency

- **Decision**: Model Speckit support as a bridge layer that coexists with `spec.md`, `plan.md`, and `tasks.md` without modifying `/speckit.spec`, `/speckit.plan`, or `/speckit.tasks`.
- **Rationale**: The user asked for full compatibility with artifact-first workflow, not for the worktree skill to absorb or override Speckit.
- **Alternatives considered**:
  - Embedding Speckit logic directly into core prompts: rejected because it would force Speckit semantics onto projects that do not use Speckit.
  - Ignoring Speckit entirely: rejected because the current worktree workflow depends on spec-driven branch alignment and handoff discipline.

## Decision 5: Use Copy-As-Is as the Primary Install Model

- **Decision**: The first-class install path should be "copy artifacts as-is", with optional bootstrap or register scripts for convenience.
- **Rationale**: This matches the target user expectation and keeps installation understandable and transparent.
- **Alternatives considered**:
  - Registry-only install: rejected because it hides file placement and makes local customization harder.
  - Script-only install: rejected because users want to inspect and copy the artifacts directly.

## Source Inventory and Classification

| Source Path | Current Role | Classification | Extraction Action |
|-------------|--------------|----------------|-------------------|
| `.claude/commands/worktree.md` | Main worktree workflow contract and prompt surface | `portable core` with `adapter split` | Move reusable flow semantics into core command template; strip Moltinger-specific paths and make Beads hooks optional |
| `.claude/commands/session-summary.md` | Session-boundary reconciliation and handoff summary | `partial portable` + `host-only residue` | Extract only worktree-handoff summary rules; leave secrets/GitHub-specific behavior in host project |
| `scripts/worktree-ready.sh` | Deterministic planning, readiness, handoff helper | `portable core` | Move into core scripts with generalized config and optional probes |
| `scripts/worktree-phase-a.sh` | Deterministic create-from-base executor | `portable core` | Move into core scripts; parameterize base branch and optional issue system usage |
| `scripts/git-topology-registry.sh` | Shared topology registry refresh/check/doctor | `portable core` with `template required` | Keep as portable helper, but rename docs/paths and configurable registry target to avoid Moltinger-specific assumptions |
| `.claude/commands/git-topology.md` | Human command surface for topology registry | `adapter candidate` | Re-home as optional command adapter bound to the portable topology helper |
| `docs/claude-to-codex-migration.md` | Claude/Codex bridge explanation | `adapter reference` | Convert into generic bridge/migration doc for Claude/Codex, remove repo-specific generated-file assumptions |
| `scripts/sync-claude-skills-to-codex.sh` | Bulk bridge sync for all Claude assets into Codex | `adapter utility` | Extract a narrower bridge installer for worktree-skill artifacts only |
| `.ai/instructions/codex-adapter.md` | Repo-level Codex governance notes | `host-project only` with reusable fragments | Keep Moltinger governance in host repo; extract only generic invocation notes if still useful |
| `specs/005-worktree-ready-flow/*` | Design source for worktree handoff and create semantics | `design reference` | Mine decisions and contracts; do not ship as runtime artifacts |
| `specs/006-git-topology-registry/*` | Design source for topology registry behavior | `design reference` | Mine decisions and contracts; do not ship as runtime artifacts |
| `.claude/skills/beads/resources/SPECKIT_BRIDGE.md` | Beads/Speckit planning bridge guidance | `Speckit bridge candidate` | Recast as optional bridge documentation that does not require Beads in core |
| `.claude/hooks/session-save.sh` | Repo-specific hook automation | `host-project only` | Do not extract into portable core |
| `.claude/hooks/session-precommit.sh` | Repo-specific precommit behavior | `host-project only` | Do not extract into portable core |
| `MEMORY.md`, `SESSION_SUMMARY.md`, `docs/SECRETS-MANAGEMENT.md` | Project operating memory and secrets model | `host-project only` | Never extract into the portable repo |
| `.github/workflows/*`, deploy scripts, runtime configs | Product runtime and deployment behavior | `Moltinger-specific` | Never extract; mention only as exclusions or migration non-goals |

## Files That Need Templating or Renaming

| Source Path | Why It Cannot Move As-Is | Required Generalization |
|-------------|--------------------------|-------------------------|
| `.claude/commands/worktree.md` | Hardcodes `bd`, `main`, and repo-local topology assumptions | Parameterize issue tracker, base branch, and topology doc location |
| `scripts/git-topology-registry.sh` | Assumes `docs/GIT-TOPOLOGY-REGISTRY.md` and `docs/GIT-TOPOLOGY-INTENT.yaml` in host repo | Move target paths into config or install-time defaults |
| `.claude/commands/session-summary.md` | Mixes worktree handoff with GitHub secrets inventory | Split portable handoff summary guidance from host-project operational summary |
| `scripts/sync-claude-skills-to-codex.sh` | Bridges every Claude artifact in the repo, not only worktree-skill assets | Create extraction-scoped installer that syncs only selected worktree-skill surfaces |
| `.ai/instructions/codex-adapter.md` | References Moltinger-specific worktree naming and governance paths | Keep in host repo or rewrite as generic adapter notes in extracted docs |

## Files That Should Stay in the Host Project

- `AGENTS.md`
- `.ai/instructions/shared-core.md`
- `.ai/instructions/codex-adapter.md`
- `.github/workflows/*`
- `MEMORY.md`
- `SESSION_SUMMARY.md`
- `docs/SECRETS-MANAGEMENT.md`
- Project runtime configs under `config/`
- Repository-local hooks that encode product or CI policy rather than generic worktree behavior

## Conflicting Artifacts Recorded Before Runtime Extraction

1. The current `worktree` prompt mixes reusable worktree semantics with Beads-specific issue updates and Moltinger topology landing rules.
2. `session-summary.md` mixes portable handoff ideas with GitHub secrets bookkeeping, which is not portable.
3. `git-topology-registry.sh` is logically reusable, but its committed doc targets and naming are still repo-bound.
4. The current Claude-to-Codex bridge script is too broad for an extracted repo because it bundles every Claude command and agent, not only worktree-skill assets.
5. Existing design docs still contain absolute workstation paths and Moltinger-specific examples; they are useful as research input but cannot be shipped as portable runtime assets.

## Proposed Final Repository Naming Options

- `worktree-skill` (working name, preferred for first release)
- `portable-worktree-skill`
- `worktree-flow-kit`
- `worktree-handoff-skill`
- `spec-aware-worktree-skill`

## Proposed Release and Versioning Model

- Use semantic versioning for the standalone repo: `MAJOR.MINOR.PATCH`
- Version compatibility at two layers:
  - Core contract version: branch/worktree/handoff semantics
  - Adapter compatibility version: Claude/Codex/OpenCode registration surface
- Suggested release lanes:
  - `0.x`: extraction hardening and adapter stabilization
  - `1.0.0`: portable repo ready with Claude/Codex/OpenCode and Speckit bridge contracts documented
  - `1.x`: additive adapters, installer improvements, additional examples
- Publish a compatibility table per release showing supported adapter versions and any partial surfaces

## Open Questions

- Should the first extracted repo keep a lightweight `bd` adapter in-tree or leave Beads guidance to documentation only?
- Should the topology registry remain an always-installed core helper, or become an opt-in module layered over the core worktree flow?
- What is the minimum supported OpenCode registration surface for the first release if auto-registration is not yet uniform?
- Should the extracted repo ship host overlay templates directly, or ship a canonical `core/` tree plus install scripts that materialize overlay files?

## Assumptions

- Worktree creation and handoff behavior are the primary product of the extracted repo; issue tracking and host governance are secondary.
- A small number of explicit config variables is acceptable if they replace many hidden Moltinger-specific assumptions.
- Examples can carry limited project-specific illustrations as long as the runtime core does not depend on them.
