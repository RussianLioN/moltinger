---
title: "Stock browserless/chrome remained viable on the live host; the immediate browser hotfix was profile-dir writability, not a custom browser image"
date: 2026-03-27
severity: P1
category: process
tags: [moltis, browser, sandbox, docker, browserless, profile-dir, official-first, rca]
root_cause: "The current live browser timeout was caused by a non-writable host-visible browser profile bind; isolated proof showed stock browserless/chrome succeeds on the same host once that bind is writable."
---

# RCA: Stock browserless/chrome remained viable on the live host; the immediate browser hotfix was profile-dir writability, not a custom browser image

**Дата:** 2026-03-27  
**Статус:** Open  
**Влияние:** Без этого уточнения можно было закрепить лишнюю repo-specific кастомизацию вместо более узкого official-first hotfix для production browser path.

## Ошибка

После расследования browser timeout в Telegram ветка `031` несла default на локальный browser shim image `moltinger/browserless-chrome-no-preboot:local`. Новая isolated repro на самом live host показала, что для текущего production blocker это уже избыточно:

- stock `browserless/chrome` стартует на том же хосте;
- stock `browserless/chrome` c websocket root request тоже работает;
- падение воспроизводится именно тогда, когда browser job использует bind-mounted profile dir, который на host остаётся `root:root 755`.

## Контекст

Подтверждённые live факты:

- production Moltis сейчас работает с:
  - `sandbox_image = "browserless/chrome"`
  - `container_host = "host.docker.internal"`
  - без явного `profile_dir`
- sibling browser readiness в Moltis логах срывается повторяющимся:
  - `Connection reset by peer (os error 104)`
  - затем `browser container failed readiness check`
- host path `/home/moltis/.moltis/browser/profile` существует как `root:root 755`

Изолированные repro на том же хосте:

1. `browserless/chrome` без bind mount поднимается нормально.
2. `browserless/chrome` с `DEFAULT_USER_DATA_DIR=/data/browser-profile` и bind mount на root-owned host path падает на первом websocket/browser job:
   - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
3. Тот же stock image с writable host path (`chmod 0777` temp dir под `/tmp`) успешно проходит:
   - `/json/version`
   - websocket upgrade на `/`
   - успешный browser job cleanup

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему текущий browser path таймаутится? | Потому что sibling browser container закрывает websocket/job при первом реальном старте Chrome profile. | Moltis logs: repeated `Connection reset by peer`, then browser readiness timeout. |
| 2 | Почему Chrome profile не стартует? | Потому что bind-mounted profile dir на host не writable для non-root browser user. | Isolated repro: `SingletonLock: Permission denied (13)`. |
| 3 | Почему мы думали, что нужен custom browser image? | Потому что предыдущая repo-specific гипотеза смешала несколько слоёв риска: preboot/root-websocket behavior и profile-dir writability. | Ветка `031` закрепила local shim как default до isolated host-side proof. |
| 4 | Что показала новая изолированная проверка? | Что stock `browserless/chrome` на этом же хосте работает, если дать writable profile dir. | Successful isolated run with writable `/tmp/...` bind mount and root websocket. |
| 5 | Какой отсюда корневой вывод? | Для текущего live incident минимальный и более официальный hotfix должен чинить `profile_dir`/mount/permissions первым, а не тянуть custom image по умолчанию. | Same host, same stock image, same websocket path, different outcome based only on writable profile storage. |

## Корневая причина

Корневая причина текущего production browser blocker:

- host-visible browser profile bind был не writable.

Корневая причина process drift в ветке:

- после верной диагностики `profile_dir`/permissions ветка закрепила более широкий repo-specific workaround как default, хотя isolated proof для текущего host/tag показал, что stock official image уже достаточен.

## Что говорят источники

### Official baseline

Official Moltis docs требуют browser sandbox baseline:

- Docker-backed sandbox/browser path
- host Docker access
- `container_host` для Moltis-in-Docker sibling browser access

### Что official docs не закрывают автоматически

Official docs не дают fail-closed host bind ownership gate для browser profile storage. Это пришлось добирать live evidence.

### Что показала live repro

Для текущего host/tag:

- stock `browserless/chrome` не является сам по себе broken;
- writable profile storage является blocking invariant;
- значит safest immediate fix path должен оставаться official-first.

## Решение

1. Оставить tracked default на stock `browserless/chrome` для этого incident path.
2. Добавить/сохранять explicit:
   - `profile_dir`
   - shared host mount
   - deploy-time permission prep
   - `persist_profile = false`
3. Рассматривать local custom browser shim только как fallback path, если separate live canary снова докажет, что stock image уже недостаточен.

## Уроки

1. Не закрепляй repo-specific image workaround как default, пока isolated proof не покажет, что official stock path реально insufficient.
2. Для browser incidents разделяй:
   - official baseline
   - writable profile storage
   - optional image-specific workaround
3. Если same-host repro показывает, что один и тот же stock image работает после исправления bind permissions, минимальный hotfix должен следовать именно этому пути.
