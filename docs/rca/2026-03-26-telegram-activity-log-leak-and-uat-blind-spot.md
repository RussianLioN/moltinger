---
title: "Telegram leaked internal activity log to the user while authoritative UAT still passed because reply-quality checks were blind to telemetry variants and pre-send contamination"
date: 2026-03-26
severity: P1
category: process
tags: [moltis, telegram, uat, activity-log, telemetry-leak, prompt-guard, rca]
root_cause: "The repository had no fail-closed channel-output rule against internal activity dumps, while authoritative Telegram UAT only rejected a narrow ASCII subset of bad replies and ignored recent invalid pre-send incoming activity."
---

# RCA: Telegram leaked internal activity log to the user while authoritative UAT still passed because reply-quality checks were blind to telemetry variants and pre-send contamination

**Дата:** 2026-03-26  
**Статус:** Repo mitigated, production still requires canonical `main` landing for the tracked prompt/runtime path  
**Влияние:** Пользовательский Telegram-чат мог получать внутренний `Activity log`/tool-progress dump как обычное сообщение, а authoritative UAT при этом ошибочно показывал зелёный исход.

## Ошибка

На live Telegram-пути проявились сразу две связанные проблемы:

1. Пользователь видел внутреннюю трассировку вида:
   - `📋 Activity log`
   - `💻 Running: ...`
   - `🧠 Searching memory...`
2. Authoritative UAT не всегда ловил это как дефект:
   - run `20260326T195548Z-3531069` завершился `passed`, хотя `last_pre_send_activity` уже содержал недопустимый incoming `Activity log ...`
   - run `20260326T195639Z-3532132` завершился `passed`, хотя `reply_text` сам был `Activity log • Running: ... • Searching memory...`

После repo fix и повторного non-mutating authoritative smoke с текущими tracked скриптами тот же класс дефекта стал fail-closed:

- run `20260326T201406Z-3549308`
- verdict `failed`
- failure code `pre_send_invalid_activity`
- reason: в quiet window до отправки уже был обнаружен свежий incoming `Activity log • Running: ... • Searching memory...`

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему пользователь увидел `Activity log` в Telegram? | Потому что user-facing messaging path не был fail-closed против внутренних activity/tool-progress сообщений. | В tracked `config/moltis.toml` до фикса не было прямого запрета на `Activity log`, `Running`, `Searching memory`, raw tool names и raw shell commands в мессенджер-каналах. |
| 2 | Почему authoritative UAT не отловил этот дефект сразу? | Потому что reply-quality gate распознавал только узкую ASCII-форму `Activity log ...` и не учитывал emoji-prefixed telemetry или другие telemetry markers. | `isReplyErrorSignature("Activity log ...") === true`, но live reply с `📋/💻/🧠` прошёл как clean до фикса. |
| 3 | Почему UAT смог отдать `passed`, даже когда чат уже был загрязнён? | Потому что quiet window only waited for silence and reused `last_pre_send_activity` как evidence, но не трактовал свежий invalid incoming activity leak как blocking failure. | run `20260326T195548Z-3531069` показал `passed` при `last_pre_send_activity.messages[0].text = "Activity log • Running: ..."` |
| 4 | Почему такой blind spot survived после предыдущего Telegram hardening? | Потому что прошлый hardening был сфокусирован на stale session/context drift и ASCII tool-trace summaries, а не на полном классе user-facing telemetry leakage. | RCA `2026-03-21-moltis-telegram-session-context-drift.md` уже ловил `Activity log ...`, но не описывал emoji-prefixed variants и pre-send contamination как отдельный blocking contract. |
| 5 | Почему это стало системной проблемой, а не единичным артефактом? | Потому что repo-owned barriers были неполными одновременно в двух местах: в prompt contract и в authoritative UAT contract. | До фикса отсутствовал explicit prompt guard, а UAT contract не проверял recent invalid pre-send incoming activity. |

## Корневая причина

Корневая причина не в одном regex и не только в Telegram adapter. Репозиторий не задавал fail-closed контракт для user-facing messaging channels, а authoritative Telegram UAT не покрывал два реальных класса недопустимых состояний:

- emoji-prefixed/internal telemetry replies
- recent invalid incoming activity leakage ещё до текущего probe send

Это позволило реальному user-facing дефекту выглядеть как зелёный UAT.

## Принятые меры

1. **Prompt/channel guardrail**
   - В `config/moltis.toml` добавлен явный запрет на user-facing `Activity log`, `Running`, `Searching memory`, `thinking`, raw tool names и raw shell commands в Telegram и других messaging channels.
   - Разрешён максимум один короткий человеческий префейс перед финальным ответом.
2. **Probe hardening**
   - `scripts/telegram-web-user-probe.mjs` теперь:
     - классифицирует emoji-prefixed telemetry replies как error signatures;
     - выделяет `recent invalid pre-send incoming activity`;
     - fail-closed завершает authoritative run кодом `pre_send_invalid_activity`.
3. **Wrapper defense in depth**
   - `scripts/telegram-e2e-on-demand.sh` теперь дополнительно режет случаи, где helper ошибочно вернул green на:
     - `semantic_activity_leak`
     - `semantic_pre_send_activity_leak`
4. **Regression coverage**
   - `tests/component/test_telegram_web_probe_correlation.sh`
   - `tests/component/test_telegram_remote_uat_contract.sh`
   - `tests/static/test_config_validation.sh`

## Подтверждение

- Component:
  - `bash tests/component/test_telegram_web_probe_correlation.sh` -> `12/12 PASS`
  - `bash tests/component/test_telegram_remote_uat_contract.sh` -> `8/8 PASS`
- Static:
  - `bash tests/static/test_config_validation.sh` -> `113/113 PASS`
- Live authoritative proof with tracked patched scripts executed non-destructively from a temp dir on `ainetic.tech`:
  - run `20260326T201406Z-3549308`
  - verdict `failed`
  - stage `quiet_window`
  - failure `pre_send_invalid_activity`

## Уроки

1. **User-facing telemetry leakage must be treated as a first-class reliability defect**, not as cosmetic noise.
2. **Quiet-window attribution is insufficient without contamination review**: silence after a bad incoming message is not a clean chat.
3. **Prompt contract and UAT contract must agree**: если prompt запрещает internal telemetry наружу, UAT обязан fail-closed на тех же признаках.
4. **Wrapper must not trust helper blindly**: cheap semantic_review defense-in-depth is worth keeping even when helper logic is strong.
