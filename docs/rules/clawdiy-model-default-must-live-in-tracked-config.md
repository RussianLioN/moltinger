# Clawdiy model default must live in tracked config, not only in runtime wizard state (RCA-017)

**Статус:** Active  
**Дата вступления:** 2026-03-14  
**Область действия:** `config/clawdiy/openclaw.json`, `scripts/render-clawdiy-runtime-config.sh`, `docs/runbooks/clawdiy-repeat-auth.md`, post-deploy verification

## Какую проблему предотвращает это правило

Если модель Clawdiy была настроена только внутри live runtime через wizard или `openclaw models set`, но tracked config не обновлен, любой следующий redeploy вернет агента к шаблонному default-model и сломает рабочий baseline.

## Обязательный протокол

1. Для long-lived Clawdiy baseline tracked template `config/clawdiy/openclaw.json` обязан хранить:
   - `agents.defaults.model.primary`
   - соответствующую запись в `agents.defaults.models`
2. После любого успешного wizard/runtime изменения, влияющего на baseline модель, оператор обязан:
   - проверить live `openclaw models status --agent main --json`
   - зеркалировать новый baseline в tracked config
3. Post-deploy verification обязана подтверждать:
   - `defaultModel`
   - `missingProvidersInUse = []`
   - успешный реальный ответ агента

## Жесткое ограничение

Для Clawdiy запрещено:

- считать живой `auth-profiles.json` достаточным доказательством, что модельный baseline защищен от redeploy;
- оставлять рабочую модель только в runtime state без tracked config update;
- закрывать rollout green, если `defaultModel` откатился к неавторизованному provider.

## Ожидаемое поведение

- Wizard/runtime flow может изменить live состояние.
- Но следующий deploy не сотрет рабочую модель, потому что тот же baseline уже закреплен в GitOps template.
