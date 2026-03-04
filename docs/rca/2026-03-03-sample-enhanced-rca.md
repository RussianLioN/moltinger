# RCA: Docker Container 404 через Traefik

**Дата:** 2026-03-03
**Статус:** Resolved
**Влияние:** Production service unavailable for 15 minutes
**Контекст:** Deployment to production server

## Context

*Автоматически собрано через `bash .claude/skills/rca-5-whys/lib/context-collector.sh docker`*

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-03T22:30:00+03:00 |
| PWD | /home/deploy/moltinger |
| Shell | /bin/bash |
| Git Branch | main |
| Git Status | M docker-compose.prod.yml |
| Docker Version | Docker version 24.0.7 |
| Disk Usage | 45% (20G available) |
| Memory | 3.2G/8G |
| Error Type | docker |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | infra |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Container in wrong Docker network | 80% |
| H2 | Traefik labels missing or incorrect | 15% |
| H3 | Container not running | 5% |

## Ошибка

При обращении к `https://moltis.ainetic.tech` возвращается 404. Traefik не маршрутизирует запросы к контейнеру Moltis.

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему возвращается 404? | Traefik не находит маршрут к контейнеру Moltis | `curl -s https://moltis.ainetic.tech` → 404 |
| 2 | Почему Traefik не находит маршрут? | Контейнер Moltis в сети `traefik_proxy`, а Traefik ожидает его в `traefik-net` | `docker inspect moltis --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'` → traefik_proxy |
| 3 | Почему Moltis в неправильной сети? | В docker-compose.yml указана сеть `traefik_proxy`, но на сервере используется `traefik-net` | `grep -A5 networks docker-compose.prod.yml` |
| 4 | Почему конфигурация сети не совпадает с сервером? | Нет проверки соответствия конфигурации перед деплоем | Missing preflight check |
| 5 | Почему нет валидации сетевой конфигурации? | Отсутствует preflight-check для Docker сетей и документация сетевой топологии | No validation script found |

## Корневая причина

Отсутствие системной валидации сетевой конфигурации Docker перед деплоем и документации сетевой топологии продакшена.

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Можно добавить preflight-check и документацию |
| □ Systemic? | yes | Проблема процесса, не ошибка человека |
| □ Preventable? | yes | Автоматическая проверка предотвратит повторение |

## Принятые меры

1. **Немедленное исправление:** Добавлен label `traefik.docker.network=traefik-net` в docker-compose.prod.yml
2. **Предотвращение:** Создан `scripts/preflight-check.sh` с проверкой Docker сетей
3. **Документация:** Зафиксирована сетевая топология в MEMORY.md

## Связанные обновления

- [X] Инструкции CLAUDE.md обновлены
- [X] MEMORY.md обновлён (Docker Networks section)
- [ ] Новые навыки созданы (RCA skill enhanced)
- [ ] Тесты добавлены
- [X] Чеклисты обновлены (preflight-check.sh)

## Уроки

1. Всегда проверять Docker network конфигурацию перед деплоем
2. Документировать сетевую топологию продакшена
3. Использовать явные `traefik.docker.network` labels для избежания неоднозначности

---

*Создано с помощью enhanced rca-5-whys skill (v1.1)*
*Features used: Auto-Context, Chain-of-Thought, Docker Template*
