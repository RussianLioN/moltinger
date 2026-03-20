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

## Rejected Directions

- **Shared redirect revival**: возвращает cross-worktree leakage и противоречит текущему operating model.
- **Canonical-root mediator as normal path**: делает root tracker неявной шиной и ухудшает ownership transparency.
- **Git merge-driver only fix**: полезен против части noise, но не решает ownership violations и explicit RCA evidence.
- **Background watcher/daemon**: не нужен для deterministic repo-local workflow и усложняет rollback.
