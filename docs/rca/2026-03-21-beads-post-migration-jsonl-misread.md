# RCA: Beads post-migration `.beads/issues.jsonl` was misread as backlog loss

**Date:** 2026-03-21  
**Status:** Resolved  
**Влияние:** Соседние preserved worktree могли ошибочно воспринимать штатное post-migration состояние как неожиданное удаление backlog, останавливать работу и уходить в `docs/plans/*` вместо локальной Dolt-backed Beads БД.

## Ошибка

После Dolt migration и local-only cleanup агент в sibling worktree увидел
`D .beads/issues.jsonl` и интерпретировал это как unexpected deletion /
backlog unavailable. Это вызвало лишнюю эскалацию и уход от Beads source of
truth.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ |
|---------|--------|-------|
| 1 | Почему агент решил, что backlog недоступен? | Потому что в worktree отсутствовал tracked `.beads/issues.jsonl`, а это трактовалось как missing foundation. |
| 2 | Почему отсутствие tracked JSONL трактовалось как missing foundation? | Потому что часть системной логики и вспомогательных скриптов всё ещё жила в SQLite-era модели, где JSONL считался обязательным признаком валидного состояния. |
| 3 | Почему эта SQLite-era модель пережила Dolt migration? | Потому что миграция закрыла runtime/cutover path, но не довела до конца compatibility helpers, audit/localize классификацию и prompt-level guardrails для preserved sibling worktree. |
| 4 | Почему helper-слои и инструкция разошлись? | Потому что не было одного зафиксированного правила для post-migration состояния `config + local runtime + no tracked issues.jsonl` и тестов, которые бы требовали одинаковой трактовки во всех слоях. |
| 5 | Почему не было такого правила и тестов? | Потому что migration acceptance была сосредоточена на active target cutover, а residual preserved sibling repair path не был превращён в first-class, тестируемый системный контракт. |

## Корневая причина

Не было зафиксированного и тестируемого системного контракта для
post-migration состояния preserved worktree, где tracked
`.beads/issues.jsonl` уже retired, а source of truth живёт только в локальном
Beads runtime.

## Принятые меры

1. **Немедленное исправление:** главная системная инструкция теперь прямо запрещает трактовать отсутствие tracked `.beads/issues.jsonl` как proof of backlog loss и требует сначала использовать локальную Dolt-backed Beads БД.
2. **Предотвращение:** `scripts/beads-worktree-localize.sh`, `scripts/beads-worktree-audit.sh` и `scripts/bd-local.sh` синхронизированы с post-migration local-runtime state.
3. **Документация:** добавлено правило [docs/rules/beads-post-migration-local-runtime-state.md](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/docs/rules/beads-post-migration-local-runtime-state.md) и расширено описание в [docs/CODEX-OPERATING-MODEL.md](/Users/rl/coding/moltinger/029-beads-dolt-native-migration/docs/CODEX-OPERATING-MODEL.md).
4. **Тесты:** добавлены проверки на state `post_migration_runtime_only` и на наличие repair protocol в root instructions.

## Связанные обновления

- [x] Новый файл правила создан
- [x] Главная системная инструкция обновлена
- [x] Тесты добавлены

## Уроки

- После архитектурной миграции нужно закрывать не только target cutover, но и
  state vocabulary для preserved sibling worktree.
- Prompt-level guidance без синхронизации с helper scripts и тестами быстро
  деградирует обратно в старую модель.
- Для Beads migration отсутствие tracked JSONL само по себе больше не является
  сигналом потери backlog; сигналом является только невозможность открыть
  локальный runtime после read-only диагностики.
