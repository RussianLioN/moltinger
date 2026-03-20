# Implementation Plan: Deterministic Beads Issues JSONL Ownership

**Branch**: `028-beads-issues-jsonl-rca` | **Date**: 2026-03-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/028-beads-issues-jsonl-rca/spec.md`

## Summary

Текущее состояние репозитория уже закрывает часть Beads-рисков: plain `bd` роутится через repo-local shim, canonical root mutating path блокируется по умолчанию, legacy redirect residue локализуется отдельным helper’ом, а dependency ordering в `.beads/issues.jsonl` частично нормализуется. Но это не закрывает всю проблему, потому что observed issue касается не только runtime DB routing. В `SESSION_SUMMARY.md` отдельно зафиксирован случай, когда даже после localized ownership `bd sync` из manual hotfix worktree все еще мог экспортировать state в canonical root `.beads/issues.jsonl`.

Следовательно, проблема лежит в missing deterministic ownership/sync contract именно для tracked `.beads/issues.jsonl`. Дополнительно появился важный compatibility signal: локально установлен `bd 0.49.6`, а `bd info` в этой worktree сообщает `Mode: direct` и `Reason: worktree_safety`, при том что локальный `.beads/config.yaml` и часть repo-local docs/skills все еще описывают daemon/auto-sync-to-JSONL assumptions. Значит перед implementation нужно отдельно сверить repo-local JSONL workflow с текущей официальной моделью upstream Beads.

План вводит единый слой sync authority для JSONL rewrites, воспроизводимый RCA/evidence path, noise-vs-semantic classification, bounded migration workflow и отдельные rollout/rollback stages. Implementation останется script-first и reuse-first: существующие resolver, audit, normalization и recovery surfaces расширяются, а не заменяются второй параллельной системой. `direnv` рассматривается здесь как repo-local bootstrap factor, который влияет на выбор `bd` через `PATH`, но не считается прямым writer’ом `.beads/issues.jsonl`.

## Observed Local Integration

- User-observed `direnv: loading ~/coding/moltinger/moltinger-main/.envrc` messages are relevant evidence inputs, but they are not standalone proof that canonical-root `bd` handled a rewrite. Current `direnv status` in this worktree resolves the loaded RC to this worktree’s `.envrc`, and that `.envrc` computes `repo_root` dynamically via `git rev-parse --show-toplevel` before prepending `<repo_root>/bin` to `PATH`, so `direnv` affects which `bd` binary wins in the current shell but does not write `.beads/issues.jsonl` by itself.
- Repo-local `bin/bd` sources `scripts/beads-resolve-db.sh`, then either blocks unsafe commands, passes through read-only/global flows, or execs the installed system `bd` against the current worktree DB.
- The installed runtime in this worktree is `bd 0.49.6`; `bd info` currently reports `Mode: direct` and `Reason: worktree_safety`, which already diverges from older daemon-centric assumptions in local comments/config.
- Tracked JSONL can still be rewritten by repo-local mutation surfaces such as `.githooks/pre-commit` and `scripts/beads-normalize-issues-jsonl.sh`, so RCA must distinguish “bootstrap picked a different `bd`” from “a local hook/script rewrote JSONL”.
- Official upstream Beads docs and release notes now emphasize Dolt-native paths and show active churn around `bd sync`, sync mode, JSONL export, and worktree handling, so this feature must treat upstream behavior as a compatibility boundary, not as a fixed invariant.
- RCA evidence must therefore capture both bootstrap context and writer context as one tuple: `direnv status`, computed repo root, resolved `bd` binary, installed `bd` version/mode, and the mutation surface that actually touched tracked JSONL.

## Technical Context

**Language/Version**: Bash/Zsh shell scripts, Markdown artifacts, Python 3 stdlib for deterministic JSONL canonicalization helpers
**Primary Dependencies**: `git`, installed `bd 0.49.6`, existing repo-local `bin/bd`, `scripts/beads-resolve-db.sh`, `scripts/beads-worktree-audit.sh`, `scripts/beads-normalize-issues-jsonl.sh`, tracked git hooks, existing shell test harness
**Storage**: Worktree-local `.beads/beads.db`, branch-local tracked `.beads/issues.jsonl`, repo-local RCA evidence/journal artifacts, spec-driven docs/contracts
**Testing**: Shell unit tests, static guardrail tests, fixture-based RCA scenario tests, focused quickstart validation for rollout/rollback
**Target Platform**: macOS/Linux developer and Codex/App multi-worktree workflows with POSIX-shell-compatible behavior
**Project Type**: Repository workflow hardening for multi-worktree Beads state ownership
**Performance Goals**: Sync authority resolution and noise classification complete before write handoff with no noticeable delay in daily `bd sync`; RCA fixtures remain fast enough for local regression usage; repeat safe sync yields byte-stable JSONL
**Constraints**: No silent canonical-root fallback, no sibling rewrite leakage, no issue loss during migration, no blind cleanup in `main`, no assumption that `direnv` alone guarantees safety, repo-local bootstrap effects must be distinguished from upstream Beads behavior, rollout and rollback must be separate, docs/tests/guardrails are mandatory
**Scale/Scope**: 3 user stories, 26 functional requirements, one deterministic ownership/sync model, one RCA evidence flow, one migration/rollout/rollback contract, and repo-wide guardrails against nondeterministic JSONL rewrites

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Context-First Development | ✅ PASS | Existing Beads dispatch, localization, normalization, audit, recovery, quickstart, static tests, operating-model docs, and session evidence were reviewed before planning |
| II. Single Source of Truth | ✅ PASS | Plan converges runtime DB ownership, tracked JSONL rewrite authority, and migration evidence into one deterministic ownership/sync contract |
| III. Library-First Development | ✅ PASS | No new external library is justified; current shell stack plus Python stdlib is sufficient for canonicalization and evidence serialization |
| IV. Code Reuse & DRY | ✅ PASS | Plan extends existing `bin/bd`, resolver, audit, normalization, recovery, and shell-test surfaces instead of introducing a parallel Beads control plane |
| V. Strict Type Safety | ✅ N/A | Scope is shell/Markdown/Python stdlib helper logic, not TypeScript |
| VI. Atomic Task Execution | ✅ PASS | RCA evidence, guardrails, migration, rollout docs, and tests are separable into small independently reviewable slices |
| VII. Quality Gates | ✅ PASS | Unit/static/fixture tests plus quickstart validation and doc updates are required deliverables |
| VIII. Progressive Specification | ✅ PASS | Spec, plan, tasks, and read-only analyze are being produced before any implementation |

**Gate Status**: ✅ ALL PASS - proceed to design artifacts and task generation.

## Project Structure

### Documentation (this feature)

```text
specs/028-beads-issues-jsonl-rca/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── jsonl-rewrite-guard-contract.md
│   ├── migration-rollout-contract.md
│   ├── ownership-sync-contract.md
│   └── rca-evidence-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
bin/
└── bd                                  # Existing repo-local Beads entrypoint

scripts/
├── beads-resolve-db.sh                 # Existing ownership resolver to extend with JSONL sync authority
├── beads-normalize-issues-jsonl.sh     # Existing canonicalization helper to extend beyond dependency-order-only noise
├── beads-worktree-audit.sh             # Existing sibling ownership audit to extend with JSONL authority checks
├── beads-recovery-batch.sh             # Existing recovery workflow to align with migration boundary
├── beads-issues-jsonl-rca.sh           # Planned reproducible RCA/evidence runner
└── beads-sync-migration.sh             # Planned audit/apply/rollback workflow for existing worktrees

docs/
├── beads-issues-jsonl-sync-model.md
├── CODEX-OPERATING-MODEL.md
├── WORKTREE-HOTFIX-PLAYBOOK.md
├── rules/
│   └── beads-issues-jsonl-deterministic-sync-authority.md
└── rca/
    └── 2026-03-xx-beads-issues-jsonl-drift-ownership-gap.md

.githooks/
├── pre-commit
└── pre-push

.claude/docs/
├── beads-quickstart.md
└── beads-quickstart.en.md

.claude/skills/beads/resources/
├── COMMANDS_QUICKREF.md
└── WORKFLOWS.md

tests/
├── unit/
│   ├── test_bd_dispatch.sh
│   ├── test_beads_issues_jsonl_sync.sh
│   ├── test_beads_normalize_issues_jsonl.sh
│   ├── test_beads_worktree_audit.sh
│   ├── test_beads_issues_jsonl_rca.sh
│   └── test_beads_sync_migration.sh
└── static/
    └── test_beads_worktree_ownership.sh
```

**Structure Decision**: Keep daily-work ownership logic inside the current repo-local Beads surfaces and add only two dedicated flows: one reproducible RCA/evidence runner and one explicit migration/rollout workflow. This avoids another long-lived wrapper layer while making tracked JSONL rewrite authority explicit and testable.

## Phase 0: Research Decisions

Research outcomes are recorded in [research.md](./research.md). The design direction is:

1. Treat `.beads/issues.jsonl` as an owned tracked projection, not as an incidental byproduct of whichever worktree ran `bd sync`.
2. Extend current ownership resolution so tracked JSONL rewrites have explicit authority checks and deterministic decision codes.
3. Distinguish semantic issue mutation from nondeterministic rewrite noise before any write is allowed.
4. Make RCA evidence reproducible through fixture-driven logs and stable machine-readable verdicts.
5. Keep migration audit/apply/rollback separate from routine sync and separate from canonical-root cleanup.
6. Roll out enforcement in stages: observe, enforce, verify, with a separate rollback path.
7. Before implementation, verify the current official Beads docs/releases/issues for `bd sync`, sync mode, worktree safety, and JSONL export semantics so the repo does not harden a stale upstream assumption.
8. Treat `direnv` as a repo-local bootstrap path that changes which `bd` binary wins on `PATH`; do not treat it as direct evidence that `direnv` itself writes `.beads/issues.jsonl`.
9. Reconcile repo-local tracked-JSONL workflow against current upstream Dolt-native guidance before finalizing execution order, because the local branch is pinned to installed `bd 0.49.6`, not to whatever the latest README now recommends.
10. Require RCA fixtures and operator docs to log the bootstrap tuple (`direnv status`, `git rev-parse --show-toplevel`, `command -v bd`, `bd --version`, `bd info`) before attributing any cross-worktree JSONL rewrite.

## Phase 1: Design Outcomes

Phase 1 artifacts define:

- the ownership/sync entities and evidence lifecycle in [data-model.md](./data-model.md)
- sync authority invariants in [contracts/ownership-sync-contract.md](./contracts/ownership-sync-contract.md)
- rewrite classification and blocking rules in [contracts/jsonl-rewrite-guard-contract.md](./contracts/jsonl-rewrite-guard-contract.md)
- reproducible RCA expectations in [contracts/rca-evidence-contract.md](./contracts/rca-evidence-contract.md)
- migration, rollout, and rollback boundaries in [contracts/migration-rollout-contract.md](./contracts/migration-rollout-contract.md)
- operator-facing validation scenarios in [quickstart.md](./quickstart.md)

## Phase 2: Execution Readiness

- Implementation will stay script-first and reuse current Beads ownership surfaces.
- Guardrails will be added before broad workflow changes so leakage/noise cannot be reintroduced silently.
- RCA and migration flows will be fixture-driven and must produce machine-readable evidence that reviewers can compare across reruns.
- High-traffic docs and operating-model guidance must reflect the final deterministic ownership/sync model and keep canonical-root cleanup out of the daily sync path.
- No implementation task should start until the official Beads review, bootstrap evidence model, and consilium checkpoint are complete and reflected in task ordering.
- Before Phase B implementation starts, a consilium checkpoint must reconcile official upstream Beads semantics, local bootstrap evidence, and the repo-local JSONL workflow, then refresh task ordering if needed.

## V1 Scope Freeze

### In Scope

- One explicit deterministic ownership/sync contract for tracked `.beads/issues.jsonl`
- One reproducible RCA/evidence flow for drift/noise scenarios
- One bounded migration workflow for current, legacy, and ambiguous worktrees
- Report-only, enforce, verify rollout stages plus a separate rollback contract
- Unit/static regression coverage for leakage, noise, ambiguity, and byte-stable safe sync
- Documentation and operator rules for the new contract

### Out of Scope

- Bulk canonical-root cleanup in the same feature
- Prefix migration for historic `molt` / `moltinger-*` issue namespaces
- Replacing Beads with another tracker or removing tracked `.beads/issues.jsonl` entirely
- Silent best-effort recovery for ambiguous ownership cases
- Unrelated topology-publish or deploy-drift work outside Beads issue-state ownership

## Executor Lanes

| Lane | Scope | Primary owner |
|---|---|---|
| `sync-core` | `bin/bd`, resolver, normalization, git-hook enforcement | main implementer |
| `rca-evidence` | RCA runner, evidence schema, RCA doc | main implementer |
| `migration-rollout` | migration audit/apply/rollback surfaces and operator docs | main implementer |
| `tests` | unit/static/fixture coverage | main implementer, reviewable independently |

## Test Fixture Strategy

- Reuse temporary repo/worktree fixtures from the existing shell harness.
- Model at least one manual hotfix leakage scenario, one noise-only rewrite scenario, one ambiguous owner scenario, and one safe byte-stable sync scenario.
- Model bootstrap variance explicitly: repo-local shim selected on `PATH` versus system `bd` bypassing the shim.
- Capture before/after hashes and normalized diff classes for `.beads/issues.jsonl`.
- Ensure migration fixtures cover current, legacy, partial, duplicate, and blocked worktrees without requiring canonical-root cleanup.

## Agent Context Update

- No new language, framework, or external service is introduced.
- Agent context files do not need semantic updates beyond the new Speckit package.
