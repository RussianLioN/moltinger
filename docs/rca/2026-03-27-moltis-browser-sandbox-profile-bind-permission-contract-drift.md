---
title: "Moltis browser timeout persisted after Docker socket recovery because the sibling browser profile bind mount was not writable and the repair stopped before full end-to-end contract proof"
date: 2026-03-27
severity: P1
category: process
tags: [moltis, browser, sandbox, docker, browserless, telegram, timeout, profile-dir, rca]
root_cause: "The first repair restored only Docker/socket connectivity, but the full Docker-backed browser contract also required writable host-visible browser profile storage and an exercised browser canary on the real Telegram path."
---

# RCA: Moltis browser timeout persisted after Docker socket recovery because the sibling browser profile bind mount was not writable and the repair stopped before full end-to-end contract proof

**Дата:** 2026-03-27  
**Статус:** In Progress, root cause confirmed with authoritative live browser repro  
**Влияние:** Пользовательский Telegram-запрос мог завершаться `Timed out after 30s`, а бот при этом показывал внутренний `Activity log`, хотя первая часть browser sandbox repair уже казалась успешной.

## Ошибка

После частичного browser sandbox repair пользователь всё ещё видел в Telegram:

- `⚠️ Timed out: Agent run timed out after 30s`
- `📋 Activity log`
- browser path с `Navigating to t.me/...`

При этом более ранняя конкретная ошибка про доступ к Docker API уже исчезла. Это означало, что первая причина устранена, но incident не был закрыт полностью.

## Контекст

Live evidence разделилось на два слоя:

1. **Первый слой был уже исправлен**
   - доступ к host Docker socket из контейнера Moltis был восстановлен
   - sibling browser container начал стартовать
2. **Второй слой остался сломан**
   - sibling browser container не мог создать `SingletonLock` в browser profile dir
   - реальный Telegram `t.me/...` canary после первой правки не был доведён до полного exercised browser proof

Позднее authoritative evidence от 2026-03-27 добавило ещё одну важную коррекцию:

- текущий production runtime на `main` больше вообще не живёт по tracked browser contract из `031`
- live runtime config внутри контейнера сейчас содержит только:
  - `sandbox_image = "browserless/chrome"`
  - `container_host = "host.docker.internal"`
  - без `profile_dir`
  - без `persist_profile`
- ручной `docker pull browserless/chrome` изнутри контейнера `moltis` теперь проходит
- изолированный stock `browserless/chrome` на том же хосте успешно стартует, но `/json/version` возвращает websocket URL вида `ws://127.0.0.1:<port>` вместо явного `/devtools/browser/*` пути

Это означает, что текущий live browser outage уже не лучше всего объясняется активной проблемой image-pull permissions. Более сильное объяснение: production остался на stock browserless baseline из `main`, а repo-specific sibling-browser compatibility shim из `031` туда так и не попал.

### Authoritative live repro from the browser path itself

К 2026-03-27 20:23 UTC инцидент был подтверждён уже не только через Telegram, но и через чистый RPC path после `chat.clear`:

- live `chat.send` с явным требованием использовать `browser`, а не `web_fetch`, стартовал run `f07bf3a7-0c29-49c0-9e61-8fce95331c58`
- runtime ушёл в `tool_call_start` для `browser`
- затем дал `Timed out` через 30 секунд, не дойдя до `final`
- одновременно `docker logs moltis` показал запуск sibling browser container `moltis-browser-77ee33c642484bb59bb5ff866d4310a4`
- его собственные логи подтвердили точную причину:
  - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
  - `Failed to create a ProcessSingleton for your profile directory`
- `docker inspect` этого контейнера показал bind mount:
  - source: `/home/moltis/.moltis/browser/profile/sandbox/browser-49e1166b10909a09`
  - destination: `/data/browser-profile`
  - user: `blessuser`
- host path при этом был `root:root 755`, то есть не writable для браузерного процесса внутри stock image

Это замыкает RCA: текущий live browser failure воспроизводится и без Telegram, а значит Telegram здесь только surface, а не первичный источник дефекта.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему Telegram по-прежнему отдавал timeout на browser path? | Потому что browser sandbox всё ещё не поднимал рабочий Chrome profile, несмотря на восстановленный Docker доступ. | Live Telegram reply: `Timed out after 30s`; Moltis logs continued browser startup before timeout. |
| 2 | Почему Chrome profile не поднимался? | Потому что sibling browser container получал host-visible bind mount, который был не writable для его non-root пользователя. | Browser container logs: `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`. |
| 3 | Почему bind mount оказался не writable? | Потому что host path был auto-created/owned не тем UID:GID, который использовал browserless container, а contract writability не проверялся fail-closed. | Container inspection showed browser container user `uid=999`, while mounted profile dir was `root:root` on host. |
| 4 | Почему эта вторая причина не была поймана сразу после первого fix? | Потому что repair остановился после восстановления Docker/socket connectivity и не дошёл до полного end-to-end browser contract proof на реальном `t.me/...` пути. | First repair removed Docker permission error, but authoritative Telegram/browser canary later still failed. |
| 5 | Почему это выглядит как “не следовал инструкции”, хотя причина глубже? | Потому что official docs покрывают sandbox mode, Docker/socket access и `container_host`, но repo process не закреплял обязательную проверку writable `profile_dir` и exercised browser canary как blocking invariant. | Official Moltis docs describe Docker-backed sandbox baseline; repo lacked a fail-closed browser profile/storage gate and stopped after a partial fix. |

## Корневая причина

Это не сводится к одной фразе “не следовал инструкции”.

Более точный вывод такой:

- официальный Moltis baseline для sandbox/browser path был применён только частично;
- первая правка восстановила **Docker-backed connectivity contract**, но не весь **browser runtime contract**;
- недостающими инвариантами оказались:
  - writable host-visible `profile_dir`
  - согласованный `persist_profile` strategy
  - обязательный exercised browser canary на том же user-facing path, который ломался у пользователя

То есть ошибка была не в намеренном отходе от official path, а в том, что repair был остановлен после первой восстановленной инварианты и не был доведён до полного browser contract proof.

## Official vs Repo-Specific Evidence

### Что говорят official Moltis docs

- Browser sandbox следует session sandbox mode и в Docker-backed сценарии требует рабочий sibling-container path.
- Если Moltis сам запущен в Docker, для browser sandbox нужен host Docker access и `container_host`.
- Cloud/self-hosted docs прямо предупреждают, что sandboxed execution зависит от Docker availability и не везде поддерживается.
- Official changelog уже упоминает browser `profile_dir` и `persist_profile`, но browser automation guide не доводит этот слой до fail-closed host-visible ownership checklist для sibling browser containers.

Это подтверждает baseline для:

- sandbox mode
- Docker/socket access
- `container_host`

### Что official docs не закрывают fail-closed сами по себе

Official docs не дают готового blocking deploy gate на конкретный host bind-mount ownership drift для browser profile dir. Этот слой пришлось добирать из:

- live runtime evidence
- tracked repo contract
- primary browserless / Chromium behavior

Secondary evidence corroborated the failure mode:

- Chromium stores `SingletonLock` and related singleton state in the profile directory
- browserless/Chromium on non-root users breaks predictably when bind-mounted profile storage is not writable
- stock `browserless/chrome` может быть operationally несовместим с Moltis sibling-CDP contract даже когда image pull и basic container start уже работают, потому что websocket endpoint из `/json/version` не даёт тот concrete `/devtools/browser/*` путь, на который опирается tracked local proxy shim

## Текущий взвешенный вывод

Смешанную evidence надо трактовать так:

1. Более ранняя пользовательская строка `failed to pull browser image: permission d...` реальна как historical evidence, но уже не является лучшим объяснением текущего live состояния.
2. Больше веса у текущих фактов:
   - stock image pull сейчас успешен
   - stock `browserless/chrome` на том же хосте поднимается
   - live `moltis` всё ещё настроен на stock image вместо tracked shim из `031`
3. Поэтому наиболее вероятная текущая корневая причина такая:
   - **production runtime drift назад к stock browserless baseline из `main`**
   - плюс **websocket/readiness несовместимость stock browserless для Moltis sibling-container browser sessions на этом deployment**
4. Writability `profile_dir` остаётся частью полного browser contract и по-прежнему должна быть доказана end-to-end, но уже недостаточна как единственное описание всего текущего инцидента.

## Authoritative follow-up proof (2026-03-27)

Дополнительная authoritative проверка после расширения Telegram/browser UAT закрыла оставшиеся сомнения:

1. **Current production still matches the stock `origin/main` browser contract.**
   Live runtime config on the server still shows:
   - `sandbox_image = "browserless/chrome"`
   - `container_host = "host.docker.internal"`
   - no tracked `profile_dir`
   - no tracked `persist_profile`
2. **The stock image is not generically broken on this host.**
   A plain isolated `browserless/chrome` container starts and answers `/json/version`.
3. **The stock image fails once the real browser/profile path is exercised with the host bind class used by this deployment.**
   In an isolated remote reproduction with:
   - `DEFAULT_USER_DATA_DIR=/data/browser-profile`
   - bind mount `/home/moltis/.moltis/browser/profile:/data/browser-profile`
   the first actual browser job fails with:
   - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`

Это переводит диагноз из “вероятный profile-dir drift” в “напрямую воспроизведённый stock-image failure mode под тем же классом host path, который production использует сейчас”.

## Принятые меры

1. **Backlog expansion**
   - В Speckit добавлен отдельный follow-up backlog на полный browser/sandbox contract audit, а не только на socket-level repair.
2. **Durable rule**
   - Добавлено правило `docs/rules/moltis-browser-sandbox-contract-must-be-proven-end-to-end.md`.
3. **Runbook hardening**
   - Remote Moltis Docker runbook теперь явно требует browser profile storage contract и exercised browser proof.
4. **Lessons path**
   - Этот инцидент сохраняется отдельно от Telegram leak и отдельно от первого browser repair, чтобы новые инстансы агента не считали “docker.sock заработал” достаточным критерием закрытия browser outage.
5. **Mainline landing requirement**
   - Без минимального browser hotfix carrier в `main` production останется на stock browser contract, потому что текущий live runtime всё ещё совпадает с `origin/main`, а не с tracked browser stack из `031`.

## Уроки

1. **Browser sandbox repair нельзя закрывать по первой исчезнувшей ошибке.**
   Если исчез `docker.sock permission denied`, это ещё не означает, что Chrome реально стартует.
2. **Official docs задают baseline, но не всегда все repo-specific blocking gates.**
   Для Moltinger нужно дополнительно валидировать writable host-visible browser profile storage.
3. **Real user path matters.**
   После любой browser repair нужен exercised canary на том же классе user-facing path, например `t.me/...`, а не только `/health` или “container started”.
4. **Новые инстансы агента должны начинать с полной browser checklist.**
   Не с “browser enabled” и не с “docker.sock mounted”, а с полного контракта: sandbox mode, socket, `container_host`, `sandbox_image`, `profile_dir`, `persist_profile`, writability, exercised canary.
