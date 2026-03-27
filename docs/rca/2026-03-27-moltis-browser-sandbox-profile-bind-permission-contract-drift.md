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
**Статус:** In Progress  
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

## Принятые меры

1. **Backlog expansion**
   - В Speckit добавлен отдельный follow-up backlog на полный browser/sandbox contract audit, а не только на socket-level repair.
2. **Durable rule**
   - Добавлено правило `docs/rules/moltis-browser-sandbox-contract-must-be-proven-end-to-end.md`.
3. **Runbook hardening**
   - Remote Moltis Docker runbook теперь явно требует browser profile storage contract и exercised browser proof.
4. **Lessons path**
   - Этот инцидент сохраняется отдельно от Telegram leak и отдельно от первого browser repair, чтобы новые инстансы агента не считали “docker.sock заработал” достаточным критерием закрытия browser outage.

## Уроки

1. **Browser sandbox repair нельзя закрывать по первой исчезнувшей ошибке.**
   Если исчез `docker.sock permission denied`, это ещё не означает, что Chrome реально стартует.
2. **Official docs задают baseline, но не всегда все repo-specific blocking gates.**
   Для Moltinger нужно дополнительно валидировать writable host-visible browser profile storage.
3. **Real user path matters.**
   После любой browser repair нужен exercised canary на том же классе user-facing path, например `t.me/...`, а не только `/health` или “container started”.
4. **Новые инстансы агента должны начинать с полной browser checklist.**
   Не с “browser enabled” и не с “docker.sock mounted”, а с полного контракта: sandbox mode, socket, `container_host`, `sandbox_image`, `profile_dir`, `persist_profile`, writability, exercised canary.
