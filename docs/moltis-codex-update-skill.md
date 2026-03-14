# Moltis Codex Update Skill

## Что это

Это новый канонический Moltis-native навык для отслеживания обновлений `Codex CLI`.

Простыми словами:
- Moltis сам проверяет официальный changelog;
- Moltis сам запоминает последнее увиденное состояние;
- Moltis сам отвечает пользователю по-русски;
- optional project profile помогает делать рекомендации более прикладными.

Этот путь заменяет старую гибридную модель, где canonical runtime жил в repo-side watcher scripts.

## Как это работает сейчас

На текущем implementation slice навык уже умеет:

1. прочитать официальный источник Codex CLI;
2. распознать свежую upstream-версию и её ключевые изменения;
3. понять, новое это состояние или уже виденное;
4. вернуть краткий русский summary;
5. при наличии project profile учесть его правила.

Пока ещё не включено в production-final виде:
- scheduler duplicate suppression как окончательный live path;
- production delivery orchestration;
- полный rollout старого fallback path.

## On-demand usage

Прямой runtime:

```bash
bash scripts/moltis-codex-update-run.sh --mode manual
```

С project profile:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --profile-file tests/fixtures/codex-update-skill/project-profile-basic.json
```

С fixture-источником:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --release-file tests/fixtures/codex-update-skill/releases-0.114.0.html \
  --include-issue-signals \
  --issue-signals-file tests/fixtures/codex-update-skill/issue-signals.json
```

## Scheduler path

Scheduler использует тот же runtime:

```bash
bash scripts/moltis-codex-update-run.sh --mode scheduler --stdout json
```

На этом slice scheduler уже является частью нового Moltis-native skill path, но его delivery semantics
ещё intentionally отмечены как `deferred` до следующего implementation этапа.

## State helper

Состояние навыка живёт через:

```bash
bash scripts/moltis-codex-update-state.sh get
```

По умолчанию state file:

```text
.tmp/current/moltis-codex-update-state.json
```

## Profile helper

Проверка профиля:

```bash
bash scripts/moltis-codex-update-profile.sh validate \
  --file tests/fixtures/codex-update-skill/project-profile-basic.json
```

## Что пользователь должен получить

Если пользователь пишет:

```text
Проверь обновления Codex CLI
```

Moltis должен ответить простым русским summary:
- вышло ли новое upstream-обновление;
- насколько это важно;
- почему это важно;
- какие следующие шаги разумны.

## Деградация

Если официальный источник недоступен или changelog поменял формат:
- навык должен честно вернуть `нужно проверить`;
- он не должен угадывать или выдавать ложный `upgrade-now`.

## Migration note

Старый гибридный advisory path остаётся только как временный migration fallback.
Новый canonical target для этой функции — `023-full-moltis-codex-update-skill`.
