# Clawdiy upgrade health must tolerate official OpenClaw startup warmup (RCA-018)

**Статус:** Active  
**Дата вступления:** 2026-03-14  
**Область действия:** `docker-compose.clawdiy.yml`, `scripts/deploy.sh`, `.github/workflows/deploy-clawdiy.yml`, operator runbooks

## Какую проблему предотвращает это правило

Official OpenClaw Docker image при cold start и включенных каналах может проходить через временный `unhealthy`, а затем самостоятельно восстановиться в `healthy`. Если Clawdiy deploy трактует первый `unhealthy` как окончательный провал, production update откатится слишком рано.

## Обязательный протокол

1. Clawdiy health window обязан учитывать startup и channel warmup OpenClaw, а не только “голый” запуск gateway.
2. Docker healthcheck для Clawdiy должен иметь расширенный startup grace period.
3. Deploy verification для Clawdiy не должен завершаться ошибкой на первом `unhealthy`, если:
   - контейнер продолжает работать;
   - общий rollout timeout еще не исчерпан.
4. Если локальный Clawdiy `/health` уже отвечает `200`, rollout может считаться готовым даже до того, как Docker успеет обновить внутренний health status.
5. Итоговый rollback допустим только после исчерпания общего timeout или явного terminal state (`exited` / `dead`).

## Жесткое ограничение

Для Clawdiy запрещено:

- считать Docker `unhealthy` во время startup автоматическим доказательством несовместимости нового official OpenClaw image;
- держать startup grace короче, чем фактический warmup official OpenClaw с каналами;
- откатывать upgrade candidate без проверки, не начал ли контейнер уже отдавать `200` на локальный `/health`.

## Ожидаемое поведение

- Official OpenClaw upgrade canary может пережить временный `unhealthy` и все равно завершиться green.
- Rollback срабатывает только при настоящем terminal failure, а не при ложном cold-start сигнале.
- Следующий upgrade на `2026.3.12+` проверяется воспроизводимо и без лишних откатов.
