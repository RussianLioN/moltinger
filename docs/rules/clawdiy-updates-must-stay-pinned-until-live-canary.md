# Clawdiy updates must stay pinned until live canary proves the new image (RCA-016)

**Статус:** Active  
**Дата вступления:** 2026-03-14  
**Область действия:** `.github/workflows/deploy-clawdiy.yml`, `scripts/deploy.sh`, `scripts/preflight-check.sh`, `scripts/health-monitor.sh`, operator runbooks

## Какую проблему предотвращает это правило

Если repo-default Clawdiy image переключить на плавающий `ghcr.io/openclaw/openclaw:latest` до отдельной live-проверки, следующий обычный production deploy может немедленно выкатить непроверенный образ и увести Clawdiy в `unhealthy`.

## Обязательный протокол

1. Tracked default image для Clawdiy обязан оставаться pinned на последнем live-verified baseline.
   - Если exact GHCR tag отсутствует, pinned baseline фиксируется digest-референсом.
   - Текущий live-verified baseline: `ghcr.io/openclaw/openclaw@sha256:d7e8c5c206b107c2e65b610f57f97408e8c07fe9d0ee5cc9193939e48ffb3006` (`org.opencontainers.image.version=2026.3.13-1`).
2. Новый OpenClaw образ для Clawdiy запускается только как явный upgrade rollout через `workflow_dispatch` input `clawdiy_image`.
3. До перевода нового образа в tracked default upgrade candidate обязан пройти:
   - `Deploy Clawdiy` green
   - внешний `/health`
   - `docker inspect ... healthy`
   - `./scripts/clawdiy-runtime-attestation.sh --json`
   - `openclaw models status --agent main --json`
   - реальный canary-ответ агента
4. Если rollout провалился, tracked default не меняется; выполняется rollback на предыдущий pinned image.

## Жесткое ограничение

Для Clawdiy запрещено:

- менять repo-default на floating `latest` только потому, что это официальный Docker channel;
- считать GitHub release page достаточным доказательством безопасности нового Docker image;
- использовать новый image как стандартный default до live-canary.

## Ожидаемое поведение

- Обычный deploy всегда ведет на последний подтвержденный pinned baseline.
- Upgrade testing идет как явное отдельное действие.
- Новая версия становится default только после доказанного live-успеха.
