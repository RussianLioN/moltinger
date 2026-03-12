---
title: "Официальный мастер настройки Clawdiy не мог завершить OAuth из-за неверного контракта домашнего каталога OpenClaw"
date: 2026-03-13
severity: P1
category: process
tags: [process, clawdiy, openclaw, docker, deploy, oauth, wizard, runtime-home, lessons]
root_cause: "Контракт разворачивания Clawdiy монтировал только read-only файл openclaw.json вместо записываемого домашнего каталога ~/.openclaw, который требуется официальному мастеру настройки OpenClaw"
---

# RCA: Официальный мастер настройки Clawdiy не мог завершить OAuth из-за неверного контракта домашнего каталога OpenClaw

**Дата:** 2026-03-13  
**Статус:** Mitigated in branch / pending rollout  
**Влияние:** Высокое; подключение `OpenAI Codex` / `gpt-5.4` по официальной инструкции было заблокировано на живом Clawdiy  
**Контекст:** На `ainetic.tech` пользователь прошел официальный мастер настройки `openclaw onboard --auth-choice openai-codex`, успешно завершил OAuth-шаг, но мастер упал до сохранения конфигурации с ошибкой `EACCES`

## Контекст

| Поле | Значение |
|------|----------|
| Timestamp | 2026-03-13T00:50:00+03:00 |
| PWD | /Users/rl/coding/moltinger-openclaw-control-plane |
| Shell | /bin/zsh |
| Git Branch | 022-clawdiy-wizard-writability-fix |
| Runtime Target | `ainetic.tech` / контейнер `clawdiy` |
| Error Type | process / deploy-contract / runtime permissions |

## Ошибка

Официальный мастер настройки OpenClaw для Docker/headless режима дошел до шага:

- OAuth callback вставлен успешно
- мастер подтвердил `Default model set to openai-codex/gpt-5.4`

После этого мастер попытался сохранить обновленную конфигурацию и завершился ошибкой:

```text
Error: EACCES: permission denied, open '/home/node/.openclaw/openclaw.json.<tmp>.tmp'
```

Это означало, что live Clawdiy не соответствует официальному контракту OpenClaw на запись во внутренний каталог `~/.openclaw`.

## Анализ 5 Почему (с доказательствами)

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему официальный мастер настройки упал после успешного OAuth? | Потому что OpenClaw не смог создать временный файл рядом с `openclaw.json` | Live SSH output from `openclaw onboard --auth-choice openai-codex` on `ainetic.tech` |
| 2 | Почему рядом с `openclaw.json` нельзя было писать? | Потому что в контейнер был смонтирован только одиночный файл `openclaw.json` в read-only режиме | `docker-compose.clawdiy.yml` before fix mounted `./data/clawdiy/runtime/openclaw.json -> /home/node/.openclaw/openclaw.json:ro` |
| 3 | Почему это было системным, а не единичным сбоем прав на файл? | Потому что весь каталог `/home/node/.openclaw` внутри контейнера был root-owned, а не runtime-owned; туда же OpenClaw может писать временные файлы и OAuth-артефакты | Live inspection on server: `/home/node/.openclaw` and `/home/node/.openclaw/openclaw.json` were `root:root`; official docs mention runtime artifacts under `~/.openclaw` |
| 4 | Почему такой контракт вообще был внедрен? | Потому что мы оптимизировали Clawdiy под неизменяемый GitOps-рендер одного файла конфигурации и не сверили это с официальным поведением мастера настройки OpenClaw | Historical regression introduced by commit `13b2e6a` (“mount runtime config as file”) plus static tests locking that contract in place |
| 5 | Почему это не было поймано до live OAuth-попытки? | Потому что проверки перед запуском, smoke и документация валидировали неверный контракт и не проверяли совместимость с официальным мастером настройки | `preflight-check.sh`, `clawdiy-smoke.sh`, `tests/static/test_config_validation.sh`, runbooks before this fix |

## Корневая причина

Контракт разворачивания Clawdiy монтировал только read-only файл `openclaw.json` вместо записываемого домашнего каталога `~/.openclaw`, который требуется официальному мастеру настройки OpenClaw. Из-за этого система выглядела GitOps-аккуратной, но была несовместима с официальным OAuth/wizard жизненным циклом OpenClaw для Docker/headless режима.

### Проверка корневой причины

| Проверка | Результат | Примечание |
|----------|-----------|------------|
| Исправляется конкретным действием? | yes | Нужно менять контракт монтирования, права и проверки перед запуском |
| Системная? | yes | Повторится при любом повторном запуске официального мастера настройки или записи OAuth-артефактов |
| Предотвратима? | yes | Через правило “официальный мастер настройки требует записываемый `runtime home`” и явные проверки до выката |

## Принятые меры

1. **Немедленное исправление контракта:** `docker-compose.clawdiy.yml` переведен с одиночного file-bind на bind всего каталога `data/clawdiy/runtime -> /home/node/.openclaw`.
2. **Нормализация прав:** `scripts/deploy.sh` и `scripts/render-clawdiy-runtime-config.sh` теперь приводят `data/clawdiy/runtime` к uid/gid рантайма OpenClaw (`1000:1000` по умолчанию).
3. **Предотвращение:** `scripts/preflight-check.sh` теперь падает, если `data/clawdiy/runtime` отсутствует или принадлежит не runtime-пользователю.
4. **Покрытие резервным копированием и smoke:** резервное копирование и same-host smoke теперь считают `data/clawdiy/runtime` частью обязательного live-инвентаря.
5. **Статическая защита:** тесты фиксируют новый контракт и отдельно требуют наличие проверки `runtime home` в `preflight`.

## Связанные обновления

- [X] Новый файл правила создан: [docs/rules/clawdiy-official-wizard-needs-writable-runtime-home.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/rules/clawdiy-official-wizard-needs-writable-runtime-home.md)
- [X] `MEMORY.md` обновлен кратким правилом
- [X] `SESSION_SUMMARY.md` обновлен
- [X] Индекс уроков должен быть пересобран после landing
- [X] Резервная копия live-состояния снята до исправления:
  - `/root/clawdiy-backups/clawdiy-pre-codex-oauth-20260313-004707.tar.gz`
  - `sha256: 7684188246ea345ff60cbfd1cc267580b87a5e75427b81eee5614e1e425db0da`

## Уроки

1. **Официальный мастер настройки важнее локальной гипотезы о “неизменяемом конфиге”** — если upstream ожидает запись в `~/.openclaw`, нельзя монтировать только read-only файл.
2. **`runtime home` — это отдельный постоянный артефакт, а не просто каталог для одного `openclaw.json`** — туда пишутся временные файлы, OAuth-артефакты и другие служебные данные OpenClaw.
3. **GitOps-контракт тоже надо валидировать на совместимость с официальными мастер-потоками** — smoke и preflight должны проверять не только “файл существует”, но и “официальный путь настройки сможет его обновить”.

---

*Создано по протоколу rca-5-whys (RCA-013).*
