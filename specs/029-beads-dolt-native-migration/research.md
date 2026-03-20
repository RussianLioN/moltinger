# Research: Beads Dolt-Native Migration

## Scope

Исследование ограничено миграцией проекта на новый `beads` contract, который соответствует текущему upstream Dolt-native direction, но учитывает фактический локальный CLI/runtime и repo-local legacy surfaces.

## Decision 1: Target upstream Dolt-native Beads, but do not do immediate full cutover

- **Decision**: Целевой архитектурой считается текущий official upstream Beads contract вокруг Dolt-native backend and sync model.
- **Rationale**: Official docs описывают Dolt-native path как основной, а legacy sync-branch / JSONL-first workflow уже не выглядит recommended everyday path.
- **Alternatives considered**:
  - Остаться на legacy JSONL-first contract как долгосрочной архитектуре: отклонено как стратегическая консервация drift-prone path.
  - Сделать немедленный full cutover: отклонено как слишком рискованное для текущего repo topology.
- **Library**: Дополнительные библиотеки не нужны; migration опирается на existing `bd` CLI and repo scripts.

## Decision 2: Treat tracked `.beads/issues.jsonl` as a migration source, not the long-term source of truth

- **Decision**: Migration должна перестать проектировать tracked `.beads/issues.jsonl` как primary issue-state transport.
- **Rationale**: Official upstream docs связывают JSONL прежде всего с export/backup/portability, а не с основным sync contract.
- **Alternatives considered**:
  - Сохранить `.beads/issues.jsonl` в роли постоянного primary sync artifact: отклонено.
  - Удалить `.beads/issues.jsonl` немедленно без compatibility phase: отклонено, потому что текущий repo еще heavily depends on it.

## Decision 3: Inventory first, then report-only compatibility, then pilot

- **Decision**: До любого mutating cutover сначала нужен полный inventory всех repo-local surfaces, затем report-only compatibility layer, и только потом pilot worktree.
- **Rationale**: Репо использует legacy behavior не только в runtime, но и в docs, hooks, tests, bootstrap and operator guidance.
- **Alternatives considered**:
  - Делать pilot без inventory: отклонено как слишком слепой путь.
  - Делать массовый rollout сразу после inventory: отклонено как unsafe without pilot evidence.

## Decision 4: Ban long-lived mixed mode

- **Decision**: Mixed mode, где часть worktree живет по legacy JSONL-first workflow, а часть по новому contract, недопустим как steady state.
- **Rationale**: Это создаст двойной source of truth и новые drift scenarios.
- **Alternatives considered**:
  - Разрешить indefinite mixed mode: отклонено.
  - Жестко переключить все worktree за один шаг: отклонено как операционно рискованный путь.

## Decision 5: Keep rollout and rollback separate and evidence-preserving

- **Decision**: Rollout должен идти stages `report-only -> pilot -> controlled cutover -> verification`, а rollback должен быть отдельной documented procedure.
- **Rationale**: Возврат должен восстанавливать operator usability and consistent issue-state, а не только отменять wrapper changes.
- **Alternatives considered**:
  - Rollback как скрытая часть rollout script: отклонено.
  - Docs-only rollback without snapshots/evidence: отклонено.

## Decision 6: Scope migration against the local `bd 0.49.6` command surface

- **Decision**: Migration design must be compatible with the observed local CLI/runtime (`bd 0.49.6`) until an explicit version-upgrade step is separately proven.
- **Rationale**: Local CLI already exposes `backend`, `branch`, `vc`, `export`, `sync`, `migrate`, `migrate dolt`, but the repo still uses SQLite backend and shared/canonical-root coupling in practice.
- **Alternatives considered**:
  - Assume latest upstream docs fully describe the installed local binary: отклонено.
  - Freeze migration to current SQLite-only behavior: отклонено.

## Direct Findings: Official Upstream

### Finding A: Official upstream now centers Beads around Dolt-native usage

- **Evidence**: Official `README.md`, `docs/DOLT.md`, and `docs/CONFIG.md` describe Beads as Dolt-powered and document Dolt-native configuration and workflows.
- **Implication**: The project should migrate toward Dolt-native Beads rather than deepen legacy JSONL-first assumptions.
- **Inference**: Current repo-local wrappers/docs should be treated as migration subjects, not as target architecture.

### Finding B: JSONL is now framed as export/backup portability, not the primary sync layer

- **Evidence**: Official `docs/CONFIG.md` and `docs/CLI_REFERENCE.md` tie JSONL to export/import/backup flows.
- **Implication**: Keeping tracked `.beads/issues.jsonl` as the main operational truth would diverge from upstream direction.
- **Inference**: Repo-local review surface must be redesigned for the new contract.

### Finding C: Old sync-branch/protected-branch guidance is historical or transitional

- **Evidence**: Official `docs/PROTECTED_BRANCHES.md` says the old workflow was removed; `docs/WORKTREES.md` still carries transitional/historical material; official issues `#519`, `#520`, `#1860`, `#1663`, `#1667`, `#1744` show prolonged instability or confusion in sync/worktree/JSONL behavior.
- **Implication**: Migration must not rely on “stock legacy behavior will probably be fine”.
- **Inference**: Inventory, pilot, and rollback are mandatory, not optional polish.

## Direct Findings: Local Repo + CLI

### Finding D: The local CLI is transition-capable, but the repo is still on SQLite + JSONL-first behavior

- **Evidence**:
  - `bd --version` reports `0.49.6`
  - `bd backend show` reports `sqlite`
  - `bd migrate dolt --help` exists
  - `bd branch --help` and `bd vc --help` exist and explicitly require Dolt backend
  - `bd export --help` still supports JSONL export
- **Implication**: The local CLI can support migration work, but the repo has not yet adopted the new backend contract.
- **Inference**: Migration can be piloted without waiting for a separate tooling rewrite, but it still needs staged repo adaptation.

### Finding E: The new `029` worktree still resolves Beads state through canonical-root coupling

- **Evidence**: `bd backend show` and `bd info` in the new `029` worktree point to `/Users/rl/coding/moltinger/moltinger-main/.beads`.
- **Implication**: Current topology behavior is exactly the kind of coupling that makes immediate cutover unsafe.
- **Inference**: Pilot and rollout must explicitly validate worktree isolation under the new contract.

### Finding F: Repo-local legacy surfaces are numerous and materially operational

- **Evidence**: `AGENTS.md`, `.beads/AGENTS.md`, `.beads/config.yaml`, `.githooks/pre-commit`, `.envrc`, `bin/bd`, `scripts/beads-resolve-db.sh`, `scripts/beads-normalize-issues-jsonl.sh`, `scripts/worktree-ready.sh`, `.claude/docs/beads-quickstart*.md`, `.claude/skills/beads/resources/*`, and multiple tests still encode JSONL-first and `bd sync` expectations.
- **Implication**: Migration is not only a backend flip; it is a workflow contract rewrite.
- **Inference**: Full cutover must include docs, hooks, bootstrap, and tests alignment.

## Official Sources Reviewed

- Official repository / README: <https://github.com/steveyegge/beads>
- Official Dolt backend guide: <https://github.com/steveyegge/beads/blob/main/docs/DOLT.md>
- Official config reference: <https://raw.githubusercontent.com/steveyegge/beads/main/docs/CONFIG.md>
- Official CLI reference: <https://raw.githubusercontent.com/steveyegge/beads/main/docs/CLI_REFERENCE.md>
- Official protected-branch migration note: <https://raw.githubusercontent.com/steveyegge/beads/main/docs/PROTECTED_BRANCHES.md>
- Official worktree note: <https://github.com/steveyegge/beads/blob/main/docs/WORKTREES.md>
- Official issues: <https://github.com/steveyegge/beads/issues/519>, <https://github.com/steveyegge/beads/issues/520>, <https://github.com/steveyegge/beads/issues/1860>, <https://github.com/steveyegge/beads/issues/1663>, <https://github.com/steveyegge/beads/issues/1667>, <https://github.com/steveyegge/beads/issues/1744>

## Rejected Directions

- **Immediate full cutover**: отклонен как unsafe for current repo-local contract.
- **Legacy JSONL-first as final design**: отклонен как divergence from upstream direction.
- **Indefinite mixed mode**: отклонен как guaranteed double-source-of-truth risk.
- **Docs-only adaptation without pilot/rollback**: отклонено как недостаточно для migration safety.
