# Runtime OAuth token stores must stay under ignored data paths, not tracked config (RCA-019)

**Статус:** Active  
**Дата вступления:** 2026-03-15  
**Область действия:** `scripts/gitops-repair-managed-checkout.sh`, `.github/workflows/deploy.yml`, `.github/workflows/deploy-clawdiy.yml`, runbook'и deploy / rollback

## Какую проблему предотвращает это правило

Если временный или побочный runtime пишет `oauth_tokens.json` рядом с конфигом внутри git checkout, production deploy блокируется на dirty worktree, а OAuth-секреты смешиваются с отслеживаемой конфигурацией.

## Обязательный протокол

1. Runtime OAuth token store не должен жить под tracked `config/` в `/opt/moltinger`.
2. Для Moltis/OpenClaw допустимые runtime-пути должны быть только под ignored `data/` или внутри runtime-home конкретного сервиса.
3. Если GitOps repair обнаруживает `config/oauth_tokens.json`, он обязан:
   - сохранить drift snapshot;
   - перенести файл в `data/oauth-config/oauth_tokens.json` или в timestamped recovered-copy рядом с ним;
   - только потом очищать checkout.
4. Deploy workflow для Clawdiy обязан считать `config/oauth_tokens.json` известным repairable runtime-артефактом, а не hard blocker'ом вне управляемой поверхности.
5. Любой новый runtime test для OAuth обязан писать токены в отдельный ignored runtime/data path, а не рядом с tracked конфигом.

## Жесткое ограничение

Запрещено:

- хранить runtime OAuth token store в `config/` и полагаться на ручную чистку перед deploy;
- удалять stray `config/oauth_tokens.json` без snapshot или controlled evacuation;
- трактовать runtime OAuth token store как обычный tracked config drift.

## Ожидаемое поведение

- OAuth state остается вне git checkout.
- Repair path не теряет токены молча и не стопорит production deploy на известном runtime-артефакте.
- Любой новый drift такого типа оставляет auditable след и переводится в правильное ignored-хранилище.
