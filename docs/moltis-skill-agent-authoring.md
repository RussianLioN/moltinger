# Moltis Skill/Agent Authoring Guide

Last reviewed: 2026-03-14

## Зачем этот документ

Это канонический проектный гайд о том, как правильно добавлять новые навыки, агенты и смежные возможности в Moltis/Moltinger.

Он нужен, чтобы не повторять одну и ту же архитектурную ошибку:

- не пытаться перенести чужой workflow "как есть";
- не путать всегда-активный проектный контекст с on-demand skill;
- не считать capability внедрённой, если она лежит только в repo, но не видна live runtime.

Если задача звучит как:

- "добавь новый skill в Moltis"
- "перенеси workflow из Claude Code / Codex / OpenCode"
- "сделай нового Moltis-агента"
- "подключи периодический skill через scheduler"

начинать нужно с этого документа.

## Короткий ответ

Оптимальный путь такой:

1. Сначала зафиксировать долгоживущие правила и знания в проектной документации.
2. Держать `AGENTS.md` и системный prompt короткими: они должны маршрутизировать к правильным docs, а не содержать весь навык целиком.
3. Делать `skill` для повторяемого on-demand workflow.
4. Делать `agent preset` только если нужен отдельный режим работы: другой набор инструментов, модель, memory/session policy или явная специализация.
5. Делать `MCP`/hooks/tools для внешних действий и enforcement, а не кодировать API-интеграцию только текстом в prompt.
6. Делать `session_state` для краткоживущего рабочего состояния, а `memory/knowledge` — для долговременных знаний.
7. Для периодики использовать нативный Moltis scheduler/heartbeat path, а не внешний shell-cron, если можно остаться внутри Moltis runtime.
8. Считать skill внедрённым только после проверки runtime visibility: skill/agent должен реально быть видим контейнеру и его `search_paths`, а не только лежать в git.

## Что использовать и когда

| Задача | Правильный механизм | Почему |
|---|---|---|
| Всегда-активный проектный контекст | `AGENTS.md`, workspace files, `identity.soul` | Это карта и общие правила, а не целый workflow |
| Повторяемый on-demand сценарий | `skills/<name>/SKILL.md` | Переиспользуемый workflow с явным trigger |
| Отдельная роль с другими правами или моделью | `agent presets` / markdown agents | Нужен другой режим доступа и поведения |
| Временное или сессионное состояние | `session_state` | Не нужно запихивать состояние в prompt |
| Долговременные знания и ссылки | `memory`, `knowledge/`, RAG watch dirs | Knowledge нужно переиспользовать между сессиями |
| Периодический запуск | built-in scheduling / `HEARTBEAT.md` / cron tool | Нативная периодика ближе к runtime и audit trail |
| Внешние API, базы и системные интеграции | MCP servers / built-in tools / hooks | Это tool boundary, а не текстовый паттерн |
| Жёсткие guardrails и фильтрация | hooks | Enforcement должен быть вне обычного skill narrative |

## Рекомендуемая архитектура для нового Moltis capability

### 1. Источник истины для знаний держать в docs

Для сложного capability сначала нужен нормальный документ:

- что делает capability;
- когда его вызывать;
- какой у него boundary;
- что является canonical entrypoint;
- какие ограничения и rollout criteria.

Причина простая: длинные инструкции и миграционные детали живут лучше в обычной документации, чем в одном разрастающемся `AGENTS.md` или в огромном `SKILL.md`.

### 2. `AGENTS.md` должен быть маршрутизатором, а не свалкой

Хороший `AGENTS.md`:

- короткий;
- стабильно перечитывается;
- указывает на нужные durable docs;
- задаёт порядок чтения и обязательные правила.

Плохой `AGENTS.md`:

- содержит весь доменный handbook целиком;
- дублирует проектные runbook-и;
- превращается в гигантский prompt, который трудно поддерживать и легко потерять при compaction.

### 3. Skill должен быть тонким слоем поверх канонического runtime

Правильный Moltis skill:

- понимает триггеры;
- знает canonical runtime entrypoint;
- описывает порядок действий и ограничения;
- ссылается на docs за подробностями.

Неправильно:

- прятать всю логику в skill prompt;
- плодить ad-hoc shell команды вместо одного канонического runtime;
- дублировать длинные инструкции и шаблоны сразу в нескольких skills.

### 4. Агент нужен только когда skill уже недостаточен

Создавай отдельный `agent preset`, если нужен хотя бы один из признаков:

- отдельный набор инструментов;
- read-only vs write-enabled режим;
- отдельная модель или temperature policy;
- отдельная memory/session policy;
- специализированная роль, которую primary agent должен вызывать как subagent.

Если всего этого нет, скорее всего нужен просто `skill`, а не новый агент.

### 5. Runtime visibility проверять как acceptance criterion

Для Moltinger это особенно важно.

Если новый skill:

- лежит в `skills/` репозитория,
- но контейнер его не видит,
- или `search_paths` не совпадают с mount points,

то capability ещё не внедрён.

Минимальная проверка:

1. skill/agent лежит в правильном runtime-visible path;
2. этот path есть в `search_paths` или в documented import path;
3. live runtime может реально прочитать skill и вызвать canonical entrypoint;
4. это подтверждено не только hermetic test, но и runtime smoke/UAT.

## Рекомендуемый workflow добавления нового skill/agent

### Шаг 1. Определи тип capability

Сначала ответь на вопрос:

- это always-on контекст?
- это on-demand workflow?
- это периодическая задача?
- это отдельная роль с другим доступом?

Только после этого выбирай механизм.

### Шаг 2. Сначала напиши краткий durable doc

Минимум зафиксируй:

- цель capability;
- trigger-фразы;
- canonical runtime;
- state model;
- deployment boundary;
- rollback path.

### Шаг 3. Выбери минимально достаточный примитив

Предпочтительный порядок:

1. docs + `AGENTS.md` routing
2. skill
3. agent preset
4. hooks/MCP/scheduler, если это реально нужно

Не начинай с нового агента только потому, что capability "звучит солидно".

### Шаг 4. Подвяжи runtime и state

Если capability не чисто разговорный, заранее реши:

- где state хранится;
- как выглядит canonical CLI/runtime entrypoint;
- кто владеет delivery;
- какой audit trail нужен;
- какой mode будет для scheduler и для on-demand path.

### Шаг 5. Проверь rollout boundary

Отдельно проверь:

- repo path;
- runtime-visible path;
- container mounts;
- `search_paths`;
- права на execution;
- наличие нужных инструментов внутри live runtime.

### Шаг 6. Только потом делай UX и automation

Не начинай с красивых Telegram-кнопок или чатового UX, пока:

- не определён canonical runtime;
- не доказана runtime visibility;
- не подтверждено, что capability работает вручную;
- не закрыт degraded mode.

## Миграция из Claude Code, Codex и OpenCode

### Из Claude Code

Что полезно переносить:

- идею компактного `SKILL.md`;
- явные trigger phrases;
- чёткое разделение skill vs agent.

Что нельзя переносить вслепую:

- надежду, что discovery и natural-language invocation всегда сами сработают;
- marketplace semantics как замену проектной документации;
- слишком длинный skill prompt вместо канонического runtime.

Практический вывод:

- берём формат и дисциплину skill authoring;
- но в Moltis добавляем явный routing через docs, runtime entrypoint и rollout validation.

### Из Codex

Что полезно переносить:

- короткий `AGENTS.md` как карту проекта;
- явные project docs рядом с кодом;
- principle: durable docs важнее гигантского системного prompt.

Что нельзя переносить как есть:

- представление, что `AGENTS.md` сам по себе уже является skill system;
- ad-hoc shell probing вместо отдельного Moltis-native runtime;
- хранение всей доменной логики только в одном агентном prompt.

Практический вывод:

- из Codex в Moltis обычно переносится не "skill", а комбинация:
  - `docs`
  - `AGENTS.md` routing
  - `skill`
  - иногда `agent preset`

### Из OpenCode

Что полезно переносить:

- markdown-based definitions для agents/commands;
- явное разделение primary agents, subagents и modes;
- удобную мысль, что другой режим = другой policy, а не просто другой prompt.

Что нельзя переносить вслепую:

- permissions/modes без перепроверки под Moltis tool model;
- agent descriptions без проверки фактических trigger и tool boundaries;
- file layout как будто он автоматически равен Moltis layout.

Практический вывод:

- OpenCode — хороший донор структуры agent/mode thinking;
- но в Moltis нужно явно сопоставлять это с `agent presets`, `session_state`, hooks и runtime-visible skill paths.

## Практические рекомендации для Moltinger

Для этого репозитория оптимальный паттерн такой:

1. Полное объяснение capability держать в `docs/`.
2. В `AGENTS.md` и локальных `AGENTS.md` держать короткие указатели на канонический doc.
3. В `skills/<name>/SKILL.md` держать только:
   - trigger;
   - canonical runtime;
   - запреты и boundary;
   - краткий порядок действий.
4. Если capability требует другого tool/model/session policy, добавлять agent preset отдельно от skill.
5. Для project-specific знания использовать data/profile/docs, а не зашивать всё в prompt.
6. Сразу планировать:
   - manual path;
   - scheduler path;
   - degraded mode;
   - audit trail;
   - live runtime visibility.

## Антипаттерны

- Один огромный `SKILL.md`, который пытается быть и handbook, и runtime, и knowledge base.
- Переносить Claude/OpenCode/Codex capability "один в один" без сопоставления primitive-to-primitive.
- Считать feature внедрённой, если она существует только в git, но не видна live runtime.
- Использовать внешний cron, если capability естественнее живёт внутри Moltis scheduler/tooling.
- Хранить state в prompt или в reply history вместо `session_state`.
- Пытаться решить enforcement через prose там, где нужен hook или tool policy.
- Подключать чужие third-party skills без trust review, provenance и drift policy.

## Минимальный checklist перед внедрением

### Новый skill

- [ ] Есть краткий durable doc
- [ ] Определён canonical runtime
- [ ] `SKILL.md` тонкий и не дублирует handbook
- [ ] Trigger phrases и anti-patterns описаны явно
- [ ] Skill path виден runtime

### Новый agent preset

- [ ] Есть причина, почему skill недостаточен
- [ ] Зафиксированы tools/model/session policies
- [ ] Понятно, это primary agent или subagent
- [ ] Есть manual invocation path
- [ ] Есть rollout smoke/UAT

### Периодический capability

- [ ] Решено, почему нужен scheduler/heartbeat
- [ ] State и fingerprint определены
- [ ] Duplicate suppression определён
- [ ] Есть degraded mode
- [ ] Delivery path и audit trail проверены

## Что говорят официальные источники и community

### Официальные опоры

- Moltis уже поддерживает:
  - `project context` и workspace files;
  - `skill self-extension`;
  - `session_state`;
  - built-in scheduling;
  - `agent presets` и markdown agent definitions;
  - trust model для third-party skills.
- OpenCode официально разделяет primary agents, subagents, commands и modes, что полезно как ориентир при проектировании отдельных ролей.
- Codex официально опирается на `AGENTS.md` и project docs как на основной механизм направления агента.

### Практические сигналы из issues и community

- У Claude Code auto-discovery и natural-language matching skills могут вести себя не так надёжно, как кажется по happy path. Значит важные capability лучше маршрутизировать явно, а не надеяться только на описание skill.
- У Codex слишком длинные и перегруженные агентные инструкции дают худший operational result, чем короткий `AGENTS.md` с хорошими ссылками на docs.
- У OpenCode agent/mode model полезна для разделения прав и ролей, но переносить её надо вместе с явной проверкой permissions/tool policy.

## Рекомендуемый итоговый шаблон решения

Для большинства новых Moltis capability оптимальная схема такая:

1. **Docs first**
   - один канонический гайд/спека в `docs/`
2. **Short routing**
   - короткий `AGENTS.md` и локальные указатели
3. **Thin skill**
   - on-demand workflow в `SKILL.md`
4. **Optional preset**
   - отдельный агент только если нужны иные права/модель/роль
5. **Runtime proof**
   - проверка видимости path, state, scheduler, audit, live UAT

Простыми словами:

не "перенеси skill",
а "перенеси capability в правильные нативные примитивы Moltis".

## Внешние ссылки

### Moltis / OpenClaw official

- [Moltis: system prompt / project context](https://docs.moltis.org/system-prompt.html#project-context)
- [Moltis: skills in system prompt](https://docs.moltis.org/system-prompt.html#skills)
- [Moltis: creating a skill](https://docs.moltis.org/skill-tools.html#creating-a-skill)
- [Moltis: updating a skill](https://docs.moltis.org/skill-tools.html#updating-a-skill)
- [Moltis: session state](https://docs.moltis.org/session-state.html#session-state)
- [Moltis: scheduling cron jobs](https://docs.moltis.org/scheduling.html#scheduling-cron-jobs)
- [Moltis: agent presets](https://docs.moltis.org/agent-presets.html#agent-presets)
- [Moltis: markdown agent definitions](https://docs.moltis.org/agent-presets.html#markdown-agent-definitions)
- [Moltis: workspace files explained](https://docs.moltis.org/openclaw-import.html#workspace-files-explained)
- [Moltis: multi-agent support](https://docs.moltis.org/openclaw-import.html#multi-agent-support)
- [Moltis: third-party skills security](https://docs.moltis.org/skills-security.html#third-party-skills-security)

### Claude Code / Anthropic

- [anthropics/claude-code issue #4250](https://github.com/anthropics/claude-code/issues/4250)
- [anthropics/claude-code issue #3887](https://github.com/anthropics/claude-code/issues/3887)
- [Agent Skills specification](https://agentskills.io/)

### Codex / OpenAI

- [Codex README: Memory & project docs](https://github.com/openai/codex#memory--project-docs)
- [OpenAI: Unrolling the Codex agent loop](https://developers.openai.com/blog/unrolling-the-codex-agent-loop)
- [OpenAI: AGENTS.md](https://developers.openai.com/blog/agents-md)
- [OpenAI: Using skills to accelerate OSS maintenance](https://developers.openai.com/blog/using-skills-to-accelerate-oss-maintenance)
- [OpenAI: Shell + Skills + Compaction](https://developers.openai.com/blog/skills-shell-tips)
- [openai/codex issue #2488](https://github.com/openai/codex/issues/2488)
- [openai/codex issue #1115](https://github.com/openai/codex/issues/1115)

### OpenCode

- [OpenCode: Agents](https://opencode.ai/docs/agents/)
- [OpenCode: Commands](https://opencode.ai/docs/commands/)
- [OpenCode: Modes](https://opencode.ai/docs/modes/)

### Community signals

- [Vercel: AGENTS.md outperforms skills in agent evals](https://vercel.com/blog/agents-md-more-important-than-ever)
- [Hacker News discussion: AGENTS.md and open instruction files](https://news.ycombinator.com/item?id=46527876)
