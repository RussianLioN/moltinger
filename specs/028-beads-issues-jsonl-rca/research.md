# Research: Deterministic Beads Issues JSONL Ownership

## Scope

Исследование ограничено root cause для drift/шума `.beads/issues.jsonl` между worktree, deterministic ownership/sync моделью, guardrails против nondeterministic rewrites и безопасной migration/rollout стратегией без потери issues.

## Decision 1: Reuse the current repo-local Beads ownership stack

- **Decision**: Строить решение поверх существующих `bin/bd`, `scripts/beads-resolve-db.sh`, `scripts/beads-worktree-audit.sh`, `scripts/beads-normalize-issues-jsonl.sh` и текущего shell test harness.
- **Rationale**: Основная проблема находится между уже существующими слоями, а не в отсутствии инструментария. Новый параллельный wrapper или daemon увеличит число truth sources и усложнит ownership reasoning.
- **Alternatives considered**:
  - Новый отдельный Beads orchestrator: отклонен как избыточный для repo-local workflow hardening.
  - Возврат к `bd-local` как единственному supported path: отклонен, потому что это возвращает UX drift и не закрывает tracked JSONL contract.
- **Library**: Дополнительная библиотека не нужна; текущего shell + Python stdlib достаточно.

## Decision 2: Treat tracked `.beads/issues.jsonl` as an owned projection, not as an incidental side effect

- **Decision**: Считать `.beads/issues.jsonl` branch-local projection, имеющей явного authoritative owner и явно разрешенные rewrite paths.
- **Rationale**: Пока JSONL воспринимается как побочный эффект `bd sync`, один слой может быть локализован корректно, а другой все равно шумит или течет в неправильный tracker.
- **Alternatives considered**:
  - Оставить JSONL как “whatever `bd sync` produced”: отклонено как доказанно nondeterministic.
  - Сделать canonical root единственным shared source of truth: отклонено, потому что это вернет shared-state leakage между worktree.
  - Полностью отказаться от tracked JSONL в пользу только SQLite DB: отклонено для V1, потому что репозиторий уже опирается на tracked issue-state и reviewable diffs.

## Decision 3: Separate semantic mutation from rewrite noise before allowing writes

- **Decision**: Перед mutating rewrite вводить классификацию минимум по трем осям: ownership authority, semantic change presence и canonical-form stability.
- **Rationale**: Нельзя лечить order-only noise и sibling leakage одной и той же эвристикой “перепиши красиво”. Разные классы drift требуют разных guardrail verdicts.
- **Alternatives considered**:
  - Только dependency-order normalization: отклонено, потому что это ловит лишь один класс noise.
  - Полагаться на review/git diff после факта: отклонено, потому что мутация уже произошла.

## Decision 4: Make RCA fixture-driven and machine-readable

- **Decision**: RCA должен опираться на повторяемые fixture scenarios и машинно-читаемые evidence artifacts с устойчивыми decision codes.
- **Rationale**: Разовые narrative-заметки не удерживают качество регрессионного reasoning. Нужно доказуемо воспроизводить leakage/noise сценарии локально и в review.
- **Alternatives considered**:
  - Только markdown RCA без executable reproduction: отклонено как недостаточно для regression safety.
  - Только unit tests без operator-readable journal: отклонено, потому что это не закрывает требование воспроизводимых шагов и логов.

## Decision 5: Keep migration bounded and separate from canonical-root cleanup

- **Decision**: Migration path должен быть audit-first и работать только с конкретными worktree/issue families, не смешиваясь с canonical-root cleanup.
- **Rationale**: Cleanup корневого tracker state требует отдельного gating и не должен прятаться внутри routine sync fix.
- **Alternatives considered**:
  - “Исправить все сразу” одним массовым rewrite: отклонено как слишком рискованное и недетерминированное.
  - Автоматически чистить canonical root по завершении migration: отклонено, потому что это меняет scope и усложняет rollback.

## Decision 6: Roll out in stages and keep rollback explicit

- **Decision**: Включать новый contract этапами `report-only -> controlled enforcement -> verification`, а rollback описать отдельным operator path.
- **Rationale**: Ownership/sync logic затрагивает высокочастотный workflow. Сразу включать hard-blocking без evidence stage рискованно.
- **Alternatives considered**:
  - Мгновенный hard cutover: отклонен как излишне рискованный.
  - Оставить только docs guidance без enforceable gates: отклонено, потому что observed incident уже показал недостаточность docs-only path.

## Decision 7: Treat upstream Beads drift as a compatibility boundary, not as the implementation contract

- **Decision**: Планировать fix как repo-local deterministic ownership layer around the installed runtime and tracked JSONL workflow, а не как прямое копирование любой одной версии upstream docs.
- **Rationale**: Официальные Beads docs/releases одновременно показывают Dolt-native current direction, legacy sync-branch migration guidance и продолжающиеся fix/behavior changes around `bd sync`, JSONL export, hooks, daemon/server mode, and worktrees.
- **Alternatives considered**:
  - Принять локальный `.beads/config.yaml` комментарий про daemon auto-sync как источник истины: отклонено, потому что `bd info` в этой worktree уже показывает `Mode: direct` и `Reason: worktree_safety`.
  - Считать latest upstream docs полным описанием локального установленного `bd 0.49.6`: отклонено, потому что репозиторий и локальная версия могут жить в другой compatibility window, а tracked `.beads/issues.jsonl` все еще активно участвует в текущем workflow.

## External Compatibility Findings: Official Beads + Local Runtime

### Finding A: Current local runtime is `bd 0.49.6` in direct worktree-safe mode

- **Evidence**: `bd --version` reports `0.49.6`; `bd info` in this worktree reports `Database: .../.beads/beads.db`, `Mode: direct`, `Connected: no`, `Reason: worktree_safety`.
- **Implication**: В этой worktree фактический runtime path уже не выглядит как “daemon happily owns sync everywhere”; worktree safety actively suppresses daemon usage.
- **Inference**: Любые repo-level assumptions про automatic daemon-driven JSONL sync должны быть перепроверены против текущего upstream behavior.

### Finding B: Local `.envrc` changes `PATH`, not `.beads/issues.jsonl`

- **Evidence**: Current `.envrc` only prepends `$(git rev-parse --show-toplevel)/bin` to `PATH`; repo-local `bin/bd` then calls `scripts/beads-resolve-db.sh` and delegates to the system `bd`.
- **Implication**: `direnv` affects which `bd` binary runs, not the tracked JSONL file directly.
- **Inference**: `direnv` is relevant as a bootstrap/context factor and can indirectly change `.beads/issues.jsonl` outcomes by selecting the repo shim or bypassing it, but there is no local evidence that `direnv` itself writes the file.

### Finding B1: Repo-local direct writers already exist outside the external `bd sync` export path

- **Evidence**: `.githooks/pre-commit` can invoke `scripts/beads-normalize-issues-jsonl.sh` and then restage `.beads/issues.jsonl`; the normalization helper itself rewrites the tracked file via a temp file and `mv`.
- **Implication**: RCA cannot collapse every JSONL mutation into “`bd sync` wrote it”; local hooks/scripts can also produce tracked rewrites.
- **Inference**: The fix must classify bootstrap selectors, upstream `bd sync` export, and repo-local hook/normalizer rewrites as separate mutation surfaces under one authority/noise contract.

### Finding C: Official upstream Beads docs/releases show active drift in sync semantics

- **Evidence**:
  - Official `README.md` presents Beads as a Dolt-powered tracker and documents env/config concepts like `BEADS_DIR`.
  - Official `docs/CLI_REFERENCE.md` documents explicit `backend`, `sync`, and `sync.branch` settings and says sandbox direct mode disables automatic background sync.
  - Official `docs/PROTECTED_BRANCHES.md` now explicitly says the old protected-branch workflow was removed and that the current solution is Dolt-native sync via `bd dolt push` / `bd dolt pull`; the rest of the page is retained for historical and migration reference.
  - Official release notes in the `0.49.x` line include: `fix(dolt): remove bd sync from AGENTS.md`, `fix(hooks): skip JSONL sync for Dolt backend`, `feat(cli): add bd backend and bd sync mode subcommands`, `fix(sync): respect dolt-native mode in JSONL export paths`, and `fix(sync): disable JSONL sync exports in dolt-native mode`.
- **Implication**: Upstream Beads semantics around `bd sync`, JSONL export, and backend mode have changed materially and may no longer match older repo-local assumptions.
- **Inference**: Our repo must treat upstream Beads compatibility as a first-class research item before hardening `bd sync` behavior around `.beads/issues.jsonl`.

### Finding D: Official upstream worktree/sync-branch edges are still an active source of fixes and user confusion

- **Evidence**:
  - Official release notes mention fixes such as ensuring the sync-branch worktree exists on fresh clone, normalizing JSONL paths in sync-branch mode, skipping sync when source and destination JSONL paths are identical, and using `GetGitCommonDir` for worktree creation in bare repo setups.
  - Official issue #520 documents that daemon auto-sync to a sync branch can fail when pre-commit hooks are installed, and the issue body explicitly points users at `bd sync --flush-only` for diagnosis in that legacy workflow.
- **Implication**: Our RCA cannot assume that worktree + sync-branch + JSONL behavior is a solved or static part of upstream Beads.
- **Inference**: Tests and RCA fixtures in this repo should explicitly model mode/branch/worktree mismatches instead of treating them as impossible states.

### Finding E: Local config assumptions and actual runtime mode may already diverge

- **Evidence**: `.beads/config.yaml` still advertises `auto-start-daemon`, `flush-debounce`, and daemon auto-commit/pull/push semantics, while `bd info` in this worktree reports direct mode with `worktree_safety`.
- **Implication**: Planning cannot assume the tracked config comments describe the actual runtime contract in this worktree.
- **Inference**: Implementation must explicitly separate “what the repo config says” from “what current upstream `bd` actually does here.”

### Finding E1: Repo-local operator guidance still reinforces the older `bd sync`/daemon mental model

- **Evidence**: Local guidance surfaces such as `.claude/docs/beads-quickstart*.md`, `.claude/skills/beads/resources/COMMANDS_QUICKREF.md`, `.claude/skills/beads/resources/WORKFLOWS.md`, and `.beads/config.yaml` continue to prescribe bare `bd sync` and daemon auto-sync language.
- **Implication**: Even if dispatch/runtime behavior is correct, operator and agent guidance can still steer users into stale assumptions about who owns `.beads/issues.jsonl`.
- **Inference**: The rollout must include explicit documentation/task cleanup for repo-local workflow guidance, not only resolver/hook/runtime changes.

### Finding F: User-observed `direnv` load path is a bootstrap signal, not standalone proof of the write path

- **Evidence**: The observed shell message is `direnv: loading ~/coding/moltinger/moltinger-main/.envrc`, but the current `.envrc` computes `repo_root="$(git rev-parse --show-toplevel)"` before prepending `${repo_root}/bin` to `PATH`.
- **Implication**: The visible `.envrc` path and the effective `repo_root` can diverge conceptually; the load message alone does not prove that canonical-root `bin/bd` or canonical-root `.beads/` handled the mutation.
- **Inference**: RCA must capture the bootstrap tuple `direnv load message + git rev-parse --show-toplevel + command -v bd + bd --version + bd info` before attributing any `.beads/issues.jsonl` rewrite to the wrong worktree.

### Finding G: Official Beads documentation is in a transition window, so compatibility must be evidence-led

- **Evidence**: The current official `PROTECTED_BRANCHES.md` explicitly says that the documented workflow has been removed and that Beads now uses Dolt-native sync via `bd dolt push` / `bd dolt pull`, while the current official CLI reference still documents sandbox/direct mode, `--no-auto-flush`, `--no-auto-import`, and JSONL bootstrap/backup flows.
- **Implication**: There is no single short upstream sentence that cleanly describes all installations of Beads right now; different official docs describe different parts of an ongoing storage/sync transition.
- **Inference**: Repo-local hardening must target the observed local runtime (`bd 0.49.6`, direct/worktree-safe mode, repo shim, tracked JSONL) and treat newer upstream Dolt-native release notes as a compatibility vector, not as proof that this repo has already migrated away from JSONL-sensitive paths.

## Official Sources Reviewed

- Official repository / README: <https://github.com/steveyegge/beads>
- Official releases/changelog: <https://github.com/steveyegge/beads/releases>
- Official CLI reference: <https://raw.githubusercontent.com/steveyegge/beads/main/docs/CLI_REFERENCE.md>
- Official protected-branch / sync-branch migration note: <https://raw.githubusercontent.com/steveyegge/beads/main/docs/PROTECTED_BRANCHES.md>
- Official issue example (`sync.branch` + hooks + daemon auto-sync): <https://github.com/steveyegge/beads/issues/520>

## Rejected Directions

- **Shared redirect revival**: возвращает cross-worktree leakage и противоречит текущему operating model.
- **Canonical-root mediator as normal path**: делает root tracker неявной шиной и ухудшает ownership transparency.
- **Git merge-driver only fix**: полезен против части noise, но не решает ownership violations и explicit RCA evidence.
- **Background watcher/daemon**: не нужен для deterministic repo-local workflow и усложняет rollback.
