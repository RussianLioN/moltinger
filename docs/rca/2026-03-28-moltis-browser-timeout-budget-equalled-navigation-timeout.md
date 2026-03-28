---
title: "Moltis browser runs still timed out because the overall agent timeout matched the browser navigation timeout and the repo smoke helper still used retired chat endpoints"
date: 2026-03-28
severity: P1
category: process
tags: [moltis, browser, timeout, telegram, ws-rpc, smoke, sandbox, config]
root_cause: "The first browser hotfix repaired sibling-container launch and writable profile storage, but the tracked config still capped the entire agent run at the same 30s budget as browser page navigation, and the repo smoke helper still used retired /login and /api/v1/chat endpoints, so browser runs timed out and the local canary path was no longer authoritative"
---

# RCA: Moltis browser runs still timed out because the overall agent timeout matched the browser navigation timeout and the repo smoke helper still used retired chat endpoints

**Дата:** 2026-03-28  
**Статус:** Resolved in git, pending canonical deploy from `main`  
**Влияние:** После уже исправленного browser sandbox/profile contract пользовательский Telegram path всё ещё мог завершаться `⚠️ Timed out: Agent run timed out after 30s`, хотя браузерный контейнер уже реально стартовал и tool calls `navigate` / `get_title` успевали начаться.

## Ошибка

Новая authoritative проверка показала другой failure mode, чем предыдущий `failed to pull browser image`:

- browser sandbox container реально стартует;
- в WS RPC событиях видны `tool_call_start` для `browser.navigate` и `browser.get_title`;
- затем chat run завершается `Timed out: Agent run timed out after 30s`.

Отдельно выяснилось, что repo helper `scripts/test-moltis-api.sh` в `main` всё ещё жил на retired path:

- `POST /login`
- `POST /api/v1/chat`

Это уже не соответствовало актуальному Moltis auth/RPC контракту:

- `/api/auth/login`
- WebSocket RPC `chat.send`

## Что было доказано

1. Browser sandbox/image/pull contract уже больше не был корнем инцидента.
2. Tracked config держал:
   - `[tools] agent_timeout_secs = 30`
   - `[tools.browser] navigation_timeout_ms = 30000`
3. Это означало, что outer agent budget и browser page-load budget были фактически одинаковыми.
4. После `navigate` у run уже не оставалось безопасного headroom на follow-up browser action, финализацию ответа и delivery.
5. `scripts/test-moltis-api.sh` больше не был authoritative smoke path, потому что опирался на retired HTTP chat flow и не отражал реальное поведение Moltis после перехода на current auth + WS RPC.

## Official-first baseline

Официальная документация Moltis по browser automation подтверждает:

- browser tool медленнее `web_fetch` и требует отдельный Chrome instance;
- browser sandbox в Docker запускается как sibling container и ждёт readiness;
- browser navigation имеет отдельный browser-side timeout budget (`navigation_timeout_ms`);
- при Docker deployment нужен отдельный sibling-container connectivity contract (`container_host`, host-gateway).

Это важно, потому что browser navigation budget — не то же самое, что общий agent run budget. Даже если browser page успела загрузиться за свой timeout, агенту всё равно нужен дополнительный запас времени на остальные шаги того же run.

Официальные источники:

- https://docs.moltis.org/browser-automation.html
- https://docs.moltis.org/sandbox.html
- https://docs.moltis.org/docker.html

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему browser path всё ещё падал на `Timed out after 30s`? | Потому что общий agent run завершался по outer timeout, хотя browser tool уже стартовал. | Authoritative WS RPC chat.send evidence |
| 2 | Почему outer timeout срабатывал так быстро? | Потому что `[tools].agent_timeout_secs` был равен 30, то есть совпадал с browser page-load budget. | `config/moltis.toml` |
| 3 | Почему этого не хватало даже после исправления sandbox/profile layer? | Потому что browser run теперь доходил дальше: `navigate` + follow-up action + финальный assistant reply уже не помещались в тот же 30s потолок. | Live RPC event stream (`navigate`, `get_title`, then timeout) |
| 4 | Почему repo canary не предупредил об этом заранее? | Потому что `scripts/test-moltis-api.sh` в `main` остался на retired `/login` + `/api/v1/chat` контракте. | `scripts/test-moltis-api.sh` before fix |
| 5 | Почему инцидент выглядел как “browser снова сломан”, хотя корень уже другой? | Потому что первая repair wave закрыла launch/storage contract и остановилась слишком рано; second-order timeout contract не был зафиксирован как обязательная часть browser closure proof. | Post-fix live evidence after the profile-dir hotfix |

## Корневая причина

Инцидент состоял из двух связанных дефектов.

### Primary root cause

Tracked Moltis config оставлял общий agent timeout равным browser navigation timeout.  
В результате outer run budget заканчивался на том же рубеже, где ещё только завершался browser page-load step.

### Contributing root cause

Repo smoke helper `scripts/test-moltis-api.sh` отстал от current Moltis auth/RPC surface и продолжал жить на retired HTTP chat flow. Это ослабляло operator proof и мешало быстро отличить transport drift от runtime timeout contract drift.

## Принятые меры

1. В `config/moltis.toml` увеличен `[tools].agent_timeout_secs` до `90`.
2. `navigation_timeout_ms` не менялся; browser page-load budget остался отдельным browser-side контрактом.
3. `scripts/test-moltis-api.sh` переведён на current contract:
   - `/api/auth/login`
   - `/api/auth/status`
   - WebSocket RPC `status`
   - WebSocket RPC `chat.clear`
   - WebSocket RPC `chat.send`
4. Smoke helper теперь умеет fail-closed проверять:
   - expected provider
   - expected model
   - expected final reply text
5. `scripts/manifest.json` обновлён под новый runtime contract (`node`, extra env vars).
6. Добавлены targeted tests:
   - `tests/component/test_moltis_api_smoke.sh`
   - `tests/component/test_moltis_browser_canary.sh` strengthened
   - `tests/static/test_config_validation.sh` strengthened

## Проверка после исправления

| Проверка | Результат |
|----------|-----------|
| `bash -n scripts/test-moltis-api.sh scripts/moltis-browser-canary.sh tests/component/test_moltis_api_smoke.sh tests/component/test_moltis_browser_canary.sh` | pass |
| `bash tests/component/test_moltis_api_smoke.sh` | pass (`2/2`) |
| `bash tests/component/test_moltis_browser_canary.sh` | pass (`2/2`) |
| `bash tests/static/test_config_validation.sh` | pass (`118/118`) |
| `git diff --check` | pass |

## Уроки

1. Browser incident closure нельзя останавливать на “container now starts”. Outer run budget и smoke path тоже входят в exercised contract.
2. Общий agent timeout не должен быть равен browser navigation timeout; outer budget обязан иметь явный запас на multi-step browser flow.
3. Repo smoke helpers должны идти в ногу с текущим auth/RPC surface, иначе операторы будут проверять уже не тот runtime contract.
4. Если live симптом меняется после первого hotfix, это не “тот же баг”, а новая корневая причина, и её нужно фиксировать отдельным RCA, а не продолжать лечить старый симптом.
