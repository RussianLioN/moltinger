# Implementation Plan: Telegram Cloneable Agent

**Branch**: `038-telegram-cloneable-agent` | **Date**: 2026-03-29 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/038-telegram-cloneable-agent/spec.md`

## Summary

Спроектировать cloneable Moltis/OpenClaw blueprint для long-running Telegram задач, где:

- `user-facing Telegram lane` остаётся коротким, безопасным и без `Activity log` leakage;
- тяжёлая работа уходит в отдельный `worker/background lane`;
- completion delivery делается явной и надёжной отдельной операцией;
- durable state хранится вне chat history;
- version-watch / notify сценарий оформляется как повторно используемый шаблон;
- watchdog и authoritative UAT fail-closed на timeout/activity-log/delivery/routing regressions.

## Technical Context

**Language/Version**: Markdown design artifacts сейчас; будущая реализация затронет TOML config, Bash-based operational scripts/tests и skill markdown packages  
**Primary Dependencies**: Moltis/OpenClaw session model, sub-agents, cron, heartbeat, message send, background exec/process, existing `scripts/telegram-bot-send.sh`, existing Telegram UAT tests, future cloneable skills under `skills/`  
**Storage**: Gateway session store and transcripts как runtime substrate; отдельный durable job/monitor store как feature requirement; fixture files and contract docs in repo  
**Testing**: Bash component tests, fixture-backed Telegram contract tests, live external Telegram smoke/UAT, static config validation  
**Target Platform**: Remote Moltis/OpenClaw gateway with Telegram polling channel and background worker capability  
**Project Type**: Agent architecture + config/preset + skill template + operational runbook + test contract  
**Performance Goals**: Short initial Telegram ack, отсутствие необходимости держать один sync-turn дольше safe window, explicit completion delivery после долгой работы, duplicate-safe monitor notifications  
**Constraints**: No new feature branch or feature number; work inside current lane `038`; no chat-history-only state; no prompt-only fix; heartbeat is secondary, not single source of truth; user-facing lane must degrade gracefully under tool-heavy load  
**Scale/Scope**: One cloneable blueprint reusable across multiple Telegram agents; one safe user lane, one or more worker patterns, one durable state contract, one explicit notify/fallback model, one authoritative UAT contract

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Context-First Development: PASS (использован локальный источник требований из `036`, изучены существующие правила, runbook и Telegram UAT surface внутри текущего repo до уточнения дизайна).
- Single Source of Truth: PASS (официальные Moltis/OpenClaw docs и upstream issues остаются основой; community evidence используется как вторичный слой, не заменяющий official truth).
- Library-First Development: PASS (дизайн опирается на уже существующие runtime primitives OpenClaw: `subagents`, `cron`, `message`, `process`, `session_state`, а не на новый самодельный orchestration runtime по умолчанию).
- Code Reuse & DRY: PASS (план переиспользует `scripts/telegram-bot-send.sh`, существующие Telegram UAT suites, existing docs/rules patterns и cloneable skill surfaces вместо ещё одной изолированной delivery stack).
- Strict Type Safety: N/A for planning slice (основной carrier ожидается в config/docs/tests/skills; при реализации durable state contracts должны быть формализованы).
- Atomic Task Execution: PASS (работа режется на независимые user stories: thin Telegram lane, worker lane/state, delivery, version-watch template, watchdog, UAT).
- Quality Gates: PASS (authoritative UAT и contract tests являются центральной частью feature, а не постфактум-polish).
- Progressive Specification: PASS (текущий scope ограничен Speckit package и planning artifacts для lane `038`; runtime implementation вынесена в tasks).

Нарушений, требующих отдельного exception handling, сейчас нет.

## Project Structure

### Documentation (this feature)

```text
specs/038-telegram-cloneable-agent/
├── spec.md
├── plan.md
├── tasks.md
└── checklists/
    └── requirements.md
```

### Source Code (future implementation surface)

```text
config/
└── moltis.toml

skills/
├── telegram-cloneable-agent/
│   └── SKILL.md
└── telegram-version-watch/
    └── SKILL.md

docs/
├── runbooks/
│   └── moltis-telegram-cloneable-agent.md
├── rules/
│   ├── moltis-telegram-cloneable-agents-must-use-explicit-completion-delivery.md
│   └── moltis-telegram-long-running-workers-must-expose-watchdog-signals.md
└── knowledge/
    └── LLM-REMOTE-MOLTIS-DOCKER-RUNBOOK.md

scripts/
└── telegram-bot-send.sh

tests/
├── component/
│   ├── test_telegram_cloneable_agent_contract.sh
│   ├── test_telegram_version_watch_contract.sh
│   └── test_telegram_remote_uat_contract.sh
├── fixtures/
│   └── telegram-cloneable-agent/
└── live_external/
    └── test_telegram_long_running_cloneable_agent_smoke.sh
```

**Structure Decision**: Этот slice проектирует один reusable blueprint, который позже будет приземлён в уже существующие репозиторные поверхности: `config/moltis.toml` для lane/policy/guardrails, `skills/` для cloneable templates, `docs/` для operator contract и `tests/` для authoritative UAT.

## Additional Research Synthesis

Ниже решения, которые сегодня выглядят самыми интересными и элегантными для long-running/автономных/сложных задач в Moltis/OpenClaw-сообществе. Это не количественный рейтинг по install-base, а инженерная выборка по тому, что повторяется в official docs, upstream field reports и свежем community evidence.

### 1. Thin Telegram Front + Background Sub-Agent

**Pattern**: пользовательский Telegram lane быстро принимает запрос, после чего `/subagents spawn` или `sessions_spawn` запускает отдельного background researcher/worker.  
**Почему сообщество это любит**: sub-agent работает non-blocking, изолирован по session, а completion handoff уже имеет собственный resilient delivery path обратно в requester chat.  
**Когда применять**: ad-hoc исследование, чтение сайта/документации, deep analysis по запросу пользователя.  
**Источники**:

- [Sub-Agents](https://docs.openclaw.ai/tools/subagents)
- [Session Tool / sessions_spawn](https://docs.openclaw.ai/concepts/session-tool)

### 2. Isolated Cron Or Custom Session Monitor

**Pattern**: recurring background tasks выполняются через `cron` в isolated session или в persistent named session (`session:custom-id`) вместо heartbeat-only модели.  
**Почему это элегантно**: precise timing, отдельный session namespace, отсутствие загрязнения main history, возможность выбрать другой model/thinking, built-in delivery modes.  
**Когда применять**: version monitoring, scheduled checks, daily/weekly deep reviews, delayed reminders.  
**Источники**:

- [Cron Jobs](https://docs.openclaw.ai/automation/cron-jobs)
- [Cron vs Heartbeat](https://docs.openclaw.ai/automation/cron-vs-heartbeat)
- [Heartbeat](https://docs.openclaw.ai/gateway/heartbeat)

### 3. Detached Shell/CLI Work Via `exec` + `process`

**Pattern**: shell-heavy or crawl-heavy work запускается в background через `exec` с background/yield semantics, а lifecycle отслеживается через `process poll/log/kill`.  
**Почему это полезно**: хороший fit для детерминированных задач вроде скачивания, сборок, скриптовых проверок, где не нужен постоянный LLM loop; можно иметь `sessionId`, опрашивать вывод и жёстко убивать зависшие процессы.  
**Когда применять**: script-driven monitors, CLI crawlers, build/report pipelines, chunked crawls with explicit polling.  
**Источники**:

- [Background Exec and Process Tool](https://docs.openclaw.ai/gateway/background-process)

### 4. OpenProse Programs For Multi-Agent Research + Durable Workflow State

**Pattern**: heavy research/synthesis оркестрируется через `.prose` program с явной параллельностью агентов и state backend в filesystem / sqlite / postgres.  
**Почему это элегантно**: workflow markdown-first, повторно используемый, умеет многoагентное исследование, хранит run-state вне chat history и маппится на runtime primitives OpenClaw (`sessions_spawn`, `read/write`, `web_fetch`).  
**Когда применять**: исследование большого сайта, multi-agent research+synthesis, повторяемые analysis pipelines.  
**Источники**:

- [OpenProse](https://docs.openclaw.ai/prose)

### 5. Lobster + `llm-task` For Deterministic Resumable Pipelines

**Pattern**: многошаговая automation цепочка живёт как deterministic workflow runtime с approval gates, resumable steps и JSON-only LLM subtasks.  
**Почему это ценно**: хорошая замена “одному большому агентному импровизационному turn” там, где нужен контроль шагов, явные approvals и возобновление без полного перезапуска.  
**Когда применять**: side-effectful workflows, approval-heavy monitors, structured analysis pipelines, resumable operations.  
**Источники**:

- [Cron vs Heartbeat: Lobster](https://docs.openclaw.ai/automation/cron-vs-heartbeat)
- [LLM Task](https://docs.openclaw.ai/tools/llm-task)

### 6. Explicit Direct Delivery / Relay Instead Of Implicit Reply

**Pattern**: completion отправляется отдельным outbound path (`message send`, direct relay to agent session, explicit account/topic-aware delivery) вместо надежды на то, что implicit reply того же long turn дойдёт сам.  
**Почему это повторяется в field practice**: именно delivery loss и wrong-topic/wrong-bot routing часто ломают UX. Community уже строит relay/fix plugins, которые обходят слабые announce/session-send paths и сохраняют delivery context для Telegram topics и multi-bot setups.  
**Когда применять**: финальная доставка результата, reminder/completion, multi-bot Telegram groups/topics, fallback после failed announce/system-event path.  
**Источники**:

- [message](https://docs.openclaw.ai/cli/message)
- [Multi-Agent Routing](https://docs.openclaw.ai/concepts/multi-agent)
- Community plugin report: [openclaw-agent-relay](https://www.reddit.com/r/openclaw/comments/1s00ybd/i_built_a_plugin_that_fixes_interagent_messaging/)

### 7. Background Task Engine With Pause/Resume/Needs-Assistance

**Pattern**: detached task engine ведёт task lifecycle отдельно от chat request, умеет pause/resume, marks `needs_assistance` и шлёт completion назад в originating chat and Telegram.  
**Почему это интересно**: это уже ближе к полноценной productized solution для “исследуй долго, не молчи бесконечно, попроси помощи если застрял”.  
**Когда применять**: более автономные исследовательские агенты, где нужен managed task lifecycle, а не просто “отправить одну задачу sub-agent’у”.  
**Источники**:

- Community ecosystem example: [SmallClaw background tasks update](https://www.reddit.com/r/openclaw/comments/1rgd32g/smallclaw_update_v102_background_tasks_multi/)

## Selected Blueprint

Для `038` выбирается не один механизм, а composition pattern:

1. **Default user request path**: thin Telegram front, быстрый ack, no long tool-heavy sync-turn.
2. **Default ad-hoc deep research path**: isolated sub-agent/session worker.
3. **Default scheduled monitor path**: isolated cron or custom named session with durable external state.
4. **Default script-heavy path**: detached `exec` + `process`, если задача лучше ложится в shell/CLI pipeline, чем в LLM loop.
5. **Default explicit workflow path**: OpenProse or Lobster, если нужен детерминированный pipeline, approvals или resumability.
6. **Default completion path**: explicit message/direct delivery with stored routing context and fallback.
7. **Default state model**: per-user conversational preference may live in `session_state`, but job/monitor/version state lives in durable store outside chat history.
8. **Default health model**: progress-aware watchdog + loop detection + authoritative UAT; heartbeat only secondary.

## Rejected Baselines

- **One long synchronous Telegram turn**: отвергнуто из-за `90s` watchdog risk, tool-heavy silence, compaction pressure и высокой вероятности потери финального reply.
- **Heartbeat-only monitor**: отвергнуто как единственный scheduler/delivery mechanism; heartbeat годится как awareness layer, но не как sole truth path.
- **Chat-history-only state**: отвергнуто, потому что isolated cron/sub-agent/process runs ломают такую модель при session rotation, compaction и reset.
- **Prompt-only fix for `Activity log` leakage**: отвергнуто, потому что transport/runtime leakage и delivery drift требуют отдельного UAT/delivery contract.
- **Announce/system-event only completion**: отвергнуто как единственный completion path; нужен explicit direct-send fallback.

## Phase 0: Research Decisions

1. Разделить `user-facing Telegram lane` и `worker lane` как default contract для cloneable long-running agents.
2. Хранить durable job/monitor/version state вне chat history и вне одного isolated session.
3. Делать completion delivery отдельной явной операцией с сохранённым route context и fallback path.
4. Использовать pattern matrix, а не один runtime primitive для всех задач:
   - ad-hoc deep research -> sub-agent/session;
   - scheduled monitor -> isolated cron/custom session;
   - shell-heavy work -> exec/process;
   - deterministic resumable workflow -> OpenProse or Lobster.
5. Ввести explicit interrupt/queue policy и progress-aware watchdog.
6. Заложить authoritative UAT contract, который проверяет именно Telegram transport/runtime long-running failures.

## Phase 1: Design Artifacts

- Спецификация cloneable user-facing vs worker-lane architecture.
- План с community patterns, выбранным blueprint и rejected alternatives.
- Набор implementation tasks для config/rules/skills/tests/docs carrier.
- Requirements checklist, фиксирующий полноту и отсутствие `NEEDS CLARIFICATION`.

## Phase 2: Execution Readiness

- `config/moltis.toml` станет carrier для lane separation, queue/watchdog/delivery guardrails.
- `skills/telegram-cloneable-agent/` и `skills/telegram-version-watch/` станут cloneable template surfaces.
- `docs/runbooks/` и `docs/rules/` зафиксируют operator contract и explicit completion rules.
- `tests/component/` и `tests/live_external/` станут authoritative proof surfaces для long-running Telegram path.
