---
title: "Telegram authoritative UAT could pass on provider/model resolution errors"
date: 2026-03-20
severity: P1
category: cicd
tags: [telegram, uat, quality-gate, model-routing, ci]
root_cause: "Reply-quality checks treated transport/runtime error text as valid content because error-signature matching did not include model/provider-resolution failures"
---

# RCA: Telegram authoritative UAT could pass on provider/model resolution errors

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Ручной post-deploy UAT мог завершаться `passed`, даже когда фактический ответ бота содержал ошибку маршрутизации модели (`model ... not found`). Это давало ложный зелёный сигнал готовности.

## Ошибка

Authoritative Telegram Web UAT подтверждал только факт корректной атрибуции и базовые сигнатуры ошибок (timeout/traceback/etc), но не учитывал класс ошибок выбора модели/провайдера:

- `model 'openai-codex::gpt-5.4' not found`
- provider authentication/provider unavailable семейство ошибок

В результате такие ответы могли проходить как валидный reply-quality `pass`.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему UAT показывал `passed` при проблеме с моделью? | Потому что quality-check проверял наличие ответа и общий `ERROR_RE`, но не ловил `model ... not found`. | Артефакты run `23330788996`/`23332083116`: `run.verdict=passed` при reply с `model ... not found`. |
| 2 | Почему эта сигнатура не попадала в error-classification? | Regex был ориентирован на generic runtime errors (timeout/exception) и не покрывал provider/model resolution path. | `scripts/telegram-web-user-probe.mjs` до фикса: `ERROR_RE` без `model ... not found`/provider-auth patterns. |
| 3 | Почему дефект не был зафиксирован тестами? | Не было отдельного компонента теста на этот тип текста ответа. | В `tests/component/test_telegram_web_probe_correlation.sh` отсутствовал кейс model-not-found signature. |
| 4 | Почему это критично для production rollout? | Потому что authoritative UAT используется как post-deploy операторское решение; ложный `pass` маскирует реальную деградацию. | Канонический runbook `docs/telegram-e2e-on-demand.md` определяет этот workflow как основной post-deploy UAT. |
| 5 | Почему это повторялось как риск, а не единичный сбой? | Потому что pipeline проверял "ответ пришёл", а не "ответ качественно валиден по model/provider контракту". | Повторяемый паттерн до обновления сигнатур в probe-check. |

## Корневая причина

Недостаточно строгий контракт reply-quality в authoritative probe: отсутствовали сигнатуры ошибок model/provider-resolution, поэтому transport-успех интерпретировался как функциональный успех.

## Принятые меры

1. **Quality gate hardening в probe:**
   - `scripts/telegram-web-user-probe.mjs`:
     - расширен `ERROR_RE` на:
       - `model ... not found`
       - `no authenticated providers`
       - provider-auth/provider-unavailable паттерны;
     - добавлен `isReplyErrorSignature()` и использован в `error_signature_clean`.
2. **Regression test добавлен:**
   - `tests/component/test_telegram_web_probe_correlation.sh`:
     - новый тест `component_telegram_web_probe_marks_model_not_found_as_error_signature`.
3. **Node24 readiness для remote UAT workflow:**
   - `.github/workflows/telegram-e2e-on-demand.yml` обновлён:
     - `actions/checkout@v6`
     - `webfactory/ssh-agent@v0.9.1`
     - `actions/upload-artifact@v5`

## Подтверждение устранения

- Тесты:
  - `bash tests/component/test_telegram_web_probe_correlation.sh` → pass
  - `bash tests/static/test_config_validation.sh` → pass
- Актуальный post-merge manual UAT пакет (main):
  - `/status`: run `23345810230` → passed
  - `/start`: run `23345876904` → passed
  - `/help`: run `23345950054` → passed
  - free-form: run `23346007597` → passed
- Во всех четырёх случаях reply-text содержал прикладной ответ, а не model-routing error.

## Уроки

1. **Transport-success ≠ functional-success**: для production UAT нужна обязательная семантическая фильтрация ошибок model/provider path.
2. **Regex quality gates должны эволюционировать вместе с runtime failure taxonomy**, а не оставаться на generic timeout/exception наборе.
3. **Каждый новый класс runtime ошибки должен сопровождаться regression-тестом**, иначе ложные pass неизбежно вернутся.
