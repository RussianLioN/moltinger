# worktree-skill

`worktree-skill` - это переносимый навык для worktree-first workflow.

Его задача: научить Claude Code, Codex CLI и OpenCode одинаково помогать пользователю работать через отдельные git worktree, а не вперемешку в одном каталоге. Навык помогает:

- создавать dedicated worktree под задачу или feature;
- держать branch/worktree discipline;
- делать handoff между сессиями и агентами;
- понимать git topology проекта;
- не ломать Speckit-артефакты `spec.md`, `plan.md`, `tasks.md`;
- одинаково работать в разных агентных IDE, даже если способ регистрации отличается.

Главная идея простая: пользователь пишет обычный текстовый запрос вроде "создай отдельный worktree под feature" или "подготовь handoff для этой ветки", а установленный навык подсказывает агенту правильный flow и ожидаемое поведение.

## Что такое навык Worktree

Навык `worktree` - это набор переносимых артефактов:

- инструкций для агента;
- командных prompt-ов;
- шаблонов handoff;
- topology/worktree helper scripts;
- install/register hooks;
- совместимых bridge-артефактов для Speckit.

Это не runtime вашего продукта и не deploy toolkit. Навык не должен зависеть от:

- секретов;
- production hostnames;
- runtime-конфигурации конкретного проекта;
- исторических веток исходного репозитория;
- Moltinger-специфичных operational правил, которые не являются переносимой частью worktree workflow.

## Для кого этот репозиторий

Этот репозиторий нужен разработчику, который хочет:

1. скачать `worktree-skill`;
2. перенести его в свой проект почти как есть;
3. при необходимости запустить маленький install/register шаг;
4. дальше использовать один и тот же worktree flow в Claude Code, Codex CLI и OpenCode;
5. сохранить совместимость со Speckit и artifact-first workflow.

## Что пользователь получает после установки

После установки пользователь получает не "ещё одну папку с markdown", а конкретное поведение помощника:

- агент перестаёт предлагать хаотичную работу в корневом каталоге;
- агент понимает, когда нужен отдельный worktree;
- агент может вести feature через branch + dedicated worktree;
- агент умеет проверять topology и состояние worktree;
- агент умеет готовить handoff;
- агент умеет сосуществовать со Speckit-пакетом feature;
- различия между Claude Code, Codex CLI и OpenCode остаются только в install/register surface, а не в логике.

## В каких IDE это работает

Поддерживаются:

- Claude Code
- Codex CLI
- OpenCode

Опционально:

- Speckit bridge

Важно: core behavior должен быть одинаковым везде. Пользовательский сценарий не должен зависеть от IDE. Разница только в том, как навык устанавливается, регистрируется и обнаруживается конкретным инструментом.

## Как установить

### 1. Скачать репозиторий

```bash
git clone https://github.com/RussianLioN/worktree-skill.git
cd worktree-skill
```

### 2. Установить навык в свой проект

Быстрый путь:

```bash
./install/bootstrap.sh --target /path/to/your-project --adapter claude-code
```

Если нужен Speckit bridge:

```bash
./install/bootstrap.sh --target /path/to/your-project --adapter claude-code --with-speckit
```

Для Codex CLI:

```bash
./install/bootstrap.sh --target /path/to/your-project --adapter codex-cli
./install/register.sh --target /path/to/your-project --adapter codex-cli
```

Для OpenCode:

```bash
./install/bootstrap.sh --target /path/to/your-project --adapter opencode
```

Потом см.:

- [adapters/opencode/README.md](./adapters/opencode/README.md)
- [adapters/opencode/register-example.md](./adapters/opencode/register-example.md)

### 3. Проверить установку

```bash
./install/verify.sh --target /path/to/your-project --adapter claude-code
```

Проверка должна подтвердить, что:

- core scripts установлены;
- выбранный adapter установлен;
- bridge для Speckit виден, если вы его включали;
- структура установки предсказуемая и пригодна к использованию.

## Как пользоваться навыком простыми текстовыми запросами

Это самый важный раздел.

После установки пользователь не обязан помнить внутреннюю файловую структуру навыка. Ему достаточно писать обычные текстовые запросы на естественном языке. Навык нужен именно для того, чтобы агент распознал намерение пользователя и провёл его по корректному worktree flow.

Пользователь может писать такие запросы:

- "Создай dedicated worktree под новую feature."
- "Проверь, правильно ли у нас устроены worktree и ветки."
- "Подготовь handoff для этой feature."
- "Скажи, можно ли продолжать работу в этом worktree."
- "Помоги завести worktree под spec-driven задачу."

То есть пользователь работает не через знание внутренностей навыка, а через понятные продуктовые формулировки.

## Что должен делать агент с установленным навыком

Когда пользователь просит про worktree workflow, агент должен:

1. понять, нужен ли dedicated worktree;
2. определить canonical root и целевую ветку;
3. не смешивать unrelated work в одном каталоге;
4. предложить или создать отдельный worktree;
5. учитывать topology проекта;
6. уважать branch-spec alignment, если проект использует Speckit;
7. уметь подготовить handoff между сессиями;
8. не требовать project-specific ручной настройки там, где достаточно portable core behavior.

## Как выглядит типовой сценарий использования

Типовой сценарий:

1. Пользователь говорит агенту, что начинает новую feature.
2. Агент предлагает создать dedicated worktree.
3. Пользователь подтверждает или явно просит создать worktree.
4. Агент создаёт или описывает корректный worktree flow.
5. Дальше работа идёт внутри отдельного worktree.
6. Если задача spec-driven, рядом живут `spec.md`, `plan.md`, `tasks.md`.
7. В конце агент подготавливает handoff или summary для следующей сессии.

## 12 примеров пользовательских запросов

Ниже не синтетические "slash commands", а обычные фразы, которые пользователь может писать в любой поддерживаемой IDE.

### 1. Создание нового worktree под feature

```text
Нам нужна новая feature. Создай dedicated worktree и новую ветку, чтобы не работать в корне репозитория.
```

### 2. Создание worktree под конкретную ветку

```text
Подготовь отдельный worktree для ветки feature/payment-retry и скажи, где дальше продолжать работу.
```

### 3. Проверка, можно ли продолжать работу в текущем каталоге

```text
Проверь, можно ли безопасно продолжать работу в текущем worktree, или лучше сначала вынести задачу в отдельный.
```

### 4. Проверка topology проекта

```text
Покажи текущую git topology: какие worktree есть, какие ветки за ними закреплены и где есть риск путаницы.
```

### 5. Handoff для другой сессии

```text
Подготовь handoff для следующей сессии по этой feature: что уже сделано, в каком worktree работать и что делать дальше.
```

### 6. Возврат к незавершённой работе

```text
Помоги безопасно продолжить незавершённую feature и сначала проверь, в правильном ли worktree я нахожусь.
```

### 7. Spec-driven workflow со Speckit

```text
Я хочу делать эту feature через Speckit. Помоги организовать spec-first workflow и отдельный worktree под эту работу.
```

### 8. Проверка branch/spec alignment

```text
Проверь, соответствует ли текущая ветка Speckit feature intent и не разъехались ли spec artifacts с рабочим worktree.
```

### 9. Подготовка worktree для передачи другому агенту

```text
Подготовь этот worktree для передачи другому агенту: проверь контекст, опиши branch contract и сделай handoff.
```

### 10. Аккуратное начало работы в существующем проекте

```text
В этом проекте уже есть свои ветки и рабочие каталоги. Помоги внедрить worktree flow без опасных изменений и без ломки текущей структуры.
```

### 11. Использование навыка без знания внутренней команды

```text
Я не помню, как тут устроен worktree flow. Просто проведи меня по правильному сценарию для новой задачи.
```

### 12. Диагностика проблемного worktree состояния

```text
У меня ощущение, что ветка и worktree разъехались. Проверь состояние и предложи безопасный следующий шаг.
```

## Ещё примеры коротких запросов

- "Создай worktree под задачу и назови следующий каталог для работы."
- "Проверь, не работаю ли я не в том worktree."
- "Собери handoff по текущей ветке."
- "Покажи, какой worktree должен быть основным для этой feature."
- "Подготовь worktree под Codex/Claude/OpenCode flow без project-specific ручной настройки."
- "Скажи, что нужно сделать перед передачей этой feature в следующую сессию."

## Как это соотносится с конкретными IDE

### Claude Code

После установки пользователь может просто формулировать запросы обычным языком:

- "Создай dedicated worktree под новую фичу."
- "Проверь topology."
- "Подготовь handoff."

Если в проекте есть зарегистрированная команда или skill-обёртка, агент может использовать её как внутренний механизм, но для пользователя важнее не синтаксис, а поведение.

### Codex CLI

Та же логика: пользователь может писать обычные текстовые запросы про worktree workflow. Если adapter установил bridge-команды, это помогает discovery, но core сценарий должен оставаться тем же.

### OpenCode

Даже если registration surface отличается и где-то нужна ручная настройка, пользовательский flow должен оставаться таким же:

- попросить создать или проверить worktree;
- получить корректный сценарий;
- продолжить работу в выделенном каталоге;
- подготовить handoff при завершении.

## Совместимость со Speckit

Если проект использует Speckit, навык должен работать рядом с:

- `spec.md`
- `plan.md`
- `tasks.md`

Навык не заменяет:

- `/speckit.spec`
- `/speckit.plan`
- `/speckit.tasks`

Он дополняет их, помогая:

- вести feature в dedicated worktree;
- соблюдать branch-spec alignment;
- готовить handoff для spec-driven feature work;
- не ломать artifact-first workflow.

Подробнее:

- [bridge/speckit/README.md](./bridge/speckit/README.md)
- [bridge/speckit/branch-spec-alignment.md](./bridge/speckit/branch-spec-alignment.md)
- [bridge/speckit/worktree-handoff.md](./bridge/speckit/worktree-handoff.md)

## Что внутри репозитория

- `core/` - переносимое ядро навыка.
- `adapters/` - IDE-specific install и discovery surfaces.
- `bridge/speckit/` - опциональный Speckit bridge layer.
- `install/` - bootstrap/register/verify scripts.
- `examples/` - примеры для greenfield и existing project.
- `docs/` - quickstart, compatibility, migration и release policy.

## Когда этот репозиторий особенно полезен

Используйте `worktree-skill`, если вы хотите:

- выделить worktree workflow из одного проекта в переиспользуемый пакет;
- получить одинаковое поведение агента в нескольких IDE;
- уменьшить project-specific ручную настройку;
- держать branch/worktree contracts в явном виде;
- улучшить handoff между сессиями и агентами;
- совместить worktree-first подход с Speckit.

## Чего этот репозиторий не делает

Этот репозиторий не должен тащить за собой:

- runtime вашего продукта;
- deploy scripts;
- secrets management;
- production configuration;
- обязательную зависимость на Beads, если базовый flow можно выполнить и без неё;
- бизнес-логику конкретного проекта.

## С чего начать

Если хотите быстро попробовать:

1. клонируйте репозиторий;
2. установите его в тестовый проект через `install/bootstrap.sh`;
3. проверьте установку через `install/verify.sh`;
4. откройте свою IDE;
5. напишите обычный запрос вроде:

```text
Помоги начать новую feature через dedicated worktree и не смешивать её с текущей работой.
```

Дальше агент должен подхватить worktree skill и провести вас по корректному сценарию.

Полезные ссылки:

- [docs/quickstart.md](./docs/quickstart.md)
- [docs/compatibility-matrix.md](./docs/compatibility-matrix.md)
- [docs/migration-from-in-repo.md](./docs/migration-from-in-repo.md)
- [adapters/claude-code/README.md](./adapters/claude-code/README.md)
- [adapters/codex-cli/README.md](./adapters/codex-cli/README.md)
- [adapters/opencode/README.md](./adapters/opencode/README.md)
