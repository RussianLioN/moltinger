---
title: "Clawdiy lost gpt-5.4 as default model after redeploy because runtime wizard state was not captured in tracked config"
date: 2026-03-14
severity: P1
category: process
tags: [clawdiy, openclaw, oauth, models, gitops, config, lessons]
root_cause: "Clawdiy model selection was completed interactively inside the live runtime, but the resulting default model state was never mirrored back into tracked config/clawdiy/openclaw.json"
---

# RCA: Clawdiy lost gpt-5.4 as default model after redeploy because runtime wizard state was not captured in tracked config

**Дата:** 2026-03-14  
**Статус:** Resolved  
**Влияние:** Высокое; после успешного rollback на `2026.3.11` Clawdiy снова стал healthy, но `main` откатился на `anthropic/claude-opus-4-6` и потерял рабочий live baseline ответа через `gpt-5.4` до ручного восстановления  
**Контекст:** post-rollback live verification после run `23090952913`

## Ошибка

После green rollback-run `23090952913` live status показал:

```json
{
  "defaultModel": "anthropic/claude-opus-4-6",
  "missingProvidersInUse": ["anthropic"],
  "providersWithOAuth": ["openai-codex (1)"]
}
```

То есть OAuth-профиль `openai-codex` сохранился, но tracked config снова вернул `main` к встроенному default-model, потому что в `config/clawdiy/openclaw.json` не было зафиксировано `agents.defaults.model.primary = openai-codex/gpt-5.4`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему после успешного rollback Clawdiy снова не имел рабочего default-model? | Потому что `defaultModel` откатился к `anthropic/claude-opus-4-6` | live `openclaw models status --agent main --json` |
| 2 | Почему это произошло, если OAuth-профиль сохранился? | Потому что auth store и config state — разные слои; auth profile остался в `auth-profiles.json`, а default model рендерился из tracked config | live status showed `openai-codex` auth `ok`, but default model `anthropic` |
| 3 | Почему tracked config не содержал правильный model default? | Потому что предыдущая настройка `gpt-5.4` была сделана через wizard/runtime command и осталась только в живом `~/.openclaw/openclaw.json` внутри runtime | diff between tracked `config/clawdiy/openclaw.json` and live `data/clawdiy/runtime/openclaw.json` |
| 4 | Почему redeploy смог стереть рабочую модель? | Потому что deploy flow заново рендерит runtime config из tracked template | `scripts/render-clawdiy-runtime-config.sh`, post-rollback live state |
| 5 | Почему это системная ошибка? | Потому что не было явного правила: успешный wizard/runtime change, влияющий на долгоживущий baseline агента, должен быть отражен в GitOps config до следующего deploy | отсутствие `agents.defaults.model.primary` в tracked template до фикса |

## Корневая причина

Настройка `gpt-5.4` была завершена интерактивно внутри live runtime, но resulting default model state не был перенесен обратно в tracked `config/clawdiy/openclaw.json`.

## Принятые меры

1. Live baseline немедленно восстановлен официальной командой:
   - `openclaw models --agent main set openai-codex/gpt-5.4`
2. В tracked `config/clawdiy/openclaw.json` добавлены:
   - `agents.defaults.model.primary = openai-codex/gpt-5.4`
   - `agents.defaults.models["openai-codex/gpt-5.4"] = {}`
3. В статические проверки добавлен guard, что tracked Clawdiy config обязан держать Codex baseline модель.
4. Runbook repeat-auth дополнен требованием зеркалировать live model state обратно в tracked config после wizard/runtime изменений.

## Уроки

1. **OAuth-профиль и default-model — это разные долгоживущие состояния**; наличие auth store не гарантирует правильную рабочую модель.
2. **Все успешные wizard/runtime изменения, влияющие на baseline агента, должны быть отражены в GitOps template** до следующего deploy.
3. **Post-deploy verification обязана проверять не только health и auth, но и `defaultModel`/`missingProvidersInUse`**, иначе функциональная деградация останется скрытой.

---

*Создано по протоколу RCA.*
