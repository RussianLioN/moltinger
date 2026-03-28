# Moltis/OpenClaw: long-running Telegram reliability and cloneable agent patterns

**Дата исследования**: 2026-03-29  
**Статус**: complete  
**Назначение**: зафиксировать, как сегодня реально обходят long-running задачи в Moltis/OpenClaw, почему в Telegram появляются таймауты и `Activity log`, и какую архитектуру стоит брать за основу для будущей инструкции по быстрому клонированию агента без типовых болезней.

---

## Executive Summary

Короткий вывод по результатам official docs, upstream issues и community evidence:

1. **Держать длинное исследование как один синхронный Telegram-turn небезопасно.**
   Для OpenClaw это известный класс проблем: watchdog около `90s`, молчание во время tool-heavy turns, слабая прозрачность compaction и сбои доставки.
2. **`Activity log` в пользовательском Telegram-чате не выглядит штатным поведением.**
   Официальные docs описывают логи и диагностику как отдельную поверхность, а не как часть финального DM-ответа.
3. **Проблему нельзя свести к одному prompt fix.**
   Prompt/guardrail полезен, но transport/runtime path всё равно может протечь.
4. **Рабочий паттерн сегодня такой:**
   - короткий быстрый ack в пользовательском чате;
   - отдельный background/isolated path для тяжёлой работы;
   - явная доставка результата обратно;
   - отдельное хранение состояния вне chat history;
   - жёсткое разделение user-facing Telegram lane и operator/tool-heavy lane.
5. **Для навыка “следить за новой версией и уведомлять пользователя” правильный путь не sync-диалог, а scheduled/background monitor.**
   Версию хранить в состоянии, проверку делать по расписанию, пользователю отправлять короткое уведомление только при изменении.

---

## Главный ответ на исходный вопрос

Да, люди это обходят и частично лечат. Но не магией и не одним “правильным prompt”.

Практический ответ такой:

- долгую работу не держат в одном Telegram-turn;
- user-facing Telegram делают максимально тонким и безопасным;
- тяжёлую работу уводят в background/isolated execution;
- уведомление о завершении делают отдельным надёжным каналом доставки;
- состояние задачи и версии не держат в prompt/history, а кладут в state/store.

Именно эта схема нужна для “клонируемого” Moltis-агента.

---

## Что подтверждено официальными источниками

### 1. Telegram официально является polling-каналом

Официальная Moltis docs по channels описывает Telegram как `Polling` channel без требования публичного webhook URL:

- https://docs.moltis.org/channels.html

Практический вывод:

- Telegram хуже подходит для одного очень длинного синхронного turn, чем web/operator surface;
- “потом просто допишем reply, когда закончим” уже на уровне transport-модели не выглядит надёжной ставкой.

### 2. Состояние надо хранить не в prompt, а в state/store

Официальная Moltis docs по `session_state` описывает per-session key-value store, доступный через `session_state` tool (`get`, `set`, `list`):

- https://docs.moltis.org/session-state.html

Практический вывод:

- для краткоживущего пользовательского состояния `session_state` подходит;
- но для job-level или bot-wide monitor state нужно помнить, что это **per-session**, а не глобальное хранилище.

### 3. Telegram user-facing lane можно отделять от более тяжёлых режимов

Moltis docs по пресетам и tool registry описывают:

- per-preset `tools.allow` / `tools.deny`;
- возможность создавать разные агентные режимы под разные сценарии;
- фильтрацию доступных tool surfaces.

Источники:

- https://docs.moltis.org/agent-presets.html
- https://docs.moltis.org/tool-registry.html

Практический вывод:

- для Telegram можно и нужно делать отдельный “безопасный” lane;
- browser/search/MCP-heavy path не должен быть дефолтом для пользовательского DM.

### 4. У платформы есть явный outbound message path

Официальная OpenClaw docs по `message` описывает прямую отправку сообщений в Telegram и другие каналы:

- https://docs.openclaw.ai/cli/message

Практический вывод:

- completion/result notification можно проектировать как отдельную отправку, а не как “хвост” того же самого длинного turn;
- это особенно важно там, где обычный implicit reply path нестабилен.

### 5. Session isolation официально важна

OpenClaw docs по session management прямо рекомендуют более строгую DM-isolation (`per-channel-peer`, `per-account-channel-peer`) для multi-user inboxes:

- https://docs.openclaw.ai/concepts/session

Практический вывод:

- если Telegram DM остаётся в общем main-session, это риск перепутанного контекста, heartbeat pollution и лишнего роста истории;
- cloneable агент должен сразу стартовать с изоляцией DM-сессий, а не с общим “main”.

### 6. Isolated cron jobs создают новый session id на каждый run

Официальные docs по session management прямо говорят:

- isolated cron jobs always mint a fresh `sessionId` per run

Источник:

- https://docs.openclaw.ai/concepts/session

Практический вывод:

- `session_state` внутри isolated cron не годится как единственное долговременное хранилище “последней известной версии”;
- для постоянного monitor state нужен либо persistent session, либо внешний durable store.

### 7. Background delegation официально предусмотрена

OpenClaw docs по session tools описывают `sessions_spawn` как isolated delegated session:

- не блокирует родительский turn;
- создаёт отдельную child session;
- route results intended back to requester flow.

Источник:

- https://docs.openclaw.ai/concepts/session-tool

Практический вывод:

- если пользователю в Telegram нужно “уйти надолго изучать курс”, это надо моделировать как sub-agent/background session, а не как один синхронный ответ.

### 8. Heartbeat и cron - не одно и то же

Официальные docs по heartbeat отдельно объясняют heartbeat vs cron:

- heartbeat не является полноценной заменой планировщику;
- cron нужен для детерминированных scheduled jobs.

Источник:

- https://docs.openclaw.ai/gateway/heartbeat

Практический вывод:

- монитор версий, уведомления о новых релизах, периодический re-check и подобные вещи лучше проектировать как cron/scheduler workflow;
- heartbeat не стоит считать единственным надёжным delivery/monitoring механизмом.

### 9. Логи и диагностика живут отдельно от пользовательского ответа

Официальные logging docs говорят про `Logs` tab, follow-logs и diagnostic surfacing:

- https://docs.openclaw.ai/logging

Практический вывод:

- `Activity log` должен жить в log/diagnostics surface;
- его появление в обычном Telegram DM выглядит как transport/status leakage, а не как нормальный UX.

---

## Что подтверждено upstream issues

Ниже не “всё подряд из интернета”, а те issue, которые реально влияют на long-running Telegram path.

### A. Telegram reply может теряться после ~90 секунд

- `#56065` — Telegram lost messages with polling watchdog around `90_000 ms`
- https://github.com/openclaw/openclaw/issues/56065

Практический вывод:

- один тяжёлый синхронный turn длиной больше ~90s уже сам по себе опасен;
- запрос вида “сейчас полностью изучи всю документацию/курс и потом ответь” архитектурно упирается в этот риск.

### B. Tool-heavy turns + compaction дают минуты тишины

- `#56378` — Telegram: multi-minute silence during tool-heavy turns and compaction
- https://github.com/openclaw/openclaw/issues/56378

Практический вывод:

- даже если ответ потом приходит, пользователь в Telegram в процессе часто видит “мертвую тишину”;
- для UX это почти так же плохо, как реальный фейл.

### C. Telegram DM может загрязнять main/heartbeat session

- `#41165` — Telegram DMs can still land in `agent:main:main`
- https://github.com/openclaw/openclaw/issues/41165

Практический вывод:

- если long-running path, heartbeat и user DM живут рядом, история раздувается и путается;
- клон агента должен стартовать с изоляцией lane/session, иначе проблема воспроизводится снова.

### D. `system event --mode now` не является надёжной completion callback-механикой

- `#52305` — async completion reports can be lost because system event/wake is not reliably session-targeted
- https://github.com/openclaw/openclaw/issues/52305

Практический вывод:

- background job может завершиться, но пользователь в Telegram ничего не увидеть;
- нельзя строить completion delivery только на `system event`/`wake`.

### E. System events теряют routing/thread context

- `#10838` — system events lose thread context, causing leaks to the main channel
- https://github.com/openclaw/openclaw/issues/10838

Практический вывод:

- если результат long-running задачи не привязан явно к исходному routing context, он может прийти не туда;
- для cloneable архитектуры нужен явный completion delivery contract.

### F. Background notification через heartbeat ломается по умолчанию

- `#29215` — `heartbeat.target` defaults to `"none"`, notifications are silently dropped
- https://github.com/openclaw/openclaw/issues/29215

Практический вывод:

- background completion “само не заработает”;
- если использовать heartbeat path, нужен как минимум `heartbeat.target = "last"`;
- но even then лучше не полагаться только на heartbeat.

### G. Cron announce в Telegram может тихо не доставляться

- `#14743` — cron `delivery.mode = "announce"` silently fails for Telegram
- https://github.com/openclaw/openclaw/issues/14743

Практический вывод:

- “запустим cron и пусть announce сам доставит в Telegram” не является железобетонным вариантом;
- нужен fallback через явный direct send.

### H. В части кейсов в Telegram доходят только explicit messages

- `#48549` — regular replies not delivered, only explicit `message` tool content arrives
- https://github.com/openclaw/openclaw/issues/48549

Практический вывод:

- прямой `message send` сейчас выглядит одним из самых практичных workaround-ов для completion/report delivery.

### I. Даже `message` tool сейчас не даёт настоящего real-time progress

- `#26224` — message tool calls are batched until turn end
- https://github.com/openclaw/openclaw/issues/26224

Практический вывод:

- просто слать “progress updates” изнутри одного длинного turn недостаточно;
- для настоящего промежуточного UX надо либо разбивать работу на несколько turn-ов, либо использовать внешнее/background delivery.

### J. Для простых scheduled jobs upstream уже просит direct exec path

- `#18160` — direct exec mode for cron jobs
- https://github.com/openclaw/openclaw/issues/18160

Практический вывод:

- если задача в основном скриптовая и не требует LLM на каждом шаге, лучше вообще не прогонять её через agentTurn;
- “проверить версию, сравнить, уведомить” отлично ложится в этот стиль.

### K. Heartbeat сам по себе ненадёжен

- `#45772` — heartbeat timer stops; workaround is cron
- https://github.com/openclaw/openclaw/issues/45772

Практический вывод:

- heartbeat полезен как вспомогательный механизм, но не как единственный scheduler.

### L. Для runaway long-turn нужны queue/interrupt guardrails

- `#56044` — workaround: `messages.queue.mode = "steer"`
- https://github.com/openclaw/openclaw/issues/56044

Практический вывод:

- если long-running path всё-таки повисает, user должен иметь способ реально его прервать;
- `steer` — полезный практический guardrail.

### M. Telegram polling channel может падать без auto-reconnect

- `#4617` — Telegram channel exits on getUpdates timeout without auto-reconnect
- https://github.com/openclaw/openclaw/issues/4617

Практический вывод:

- production-ready cloneable агенту нужен внешний health-check/watchdog на канал, а не вера в вечную стабильность polling.

---

## Что подтверждено community

### AIYA #60: timeout должен вести к screen-state diagnosis, а не к тупому retry

Публичная тема:

- https://aiya.de5.net/t/topic/60

Сигнал:

- при `chrome mcp`/MCP timeout agent может зациклиться на “нет доступа -> подай ещё раз” и не замечать парольный prompt;
- автор прямо предлагает: при timeout обязательно смотреть screenshot/page state.

Практический вывод:

- для browser-heavy path retry без state diagnosis опасен;
- user-facing Telegram lane не должен бесшумно запускать такой path по умолчанию.

### AIYA #61: подтверждение, что агент пере-фокусирован на MCP/skill вместо наблюдения за экраном

- https://aiya.de5.net/t/topic/61

Сигнал:

- community ожидает более “человеческое” поведение: сначала посмотреть, что реально происходит на экране, потом повторять действие.

Практический вывод:

- для cloneable агентной схемы полезно заранее проектировать failure diagnosis, а не только retry loop.

### AIYA #62: рестарт/исчезновение без предупреждения воспринимается как “бот умер”

- https://aiya.de5.net/t/topic/62

Сигнал:

- люди отдельно жалуются, что агент “самоубивается”/перезапускается без предварительного сообщения;
- community сама добавляет уведомления о restart/network events.

Практический вывод:

- lifecycle transparency для production-агента не optional;
- long-running workflows нуждаются в явных notify-before/notify-after паттернах.

### AIYA #63: silent overflow реально возникает от раздувшегося `toolResult`

- https://aiya.de5.net/t/topic/63

Сигнал:

- хорошо описан кейс `usage.input` на сотни тысяч токенов;
- `output=0`, `content=[]`;
- проблемы не в одном канале, а в раздувшейся истории;
- временные stopgap-меры: новая сессия, меньше raw toolResult, warning по context pressure.

Практический вывод:

- user-facing Telegram path надо проектировать так, чтобы тяжёлые raw results не накапливались в основной переписке;
- deep research job должен писать краткий итог и ссылки/артефакты, а не тащить всё тело исследования в горячий контекст.

### LinuxDo и umbrella issue #14818

Upstream umbrella issue `#14818` прямо ссылается на LinuxDo и AIYA как на реальные field reports:

- https://github.com/openclaw/openclaw/issues/14818
- LinuxDo thread mentioned there: https://linux.do/t/topic/1610098

Практический вывод:

- это не частная проблема одного deployment;
- upstream уже сам признаёт, что reliability/visibility/context-overflow pain points повторяются в реальных многоканальных установках.

### Что удалось узнать про `@clawledgechat`

Публичная web-preview страница группы доступна:

- https://t.me/clawledgechat

Но публичного DOM-доступа к самим сообщениям получить не удалось: preview показывает шапку группы, но не даёт содержательного message feed без дополнительного доступа. Поэтому:

- `@clawledgechat` зафиксирован как потенциально полезный community source;
- в этом исследовании он **не используется как доказательный источник**, потому что публично не дал извлекаемого контента.

---

## Что уже можно считать решением для нашего случая

### Не решение

Следующая схема **не годится**:

1. Пользователь пишет в Telegram: “полностью изучи курс/доки”.
2. Агент остаётся в одном turn.
3. Внутри этого turn делает длинный browser/search/MCP loop.
4. Потом пытается тем же reply path вернуть итог.

Почему не годится:

- риск watchdog around `90s`;
- риск `Activity log`/tool trace leakage;
- риск тишины на минуты;
- риск compaction/context blowup;
- риск потери completion reply.

### Рабочая схема

Для user-facing Telegram нужен **двухконтурный** дизайн.

#### Контур 1: User-facing lane

Свойства:

- отвечает быстро;
- пишет короткий ack;
- не запускает по умолчанию длинный browser/MCP chain;
- может быть ограничен по tools/preset;
- отдаёт пользователю статус и финальное уведомление.

#### Контур 2: Worker lane

Свойства:

- isolated/background session;
- scheduler/sub-agent/exec-driven workflow;
- может работать дольше;
- пишет артефакты в file/store/state;
- не обязан стримить внутренний прогресс в Telegram.

---

## Рекомендованный cloneable blueprint

Ниже схема, которую стоит положить в основу будущей инструкции по клонированию агента.

### 1. Разделить роли

Нужны как минимум два режима:

- `telegram-user` — безопасный пользовательский агент;
- `worker` или `monitor` — background/isolated исполнитель.

`telegram-user`:

- минимальный набор tools;
- никаких скрытых browser-heavy chains как default behavior;
- финальный ответ короткий и human-readable.

`worker`:

- читает/анализирует курс, релизы, docs;
- пишет результат в артефакт;
- по завершении инициирует уведомление.

### 2. Изолировать DM session model

Стартовые требования:

- per-user DM isolation;
- отсутствие смешивания Telegram DM с `main`/heartbeat session;
- явный reset/rotation strategy.

Основание:

- https://docs.openclaw.ai/concepts/session
- https://github.com/openclaw/openclaw/issues/41165

### 3. Хранить состояние отдельно от истории чата

Разделение state должно быть таким:

- **per-user, conversational state**: `session_state`
- **bot-wide/shared monitor state**: внешний durable store

Пример разделения для version-monitor:

- `session_state`: какой режим уведомлений включён у конкретного пользователя;
- shared store: какая версия уже была зафиксирована последней проверкой;
- shared store: какой release уже был отправлен в конкретный канал/пользователю.

Почему это важно:

- isolated cron runs не переиспользуют один и тот же session id;
- history/prompt не является надёжным state backend.

### 4. Делать long-running job через background path

Подходы по убыванию практичности:

1. `sessions_spawn` / sub-agent run для LLM-heavy исследования
2. cron/scheduler для периодических monitor задач
3. direct exec style для скриптовых задач без необходимости постоянной LLM-интерпретации

Основание:

- https://docs.openclaw.ai/concepts/session-tool
- https://docs.openclaw.ai/gateway/heartbeat
- https://github.com/openclaw/openclaw/issues/18160

### 5. Completion delivery делать явно

Самый практичный текущий паттерн:

- не полагаться только на `system event --mode now`;
- не полагаться только на heartbeat;
- предусматривать direct `message` send / explicit channel send.

Основание:

- https://github.com/openclaw/openclaw/issues/52305
- https://github.com/openclaw/openclaw/issues/10838
- https://github.com/openclaw/openclaw/issues/29215
- https://github.com/openclaw/openclaw/issues/48549

### 6. Ограничивать накопление tool results

Нужно заранее заложить:

- summary instead of raw dump;
- links/artifacts instead of full payload in chat;
- session rotation on high context pressure;
- user-visible fallback when context is too heavy.

Основание:

- AIYA #63
- upstream umbrella `#14818`
- silent-overflow family referenced there

### 7. Добавить operator guardrails

Минимальный набор:

- `messages.queue.mode = "steer"` или аналогичный interrupt-friendly режим;
- health-check/watchdog на Telegram polling channel;
- restart/disconnect notifications;
- authoritative UAT, который считает `Activity log`, tool names и timeout card пользовательским фейлом.

Основание:

- `#56044`
- `#4617`
- уже существующие project-side RCA/UAT contracts в этом репозитории

---

## Практический пример: навык “следить за новой версией и уведомлять”

Это пример задачи, с которой пользователь начинал разговор. Ниже не финальная инструкция, а правильная архитектура.

### Неправильный вариант

“Попросить пользователя в Telegram написать: следи за релизами X, а потом при каждом обновлении бот в этом же chat-turn пусть сам долго ищет, сравнивает и отвечает”.

Проблемы:

- слишком длинный synchronous path;
- лишний web/tool pressure;
- хранение версии быстро деградирует в chat history hack.

### Правильный вариант

#### Шаг 1. Настройка monitor-задачи

Создать отдельный monitor/worker workflow, который по расписанию:

1. читает источник версии;
2. сравнивает с сохранённым значением;
3. если версия не изменилась - молчит;
4. если изменилась - сохраняет новую версию и отправляет краткое уведомление.

#### Шаг 2. Хранение состояния

Минимально нужны три поля:

- `latest_seen_version`
- `last_notified_version`
- `last_checked_at`

Если монитор общий на весь бот:

- хранить это во внешнем durable store.

Если монитор персональный и привязан к одной устойчивой user-session:

- часть preferences можно держать в `session_state`.

#### Шаг 3. Уведомление

Формат уведомления должен быть коротким:

- “Найдена новая версия `v1.2.3`”
- “Было: `v1.2.2`”
- “Кратко что изменилось: ...”
- “Если хочешь, могу отдельно собрать подробный diff/release notes”

То есть heavy research не делается автоматически в том же ответе, если в этом нет необходимости.

#### Шаг 4. Подробный анализ - отдельной задачей

Если пользователь после уведомления хочет:

- изучить changelog;
- прочитать release notes;
- собрать impact summary;

это запускается как отдельный background task или отдельный более тяжёлый операторский workflow.

---

## Минимальный checklist для будущей инструкции

Эта инструкция ещё не написана, но в неё должны войти минимум следующие пункты:

1. Создать отдельный user-facing Telegram lane.
2. Создать отдельный worker/monitor lane.
3. Включить DM/session isolation.
4. Запретить или резко ограничить browser/MCP-heavy default path в Telegram.
5. Определить, где хранится durable version/job state.
6. Развести ack, actual work и completion delivery на разные этапы.
7. Не строить completion notification только на `system event`.
8. Предусмотреть direct send fallback.
9. Ограничить накопление raw tool results в горячем контексте.
10. Настроить watchdog/health-check для Telegram channel.
11. Проверять user-facing UAT теми запросами, которые реально занимают больше 90 секунд.
12. Считать `Activity log`, tool traces и timeout cards пользовательским дефектом, а не “нормальным degraded output”.

---

## Что пока не доказано до конца

Ниже важно не переобещать.

1. **Я не нашёл официальный текст upstream вида**
   “Telegram `Activity log` leak - известный баг, вот точный fixed version”.
2. **Я не нашёл доказательства**, что один-единственный config flag полностью решает все long-running Telegram проблемы.
3. **Я не смог использовать `@clawledgechat` как доказательную базу**, потому что публичный preview не дал содержимого сообщений.

Но уже достаточно доказано другое:

- текущий symptom cluster реальный;
- он повторяется у других пользователей;
- обходится он именно архитектурным разделением long-running worker path и пользовательского Telegram delivery.

---

## Рекомендуемый следующий шаг для репозитория

После этого исследования следующий практический шаг выглядит так:

1. На уровне `config/moltis.toml` и preset/policy явно развести `telegram-user` и `worker` режимы.
2. Выбрать durable store для version/job state.
3. Сделать proof-of-concept monitor-навык:
   - check source;
   - compare version;
   - persist state;
   - send concise notify.
4. Добавить authoritative UAT на long-running/background delivery path, а не только на обычный DM reply.

---

## Основные источники

### Official docs

- https://docs.moltis.org/channels.html
- https://docs.moltis.org/session-state.html
- https://docs.moltis.org/agent-presets.html
- https://docs.moltis.org/tool-registry.html
- https://docs.openclaw.ai/concepts/session
- https://docs.openclaw.ai/concepts/session-tool
- https://docs.openclaw.ai/cli/message
- https://docs.openclaw.ai/gateway/heartbeat
- https://docs.openclaw.ai/logging

### Upstream issues

- https://github.com/openclaw/openclaw/issues/56065
- https://github.com/openclaw/openclaw/issues/56378
- https://github.com/openclaw/openclaw/issues/41165
- https://github.com/openclaw/openclaw/issues/52305
- https://github.com/openclaw/openclaw/issues/10838
- https://github.com/openclaw/openclaw/issues/29215
- https://github.com/openclaw/openclaw/issues/14743
- https://github.com/openclaw/openclaw/issues/48549
- https://github.com/openclaw/openclaw/issues/26224
- https://github.com/openclaw/openclaw/issues/18160
- https://github.com/openclaw/openclaw/issues/45772
- https://github.com/openclaw/openclaw/issues/56044
- https://github.com/openclaw/openclaw/issues/4617
- https://github.com/openclaw/openclaw/issues/14818

### Community

- https://aiya.de5.net/t/topic/60
- https://aiya.de5.net/t/topic/61
- https://aiya.de5.net/t/topic/62
- https://aiya.de5.net/t/topic/63
- https://linux.do/t/topic/1610098
- https://t.me/clawledgechat
