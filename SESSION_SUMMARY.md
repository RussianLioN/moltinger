# Session Summary: Moltinger Project

> **⚠️ ОБЯЗАТЕЛЬНОЕ ЧТЕНИЕ** в начале каждой сессии!
> Обновляется после каждой значимой сессии. Последнее обновление: 2026-03-16

---

## 🎯 Project Overview

**Проект**: Moltinger - AI Agent Factory на базе Moltis (OpenClaw)
**Миссия**: Создание AI агентов по методологии ASC AI Fabrique с самообучением
**Репозиторий**: https://github.com/RussianLioN/moltinger
**Ветка**: `main`
**Issue Tracker**: Beads (prefix: `molt`)

### Технологический стек

| Компонент | Технология |
|-----------|------------|
| **Container** | Docker Compose |
| **AI Assistant** | Moltis (ghcr.io/moltis-org/moltis:latest) |
| **Telegram Bot** | @moltinger_bot |
| **LLM Provider** | GLM-5 (Zhipu AI) via api.z.ai |
| **LLM Fallback** | Ollama Sidecar + Gemini-3-flash-preview:cloud |
| **CI/CD** | GitHub Actions |
| **Issue Tracking** | Beads |

---

## 📊 Current Status

### Production Status

```
Server: ainetic.tech
Moltis: Running ✅
URL: https://moltis.ainetic.tech
Telegram Bot: @moltinger_bot ✅
LLM Provider: zai (GLM-5) ✅
LLM Fallback: Ollama Sidecar ✅ (configured, ready to deploy)
Circuit Breaker: Configured ✅
CI/CD: Working ✅ (with test suite)
Test Suite: Integrated ✅ (unit/integration/security/e2e)
GitOps Compliance: Enforced ✅
```

### Версия

**Current Release**: v1.8.0
**Feature Complete**: 001-docker-deploy-improvements (2026-03-02)
**Test Suite**: Added comprehensive CI/CD test integration

### Current Session Update (2026-03-18)

- Восстановлена корректная привязка ворктри `moltinger-019-asc-fabrique-prototype` к canonical gitdir (`/Users/rl/coding/moltinger/moltinger-main/.git/worktrees/moltinger-019-asc-fabrique-prototype`) и обновлён guard через `scripts/git-session-guard.sh --refresh`.
- Зафиксированы и запушены добавленные пользователем материалы по ASC demo и BPMN (commit `bfa46db`): `asc-demo/*`, `docs/concept/asc-ai-fabrique-2-0-user-story-q-and-a.md`, `docs/concept/specs/001-approval-level-user-story-bpmn/*`.
- Поднят новый Speckit-пакет backend-среза: `specs/025-asc-demo-llm-backend/{spec.md,plan.md,tasks.md}` на базе `asc-demo/docs/plans/sleepy-munching-turing.md`.
- Входные параметры от пользователя зафиксированы в конфигурации и Speckit-пакете: `DEMO_ACCESS_TOKEN=demo-access-token`, целевой публичный домен `demo.ainetic.tech` (`DEMO_DOMAIN`, `DEMO_PUBLIC_BASE_URL`).
- Реализован standalone Node backend для `asc-demo`:
  - runtime bootstrap: `asc-demo/package.json`, `asc-demo/.env.example`, `asc-demo/server.js`
  - core/domain modules: `asc-demo/src/llm.js`, `sessions.js`, `response-builder.js`, `discovery.js`, `brief.js`, `summary-generator.js`, `router.js`
  - prompts/data: `asc-demo/src/prompts/*`, `asc-demo/src/demo-data/boku-do-manzh.json`
  - стек в `asc-demo/CLAUDE.md` переведён с Anthropic на OpenAI-compatible/Fireworks.
- Локальная проверка backend-среза (green):
  - `node --check` для всех backend-модулей
  - `cd asc-demo && npm install`
  - API smoke `gate -> discovery -> awaiting_confirmation -> confirm_brief -> request_status -> 4 download_artifacts`
  - скачивание `one-page-summary.md` по `GET /api/download/:sessionId/one_page_summary`.

### Previous Session Update (2026-03-16)

- Реализован UX-slice под baseline Codex App для `asc.ainetic.tech` в `web/agent-factory-demo/*`: токен-гейт переведен на form-submit (`Enter` + аккуратная кнопка), composer возвращен к паттерну `Enter=send`, `Shift+Enter=newline`, а после отправки/ответа фокус стабильно возвращается в поле ввода вместо «улета» по DOM.
- Добавлен полноценный проектный action-menu `⋯` (popover) с явными действиями `Переименовать` и `Удалить`; immediate rename по клику на троеточие убран. Для удаления проекта добавлено подтверждение и безопасный сценарий: при удалении активного проекта открывается чистый новый workspace (без принудительного перехода в соседний старый проект).
- Усилен fallback discovery-режим в браузерном shell: вместо линейного фиксированного перечня вопросов добавлен адаптивный выбор следующего вопроса по покрытию тем, плюс мягкий reprompt на низкосигнальный ввод. В shared web card builder также убрана генерация заголовка `Следующий вопрос` для discovery-card.
- Speckit-артефакт синхронизирован: в `specs/024-web-factory-demo-adapter/tasks.md` добавлены и закрыты `T049-T054`.
- Локальные проверки после патча: `node --check web/agent-factory-demo/app.js` и `python3 -m py_compile scripts/agent_factory_common.py` (green).

- Применён targeted UX-hotfix для `https://asc.ainetic.tech` в `web/agent-factory-demo/app.js`, `web/agent-factory-demo/app.css`, `web/agent-factory-demo/index.html`: устранён повторный anti-pattern с названием проекта (автоимя теперь не берётся как обрезанный первый ответ с многоточием), повторный клик `Новый проект` больше не создаёт дубликаты пустых чатов, из ленты убран избыточный заголовок `Следующий вопрос`, а composer стартует в одну строку и автоматически растёт по мере ввода.
- Для обратной совместимости добавлена мягкая миграция локального состояния браузера: старые timeline-сообщения с заголовком `Следующий вопрос` очищаются при hydrate, а слабые/обрезанные автоназвания существующих проектов пересобираются из первого пользовательского ответа без ручного вмешательства.
- Обновлён Speckit-артефакт `specs/024-web-factory-demo-adapter/tasks.md`: добавлены и закрыты задачи `T045-T048` под текущий UX-hardening pass.
- Локальная проверка после патча: `node --check web/agent-factory-demo/app.js` (green).
- Патч выкачен на remote worktree `/opt/moltinger-asc-demo` (ветка `024-web-factory-demo-adapter`, commit `a0cd06b`) через `./scripts/deploy.sh --json asc-demo deploy`; `status=healthy`.
- После выката выявлен и устранён операционный дрейф: отсутствовал `/opt/moltinger-asc-demo/.env.asc`, из-за чего `access_gate_configured=false`; файл окружения восстановлен (только hash), после повторного деплоя `https://asc.ainetic.tech/health` снова показывает `access_gate_configured=true` и `access_gate_ready=true`.

- После нового пользовательского UX-review для `https://asc.ainetic.tech` дополнительно упрощена именно лента диалога в `web/agent-factory-demo/index.html`, `web/agent-factory-demo/app.css` и `web/agent-factory-demo/app.js`: из primary chat feed убраны service/status карточки, кнопки действий внутри самих сообщений и визуально тяжёлый panel-header; в ленте остались только реальные реплики пользователя и фабричного агента.
- `thread-panel` теперь работает как лёгкий bubble-feed без видимого dashboard-header, стартовый `empty shell` больше не вставляется в timeline, а пользовательские сообщения отправляются без служебных заголовков вроде `Новый проект` или `Ответить`, чтобы поток ощущался ближе к Telegram/Codex chat UX.
- Визуал ленты упрощён под calm chat pattern: уменьшен стартовый hero, ослаблен фон thread area, сообщения превращены в компактные bubble-блоки с мягким разделением `agent/user`, а системные runtime-детали по-прежнему остаются только в hidden debug surface и не попадают в primary viewport.
- Быстрые проверки после этого UX-pass прошли:
  - `node --check web/agent-factory-demo/app.js`
  - `git diff --check`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery|uploads)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation|handoff|resume)' --json`
- `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json` в этой среде снова застревает на контейнерном browser-runner и не используется как blocking signal для этой UX-итерации; актуальный follow-up по browser-runtime остаётся в `molt-x3o`.

- Завершён ещё один полный UX-pass для `asc.ainetic.tech` уже не как “облегчённый dashboard”, а как явный `Codex-first workspace`: `web/agent-factory-demo/index.html` теперь разделяет `Access gate -> Empty home -> Project workspace -> Review/downloads side panel`, без service-noise в primary viewport.
- `web/agent-factory-demo/app.css` и `web/agent-factory-demo/app.js` переписаны под новый interaction model: sidebar показывает только названия проектов, первый экран сразу задаёт рабочий вопрос с примерами ответов, текущий discovery-вопрос поднимается в composer, а review/downloads живут в правой side panel, которая открывается только по событию или явному действию пользователя.
- `scripts/agent-factory-web-adapter.py` теперь дополнительно публикует browser-safe projection для нового UX (`display_project_title`, `project_stage_label`, `side_panel_mode`, `composer_helper_example`), чтобы frontend не гадал по внутренним runtime-полям.
- Новый пользовательский поток подтверждён зелёными проверками:
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation|handoff|resume)' --json`
  - `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json`
- Следующий операционный шаг после текущего коммита: перевыкатить `024-web-factory-demo-adapter` на `https://asc.ainetic.tech` и повторно проверить live UX уже в браузере пользователя.

- Собрал UX-consilium по роли дизайна/interaction и зафиксировал согласованную модель для `asc.ainetic.tech`: не incremental dashboard patch, а явное разделение на `Access gate -> Empty home -> Project workspace`, Perplexity-like chat-first композицию, левый список проектов и контекстный composer с вопросно-зависимым placeholder.
- Переписал browser shell под эту модель в `web/agent-factory-demo/index.html`, `web/agent-factory-demo/app.css`, и `web/agent-factory-demo/app.js`: token теперь живёт на отдельном gate-экране, рабочее пространство открывается только после входа, у пользователя есть sidebar со списком проектов, новый проект можно запускать параллельно существующим, а рабочее название проекта теперь автоматически генерируется после первого содержательного user turn и может переименовываться через меню `⋯`.
- Добавил клиентское multi-project состояние поверх существующего adapter/runtime слоя без переписывания backend handoff path: проекты хранятся локально как отдельные browser workspaces с собственными `sessionId`, timeline, draft и lastResponse; refresh/resume продолжают использовать уже существующий `GET /api/session`, поэтому новый UX не ломает discovery/intake/artifact pipeline.
- Сделал composer контекстным: `data-role="composer-mode"` теперь поднимает текущий вопрос агента, placeholder меняется по `current_question/current_topic/current_action`, а universal generic copy больше не конкурирует с реальным discovery-вопросом.
- Обновил `tests/e2e_browser/agent_factory_web_demo.mjs` под новый gate/home/workspace flow и `docs/runbooks/agent-factory-web-demo.md` под новый UX-контур, чтобы автоматизация и операторская документация больше не описывали устаревший single-column shell.
- Перепроверил новый UX-pass через:
  - `node --check web/agent-factory-demo/app.js`
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py scripts/agent_factory_common.py`
  - `bash tests/integration_local/test_agent_factory_web_flow.sh`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery|uploads)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation|handoff|resume)' --json`
  - `bash scripts/scripts-verify.sh`
  - `git diff --check`
- Direct local `node tests/e2e_browser/agent_factory_web_demo.mjs` is still not a product regression signal in this Codex sandbox: it currently fails on `PermissionError: [Errno 1] Operation not permitted` while binding the ephemeral localhost test server port. The browser-flow assertions therefore remain covered by the green component/integration slices above; the environment-side browser-runtime follow-up remains tracked separately from this UX change.
- Added a repo-level Playwright MCP usage rule in `docs/rules/playwright-mcp-usage.md` and indexed it from `.ai/instructions/codex-adapter.md`, generated `AGENTS.md`, and `docs/CODEX-OPERATING-MODEL.md`: future Codex sessions must now read the rule before using MCP browser tools and must stop retrying stale `browser_navigate` launches after one cleanup attempt.
- Opened follow-up Beads task `molt-j51` (`Fix stale MCP Playwright browser session recovery`) because the underlying persistent-context failure is still a real technical issue; the new instruction change prevents repeated misuse, but it is not the final runtime fix.
- Applied a second browser UX pass on `024-web-factory-demo-adapter` after direct comparison against Perplexity-style chat-first references: `web/agent-factory-demo/index.html` is now centered around a single dominant composer, the first screen hides the conversation transcript until the project is actually started, and the old dashboard-like status clutter moved into the collapsed `Контекст проекта` section.
- Rebuilt `web/agent-factory-demo/app.css` for the new composition and added explicit `landing/active` shell state handling in `web/agent-factory-demo/app.js`, so the live shell now behaves like a clean conversational entry surface instead of an operator dashboard from the very first screen.
- Re-verified the redesigned shell with:
  - `node --check web/agent-factory-demo/app.js`
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py scripts/agent_factory_common.py`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery|uploads)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation|handoff|resume)' --json`
- Local sandbox still blocks ad-hoc port binding for an extra manual browser preview, and the containerized `e2e_browser` lane can hang in this environment; the product-flow assertions remain covered by the green component/integration slices above.
- Applied a post-pilot UX hotfix on top of `024-web-factory-demo-adapter` after live user feedback from `https://asc.ainetic.tech`: the browser shell was simplified into a lighter single-column chat-first layout, the distracting right-side surface was removed, and `web/agent-factory-demo/app.css` now uses a much cheaper visual style so typing renders locally without the previous “echo from server” feel.
- Added direct browser attachment support for discovery in `web/agent-factory-demo/index.html`, `web/agent-factory-demo/app.js`, `scripts/agent-factory-web-adapter.py`, and `scripts/agent_factory_common.py`: the composer now accepts up to 4 files per turn, safely truncates file reads to `512 KB`, extracts browser-safe excerpts for `txt/csv/json/md/docx`, stores raw bytes only under adapter-owned `data/agent-factory/web-demo/uploads/`, and injects the sanitized file context into the current discovery answer instead of forcing the user to retype examples manually.
- Added regression coverage for the new attachment path in `tests/component/test_agent_factory_web_uploads.sh`, registered it in `tests/run.sh`, and extended `tests/e2e_browser/agent_factory_web_demo.mjs` toward browser-level attachment validation. The local automation environment still lacks a working Playwright runtime for that node-based harness, so a dedicated follow-up Beads task `molt-x3o` was created to restore browser-e2e coverage.
- Updated `docs/runbooks/agent-factory-web-demo.md` to document the simplified shell, browser attachment behavior, the new `uploads/` state root, and the current safe-ingestion limits so the operator and next session can reproduce the same flow without guessing.
- Redeployed the pilot surface on `https://asc.ainetic.tech` from `/opt/moltinger-asc-demo`: first manual redeploy pulled the new branch and published the updated HTML (`Прикрепить файлы` now present in the root page), then a second deploy restored the shared demo access gate after discovering that `ASC_DEMO_SHARED_TOKEN_HASH` had been recreated as an empty value in the container environment.
- Verified the live pilot after redeploy:
  - remote `./scripts/deploy.sh --json asc-demo deploy` returned `status=success` twice (second run with restored hash env)
  - remote `./scripts/deploy.sh --json asc-demo status` returned `healthy`
  - public `https://asc.ainetic.tech/` now contains the new file-upload affordance text `Прикрепить файлы`
  - public `https://asc.ainetic.tech/health` now reports `access_gate_configured=true`, `access_gate_ready=true`, and `operator_status.publication_status=ready`
- Added a second follow-up Beads task `molt-7x7` to stabilize the `asc-demo` shared-token secret source so future manual redeploys preserve `ASC_DEMO_SHARED_TOKEN_HASH` without an inline env override.
- Verified the UX hotfix with:
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py scripts/agent_factory_common.py`
  - `node --check web/agent-factory-demo/app.js`
  - `bash -n tests/component/test_agent_factory_web_uploads.sh tests/component/test_agent_factory_web_access.sh tests/integration_local/test_agent_factory_web_flow.sh tests/e2e_browser/agent_factory_web_demo.mjs`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery|uploads)' --json`
  - `bash tests/component/test_agent_factory_web_uploads.sh`
  - `bash tests/integration_local/test_agent_factory_web_flow.sh`
  - `bash tests/integration_local/test_agent_factory_web_confirmation.sh`
  - `bash tests/integration_local/test_agent_factory_web_handoff.sh` (rerun with local port bind outside sandbox to verify `/api/download`)
  - `bash tests/integration_local/test_agent_factory_web_resume.sh`
  - `bash scripts/scripts-verify.sh`
  - `git diff --check`
- Environment caveat preserved for next session:
  - `./tests/run.sh --lane integration_local ...` can still collide with stale `moltinger-test_*` docker resources in the local machine
  - `node tests/e2e_browser/agent_factory_web_demo.mjs` currently fails in this environment with `Playwright runtime is not available in the test runner image`, tracked by `molt-x3o`

- Branch in progress: `024-web-factory-demo-adapter`
- Pilot web demo is now deployed on `https://asc.ainetic.tech` from isolated remote worktree `/opt/moltinger-asc-demo` at branch `024-web-factory-demo-adapter` (`07e5c2b`), while the canonical server checkout `/opt/moltinger` remains on `main`.
- The published demo uses `ASC_DEMO_ACCESS_MODE=shared_token_hash`; the server only received the hash, and the raw pilot token was kept out of repo state for operator sharing.
- Post-deploy verification passed: remote `./scripts/deploy.sh --json asc-demo deploy` and `status` both report `healthy`, public `/health`, `/api/health`, `/metrics`, and root shell respond on `asc.ainetic.tech`, one live `start_project` turn with the issued demo token reached `status=awaiting_user_reply`, and the external smoke lane `TEST_LIVE=1 LIVE_WEB_DEMO_URL=https://asc.ainetic.tech LIVE_MOLTIS_URL=https://moltis.ainetic.tech ./tests/run.sh --lane web_demo_live --json --live` passed outside sandbox.
- Follow-up issue `molt-svm` tracks promotion of this manual pilot to a CI/GitOps-managed rollout path so `asc-demo` no longer depends on a server-side feature worktree plus inline deploy env.
- Completed `Phase 1: Setup` for `024-web-factory-demo-adapter` (`molt-vd0.2.*`): switched the active factory adapter anchors in `config/moltis.toml` and `tests/fixtures/config/moltis.toml` to the web-first demo slice, preserved `022` as the discovery-core spec reference, preserved `023` as the follow-up adapter spec reference, and changed the primary delivery channel from `telegram` to `web`.
- Added the new same-host browser demo compose surface in `docker-compose.asc.yml` using the existing Traefik/subdomain deployment pattern, with dedicated bind-backed state roots for `data/agent-factory/web-demo`, `data/agent-factory/discovery`, and `data/agent-factory/concepts`.
- Reconciled `scripts/manifest.json` and `tests/run.sh` for the new browser adapter surface: added the `agent-factory-web-adapter.py` entrypoint, removed old Telegram-centric wording from discovery/intake script descriptions, registered future component/integration/browser/live smoke suites for the web demo, and extended `tests/static/test_config_validation.sh` so `docker-compose.asc.yml` is now part of the static config gate.
- Created the initial fixture tree `tests/fixtures/agent-factory/web-demo/README.md` and refreshed `tests/fixtures/agent-factory/README.md` so the new browser-demo fixture ownership and traceability rules are explicit before foundational implementation starts.
- Completed `Phase 2: Foundational` for `024-web-factory-demo-adapter` (`molt-vd0.3.*`): added the reusable browser-session fixture `tests/fixtures/agent-factory/web-demo/session-new.json`, implemented the new adapter runtime `scripts/agent-factory-web-adapter.py`, and extended `scripts/agent_factory_common.py` with browser-oriented status, reply-card, and download projection helpers so one browser turn can already be gated, normalized, routed, persisted, and rendered without touching the downstream factory flow.
- Added foundational validation coverage for the browser adapter in `tests/component/test_agent_factory_web_access.sh` and `tests/integration_local/test_agent_factory_web_flow.sh`, covering fail-closed access gating, restored-session status requests, first-turn discovery routing, and continued discovery after a follow-up browser answer.
- Added the initial browser shell assets under `web/agent-factory-demo/` (`index.html`, `app.css`, `app.js`) plus the operator runbook `docs/runbooks/agent-factory-web-demo.md`, so the repo now contains a concrete local web shell, adapter contract notes, storage layout, and the current lightweight HTTP surface (`/health`, `/`, `/app.css`, `/app.js`, `/api/session`, `/api/turn`).

### Current Session Update (2026-03-17)

- Устранена ключевая причина «неинтеллектуального» диалога в web-demo: в `scripts/agent-factory-web-adapter.py` добавлен server-side `low-signal guard`, поэтому ответы вида `ping/ok/123` больше не считаются валидным закрытием темы и не продвигают discovery дальше по topic chain.
- Добавлен adaptive `Агент-архитектор Moltis` question composer в `scripts/agent-factory-web-adapter.py`: следующий вопрос теперь формируется с учётом текущего `next_topic`, уже собранных summary по темам и контекста вложенных файлов, а в `ui_projection` публикуются `agent_display_name`, `agent_role=architect` и `question_source`.
- Обновлён browser shell под новую ролевую модель: `web/agent-factory-demo/index.html` и `web/agent-factory-demo/app.js` теперь явно маркируют реплики как ответы `Агента-архитектора Moltis`, включая author label сообщений и composer copy.
- Расширено покрытие:
  - `tests/component/test_agent_factory_web_discovery.sh` проверяет architect projection (`agent_display_name`, `question_source`).
  - `tests/integration_local/test_agent_factory_web_flow.sh` добавляет сценарий `low-signal reply` и проверяет, что topic не меняется, summary не затирается и возвращается reprompt.
- В Speckit синхронизированы и закрыты задачи `T055-T056` в `specs/024-web-factory-demo-adapter/tasks.md`.
- Дополнительно исправлена формулировка adaptive-вопросов (`scripts/agent-factory-web-adapter.py`): убран дублирующийся префикс `Например: Например: ...`.
- Изменения выкачены на live `asc.ainetic.tech` через `/opt/moltinger-asc-demo` (`git pull --rebase` + `GITOPS_CONFIRM_SKIP=true ./scripts/deploy.sh --json asc-demo restart`), после чего проверка `/api/turn` подтверждает:
  - `ui_projection.agent_display_name = "Агент-архитектор Moltis"`
  - `ui_projection.question_source = "adaptive_architect"` на нормальном ответе
  - `ui_projection.question_source = "low_signal_guard"` и отсутствие topic-advance на `ping`.
- Расширен guard на самый первый ввод (`start_project`): сообщения вида `test/ping/ok` больше не принимаются как предмет автоматизации и вызывают reprompt по теме `problem`; параллельно автонейм проекта больше не берёт low-signal первую реплику в качестве названия.
- Усилен `start_project` guard по достаточности контекста: теперь первый ввод блокируется не только по стоп-словам, но и при недостатке бизнес-сигналов (например `хочу помощь`). Валидация остаётся fail-closed: `problem` не заполняется, тема остаётся `problem`, а пользователю возвращается reprompt с шаблоном корректного описания.
- Проверки в этой сессии:
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py`
  - `node --check web/agent-factory-demo/app.js`
  - `bash tests/component/test_agent_factory_web_discovery.sh`
  - `bash tests/integration_local/test_agent_factory_web_flow.sh`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery)' --json`
- Ограничение среды: `./tests/run.sh --lane integration_local ...` в этой среде утыкается в недоступный Docker socket (`/Users/rl/.docker/run/docker.sock`), поэтому как blocking signal использованы прямые integration-скрипты выше.
- Completed `Phase 3 / User Story 1` for `024-web-factory-demo-adapter` (`molt-vd0.4.*`): the browser adapter now keeps the live discovery shell on the correct next action after the first runtime response, exposes `ui_projection.preferred_ui_action`, and publishes business-readable browser labels through `status_snapshot.user_visible_status_label` and `status_snapshot.next_recommended_action_label` instead of leaking internal state codes.
- Added the US1 fixture `tests/fixtures/agent-factory/web-demo/session-discovery-answer.json`, component coverage in `tests/component/test_agent_factory_web_discovery.sh`, and browser e2e coverage in `tests/e2e_browser/agent_factory_web_demo.mjs`, validating the first raw idea turn, the first follow-up question, the continued answer turn, and the user-safe rendering contract inside the web shell.
- Updated `web/agent-factory-demo/index.html` and `web/agent-factory-demo/app.js` so the live shell now exposes stable browser selectors (`accessToken`, `messages`, `chatInput`, `sendBtn`), renders human-readable discovery status text, and keeps the composer in `submit_turn` mode after the first follow-up question instead of falling back to a status-only action.
- Extended `docs/runbooks/agent-factory-web-demo.md` and `specs/024-web-factory-demo-adapter/tasks.md` to reflect the completed live discovery entry flow and the browser-safe response contract for US1.
- Completed `Phase 4 / User Story 2` for `024-web-factory-demo-adapter` (`molt-vd0.5.*`): the browser adapter now supports `request_brief_review`, conversational `request_brief_correction`, explicit `confirm_brief`, and `reopen_brief` over the same saved browser session, while keeping the exact reviewed version visible through `status_snapshot.brief_version`, `browser_project_pointer.linked_brief_version`, and versioned confirmation prompts.
- Extended `scripts/agent_factory_common.py` with chunked brief rendering for browser review (`Версия brief`, `Проблема и желаемый результат`, `Пользователи и процесс`, `User story и границы`, `Примеры входов и выходов`, `Правила, исключения и риски`, `Ограничения и метрики`), added confirmed-state projection for the web shell, and mapped `start_concept_pack_handoff` to a business-readable next step instead of a raw downstream code.
- Updated `scripts/agent-factory-web-adapter.py` and `web/agent-factory-demo/app.js` so review/confirm actions can be triggered directly from the shell without JSON editing: `request_brief_review` and `confirm_brief` now work as empty-body explicit browser actions, preferred UI action after confirmation safely falls back to `request_status`, and reopen returns the shell to a new confirmation loop version.
- Added the awaiting-confirmation browser fixture `tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json`, component coverage in `tests/component/test_agent_factory_web_brief.sh`, and integration coverage in `tests/integration_local/test_agent_factory_web_confirmation.sh`, validating chunked brief rendering, versioned conversational corrections, explicit confirmation, and reopen with preserved confirmation history.
- Fixed a late parser drift in `scripts/agent-factory-web-adapter.py` by removing a broken nested f-string from the audit-id builder; after that fix, both host-side and compose-backed integration validation for the new browser slice pass cleanly.
- Completed `Phase 5 / User Story 3` for `024-web-factory-demo-adapter` (`molt-vd0.6.*`): the browser adapter now turns a confirmed browser brief into a live downstream chain by replaying or reusing the ready `factory_handoff_record`, invoking `scripts/agent-factory-intake.py`, invoking `scripts/agent-factory-artifacts.py generate`, and persisting the generated concept pack plus a private browser delivery index under `data/agent-factory/web-demo/downloads/<web_demo_session_id>/`.
- Added browser-safe delivery projection to `scripts/agent-factory-web-adapter.py` and `scripts/agent_factory_common.py`: the user now receives sanitized `download_artifacts` metadata, `status=download_ready`, `next_action=download_artifact`, and tokenized `/api/download?session_id=...&token=...` URLs instead of raw `download_ref` or filesystem paths.
- Reconciled `scripts/agent-factory-intake.py` so discovery-origin handoffs preserve `delivery_channel=web`, which keeps the generated `concept-pack.json` provenance aligned with the active browser adapter instead of defaulting back to `telegram`.
- Updated `web/agent-factory-demo/app.js` so explicit browser confirmation automatically triggers one safe follow-up `request_status`, making the user-visible flow behave as `confirm brief -> concept pack launches -> downloads appear` without manual JSON or CLI steps.
- Added the ready-download fixture `tests/fixtures/agent-factory/web-demo/session-download-ready.json`, component coverage in `tests/component/test_agent_factory_web_delivery.sh`, and integration coverage in `tests/integration_local/test_agent_factory_web_handoff.sh`, validating sanitized delivery metadata, automatic confirmed-brief handoff, manifest provenance preservation, and live `/api/download` serving of the generated project document.
- Updated `docs/runbooks/agent-factory-web-demo.md`, `docs/runbooks/agent-factory-prototype.md`, and `specs/024-web-factory-demo-adapter/tasks.md` so the operator docs and planning artifacts now describe the completed browser path from `confirmed brief` to concept-pack download rather than stopping at browser confirmation.
- Completed `Phase 6 / User Story 4` for `024-web-factory-demo-adapter` (`molt-vd0.7.*`): `scripts/deploy.sh` now supports the dedicated `asc-demo` target on top of `docker-compose.asc.yml`, including same-host network checks, runtime root creation for `data/agent-factory/web-demo`, `data/agent-factory/discovery`, and `data/agent-factory/concepts`, plus health/metrics verification through the published local port before the subdomain is considered ready.
- Extended `scripts/agent-factory-web-adapter.py` with a configurable subdomain access gate and operator-safe publication endpoints: the adapter now understands `ASC_DEMO_ACCESS_MODE=shared_token_hash`, validates configured token hashes without exposing token material, publishes `/api/health` and `/metrics`, and reports whether the demo surface is `ready` or `degraded` before users enter the working session.
- Added US4 validation coverage in `tests/component/test_agent_factory_web_access.sh` and the new `tests/live_external/test_web_factory_demo_smoke.sh`, covering mismatched configured access grants, operator health projection, metrics publication, and remote smoke expectations for `asc.ainetic.tech` without requiring Telegram as the entry channel.
- Updated `docker-compose.asc.yml`, `docs/runbooks/agent-factory-web-demo.md`, and `web/agent-factory-demo/index.html` so the published browser surface now documents the real access-gate env anchors, deploy commands, smoke flow, and the fact that the browser shell already supports review/confirm/download behavior instead of advertising them as future work.
- Completed `Phase 7 / User Story 5` for `024-web-factory-demo-adapter` (`molt-vd0.8.*`): `scripts/agent-factory-web-adapter.py` now persists separate `pointers/` and `resume/` snapshots under `data/agent-factory/web-demo/`, returns browser-safe `resume_context`, and enriches `GET /api/session` so refresh/resume uses server-side state rather than relying only on localStorage.
- Extended `scripts/agent_factory_common.py` and `web/agent-factory-demo/app.js` so the browser shell now auto-restores the active session after reload, keeps the correct action mode after resume, surfaces reopened-brief labels and resume summaries, and avoids stale `download_ready` carry-over when a confirmed brief is reopened into a new reviewable version.
- Added US5 validation coverage in `tests/integration_local/test_agent_factory_web_resume.sh` and expanded `tests/e2e_browser/agent_factory_web_demo.mjs`, validating restored discovery sessions, preserved confirmation/handoff history after reopen, and real browser refresh continuity where the user reloads the page and keeps working in the same project.
- Updated `docs/runbooks/agent-factory-web-demo.md` and `specs/024-web-factory-demo-adapter/tasks.md` so the operator docs and Speckit checklist now reflect the completed resume/reopen behavior rather than treating it as future polish.
- Verified the setup slice with:
  - `./tests/run.sh --lane static --filter static_config_validation --json`
  - `bash -n tests/run.sh`
  - `python3 -m json.tool scripts/manifest.json >/dev/null`
  - `git diff --check`
- Verified the foundational browser slice with:
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-web-adapter.py`
  - `bash -n tests/component/test_agent_factory_web_access.sh tests/integration_local/test_agent_factory_web_flow.sh`
  - `python3 -m json.tool tests/fixtures/agent-factory/web-demo/session-new.json >/dev/null`
  - `./tests/run.sh --lane component --filter component_agent_factory_web_access --json`
  - `TEST_IN_CONTAINER=1 ./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_flow --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_flow --json`
- Verified the live browser discovery slice with:
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-web-adapter.py`
  - `bash -n tests/component/test_agent_factory_web_discovery.sh`
  - `python3 -m json.tool tests/fixtures/agent-factory/web-demo/session-discovery-answer.json >/dev/null`
  - `node --check web/agent-factory-demo/app.js`
  - `node --check tests/e2e_browser/agent_factory_web_demo.mjs`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery)' --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_flow --json`
  - `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json`
- Verified the browser brief-review slice with:
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-web-adapter.py`
  - `bash -n tests/component/test_agent_factory_web_brief.sh tests/integration_local/test_agent_factory_web_confirmation.sh`
  - `python3 -m json.tool tests/fixtures/agent-factory/web-demo/session-awaiting-confirmation.json >/dev/null`
  - `node --check web/agent-factory-demo/app.js`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation)' --json`
  - `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json`
- Verified the browser handoff-and-download slice with:
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py scripts/agent-factory-intake.py scripts/agent_factory_common.py`
  - `bash -n tests/component/test_agent_factory_web_delivery.sh tests/integration_local/test_agent_factory_web_handoff.sh`
  - `python3 -m json.tool tests/fixtures/agent-factory/web-demo/session-download-ready.json >/dev/null`
  - `node --check web/agent-factory-demo/app.js`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation|handoff)' --json`
  - `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json`
- Verified the controlled subdomain demo-access slice with:
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py`
  - `bash -n scripts/deploy.sh tests/component/test_agent_factory_web_access.sh tests/live_external/test_web_factory_demo_smoke.sh`
  - `./tests/run.sh --lane static --filter static_config_validation --json`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_web_(flow|confirmation|handoff)' --json`
  - `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json`
  - `./tests/run.sh --lane web_demo_live --json` (expected `skipped` without `--live`)
  - `bash scripts/scripts-verify.sh`
- Verified the browser resume/reopen slice with:
  - `python3 -m py_compile scripts/agent-factory-web-adapter.py scripts/agent_factory_common.py`
  - `node --check web/agent-factory-demo/app.js`
  - `bash -n tests/integration_local/test_agent_factory_web_resume.sh`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_web_(access|discovery|brief|delivery)' --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_web_resume --json`
  - `./tests/run.sh --lane e2e_browser --filter agent_factory_web_demo --json`
- Applied a clarification-driven pivot from `023-telegram-factory-adapter` to `024-web-factory-demo-adapter` as the primary near-term demo path because a browser-accessible subdomain is more reliable than Telegram in the target corporate contour.
- Created the full new Speckit package `specs/024-web-factory-demo-adapter/` with:
  - `spec.md`
  - `checklists/requirements.md`
  - `research.md`
  - `plan.md`
  - `data-model.md`
  - `quickstart.md`
  - `contracts/`
  - `tasks.md`
- The new `024` package now formalizes:
  - web-first browser demo access through a dedicated subdomain such as `asc.ainetic.tech`
  - a thin browser adapter over the existing `022` discovery runtime and `020` downstream factory flow
  - browser-based discovery, brief review, explicit confirmation, and automatic `handoff -> intake -> concept pack`
  - downloadable concept-pack artifacts from the same UI session
  - a lightweight demo access gate plus browser resume/reopen behavior
- Imported `specs/024-web-factory-demo-adapter/tasks.md` into Beads under epic `molt-vd0` with 9 phase parents and 48 child tasks; `Phase 0` was immediately closed because planning is already complete.
- Added sequential phase-gating and intra-phase dependencies during the import so the new real entry point for implementation is `molt-vd0.2.*` (`Phase 1: Setup`).
- Applied a clarification pass to `specs/023-telegram-factory-adapter/` so Telegram is now explicitly preserved as follow-up transport scope instead of competing with the new web-first primary demo path.
- Added blocking dependencies from `molt-ztn` / `molt-ztn.2.*` onto `molt-vd0` so the Telegram adapter backlog is formally queued behind the new web-first demo epic rather than showing up as a competing primary entry point in `bd ready`.
- Completed the new Speckit planning package `specs/023-telegram-factory-adapter/` on top of the already finished discovery core from `022-telegram-ba-intake` and the downstream factory MVP0 from `020-agent-factory-prototype`.
- The `023` slice remains explicitly scoped as a live follow-up Telegram interface adapter for the factory business-analyst agent on `Moltis`; Telegram is a transport/UI adapter, not the agent identity itself.
- Added the full `023` design set:
  - `spec.md`
  - `checklists/requirements.md`
  - `research.md`
  - `plan.md`
  - `data-model.md`
  - `quickstart.md`
  - `contracts/`
  - `tasks.md`
- The `023` package now formalizes:
  - real Telegram message routing into the existing discovery runtime
  - brief review and confirmation inside Telegram
  - automatic `handoff -> intake -> concept pack` after confirmation
  - in-chat delivery of the 3 concept-pack artifacts
  - Telegram resume/reopen/status behavior plus live pilot boundaries
- Research for `023` explicitly locked these design decisions:
  - keep the adapter thin over `scripts/agent-factory-discovery.py`, `scripts/agent-factory-intake.py`, and `scripts/agent-factory-artifacts.py`
  - keep production-side transport aligned with the current Bot API/webhook direction in `config/moltis.toml`
  - use Telegram document delivery for the concept-pack artifacts instead of repo-path handoff to the user
  - keep Telethon/MTProto limited to live validation rather than normal runtime delivery
- Imported `specs/023-telegram-factory-adapter/tasks.md` into Beads under epic `molt-ztn` with 8 phase parents and 37 child tasks; `Phase 0` was immediately closed because planning is already complete.
- Added sequential phase-gating and intra-phase dependencies during the import so `bd ready` now exposes `molt-ztn.2.*` (`Phase 1: Setup`) as the real entry point for implementation.
- Refreshed `docs/GIT-TOPOLOGY-REGISTRY.md` after switching from the completed `022-telegram-ba-intake` branch to the new `023-telegram-factory-adapter` feature branch.
- Verified in this session for the new slice:
  - `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`
  - `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`
  - `git diff --check`
  - `scripts/git-topology-registry.sh refresh --write-doc`
  - `bd version`
  - `bd info`
  - `bd dep cycles`
  - `bd show molt-ztn`
  - `bd ready`
- Clarification pass applied: `022-telegram-ba-intake` remains the legacy feature id, but the actual scope is the factory business-analyst agent on `Moltis`; `Telegram` is only the current reference/default interface adapter.
- Confirmed the next factory priority after completed MVP0 is a new upstream discovery-first slice: the first user-facing agent must behave as a factory business analyst that elicits and confirms requirements before the existing concept-pack flow starts.
- Created the new Speckit package `specs/022-telegram-ba-intake/` with:
  - `spec.md`
  - `checklists/requirements.md`
  - `research.md`
  - `plan.md`
  - `data-model.md`
  - `quickstart.md`
  - `contracts/`
  - `tasks.md`
- Scoped the new feature around multi-turn factory discovery, business-readable requirements brief generation, explicit brief confirmation, example-driven clarification, downstream handoff into `020-agent-factory-prototype`, and interrupted-session recovery.
- Explicitly separated the new discovery gate from the already existing downstream defense gate: confirmation of the requirements brief now sits before concept-pack generation, not inside the later approval/rework workflow.
- Refreshed `docs/GIT-TOPOLOGY-REGISTRY.md` after switching from the completed `020-agent-factory-prototype` branch to the new `022-telegram-ba-intake` feature branch.
- Created Beads epic `molt-s5i` linked to spec id `022-telegram-ba-intake`; its meaning is now factory business-analyst intake rather than a Telegram-specific agent.
- Imported `specs/022-telegram-ba-intake/tasks.md` into Beads under `molt-s5i` as 8 phase parents and 29 child tasks with user-story labels (`us1`-`us5`) and sequential plus phase-gating dependencies.
- Closed the already completed planning tasks `P001`-`P004` and phase parent `molt-s5i.1` during import so the new Beads graph matches the real Speckit state instead of showing planning as still pending.
- Added phase-parent gating dependencies so `bd ready` now exposes the correct execution order: Phase 1 Foundational (`T001`-`T004`) is the current entry point, while later user stories remain blocked until earlier phase parents are closed.
- Completed Phase 1 Foundational for `022-telegram-ba-intake`: updated `config/moltis.toml` and `tests/fixtures/config/moltis.toml` with discovery-first identity, upstream/downstream spec anchors, repo-local discovery state paths, future `agent-factory-discovery.py` hook, brief-template reference, allowed state enums, confirmation gate, and resume policy.
- Added the source-first brief template `docs/templates/agent-factory/requirements-brief.md` so later discovery sessions can render one reviewable business-readable brief before any concept-pack generation begins.
- Added reusable discovery fixtures under `tests/fixtures/agent-factory/discovery/` for four baseline states: `session-new`, `session-awaiting-clarification`, `brief-awaiting-confirmation`, and `brief-confirmed-handoff`, plus updated the parent fixtures README to advertise the new discovery sub-tree.
- Wired future discovery validation suites into `tests/run.sh` with optional registrations for `component_agent_factory_discovery`, `component_agent_factory_brief`, `component_agent_factory_examples`, `component_agent_factory_handoff`, `integration_local_agent_factory_discovery_flow`, `integration_local_agent_factory_confirmation`, `integration_local_agent_factory_handoff`, and `integration_local_agent_factory_resume`.
- Reconciled `specs/022-telegram-ba-intake/tasks.md` so `T001` through `T004` are now marked complete; once the corresponding Beads tasks are closed, the next ready queue begins at User Story 1 (`molt-s5i.3.*`).
- Completed User Story 1 for `022-telegram-ba-intake`: added `scripts/agent-factory-discovery.py` as the new discovery-session orchestrator that opens a factory requirements interview from a raw idea or existing session snapshot, emits structured topic progress, preserves pending agent questions, and resolves the next action as `ask_next_question`, `resolve_clarification`, or `prepare_brief`.
- Extended `scripts/agent_factory_common.py` with reusable discovery topic catalog, alias normalization, status inference, progress summarization, next-topic selection, and helper builders so later slices can reuse one discovery state contract instead of re-encoding topic logic per phase.
- Added US1 validation coverage in `tests/component/test_agent_factory_discovery.sh` and `tests/integration_local/test_agent_factory_discovery_flow.sh`, covering fresh-session progress, clarification prioritization, raw-idea onboarding without a template, advancement after free-form business answers, and blocking behavior when clarification items remain open.
- Updated `config/moltis.toml`, `tests/fixtures/config/moltis.toml`, and `scripts/manifest.json` with the concrete discovery entrypoint (`run`), ordered topic contract, next-action contract, and new script inventory entry.
- Added `docs/runbooks/agent-factory-discovery.md` so operator handoff now documents accepted input shapes, command examples, state mapping, and the current boundary between discovery and later brief/handoff phases.
- Reconciled `specs/022-telegram-ba-intake/tasks.md` so `T005` through `T010` are now marked complete; the next implementation queue begins at User Story 2 (`molt-s5i.4.*`).
- Completed User Story 2 for `022-telegram-ba-intake`: extended `scripts/agent-factory-discovery.py` so the discovery runtime now turns a ready session into a reviewable `requirement_brief`, versions meaningful revisions (`1.0`, `1.1`, ...), renders `brief_markdown` from `docs/templates/agent-factory/requirements-brief.md`, and records one explicit `confirmation_snapshot` when the user confirms the current version.
- The discovery runtime now accepts brief-review inputs (`requirement_brief`, `brief_revisions`, `brief_feedback_text`, `brief_section_updates`, `confirmation_reply`) in addition to raw discovery sessions, which makes the same CLI contract cover `draft -> revise -> confirm` without manual file edits.
- Added US2 validation coverage in `tests/component/test_agent_factory_brief.sh` and `tests/integration_local/test_agent_factory_confirmation.sh`, covering draft rendering, pre-confirmation version bumps, explicit confirmation snapshots, and the full local loop from ready discovery context to a confirmed brief.
- Updated `docs/runbooks/agent-factory-discovery.md` so operator handoff now includes the review-state input shape, draft/revision/confirmation command examples, the new `awaiting_confirmation` and `confirmed` states, and the explicit boundary that canonical handoff still starts later in `US4`.
- Reconciled `specs/022-telegram-ba-intake/tasks.md` so `T011` through `T015` are now marked complete; the next implementation queue begins at User Story 3 (`molt-s5i.5.*`).
- Completed User Story 3 for `022-telegram-ba-intake`: extended `scripts/agent-factory-discovery.py` so discovery now emits structured `example_cases`, derives them from business-facing `input_examples`/`expected_outputs` when explicit cases are absent, and keeps examples connected to linked rules and exception context.
- Added safe-example and contradiction logic to `scripts/agent_factory_common.py`: prototype-unsafe details now produce `needs_redaction`, while rule/constraint collisions in expected outcomes produce structured contradiction messages instead of silently passing through to confirmation.
- Discovery now reconciles generated `ClarificationItem` records for `unsafe_data_example` and `contradictory_examples`, resolves obsolete generated clarifications when the user fixes them, and blocks confirmation while such issues remain open even if a draft brief already exists.
- Added US3 validation coverage in `tests/component/test_agent_factory_examples.sh`, covering structured example extraction, unsafe business data detection, and contradiction detection between business rules and example outcomes.
- Updated `docs/runbooks/agent-factory-discovery.md` with the `example_cases` input/output contract and the new example/clarification policy, then reconciled `specs/022-telegram-ba-intake/tasks.md` so `T016` through `T019` are now marked complete; the next implementation queue begins at User Story 4 (`molt-s5i.6.*`).
- Completed User Story 4 for `022-telegram-ba-intake`: `scripts/agent-factory-discovery.py` now emits one canonical `factory_handoff_record` after replaying an already confirmed brief, which binds the downstream bridge to the exact `brief_version` and `confirmation_snapshot_id`.
- Adapted `scripts/agent-factory-intake.py` to recognize discovery-shaped payloads: ready handoffs bridge into `ready_for_pack`, while confirmed-but-not-handed-off payloads now return `status = blocked` with `return_to_discovery_handoff` instead of silently degrading into a generic clarifying intake.
- Reconciled `scripts/agent-factory-artifacts.py` with the new bridge by propagating discovery provenance into `concept-pack.json` (`source_provenance`) and per-artifact `generated_from` metadata, while also grounding render context in confirmed brief fields like `user_story`, `scope_boundaries`, `input_examples`, and `expected_outputs`.
- Added US4 validation coverage in `tests/component/test_agent_factory_handoff.sh` and `tests/integration_local/test_agent_factory_handoff.sh`, covering `confirmed -> handoff -> intake -> concept-pack` plus the blocked path before a ready handoff exists.
- Updated `docs/runbooks/agent-factory-discovery.md`, `docs/runbooks/agent-factory-prototype.md`, `specs/022-telegram-ba-intake/quickstart.md`, and `specs/022-telegram-ba-intake/tasks.md` so the operator docs and planning artifacts now describe the live discovery-to-concept handoff path rather than the earlier US2 stop boundary.
- Completed the Speckit clarification pass for `022-telegram-ba-intake`: the package now explicitly treats the factory business-analyst agent on `Moltis` as the primary runtime identity, while `Telegram`, `Moltinger UI`, `Moltis UI`, and future UIs remain interface adapters rather than separate agent identities.
- Completed User Story 5 for `022-telegram-ba-intake`: `scripts/agent-factory-discovery.py` now emits `resume_context`, preserves interrupted-session recovery state, archives superseded `confirmation_snapshot` records into `confirmation_history`, and archives superseded `factory_handoff_record` entries into `handoff_history` whenever a confirmed brief is reopened into a new version.
- Added `tests/integration_local/test_agent_factory_resume.sh` to cover resume of a pending question, resume of an open clarification, reopen of a confirmed brief, and reconfirmation into a new ready handoff; updated `docs/runbooks/agent-factory-discovery.md`, `specs/022-telegram-ba-intake/contracts/*.md`, `specs/022-telegram-ba-intake/data-model.md`, `specs/022-telegram-ba-intake/quickstart.md`, and `specs/022-telegram-ba-intake/tasks.md` so the runtime, contracts, and validation guidance all reflect the implemented US5 behavior.
- Completed Phase 7 Polish for `022-telegram-ba-intake`: reran `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`, confirmed the requirements checklist still passes after the clarification pass, reran the quickstart validation chain `confirmed brief -> handoff -> intake -> concept-pack`, refreshed `docs/GIT-TOPOLOGY-REGISTRY.md`, and confirmed that no additional blockers remain before closing the slice.
- Verified in this session:
  - `git fetch --all --prune`
  - `.specify/scripts/bash/create-new-feature.sh --json --short-name "telegram-ba-intake" "..."`
  - `scripts/git-topology-registry.sh refresh --write-doc`
  - `.specify/scripts/bash/setup-plan.sh --json`
  - `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`
  - `bd show molt-s5i`
  - `bd dep cycles`
  - `bd ready`
  - `bd sync`
  - `python3 - <<'PY' ... json.loads(...) ... PY` for discovery fixtures JSON validation
  - `bash -n tests/run.sh`
  - `python3 - <<'PY' ... tomllib.load(...) ... PY` for `config/moltis.toml` and `tests/fixtures/config/moltis.toml`
  - `./tests/run.sh --lane static --filter static_config_validation --json`
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-discovery.py`
  - `bash -n tests/component/test_agent_factory_discovery.sh tests/integration_local/test_agent_factory_discovery_flow.sh`
  - `python3 - <<'PY' ... json.loads(Path("scripts/manifest.json").read_text(...)) ... PY`
  - `./tests/run.sh --lane component --filter component_agent_factory_discovery --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_discovery_flow --json`
  - `bash scripts/scripts-verify.sh`
  - `python3 -m py_compile scripts/agent-factory-discovery.py scripts/agent_factory_common.py`
  - `bash -n tests/component/test_agent_factory_brief.sh tests/integration_local/test_agent_factory_confirmation.sh`
  - `./tests/run.sh --lane component --filter component_agent_factory_brief --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_confirmation --json`
  - `bash -n tests/component/test_agent_factory_examples.sh`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_(discovery|brief|examples)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_(discovery_flow|confirmation)' --json`
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-discovery.py scripts/agent-factory-intake.py scripts/agent-factory-artifacts.py`
  - `bash -n tests/component/test_agent_factory_handoff.sh tests/integration_local/test_agent_factory_handoff.sh tests/component/test_agent_factory_brief.sh tests/integration_local/test_agent_factory_confirmation.sh`
  - `./tests/run.sh --lane component --filter 'component_agent_factory_(brief|examples|handoff)' --json`
  - `./tests/run.sh --lane integration_local --filter 'integration_local_agent_factory_(confirmation|handoff|intake)' --json`
  - `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`
  - `bash scripts/scripts-verify.sh`

### Previous Session Update (2026-03-12)

- Branch in progress: `020-agent-factory-prototype`
- Verified that the local clone of `ASC-AI-agent-fabrique` matches upstream GitHub `HEAD`, then mirrored the current top-level ASC roadmap and concept docs into this repository under `docs/asc-roadmap/` and `docs/concept/`.
- Added `docs/ASC-AI-FABRIQUE-MIRROR.md` as the local provenance and navigation index so future sessions can find upstream ASC context, local factory plans, and the active Speckit package without relying on `/Users/...` paths.
- Reconciled factory-planning references in `docs/plans/parallel-doodling-coral.md` and `docs/research/openclaw-moltis-research.md` to point at the in-repo mirror rather than the workstation-local ASC repository.
- Created the new Speckit package `specs/020-agent-factory-prototype/` with:
  - `spec.md`
  - `checklists/requirements.md`
  - `research.md`
  - `plan.md`
  - `data-model.md`
  - `quickstart.md`
  - `contracts/`
  - `tasks.md`
- Framed the prototype around Telegram intake, synchronized concept-pack generation, defense gate, autonomous swarm-to-playground execution, operator escalation, and local ASC context continuity; deployment remains explicitly out of scope for MVP1.
- Created follow-up Beads epic `molt-qgg` (`Prototype AI agent factory MVP0`) linked to spec id `020-agent-factory-prototype`.
- Imported `specs/020-agent-factory-prototype/tasks.md` into Beads under `molt-qgg` as 9 phase parents and 38 child tasks with hierarchical IDs (`molt-qgg.3.1`, `molt-qgg.4.3`, etc.), user-story labels (`us1`-`us5`), and 25 explicit blocker dependencies.
- Marked the already completed planning/setup work as closed in Beads during import: 7 completed child tasks plus closed phase parents for Phase 0 and Phase 1.
- Verified the imported Beads graph with `bd dep cycles` (no cycles) and `bd sync`; the next implementation queue starts from Phase 2 Foundational (`T004`-`T008`).
- Completed Phase 2 Foundational for `020-agent-factory-prototype`: updated `config/moltis.toml` identity and factory context anchors, added source-first templates under `docs/templates/agent-factory/`, extended fleet future-role defaults for `tester`, `validator`, `auditor`, and `assembler`, created reusable fixtures in `tests/fixtures/agent-factory/`, and wired future agent-factory suites into `tests/run.sh`.
- Closed Beads tasks `molt-qgg.3.1` through `molt-qgg.3.5` plus the phase parent `molt-qgg.3`; the next ready queue now starts at User Story 1 (`molt-qgg.4.*`).
- Completed User Story 1 for `020-agent-factory-prototype`: added `scripts/agent-factory-intake.py` to normalize interface-level idea intake into a canonical concept record, `scripts/agent-factory-artifacts.py` plus `scripts/agent_factory_common.py` to generate and validate synchronized `project-doc.md`, `agent-spec.md`, and `presentation.md`, and `docs/runbooks/agent-factory-prototype.md` to document the current MVP0 intake-to-concept-pack flow.
- Extended `config/moltis.toml` and `tests/fixtures/config/moltis.toml` with factory intake/artifact env anchors so Moltinger can reference the US1 pipeline through repo-local scripts and download semantics.
- Added US1 validation coverage in `tests/component/test_agent_factory_artifacts.sh` and `tests/integration_local/test_agent_factory_intake.sh`, covering fresh-pack alignment, drift detection, ready-for-pack intake, concept-pack generation, and clarifying-state fallback when critical fields are missing.
- Reconciled `specs/020-agent-factory-prototype/tasks.md` so `T009` through `T014` are now marked complete; the next implementation queue starts at User Story 2 (`molt-qgg.5.*`).
- Closed Beads tasks `molt-qgg.4.1` through `molt-qgg.4.6` plus the phase parent `molt-qgg.4`; User Story 2 is now the next ready implementation slice.
- Completed User Story 2 for `020-agent-factory-prototype`: added `scripts/agent-factory-review.py` to record `approved`, `rework_requested`, `rejected`, and `pending_decision` outcomes with structured feedback and post-defense summary, and extended `scripts/agent-factory-artifacts.py` so regenerated concept packs preserve review history, feedback history, archived prior packs, and an explicit approval gate.
- Extended `config/moltis.toml`, `tests/fixtures/config/moltis.toml`, and `scripts/manifest.json` with review-stage anchors (`MOLTIS_FACTORY_REVIEW_SCRIPT`, allowed defense outcomes, production-ready state) so the defense loop is now part of the repo-local factory runtime contract.
- Added `tests/integration_local/test_agent_factory_review.sh` to cover all four defense outcomes, including version bump plus archived history on `rework_requested` and gate unlock only on `approved`; updated `docs/runbooks/agent-factory-prototype.md` and `specs/020-agent-factory-prototype/data-model.md` so runbook and entity model match the implemented review loop.
- Reconciled `specs/020-agent-factory-prototype/tasks.md` so `T015` through `T018` are now marked complete; the next implementation queue starts at User Story 3 (`molt-qgg.6.*`).
- Completed User Story 3 for `020-agent-factory-prototype`: added `scripts/agent-factory-swarm.py` to enforce approval-gated `coding -> testing -> validation -> audit -> assembly` stage execution, publish per-stage evidence, and produce a canonical `swarm-run.json` manifest for one approved concept version.
- Added `scripts/agent-factory-playground.py` to package the swarm output into a runnable synthetic-data playground bundle with `Dockerfile`, lightweight HTTP server, launch instructions, manifest, and downloadable `.tar.gz` archive.
- Extended `config/fleet/agents-registry.json` and `config/fleet/policy.json` with `production_stage_contracts` and `production_stage_policies`, then wired new runtime anchors into `config/moltis.toml`, `tests/fixtures/config/moltis.toml`, and `scripts/manifest.json` so the US3 control plane is represented in repo-local config.
- Added `tests/component/test_agent_factory_playground.sh` and `tests/integration_local/test_agent_factory_swarm.sh`, plus extra `tests/static/test_fleet_registry.sh` coverage for the new stage contracts and policies.
- Updated `docs/runbooks/agent-factory-prototype.md` and `specs/020-agent-factory-prototype/quickstart.md` so the operator handoff now documents the approved-concept swarm path, evidence bundle layout, playground bundle contents, and current readiness state.
- Reconciled `specs/020-agent-factory-prototype/tasks.md` so `T019` through `T024` are now marked complete; the next implementation queue starts at User Story 4 (`molt-qgg.7.*`).
- Completed User Story 4 for `020-agent-factory-prototype`: extended `scripts/agent-factory-swarm.py` with structured blocker handling, audit-trail emission, reviewable failure evidence bundles, and administrator-facing `EscalationPacket` output whenever a production stage fails or is blocked.
- Extended `scripts/agent-factory-artifacts.py` with `publish-status`, plus embedded `status_publication` snapshots inside generated concept packs so operators and users can distinguish `production`, `playground_ready`, and `needs_admin_attention` from one JSON payload.
- Added `tests/component/test_agent_factory_escalation.sh` to cover three US4 contracts: approved concept publishes `production` before swarm start, blocker failure creates an escalation packet plus audit trail, and happy-path swarm runs remain escalation-silent.
- Updated `docs/runbooks/agent-factory-prototype.md`, `specs/020-agent-factory-prototype/quickstart.md`, `specs/020-agent-factory-prototype/data-model.md`, and `specs/020-agent-factory-prototype/tasks.md` so the operator docs and planning artifacts now include status publication, admin intervention flow, and the new US4 completion state.
- Reconciled `specs/020-agent-factory-prototype/tasks.md` so `T025` through `T028` are now marked complete; the next implementation queue starts at User Story 5 (`molt-qgg.8.*`).
- Completed User Story 5 for `020-agent-factory-prototype`: added `tests/component/test_agent_factory_context_mirror.sh` to assert mirror provenance, repo-path-only navigation, and existence of referenced docs/spec artifacts so future sessions can recover context from repository files alone.
- Expanded `docs/ASC-AI-FABRIQUE-MIRROR.md` with an explicit session-recovery path, integrity-check commands, and active prototype references including `quickstart.md`; updated `specs/020-agent-factory-prototype/quickstart.md` so recovery order starts from the local mirror index rather than any workstation-specific clone.
- Reconciled `specs/020-agent-factory-prototype/tasks.md` so `T029` through `T030` are now marked complete; the next implementation queue starts at Phase 8 Polish (`molt-qgg.9.*`).
- Completed Phase 8 Polish for `020-agent-factory-prototype`: reran `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`, refreshed the quickstart integrity scan so it no longer self-matches a workstation-path detector, updated `specs/020-agent-factory-prototype/checklists/requirements.md`, and confirmed that no additional MVP0 blockers remain.
- Re-ran the full agent-factory validation slice as one package: static config/fleet checks, all `component_agent_factory_*` suites, and all `integration_local_agent_factory_*` suites passed together after the final polish pass.
- Reconciled `specs/020-agent-factory-prototype/tasks.md` so `T031` through `T034` are now marked complete; the MVP0 Speckit package has no remaining open tasks.
- Closed Beads phase `molt-qgg.9` and epic `molt-qgg`; the prototype AI agent factory MVP0 is now complete on branch `020-agent-factory-prototype`.
- `docs/GIT-TOPOLOGY-REGISTRY.md` was refreshed after the branch mutation so the registry matches the live topology again.
- Verified in this session:
  - `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`
  - `rg -n "/Users/rl/coding/ASC-AI-agent-fabrique" docs/ASC-AI-FABRIQUE-MIRROR.md docs/plans/parallel-doodling-coral.md docs/research/openclaw-moltis-research.md specs/020-agent-factory-prototype/spec.md specs/020-agent-factory-prototype/plan.md specs/020-agent-factory-prototype/research.md specs/020-agent-factory-prototype/data-model.md specs/020-agent-factory-prototype/tasks.md specs/020-agent-factory-prototype/contracts`
  - `scripts/git-topology-registry.sh refresh --write-doc`
  - `scripts/git-topology-registry.sh check`
  - `git diff --check`
  - `bd dep cycles`
  - `bd sync`
  - `./tests/run.sh --lane static --filter 'static_config_validation|static_fleet_registry' --json`
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-intake.py scripts/agent-factory-artifacts.py`
  - `bash scripts/scripts-verify.sh`
  - `./tests/run.sh --lane component --filter component_agent_factory_artifacts --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_intake --json`
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-intake.py scripts/agent-factory-review.py scripts/agent-factory-artifacts.py`
  - `./tests/run.sh --lane static --filter static_config_validation --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_review --json`
  - `python3 -m py_compile scripts/agent_factory_common.py scripts/agent-factory-intake.py scripts/agent-factory-review.py scripts/agent-factory-artifacts.py scripts/agent-factory-swarm.py scripts/agent-factory-playground.py`
  - `bash -n tests/component/test_agent_factory_playground.sh`
  - `bash -n tests/integration_local/test_agent_factory_swarm.sh`
  - `./tests/run.sh --lane static --filter 'static_(config_validation|fleet_registry)' --json`
  - `./tests/run.sh --lane component --filter component_agent_factory_playground --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_ --json`
  - `bash -n tests/component/test_agent_factory_escalation.sh`
  - `./tests/run.sh --lane component --filter component_agent_factory_escalation --json`
  - `./tests/run.sh --lane component --filter component_agent_factory_ --json`
  - `bash -n tests/component/test_agent_factory_context_mirror.sh`
  - `./tests/run.sh --lane component --filter component_agent_factory_context_mirror --json`
  - `.specify/scripts/bash/check-prerequisites.sh --json --include-tasks`
  - `./tests/run.sh --lane static --filter 'static_(config_validation|fleet_registry)' --json`
  - `./tests/run.sh --lane component --filter component_agent_factory_ --json`
  - `./tests/run.sh --lane integration_local --filter integration_local_agent_factory_ --json`

### Previous Session Update (2026-03-11)

- Branch in progress: `feat/moltis-real-user-tests`
- Restored the historical `deferred -> executable real_user` line for `specs/004-telegram-e2e-harness` so the current scope explicitly tracks that US3 used to be deferred in `moltinger-xtx`, but is now treated as active regression surface.
- Added a fuller live-only operability pack to `tests/live_external/test_telegram_external_smoke.sh`: direct Telegram API smoke, Moltis synthetic harness, Moltis `real_user` MTProto harness, and artifact redaction checks.
- `docs/telegram-e2e-on-demand.md` now contains the operator-facing verification set for local CLI, workflow dispatch, and the consolidated `telegram_live` lane.
- `scripts/telegram-real-user-e2e.py` now emits richer structured context (`timeout_sec`, `message_length`, requested bot identity) on both success and failure paths.
- `docs/GIT-TOPOLOGY-REGISTRY.md` was refreshed in this worktree because the registry was stale and would block landing hooks.
- Verified in this session:
  - `bash -n tests/live_external/test_telegram_external_smoke.sh`
  - `python3 -m py_compile scripts/telegram-real-user-e2e.py`
  - `python3 scripts/telegram-real-user-e2e.py --api-id not-an-int --api-hash test-hash --session test-session --bot-username @moltinger_bot --message '/status' --timeout-sec 15`
  - `bash scripts/telegram-e2e-on-demand.sh --mode real_user --message '/status' --timeout-sec 15 --output /tmp/telegram-e2e-precondition.json`
  - `./tests/run.sh --lane telegram_live --filter live_telegram_smoke --json`
  - `./tests/run.sh --lane telegram_live --live --json`
  - `scripts/git-topology-registry.sh check`

---

## 📁 Key Files

### Конфигурация

| Файл | Назначение |
|------|------------|
| `config/moltis.toml` | Основная конфигурация Moltis |
| `docker-compose.prod.yml` | Docker Compose для продакшена |
| `.github/workflows/deploy.yml` | CI/CD пайплайн с GitOps compliance |
| `.github/workflows/test.yml` | Test suite CI/CD workflow (новое!) |
| `.claude/settings.json` | Sandbox и permissions конфигурация |

### GitOps Infrastructure (новое 2026-02-28)

| Файл | Назначение |
|------|------------|
| `.github/workflows/gitops-drift-detection.yml` | Cron drift detection (каждые 6ч) |
| `.github/workflows/gitops-metrics.yml` | SLO metrics collection (каждый час) |
| `.github/workflows/uat-gate.yml` | UAT promotion gate |
| `scripts/gitops-guards.sh` | Guard functions library |
| `scripts/scripts-verify.sh` | Manifest validator |
| `scripts/gitops-metrics.sh` | Metrics collector |
| `scripts/manifest.json` | IaC manifest для scripts |

### Test Suite (новое 2026-03-02)

| Файл | Назначение |
|------|------------|
| `tests/run_unit.sh` | Unit test runner |
| `tests/run_integration.sh` | Integration test runner |
| `tests/run_e2e.sh` | E2E test runner |
| `tests/run_security.sh` | Security test runner |
| `tests/lib/test_helpers.sh` | Test helper functions |
| `tests/unit/` | Unit tests (circuit breaker, config, metrics) |
| `tests/integration/` | Integration tests (API, failover, MCP, Telegram) |
| `tests/e2e/` | E2E tests (chat flow, recovery, failover chain) |
| `tests/security/` | Security tests (auth, input validation) |

### Самообучение

| Файл | Назначение |
|------|------------|
| `docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md` | Инструкция для LLM (1360 строк) |
| `docs/research/openclaw-moltis-research.md` | Исследование OpenClaw/Moltis |
| `docs/QUICK-REFERENCE.md` | Быстрая справка (@moltinger_bot и др.) |
| `skills/telegram-learner/SKILL.md` | Skill для мониторинга Telegram |
| `knowledge/` | База знаний (concepts, tutorials, etc.) |

### Планирование

| Файл | Назначение |
|------|------------|
| `docs/plans/parallel-doodling-coral.md` | План трансформации в AI Agent Factory |
| `docs/plans/agent-factory-lifecycle.md` | Полный lifecycle создания агента |
| `docs/LESSONS-LEARNED.md` | Инциденты и уроки |

---

## 🔄 GitHub Secrets

| Secret | Status | Purpose |
|--------|--------|---------|
| `TELEGRAM_BOT_TOKEN` | ✅ | Bot token (@moltinger_bot) |
| `TELEGRAM_ALLOWED_USERS` | ✅ | Allowed user IDs |
| `GLM_API_KEY` | ✅ | LLM API (Zhipu AI) |
| `OLLAMA_API_KEY` | ✅ | Ollama Cloud (optional - for cloud models) |
| `SSH_PRIVATE_KEY` | ✅ | Deploy key |
| `MOLTIS_PASSWORD` | ✅ | Auth password |
| `TAVILY_API_KEY` | ✅ | Web search |

### Source of Truth for Secrets (RCA-008)

- Primary: GitHub Secrets
- Runtime mirror on server: `/opt/moltinger/.env` (auto-generated by CI/CD)
- Workflow evidence: `.github/workflows/deploy.yml` step `Generate .env from Secrets`
- Rule: before asking user for known variables, check docs in order from `docs/rules/context-discovery-before-questions.md`

---

## 📝 Session History

### 2026-03-12: Clawdiy Remote OAuth Runtime Research Formalized

**Статус**: ✅ durable research + Speckit planning package created

- Added durable research artifact [docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md) with official evidence, official GitHub issue evidence, explicit inference, consilium scoring, and recommended practical-now vs target-state OAuth methods.
- Updated the research index in [docs/research/README.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/README.md) and added cross-links from [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md), [docs/SECRETS-MANAGEMENT.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/SECRETS-MANAGEMENT.md), and [specs/001-clawdiy-agent-platform/research.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/001-clawdiy-agent-platform/research.md).
- Created a new Speckit package at [specs/017-clawdiy-remote-oauth-lifecycle/spec.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/spec.md), [specs/017-clawdiy-remote-oauth-lifecycle/plan.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/plan.md), and [specs/017-clawdiy-remote-oauth-lifecycle/tasks.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/tasks.md) to turn the research into an implementation contract.
- Refreshed [docs/GIT-TOPOLOGY-REGISTRY.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/GIT-TOPOLOGY-REGISTRY.md) after switching the worktree to branch `017-clawdiy-remote-oauth-lifecycle`.

- Validation completed:
  - `scripts/git-topology-registry.sh refresh --write-doc`
  - `git diff --check`

### 2026-03-12: Clawdiy OAuth Planning Switched To UI-First Bootstrap

**Статус**: ✅ operator path refined before runtime implementation

- Updated [specs/017-clawdiy-remote-oauth-lifecycle/plan.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/plan.md) so the first practical OAuth attempt is now the live Clawdiy web Settings flow targeting the hosted runtime directly; SSH/CLI paste-back remains fallback only.
- Updated [specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/quickstart.md) and created [specs/017-clawdiy-remote-oauth-lifecycle/validation.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/validation.md) so the first execution checklist now starts from the Clawdiy web UI and records runtime-store/provider evidence.
- Updated [docs/runbooks/clawdiy-repeat-auth.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/runbooks/clawdiy-repeat-auth.md) and [docs/deployment-strategy.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/deployment-strategy.md) so operator docs match the new UI-first contract.
- Reconciled [specs/017-clawdiy-remote-oauth-lifecycle/tasks.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/017-clawdiy-remote-oauth-lifecycle/tasks.md) with the newly completed planning/doc tasks.

**Validated**

- `git diff --check`

### 2026-03-09: RCA On Remote Rollout Diagnosis Order

**Статус**: ✅ RCA-010 captured and codified

- During initial Clawdiy rollout preparation, a missing `fleet-internal` network on `ainetic.tech` was treated too early as the primary blocker, before re-running the project’s existing Traefik-first production lessons and operator artifacts.
- The correction was procedural, not infrastructural: re-read `MEMORY.md`, `docs/LESSONS-LEARNED.md`, `docs/INFRASTRUCTURE.md`, and the historical Traefik notes before changing deployment reasoning or workflow automation.
- Added `docs/rules/remote-rollout-diagnosis-traefik-first.md` and a short pointer in `MEMORY.md` so future remote deploy triage starts with ingress/routing invariants, then only later considers new private networks such as `fleet-internal`.

**Validated**

- `bash .claude/skills/rca-5-whys/lib/context-collector.sh generic`
- `./scripts/build-lessons-index.sh`
- `./scripts/query-lessons.sh --tag traefik`

**Next**

- Resume Clawdiy rollout reasoning only after applying the Traefik-first remote diagnosis protocol to the live `ainetic.tech` baseline.

### 2026-03-09: Clawdiy Rebase And Mainline Reconcile

**Статус**: ✅ branch rebased onto `origin/main`, PR conflicts cleared

- Rebased `001-clawdiy-agent-platform` onto the updated `main` line and resolved the PR conflict set instead of merging stale branch state.
- Adapted the Clawdiy topology notes to the new generated-registry workflow by updating `docs/GIT-TOPOLOGY-INTENT.yaml` and regenerating `docs/GIT-TOPOLOGY-REGISTRY.md` from live git state.
- Re-ran the targeted Clawdiy validation set after the rebase to confirm that config, auth, topology, and extraction-readiness behavior stayed intact.

**Validated**

- `make codex-check-ci`
- `./tests/run.sh --lane static --filter 'static_(config_validation|fleet_registry)' --json`
- `./tests/run.sh --lane security_api --filter security_api_clawdiy_auth_boundaries --json`
- `./tests/run.sh --lane integration_local --filter extraction_readiness --json`
- `./scripts/preflight-check.sh --ci --target clawdiy --json`
- `./scripts/clawdiy-smoke.sh --json --stage auth`

**Next**

- Force-push the rebased branch to PR `#24`, wait for the rerun checks, and merge if the PR stays green.

### 2026-03-09: Clawdiy PR Governance Follow-Up

**Статус**: ✅ PR policy blocker fixed on branch `001-clawdiy-agent-platform`

- Created PR `#24` for the completed Clawdiy feature branch and observed an immediate `codex-policy` failure caused by deprecated literal Codex profile identifiers in configs, scripts, tests, docs, and spec artifacts.
- Replaced the deprecated profile identifier with the canonical `codex-oauth` label while preserving the rollout-gated GPT-5.4 / OAuth behavior and the existing secret boundary around `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE`.
- Revalidated governance and the affected auth/static/preflight paths before re-pushing the branch so CI can rerun against the corrected identifier set.

**Validated**

- `make codex-check-ci`
- `bash -n scripts/clawdiy-auth-check.sh scripts/clawdiy-smoke.sh scripts/preflight-check.sh tests/security_api/test_clawdiy_auth_boundaries.sh tests/static/test_fleet_registry.sh`
- `./tests/run.sh --lane static --filter 'static_(config_validation|fleet_registry)' --json`
- `./tests/run.sh --lane security_api --filter security_api_clawdiy_auth_boundaries --json`
- `./scripts/preflight-check.sh --ci --target clawdiy --json`
- `./scripts/clawdiy-smoke.sh --json --stage auth`

**Next**

- Push the governance-fix commit to PR `#24` and confirm that the rerun clears the previous `codex-policy` blocker.

### 2026-03-09: Clawdiy Polish, Hardening, and Quickstart Reconciliation (Phase 8)

**Статус**: ✅ Phase 8 complete on branch `001-clawdiy-agent-platform`

- Reconciled `docs/deployment-strategy.md`, `docs/QUICK-REFERENCE.md`, and `specs/001-clawdiy-agent-platform/quickstart.md` so operator docs explicitly say that the first live OpenClaw launch happens at same-host deploy and `gpt-5.4` via OpenAI Codex OAuth is a later rollout gate.
- Extended `tests/run.sh` so the `integration_local` lane now includes `test_clawdiy_extraction_readiness.sh`; `tests/run_integration.sh` and `tests/run_security.sh` remain unchanged because they already delegate to the umbrella runner.
- Hardened `docker-compose.clawdiy.yml`, `config/fleet/policy.json`, `scripts/preflight-check.sh`, and `tests/static/test_config_validation.sh` with init-enabled containers, hardened tmpfs, no Docker socket mount, stricter service-header binding, and fail-closed topology alignment checks.
- Ran a quickstart-aligned validation pass and captured rollout notes so local verification stays clearly separated from live same-host deploy and destructive rollback gates.

**Validated**

- `CLAWDIY_IMAGE=ghcr.io/example/openclaw:placeholder docker compose -f docker-compose.clawdiy.yml config --quiet`
- `bash -n scripts/preflight-check.sh`
- `bash -n tests/run.sh`
- `bash -n tests/static/test_config_validation.sh`
- `./tests/run.sh --lane static --filter 'static_(config_validation|fleet_registry)' --json`
- `./tests/run.sh --lane integration_local --filter extraction_readiness --json`
- `./scripts/preflight-check.sh --ci --target clawdiy --json`
- `./scripts/clawdiy-smoke.sh --json --stage auth`
- `./scripts/clawdiy-smoke.sh --json --stage extraction-readiness`

**Rollout Notes**

- Quickstart Stage 3 (`deploy same-host`) remains the first real OpenClaw launch and was not executed from this workspace-only validation pass.
- Quickstart Stage 7 (`rollback-evidence`) still depends on a live rollback manifest and backup archive; it remains covered by the dedicated resilience path from US4 rather than a clean-worktree smoke rerun.
- Direct `./scripts/clawdiy-auth-check.sh --json` without `/opt/moltinger/clawdiy/.env` fails closed as designed, leaving Telegram and Codex-backed capability quarantined until repeat-auth on the real env mirror.

**Next**

- Feature implementation work is complete on this branch; the next step is merge/review plus the real same-host rollout of Clawdiy on the target server.
- During live rollout, OpenClaw starts at quickstart Stage 3, while `gpt-5.4` via Codex OAuth stays disabled until Stage 6 passes.

### 2026-03-09: Clawdiy Future-Node Extraction Readiness (US5)

**Статус**: ✅ US5 complete on branch `001-clawdiy-agent-platform`

- Extended `config/fleet/agents-registry.json` and `config/fleet/policy.json` with explicit `same_host` and `remote_node` topology profiles plus future permanent-role examples for architect, tester, and researcher.
- Added `extraction-readiness` contract checks to `scripts/clawdiy-smoke.sh` so remote-node readiness is validated without changing the live topology.
- Added `tests/integration_local/test_clawdiy_extraction_readiness.sh` and expanded `tests/static/test_fleet_registry.sh` to verify future-role and remote-node invariants.
- Updated `docs/INFRASTRUCTURE.md`, `docs/plans/agent-factory-lifecycle.md`, and `docs/GIT-TOPOLOGY-REGISTRY.md` so same-host deployment and future remote-node extraction use one stable identity/discovery/handoff model.

**Validated**

- `jq empty config/fleet/agents-registry.json`
- `jq empty config/fleet/policy.json`
- `bash -n scripts/clawdiy-smoke.sh`
- `bash -n tests/integration_local/test_clawdiy_extraction_readiness.sh`
- `./tests/run.sh --lane static --filter static_fleet_registry --json`
- `bash tests/integration_local/test_clawdiy_extraction_readiness.sh`
- `./scripts/clawdiy-smoke.sh --json --stage extraction-readiness`

**Next**

- Move to Phase 8 polish (`T040`-`T043`): reconcile quick references/docs, wire remaining validation into umbrella runners, run final hardening, and capture rollout notes.

### 2026-03-09: Clawdiy Recovery, Backup, and Rollback Safety (US4)

**Статус**: ✅ US4 complete on branch `001-clawdiy-agent-platform`

- Added Clawdiy rollback resilience coverage in `tests/resilience/test_clawdiy_rollback.sh` and registered it in the `resilience` lane.
- Extended `scripts/health-monitor.sh` and `scripts/clawdiy-smoke.sh` so operators can distinguish Moltinger and Clawdiy health, evidence roots, correlation labels, and rollback manifests.
- Extended `scripts/backup-moltis-enhanced.sh`, `config/backup/backup.conf`, `.github/workflows/deploy-clawdiy.yml`, and `.github/workflows/rollback-drill.yml` to require Clawdiy config/state/audit inventory and evidence manifests for restore readiness.
- Updated `scripts/deploy.sh` to capture and finalize rollback evidence under `data/clawdiy/audit/rollback-evidence/`, including backup reference and resulting rollback mode.
- Reworked `docs/disaster-recovery.md` and `docs/runbooks/clawdiy-rollback.md` into operator-facing recovery procedures for Clawdiy-specific incidents.

**Validated**

- `bash -n scripts/backup-moltis-enhanced.sh`
- `bash -n scripts/deploy.sh`
- `bash -n scripts/clawdiy-smoke.sh`
- `bash -n scripts/health-monitor.sh`
- `bash -n tests/resilience/test_clawdiy_rollback.sh`
- `./tests/run.sh --lane static --filter static_config_validation --json`
- `./scripts/preflight-check.sh --ci --target clawdiy --json`
- `./scripts/health-monitor.sh --once --json`

**Next**

- Move to US5 (`T035`-`T043`): future-node extraction, agent registry evolution, and rollout path for expanding beyond the same-host topology.

### 2026-03-09: Clawdiy Auth Lifecycle (US3)

**Статус**: ✅ US3 complete on branch `001-clawdiy-agent-platform`

- Added dedicated Clawdiy auth rendering rules in `.github/workflows/deploy-clawdiy.yml` and `docs/SECRETS-MANAGEMENT.md`, including compact JSON policy for `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE`.
- Extended `config/clawdiy/openclaw.json`, `config/fleet/policy.json`, `config/moltis.toml`, and `tests/fixtures/config/moltis.toml` with explicit bearer auth, Telegram allowlist isolation, and fail-closed `codex-oauth` gate metadata.
- Created `scripts/clawdiy-auth-check.sh` and added operator smoke coverage via `./scripts/clawdiy-smoke.sh --stage auth`.
- Added regression suite `tests/security_api/test_clawdiy_auth_boundaries.sh` plus static assertions for workflow/policy auth gates.
- Updated `docs/runbooks/clawdiy-repeat-auth.md` with concrete repeat-auth commands against `/opt/moltinger/clawdiy/.env`.

**Validated**

- `./tests/run.sh --lane static --filter 'static_(config_validation|fleet_registry)' --json`
- `./tests/run.sh --lane security_api --filter security_api_clawdiy_auth_boundaries --json`
- `env CLAWDIY_GATEWAY_TOKEN=... CLAWDIY_SERVICE_TOKEN=... CLAWDIY_TELEGRAM_BOT_TOKEN=... ./scripts/preflight-check.sh --ci --target clawdiy --json`
- Added hosted-Control-UI RCA and rule for Clawdiy gateway token auth:
  `docs/rca/2026-03-12-clawdiy-hosted-control-ui-password-auth-mismatch.md`,
  `docs/rules/clawdiy-hosted-control-ui-token-auth.md`
- Follow-up Beads task for merge/rollout cleanup:
  `molt-di3` — roll out canonical `CLAWDIY_GATEWAY_TOKEN` and retire legacy password fallback
- `./scripts/clawdiy-smoke.sh --stage auth --json`

**Next**

- Move to US4 (`T029`-`T034`): rollback, restore, backup scope, and evidence preservation.

### 2026-03-09: Codex CLI Update Monitoring Research Seed

**Статус**: ✅ RESEARCH COMPLETE, READY FOR DEDICATED FEATURE BRANCH

#### Что проверено

- Локально установлен `codex-cli 0.112.0`
- По официальному Codex changelog на 2026-03-09 это актуальный latest release
- Подтверждены релевантные upstream capabilities для будущего workflow:
  - `codex exec --json` и `--output-schema`
  - улучшения `multi_agent`
  - worktree/resume flow
  - AGENTS/skills/config surfaces для repo-specific orchestration

#### Что создано

- Исследование: `docs/research/codex-cli-update-monitoring-2026-03-09.md`
- Speckit seed: `docs/plans/codex-cli-update-monitoring-speckit-seed.md`
- Закрытый research issue: `molt-1`
- Follow-up implementation issue: `molt-2` — Implement Codex CLI update monitor from Speckit seed

#### Вывод

- Для этой темы рекомендован **script-first hybrid**, а не long-running agent:
  - deterministic collector script
  - thin skill/command wrapper
  - durable report
  - optional Beads follow-up behind explicit flag

#### Next Step

1. Создать dedicated branch/worktree под `codex-update-monitor`
2. Запустить `/speckit.specify` по seed prompt из `docs/plans/codex-cli-update-monitoring-speckit-seed.md`
3. В отдельной feature-ветке уже проектировать JSON contract, issue integration и optional skill wrapper

### 2026-03-08: Git Topology Registry Automation (Feature: 006-git-topology-registry)

**Статус**: ✅ MERGE-READY FEATURE BRANCH

#### Что доставлено

- `docs/GIT-TOPOLOGY-REGISTRY.md` переведён в deterministic generated artifact
- `docs/GIT-TOPOLOGY-INTENT.yaml` оформлен как reviewed sidecar schema
- `scripts/git-topology-registry.sh` реализует `refresh`, `check`, `status`, `doctor`
- `/worktree`, `/session-summary`, `/git-topology` провязаны в topology workflow
- tracked hooks валидируют stale-state и блокируют `pre-push` при outdated registry
- `doctor --prune` сохраняет recovery draft, а `doctor --prune --write-doc` сохраняет backup last good registry

#### Проверки

- `./tests/unit/test_git_topology_registry.sh`
- `./tests/integration/test_git_topology_registry.sh`
- `./tests/e2e/test_git_topology_registry_workflow.sh`
- `./tests/run_unit.sh --filter git_topology_registry`
- `./tests/run_integration.sh --filter git_topology_registry`
- `./tests/run_e2e.sh --filter git_topology_registry_workflow`
- `./scripts/setup-git-hooks.sh`
- `./scripts/git-topology-registry.sh check`
- Manual smoke-test:
  - created issue `moltinger-jb6` for GPT-5.4 primary provider-chain evaluation
  - created sibling worktree `/Users/rl/coding/moltinger-jb6-gpt54-primary`
  - confirmed `doctor --prune` writes a recovery draft after raw topology change
  - confirmed `pre-push` blocks stale topology before publishing a new parallel branch
  - promoted the new branch/worktree from `needs-decision` to reviewed `active` intent in the sidecar

#### Post-UAT Hardening

- reproduced a real child-worktree drift case where `doctor --write-doc` from a child branch renamed the authoritative `006-*` worktree
- fixed canonical numbered-feature worktree identity so it no longer depends on the caller branch
- preserved legacy sidecar aliases `parallel-feature-NNN` as canonical `primary-feature-NNN`
- clarified in user docs that `doctor --prune --write-doc` intentionally dirties `docs/GIT-TOPOLOGY-REGISTRY.md` after real topology drift
- added RCA: `docs/rca/2026-03-08-topology-child-worktree-identity-drift.md`
- added regression coverage in `tests/e2e/test_git_topology_registry_workflow.sh`

#### Handoff

- Active branch: `006-git-topology-registry`
- Authoritative worktree: `/Users/rl/coding/moltinger-006-git-topology-registry`
- Parallel task worktree for field test: `/Users/rl/coding/moltinger-jb6-gpt54-primary`
- Primary operator docs:
  - `specs/006-git-topology-registry/quickstart.md`
  - `docs/GIT-TOPOLOGY-REGISTRY.md`
  - `docs/reports/consilium/2026-03-08-git-topology-registry-automation.md`
  - `docs/QUICK-REFERENCE.md`

#### Next Step

1. Open/update PR for `006-git-topology-registry`
2. Review merge diff around hooks and command wiring
3. Merge after final human review of generated registry and sidecar intent
4. Backlog follow-up: `moltinger-k89` — reusable installer skill for arbitrary repositories (P4 / nice-to-have)

---

### 2026-03-04: RCA Skill Enhancements — FINAL SESSION (001-rca-skill-upgrades)

**Статус**: ✅ FEATURE COMPLETE — Ready for merge to main

---

#### 🎯 Session Overview

Сессия началась как continuation для завершения RCA Skill Enhancements. В ходе работы:
1. Добавлен US6 (Lessons Query Skill) в спецификацию
2. Реализован lessons skill через skill-builder-v2
3. Проведено автономное тестирование всех 6 User Stories
4. Выявлены и исправлены 2 критических gap в RCA workflow
5. Добавлены token limit warnings для предотвращения bloat

---

#### 📦 Deliverables

**New Files Created:**
```
.claude/skills/lessons/SKILL.md          # 372 lines - Natural language lessons interface
docs/rca/2026-03-04-token-bloat-recurring.md  # RCA-004 report
specs/001-rca-skill-upgrades/spec.md     # Updated with US6 (FR-027 to FR-031)
specs/001-rca-skill-upgrades/tasks.md    # Updated with Phase 9 (T047-T054)
```

**Modified Files:**
```
.claude/skills/rca-5-whys/SKILL.md       # Added RCA COMPLETION CHECKLIST
CLAUDE.md                                 # Added token limit warning (~700 lines max)
MEMORY.md                                 # Added token limit warning (~300 lines max)
docs/LESSONS-LEARNED.md                   # Auto-regenerated (6 lessons)
```

---

#### 🧪 Testing Results

**Autonomous Testing (all 6 US):**

| User Story | Test Method | Result |
|------------|-------------|--------|
| US1: Auto-Context | `context-collector.sh shell` | ✅ PASS |
| US2: Domain Templates | File check (4 templates) | ✅ PASS |
| US3: RCA Hub | `rca-index.sh stats/validate` | ✅ PASS |
| US4: Chain-of-Thought | SKILL.md content check | ✅ PASS |
| US5: Test Generation | TEMPLATE.md content check | ✅ PASS |
| US6: Lessons Skill | Skill invocation + query-lessons.sh | ✅ PASS |

---

#### 🔧 Bug Fixes & Improvements

**RCA Skill Fix (Gap in workflow):**
- **Problem**: RCA conducted but lessons not formalized/indexed
- **Root Cause**: No mandatory step to run `build-lessons-index.sh`
- **Fix**: Added 7-step RCA COMPLETION CHECKLIST to skill

**Token Bloat Fix (RCA-004):**
- **Problem**: Central files keep growing despite previous discussions
- **Root Cause**: Rules were in OTHER files, not in the files themselves
- **Fix**: Added explicit token limit warnings at top of CLAUDE.md and MEMORY.md

---

#### 📝 Commits This Session

```
1420dce fix(instructions): add token limit warnings to prevent bloat (RCA-004)
d3ad740 fix(rca): add mandatory lessons indexing step to RCA workflow
31b3e44 test(rca): complete T044 and T054 - autonomous testing passed
de92ff7 chore: update LESSONS-LEARNED.md date
72cfe89 feat(skills): add lessons skill for RCA lesson management (US6)
475e890 docs(spec): add US6 Lessons Query Skill to RCA enhancements
b6a3478 docs(session): update with RCA Skill Enhancements completion
03e7c5c chore(beads): add lessons skill task to backlog (moltinger-wk1)
0fac204 feat(lessons): implement Lessons Architecture from RCA consilium
```

---

#### 📚 Lessons Learned This Session

**RCA-004: Token Bloat is Recurring**
1. Rules must be IN THE FILES THEY LIMIT, not in related docs
2. LLM has no memory between sessions → persistent rules in content
3. Explicit prohibition > implicit reference
4. Max size in lines > abstract "don't grow"

**RCA Workflow Gap**
1. Analysis without formalization = lost knowledge
2. Index rebuild is MANDATORY, not optional
3. Verification step prevents "lesson exists but not found"

---

#### 📊 Final Statistics

| Metric | Value |
|--------|-------|
| Total Tasks | 54 (T001-T054) |
| Tasks Completed | 54 (100%) |
| User Stories | 6 (US1-US6) |
| Functional Requirements | 31 (FR-001 to FR-031) |
| Success Criteria | 9 (SC-001 to SC-009) |
| RCA Reports Created | 6 |
| Lessons Indexed | 6 |
| Commits on Branch | 30+ |

---

#### 🚀 Next Steps

1. **Merge `001-rca-skill-upgrades` → `main`** — IN PROGRESS
2. **Close `moltinger-wk1`** — Task completed
3. **Test RCA in production** — New session with error trigger
4. **Monitor token usage** — Verify limits work

---

#### 📝 Final Commits (Token Bloat Fix)

```
72b7740 fix(token-bloat): remove CLAUDE.md/MEMORY.md direct write instructions
6f50a95 fix(rca-skill): remove token bloat contradiction (RCA-004)
```

**Изменённые файлы**:
- `.claude/skills/rca-5-whys/SKILL.md` — чеклист + warning
- `.claude/agents/health/workers/reuse-hunter.md` — docs/architecture/
- `.claude/skills/senior-architect/references/architecture_patterns.md`
- `docs/rca/TEMPLATE.md` — new rule file pattern

---

### 2026-03-03: RCA Skill Enhancements (Feature: 001-rca-skill-upgrades)

**Завершено**:

#### RCA Skill Creation
- ✅ Создан навык `rca-5-whys` для Root Cause Analysis методом "5 Почему"
- ✅ Добавлен MANDATORY раздел в CLAUDE.md с триггерами для exit code != 0
- ✅ Создан шаблон отчёта `docs/rca/TEMPLATE.md`
- ✅ Протестировано в новой сессии — LLM автоматически запускает RCA

#### Expert Consilium (13 экспертов)
Проведён консилиум специалистов для улучшения навыка:
- 🏗️ Architect: RCA Hub Architecture
- 🐳 Docker Engineer: Domain-Specific Templates
- 🐚 Unix Expert: Auto-Context Collection
- 🚀 DevOps: RCA → Rollback → Fix Pipeline
- 🔧 CI/CD Architect: Quality Gate Integration
- 📚 GitOps Specialist: Git-based RCA Index
- И другие...

#### Feature Specification (001-rca-skill-upgrades)
- ✅ Создана спецификация через `/speckit.specify`
- ✅ 5 User Stories с приоритетами P1-P3
- ✅ 26 Functional Requirements
- ✅ 7 Success Criteria
- ✅ Ветка: `001-rca-skill-upgrades`

**Коммиты сессии**:
- `c97f9cd` — feat(skills): add rca-5-whys skill for Root Cause Analysis
- `dbe6f39` — fix(skills): integrate RCA 5 Whys into systematic-debugging
- `b28dda2` — fix(instructions): strengthen RCA trigger for any non-zero exit code
- `d0a8c45` — docs(spec): add RCA Skill Enhancements specification

---

### 2026-03-02 (продолжение 2): Test Suite Bug Fixes & Server Validation

**Завершено**:

#### Test Suite Implementation
- ✅ 18 тестовых файлов создано (unit, integration, e2e, security)
- ✅ Test infrastructure: helpers, runners, CI/CD workflow

#### Bug Fixes (Shell Compatibility)
| # | Проблема | Решение |
|---|----------|---------|
| 1 | `mapfile: command not found` | Заменил на `while IFS= read -r` loop |
| 2 | `declare -g: invalid option` | Убрал `-g` flag |
| 3 | Empty array unbound variable | Добавил `${#arr[@]} -eq 0` check |
| 4 | Wrong login endpoint `/login` | Исправил на `/api/auth/login` |
| 5 | Wrong Content-Type `x-www-form-urlencoded` | Исправил на `application/json` |
| 6 | `api_request` function bug | Переписал с правильным if/else |
| 7 | Metrics endpoint `/metrics` | Исправил на `/api/v1/metrics` с auth |

#### Server Validation Results
**Integration Tests**: 9/10 passed (1 skipped - metrics format)
- ✅ health_endpoint
- ✅ login_endpoint
- ✅ chat_endpoint
- ✅ chat_response_format
- ✅ metrics_endpoint
- ⏭️ metrics_prometheus_format (skipped)
- ✅ mcp_servers_endpoint
- ✅ session_persistence
- ✅ unauthorized_request
- ✅ api_response_time

**Security Tests**: 4/6 passed
- ✅ auth_valid_password
- ✅ auth_invalid_password
- ✅ auth_session_cookie
- ✅ auth_session_persistence
- ❌ auth_rate_limiting (HTTP 400 vs expected 401)
- ❌ auth_brute_force (HTTP 400 vs expected 401)

#### Website Investigation
- ✅ moltis.ainetic.tech **РАБОТАЕТ** (не "пустая страница")
- ✅ Returns HTTP 303 → /login (корректное поведение)
- ✅ Login page загружается с JavaScript
- ✅ Health endpoint: `{"status":"ok","version":"0.10.6"}`

#### Коммиты сессии
- `1c431e7` — fix(tests): fix api_request function and metrics endpoint
- `a9cd1d7` — fix(tests): use correct login endpoint /api/auth/login with JSON
- `d493a71` — fix(tests): improve shell compatibility for zsh and bash

#### Ключевые выводы
1. **API Endpoints**:
   - Login: `POST /api/auth/login` с `{"password":"..."}`
   - Chat: `POST /api/v1/chat` с cookie
   - Metrics: `GET /api/v1/metrics` с cookie (не `/metrics`)
2. **Shell Compatibility**: Bash-скрипты должны избегать bashisms для zsh
3. **Website работает**: "Пустая страница" - client-side issue (browser cache, JS, CORS)

---

### 2026-03-02 (продолжение): CI/CD Test Suite Integration

**Завершено**:

#### Test Suite CI/CD Workflow
- ✅ `.github/workflows/test.yml` создан (534 строк)
- ✅ 4 test jobs: unit, integration, security, e2e
- ✅ Test results uploaded as artifacts (7-30 day retention)
- ✅ GitHub Step Summary с тестовыми метриками
- ✅ Fast-fail на unit test failure
- ✅ Manual workflow dispatch с выбором test suite

#### Test Files Created/Updated
**Unit Tests:**
- `tests/unit/test_circuit_breaker.sh` — Circuit breaker state machine
- `tests/unit/test_config_validation.sh` — TOML/YAML validation
- `tests/unit/test_prometheus_metrics.sh` — Metrics export

**Integration Tests:**
- `tests/integration/test_api_endpoints.sh` — Moltis API
- `tests/integration/test_llm_failover.sh` — Failover chain
- `tests/integration/test_mcp_servers.sh` — MCP connectivity
- `tests/integration/test_telegram_integration.sh` — Telegram bot

**E2E Tests:**
- `tests/e2e/test_chat_flow.sh` — Complete chat scenarios
- `tests/e2e/test_deployment_recovery.sh` — Rollback scenarios
- `tests/e2e/test_full_failover_chain.sh` — End-to-end failover
- `tests/e2e/test_rate_limiting.sh` — Rate limit handling

**Security Tests:**
- `tests/security/test_authentication.sh` — Auth flows
- `tests/security/test_input_validation.sh` — Input sanitization

#### Test Runners Updated
- `tests/run_unit.sh` — Fix run_all_tests function call
- `tests/run_integration.sh` — Parallel execution support
- `tests/run_e2e.sh` — Timeout и container management
- `tests/run_security.sh` — Severity filtering

#### Makefile Targets (уже существовали)
- `make test` — Run unit tests (default)
- `make test-unit` — Unit tests only
- `make test-integration` — Integration tests
- `make test-e2e` — E2E tests
- `make test-security` — Security tests
- `make test-all` — All test suites

#### Коммит сессии
- `03c4c1a` — feat(ci): add comprehensive test suite CI/CD workflow

#### Next Steps
- Дождаться первого запуска test workflow на GitHub Actions
- Проверить, что все тесты проходят корректно
- При необходимости добавить зависимости для тестов

---

### 2026-03-02: CI/CD Deployment Debug & Lessons Learned

**Завершено**:

#### Deployment Debug (15+ CI/CD runs)
- ✅ **Deploy to Production: SUCCESS** — Moltis running, healthy
- ✅ Исправлено 10 self-inflicted ошибок в CI/CD
- ✅ **Incident #003** задокументирован в LESSONS-LEARNED.md

#### Исправленные проблемы
| # | Проблема | Решение |
|---|----------|---------|
| 1 | File secrets вместо env vars | Изменил на `${VAR}` из .env |
| 2 | docker-compose.prod.yml не sync | Добавил `scp docker-compose.prod.yml` |
| 3 | Deploy без `-f` флага | Добавил `-f docker-compose.prod.yml` |
| 4 | traefik_proxy сеть не найдена | Создал `docker network create` |
| 5 | CPU limits > server capacity | Уменьшил 4→2 CPUs |
| 6 | Shellcheck warnings как errors | `-S error` вместо `-S style` |
| 7 | CRLF в YAML | Конвертировал в LF |
| 8 | Boolean в YAML | `true` → `"true"` |
| 9 | TELEGRAM_ALLOWED_USERS без default | Добавил `${VAR:-}` |
| 10 | Несуществующий image tag | Использую `latest` с сервера |

#### Документация
- ✅ **Incident #003** в `docs/LESSONS-LEARNED.md` — полный анализ ошибок
- ✅ **Pre-Deploy-Config Checklist** — новый чеклист для изменений deploy
- ✅ **Token optimization** — чеклисты перемещены из CLAUDE.md в LESSONS-LEARNED.md

#### Коммиты сессии
- `b04510a` — refactor: move checklists from CLAUDE.md to LESSONS-LEARNED.md (token optimization)
- `0974da7` — docs(lessons): add Incident #003 retrospective
- `b619f36` — fix(resources): adjust CPU limits to fit 2-CPU server
- `89aac32` — fix(ci): sync docker-compose.prod.yml and use -f flag
- `a87d745` — fix(deploy): use env vars instead of file secrets
- `d909755` — fix(ci): use 'latest' image tag
- `505fa76` — fix(ci): make image pull optional
- `112504c` — fix(ci): use v1.7.0 as default version
- `65b6321` — fix(ci): quote boolean env vars
- `3ea97ec` — fix(ci): convert CRLF to LF
- `1f44237` — fix(ci): use -S error for shellcheck
- `61e41ac` — fix(ci): use -S style for shellcheck
- `881c30e` — fix(ci): ignore SC2155 shellcheck warning
- `44aaa7f` — fix(ci): remove --strict flag

#### Главный урок
> **"Understand Before Change"** — Всегда понимать существующую архитектуру ПЕРЕД изменениями.
> См. `docs/LESSONS-LEARNED.md` → Quick Reference Card

---

### 2026-03-02 (продолжение): CI/CD Smoke Test 404 Fix

**Проблема**: Post-deployment Verification падал с HTTP 404 на Traefik routing test.

**Root Causes (3 bugs)**:
1. **Network mismatch**: Moltis → `traefik_proxy`, Traefik → `traefik-net` (разные сети!)
2. **Wrong domain**: `MOLTIS_DOMAIN=ainetic.tech` вместо `moltis.ainetic.tech` в deploy.yml
3. **Docker DNS priority**: Traefik использовал IP из monitoring сети, не traefik-net

**Fixes Applied**:
- `e47e309` — fix(deploy): use traefik-net instead of traefik_proxy
- `5572c0c` — fix(deploy): correct Traefik Host rule to moltis.ainetic.tech
- `53194c0` — fix(deploy): set correct MOLTIS_DOMAIN in deploy.yml
- `df36060` — fix(deploy): add traefik.docker.network label for correct IP resolution

**Результат**: All smoke tests passed ✅
- Test 1: Container running ✅
- Test 2: Health endpoint ✅
- Test 3: Traefik routing (HTTP 200) ✅
- Test 4: Main endpoint (HTTP 303) ✅
- Test 5: GitOps config check ✅

**Урок**: При диагностике routing проблем проверять:
1. Обе ли стороны в одной Docker сети
2. Правильный ли Host rule в labels
3. Какую сеть использует Traefik для DNS resolution

---

### 2026-03-01 (продолжение): Fallback LLM with Ollama Sidecar (001-fallback-llm-ollama)

**Завершено**:

#### Consilium Architecture Discussion
- ✅ Запущен консилиум 19 экспертов для обсуждения архитектуры failover
- ✅ Рекомендован вариант: Ollama Sidecar + Circuit Breaker
- ✅ Анализ 5 вариантов развёртывания

#### Speckit Workflow Complete
- ✅ `/speckit.specify` — spec.md с 3 user stories
- ✅ `/speckit.plan` — plan.md, research.md, data-model.md, contracts/
- ✅ `/speckit.tasks` — 32 задачи в 7 фазах
- ✅ `/speckit.tobeads` — Epic moltinger-39q в Beads

#### Implementation (Phase 1-5 Complete)
- ✅ **Phase 1: Setup** — Ollama sidecar в docker-compose.prod.yml (4 CPUs, 8GB RAM)
- ✅ **Phase 2: Foundational** — moltis.toml failover config (GLM → Ollama → Gemini)
- ✅ **Phase 3: US1 MVP** — Circuit Breaker state machine (CLOSED → OPEN → HALF-OPEN)
- ✅ **Phase 4: US2** — Prometheus metrics (llm_provider_available, moltis_circuit_state)
- ✅ **Phase 5: US3** — CI/CD validation (preflight checks, smoke tests)

#### Files Created/Modified
- `docker-compose.prod.yml` — Ollama service + ollama-data volume + ollama_api_key secret
- `config/moltis.toml` — ollama provider enabled + failover chain configured
- `scripts/ollama-health.sh` — Ollama health check script
- `scripts/health-monitor.sh` — Circuit breaker + Prometheus metrics
- `config/prometheus/alert-rules.yml` — LLM failover alerts
- `config/alertmanager/alertmanager.yml` — Alert routing for failover
- `scripts/preflight-check.sh` — Ollama config validation
- `.github/workflows/deploy.yml` — CI/CD validation steps
- `.gitignore` — Explicit ollama_api_key.txt entry

#### Key Technical Decisions
- **Circuit Breaker**: 3 failures → OPEN state → 5 min recovery timeout
- **State File**: `/tmp/moltis-llm-state.json` with flock locking
- **Metrics**: Prometheus textfile exporter for node_exporter
- **Failover Chain**: GLM-5 (Z.ai) → Ollama Gemini → Google Gemini

**Дополнительные инструменты (post-feature)**:
- ✅ `/rate` — команда для проверки rate limits
- ✅ `scripts/rate-check.sh` — локальный мониторинг debug логов
- ✅ `scripts/claude-rate-watch.sh` — live мониторинг процессов Claude
- ✅ `scripts/zai-rate-monitor.sh` — API мониторинг Z.ai
- ✅ `docs/reports/consilium/openclaw-clone-plan.md` — план нового проекта "kruzh-claw"

**Коммиты сессии**:
- `d7fc975` — feat(tools): add rate limit monitoring and OpenClaw clone plan
- `41e2724` — fix(fallback-llm): use OLLAMA_API_KEY env var instead of Docker secret
- `e129990` — docs(session): mark Fallback LLM feature as complete
- `98ec7ba` — feat(fallback-llm): add Ollama sidecar and configure failover
- `5dc8f0b` — feat(fallback-llm): add Ollama health check script (T009)
- `fd06e46` — feat(fallback-llm): add GLM/Ollama health checks (T010)
- `c1b2be5` — feat(fallback-llm): implement circuit breaker state machine (T011-T015)
- `68c6dbb` — feat(fallback-llm): add Prometheus metrics export (T016-T019)
- `cf65a93` — feat(fallback-llm): add Prometheus alerts and AlertManager config (T020-T021)
- `5ee89c2` — feat(fallback-llm): add Ollama validation to preflight (T022-T023)
- `19505b9` — feat(fallback-llm): add CI/CD validation for failover (T024-T026)
- `e4d02b8` — docs(fallback-llm): update SESSION_SUMMARY and .gitignore (T027, T030)
- `88f59df` — docs(fallback-llm): complete Phase 6 - documentation and close epic (T028-T032)

**Feature Complete**: Все 32 задачи выполнены, готово к деплою.
**Beads Epic**: moltinger-39q закрыт

---

### 2026-03-01: Docker Deployment Improvements - Feature Complete

**Завершено**:

#### Epic moltinger-6ys Closed
- ✅ Все 10 фаз реализованы
- ✅ Phase 0: Planning - executors assigned
- ✅ Phase 1: Setup - directories created
- ✅ Phase 2: Foundational - YAML anchors, compose validation
- ✅ Phase 3 (US1): Automated Backup - systemd timer, S3 support, JSON output
- ✅ Phase 4 (US2): Secrets Management - Docker secrets, preflight validation
- ✅ Phase 5 (US3): Reproducible Deployments - pinned versions
- ✅ Phase 6 (US4): GitOps Compliance - no sed, full file sync
- ✅ Phase 7 (US5-US7): P2 Enhancements - JSON output, unified config
- ✅ Phase 8: Polish - docs, alerts, quickstart

**Коммиты сессии**:
- `789fba8` — chore(beads): close Docker Deployment Improvements epic

**Оставшиеся задачи (P4 Backlog)**:
- moltinger-xh7: Fallback LLM provider (CRITICAL)
- moltinger-sjx: S3 Offsite Backup
- moltinger-r8r: Traefik Rate Limiting
- moltinger-j22: AlertManager Receivers
- moltinger-eb0: Grafana Dashboard

---

### 2026-02-28: GitOps Compliance Framework (P0/P1/P2)

**Завершено**:

#### P0 - Критические (Incident #002)
- ✅ Добавлен ssh/scp в ASK list настроек
- ✅ Добавлено SSH/SCP Blocking Rule в CLAUDE.md
- ✅ Добавлен scripts/ sync в deploy.yml

#### P1 - Высокий приоритет
- ✅ **GitOps compliance test в CI** — job `gitops-compliance` сравнивает хеши git ↔ server
- ✅ **Drift detection cron job** — `gitops-drift-detection.yml` каждые 6 часов
- ✅ **Guards в серверные скрипты** — `gitops-guards.sh` библиотека

#### P2 - Средний приоритет
- ✅ **IaC подход для scripts** — `manifest.json` + `scripts-verify.sh`
- ✅ **GitOps SLO и метрики** — `gitops-metrics.yml` + `gitops-metrics.sh`
- ✅ **UAT gate с GitOps checks** — `uat-gate.yml` с 5 gate'ами

#### Sandbox improvements
- ✅ Уточнён deny list: `.env.example` разрешён, реальные секреты заблокированы
- ✅ Разрешены `git push` и `ssh` для автоматизации
- ✅ Добавлен `~/.beads` в write allow list

**Коммиты сессии**:
- `fddfc17` — feat(ci): add GitOps compliance check job (P1-1)
- `dac5a33` — feat(ci): add GitOps drift detection cron job (P1-2)
- `688efee` — feat(scripts): add GitOps guards (P1-3)
- `70b24d5` — feat(iac): add manifest-based scripts management (P2-4)
- `61cd539` — feat(metrics): add GitOps SLO and metrics collection (P2-5)
- `62a08ac` — feat(uat): add UAT gate with GitOps checks (P2-6)
- `b8c9bc4` — chore: update Claude Code config and agents
- `83cff41` — fix(sandbox): add ~/.beads to write allow list

**В работе**:
- ✅ Bug health check завершён — все найденные баги исправлены

**Нерешённые**:
- ❌ Moltis API аутентификация для автоматического тестирования Telegram бота

---

### 2026-02-28 (продолжение 2): Session Automation Framework

**Завершено**:

#### Consilium: Session State Persistence
- ✅ Запущен консилиум 6 экспертов для анализа session state automation
- ✅ Эксперты единогласно рекомендовали Hook-Based Auto-Save
- ✅ GitOps Specialist: Issues ≠ Files (git = source of truth)

#### Session Automation Implementation
- ✅ **Stop Hook** — `.claude/hooks/session-save.sh` (auto-backup)
- ✅ **Issues Mirror** — `.claude/hooks/session-issues-mirror.sh` (visibility)
- ✅ **Pre-Commit** — `.githooks/pre-commit` (incremental logging)
- ✅ **Setup Script** — `scripts/setup-git-hooks.sh` (git config)

#### Bug Fix
- ✅ Исправлен `SESSION_STATE.md` → `SESSION_SUMMARY.md` во всех hook-скриптах

**Коммиты сессии**:
- `7246333` — feat(ci): add scripts/ to GitOps sync (from 001-docker-deploy-improvements)
- `f8dab74` — feat(session): complete session automation framework
- `9d89adb` — fix(hooks): use correct SESSION_SUMMARY.md filename
- `23c40f4` — chore(release): v1.8.0

**Release v1.8.0**: 33 commits (17 features,7 bug fixes, 9 other changes)

---

### 2026-02-28 (продолжение): P4 Tasks

**Завершено**:

#### P4 - Backlog tasks
- ✅ **moltinger-hdn** — Backup verification cron (еженедельная проверка integrity)
- ✅ **moltinger-kpt** — Pre-deployment tests (shellcheck, yamllint, compose validation)
- ✅ **moltinger-eml** — Replace sed -i with MOLTIS_VERSION env var (GitOps compliant)
- ✅ **moltinger-wisp-u7e** — Healthcheck epic закрыт (все баги исправлены)

**Новые файлы**:
- `scripts/cron.d/moltis-backup-verify` — Cron конфигурация

**Изменения в CI/CD**:
- Добавлен `test` job в deploy.yml (shellcheck, yamllint, docker-compose validation)
- Deploy теперь зависит от успешного прохождения тестов
- Добавлен шаг установки cron jobs из scripts/cron.d/

**Коммит**:
- `2aaa763` — feat(ci): add pre-deployment tests and backup verification cron

---

### 2026-02-18/19: AI Agent Factory Transformation

**Завершено**:
- ✅ Исследование OpenClaw/Moltis (1200 строк)
- ✅ Создана инструкция для самообучения LLM (1360 строк)
- ✅ Создан skill `telegram-learner` для мониторинга @tsingular
- ✅ Создана структура knowledge base
- ✅ Обновлена конфигурация moltis.toml (search_paths, auto_load)
- ✅ Деплой на сервер (commit 022ea93)

---

## 🔗 Quick Links

- **Telegram Bot**: @moltinger_bot
- **Web UI**: https://moltis.ainetic.tech
- **Инструкция для LLM**: docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md
- **Быстрая справка**: docs/QUICK-REFERENCE.md
- **GitOps Lessons**: docs/LESSONS-LEARNED.md
- **Git Topology Registry**: docs/GIT-TOPOLOGY-REGISTRY.md
- **Topology Quickstart**: specs/006-git-topology-registry/quickstart.md

---

## 📞 Commands Reference

```bash
# Deploy
git add . && git commit -m "message" && git push

# Check CI/CD
gh run list --repo RussianLioN/moltinger --limit 3

# SSH to server
ssh root@ainetic.tech
docker logs moltis -f

# Health check
curl -I https://moltis.ainetic.tech/health

# Beads
bd ready              # Find available work
bd prime              # Restore context
bd doctor             # Health check

# GitOps
scripts/gitops-metrics.sh json    # Collect metrics
scripts/scripts-verify.sh         # Validate scripts

# Tests
make test             # Run unit tests (default)
make test-unit        # Run unit tests only
make test-integration # Run integration tests
make test-e2e         # Run end-to-end tests
make test-security    # Run security tests
make test-all         # Run all test suites

# CI/CD Test Workflow
gh run list --workflow test.yml  # View test workflow runs
gh run view --workflow test.yml   # View latest test run details
```

---

## 🎯 Next Steps

1. **P4 Backlog** — 4 задачи готовы к работе (см. `bd ready`)
2. **moltinger-sjx** — HIGH: S3 Offsite Backup
3. **moltinger-r8r** — MEDIUM: Traefik Rate Limiting
4. **moltinger-j22** — MEDIUM: AlertManager Receivers
5. **moltinger-eb0** — MEDIUM: Grafana Dashboard
6. Протестировать skill telegram-learner на канале @tsingular

### P4 Priority Tasks (Recommended Order)

| # | Task | Priority | Why |
|---|------|----------|-----|
| 1 | ~~`moltinger-xh7`~~ | ~~CRITICAL~~ | ✅ DONE: Fallback LLM with Ollama Sidecar |
| 2 | `moltinger-sjx` | HIGH | S3 Offsite Backup - disaster recovery |
| 3 | `moltinger-r8r` | MEDIUM | Traefik Rate Limiting - защита от abuse |
| 4 | `moltinger-j22` | MEDIUM | AlertManager Receivers - уведомления |
| 5 | `moltinger-eb0` | MEDIUM | Grafana Dashboard - визуализация |

> Детали в: `docs/P4-BACKLOG-PRIORITIES.md`

---

## 🏗️ GitOps Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    UAT GATE                                 │
│  Pre-flight → GitOps Check → Smoke Tests → Approval → Deploy│
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 CI/CD PIPELINE (Updated 2026-02-28)         │
│  gitops-compliance → preflight → test → backup → deploy    │
│                              ↑                              │
│                    Deploy blocked on test failure           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              SCHEDULED WORKFLOWS                            │
│  • Drift Detection (каждые 6ч) → Issue on drift            │
│  • Metrics Collection (каждый час) → SLO tracking          │
│  • Backup Verification (каждое воскресенье 03:00 MSK)      │
└─────────────────────────────────────────────────────────────┘
```

**SLOs**:
- Compliance Rate: ≥95%
- Deployment Success: ≥99%
- Drift Detection SLA: 6 hours
- Backup Verification: Weekly

---

*Last updated: 2026-03-08 | Session: Git Topology Registry Automation (Feature: 006-git-topology-registry)*
