# Deploy Clawdiy должен иметь auditable checkout repair для Clawdiy-managed surface (RCA-015)

**Статус:** Active  
**Дата вступления:** 2026-03-14  
**Область действия:** `.github/workflows/deploy-clawdiy.yml`, `scripts/gitops-repair-managed-checkout.sh`, `docs/runbooks/clawdiy-deploy.md`, статические проверки Clawdiy deploy

## Какую проблему предотвращает это правило

Если `Deploy Clawdiy` умеет только блокировать dirty server checkout, но не умеет безопасно восстанавливать deploy-managed drift, production rollout замирает даже тогда, когда проблема ограничена управляемой поверхностью Clawdiy и уже может быть исправлена через auditable repair path.

## Обязательный протокол

1. `Deploy Clawdiy` обязан поддерживать `workflow_dispatch`-флаг `repair_server_checkout`.
2. Repair допускается только для Clawdiy-managed surface:
   - `docker-compose.clawdiy.yml`
   - `config/clawdiy/*`
   - `config/fleet/*`
   - `config/backup/*`
   - `scripts/*`
3. Repair должен использовать auditable путь через `scripts/gitops-repair-managed-checkout.sh` с сохранением drift snapshot.
4. Production repair разрешен только из `main` или соответствующего release tag.
5. Если dirty path выходит за пределы Clawdiy-managed surface, workflow обязан fail-closed и не пытаться чинить checkout автоматически.

## Жесткое ограничение

Для Clawdiy запрещено:

- вручную выравнивать `/opt/moltinger` ad-hoc командами через SSH вместо auditable repair path, если drift уже попадает в управляемую поверхность workflow
- добавлять `repair_server_checkout`, который может затронуть произвольные path без явной классификации
- удалять hard gate на dirty checkout без равноценного controlled repair механизма

## Ожидаемое поведение

- Обычный deploy по-прежнему блокируется на грязном checkout.
- Operator может осознанно перезапустить workflow с `repair_server_checkout=true`, если drift ограничен Clawdiy-managed surface.
- Drift snapshot сохраняется до repair, а server checkout после repair и deploy снова совпадает с `main`.
