---
title: "Moltis repo-managed codex-update skill existed in git but never became a live runtime skill"
date: 2026-03-27
severity: P1
category: process
tags: [moltis, skills, gitops, official-docs, runtime-contract, discovery, codex-update]
root_cause: "Project docs, deploy verification, and config relied on /server/skills plus search_paths as a live skill contract, while official Moltis runtime actually discover-ed skills from data-dir-backed default paths"
---

# RCA: Moltis repo-managed codex-update skill existed in git but never became a live runtime skill

**Дата:** 2026-03-27  
**Статус:** Resolved  
**Влияние:** Высокое; `codex-update` был в репозитории и в контейнере, но Moltis в production не видел его как skill и отвечал пользователю так, будто capability отсутствует  
**Контекст:** исправление Moltis skill discovery contract для уведомлений об обновлениях Codex CLI

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-27T00:00:00Z |
| PWD | `/Users/rl/coding/moltinger/moltinger-fix-codex-skill-discovery` |
| Shell | `zsh` |
| Git Branch | `fix/moltis-codex-skill-discovery-contract` |
| Git Status | repo files modified as part of the fix |
| Docker Version | N/A |
| Disk Usage | N/A |
| Memory | N/A |
| Error Type | process |

## Error Classification

| Field | Value |
|-------|-------|
| Error Type | config/process/runtime-contract |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | `codex-update` не был создан в репозитории | 0% |
| H2 | deploy/mount path был верным, но runtime discovery contract был неверно понят | 90% |
| H3 | проблема была только в dirty checkout или rollback логике | 10% |

## Ошибка

Пользователь ожидал, что Moltis умеет сам сообщать о новых версиях Codex CLI через уже созданный `codex-update` skill. На практике в git был `skills/codex-update/SKILL.md`, контейнер видел `/server/skills/codex-update/SKILL.md`, а Moltis всё равно отвечал так, будто навыка нет. Проектная документация и deploy verification подтверждали ложный инвариант: “если `/server/skills` доступен и `search_paths` указывает туда, skill считается live”.

## Проверка прошлых уроков

**Проверенные источники:**
- `docs/LESSONS-LEARNED.md`
- `./scripts/query-lessons.sh --tag moltis`
- historical RCA around official-first runtime contracts

**Релевантные прошлые RCA/уроки:**
1. [Moltis deploy rollback to 0.9.10 after non-official image pin and missing GitOps checkout repair](./2026-03-13-moltis-official-docker-channel-and-gitops-repair.md) — уже учил, что production contract надо строить от official source, а не от локальных предположений.
2. [Clawdiy UI bootstrap был задокументирован как Settings/OAuth flow вместо реального browser bootstrap](./2026-03-12-clawdiy-ui-bootstrap-doc-drift.md) — уже показывал, что documentation drift от official/runtime reality создаёт системные ошибки.
3. [Официальный мастер настройки Clawdiy не мог завершить OAuth из-за неверного контракта домашнего каталога OpenClaw](./2026-03-13-clawdiy-official-wizard-runtime-home-contract-mismatch.md) — уже доказывал, что runtime home contract важнее локальных предположений о путях.

**Что могло быть упущено без этой сверки:**
- Мы могли бы снова “починить” только config или docs, не меняя реальный runtime-discovery path.
- Мы могли бы продолжить считать `search_paths` production-proof, хотя official code/live runtime этого не подтверждают.

**Что в текущем инциденте действительно новое:**
- Проблема затронула не Docker image/update path, а именно Moltis-native skill discovery contract для Git-managed repo skills.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему пользователь не видел `codex-update` как доступный навык? | Потому что live Moltis не discover-ил repo-managed skill как runtime skill | live server logs watched `/home/moltis/.moltis/skills`; `codex-update` не загружался из `/server/skills` |
| 2 | Почему live runtime не discover-ил skill из `/server/skills`? | Потому что основной runtime discovery использует data-dir-backed default paths, а не наш локальный repo path | official `crates/skills/src/discover.rs`, `crates/chat/src/lib.rs`, `crates/gateway/src/server.rs` |
| 3 | Почему проект всё равно считал `/server/skills` правильным контрактом? | Потому что docs, config и deploy verification закрепили это как “live visibility” | `config/moltis.toml`, `docs/moltis-codex-update-skill.md`, `docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md`, `scripts/deploy.sh` before fix |
| 4 | Почему этот неверный контракт не был пойман тестами? | Потому что тесты проверяли наличие mount/path и прямой shell runtime, но не actual runtime discovery через live Moltis | `tests/static/test_config_validation.sh`, `tests/component/test_moltis_codex_update_*` before fix |
| 5 | Почему это системная проблема, а не единичная ошибка skill migration? | Потому что команда ориентировалась на локальную методичку, а не на official docs + upstream runtime code + live evidence | canonical project docs drifted away from official Moltis skill contract |

## Корневая причина

Проект смешал три разных слоя в один ложный контракт:

1. Git-tracked repo source `skills/`
2. container-visible repo mount `/server/skills`
3. live Moltis skill discovery

В official Moltis это не одно и то же. Репозиторий и `/server/skills` были только source surface, но не runtime discovery surface. В результате capability считалась внедрённой по статическим признакам, хотя live runtime её не видел.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Исправляется deploy/install contract, docs и tests |
| □ Systemic? | yes | Ошибка была закреплена в нескольких canonical surfaces |
| □ Preventable? | yes | Runtime-first acceptance и official-first research это предотвращают |

## Принятые меры

1. **Немедленное исправление:** добавлен `scripts/moltis-repo-skills-sync.sh`, а deploy verification теперь sync-ит repo-managed skills в `/home/moltis/.moltis/skills`, логинится через `/api/auth/login` и проверяет их через аутентифицированный live `/api/skills`.
2. **Предотвращение:** `config/moltis.toml` больше не утверждает `/server/skills` как live contract; static/unit/component tests переписаны на runtime-first proof.
3. **Документация:** добавлен официальный research artifact `docs/research/moltis-official-skill-runtime-contract-2026-03-27.md`, обновлены canonical skill docs и self-learning handbook.

## Связанные обновления

- [ ] Новый файл правила создан (docs/rules/ или .claude/skills/)
- [ ] Краткая ссылка добавлена в CLAUDE.md (1-2 строки)
- [ ] Новые навыки созданы
- [x] Тесты добавлены
- [x] Чеклисты обновлены

## Уроки

1. Для Moltis skill delivery нельзя считать repo path и live discovery одним и тем же контрактом.
2. `search_paths` в конфиге не является достаточным production-proof, пока live runtime и official callsites не подтверждают это явно.
3. Для GitOps-managed skills acceptance должен идти от аутентифицированного live `/api/skills` и реального использования skill, а не от mount/path existence.
4. Если official docs и live behavior расходятся, нужно поднимать authoritative research artifact и фиксировать принятый production contract отдельно, а не размазывать частичные выводы по handbook-ам.
